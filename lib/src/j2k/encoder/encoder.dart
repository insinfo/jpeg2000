import '../codestream/writer/file_codestream_writer.dart';
import '../codestream/writer/header_encoder.dart';
import '../codestream/writer/pkt_encoder.dart';
import '../entropy/encoder/entropy_coder.dart';
import '../entropy/encoder/post_comp_rate_allocator.dart';
import '../fileformat/writer/file_format_writer.dart';
import '../image/blk_img_data_src.dart';
import '../image/img_data_converter.dart';
import '../image/forwcomptransf/forw_comp_transf.dart';
import '../image/input/img_reader.dart';
import '../image/input/img_reader_pgm.dart';
import '../image/input/img_reader_ppm.dart';
import '../image/tiler.dart';
import '../quantization/quantizer/quantizer.dart';
import '../roi/encoder/roi_scaler.dart';
import '../util/facility_manager.dart';
import '../util/msg_logger.dart';
import '../util/parameter_list.dart';
import '../wavelet/analysis/an_wt_filter.dart';
import '../wavelet/analysis/forward_wt.dart';
import 'encoder_specs.dart';

/// This class is the JPEG 2000 encoder entry point, mirroring JJ2000's
/// `Encoder` class. It instantiates the whole encoding chain and writes the
/// codestream (optionally wrapped in the JP2 file format) to the output file.
///
/// The encoding chain:
/// `ImgReader → Tiler → ForwCompTransf → ImgDataConverter → ForwardWT →
/// Quantizer → ROIScaler → StdEntropyCoder → EBCOTRateAllocator →
/// FileCodestreamWriter (+ HeaderEncoder, + FileFormatWriter)`.
///
/// Differences from the Java original (documented deviations):
/// - A single input file is supported per invocation (`,`-joined multi-file
///   inputs / ImgDataJoiner wiring is not implemented yet).
/// - PGX input and the CodestreamManipulator post-processing options
///   (`tile_parts`, `pph_tile`, `pph_main`) are not implemented yet.
class Encoder {
  Encoder(this.pl) : defpl = pl.getDefaultParameterList();

  /// The parameter list (arguments)
  final ParameterList pl;

  /// The default parameter list (arguments)
  final ParameterList? defpl;

  /// Exit code produced by [run]; zero indicates success.
  int exitCode = 0;

  /// The exponent offset used when specifying rates in bytes.
  static const List<List<String?>> pinfo = [
    [
      'debug',
      '[on|off]',
      'Print debugging messages when an error is encountered.',
      'off'
    ],
    [
      'file_format',
      '[on|off]',
      'Puts the JPEG 2000 codestream in a JP2 file format wrapper.',
      'off'
    ],
    [
      'lossless',
      '[on|off]',
      'Specifies a lossless compression for the encoder. This options is '
          'equivalent to use reversible quantization and 5x3 wavelet filters '
          'pair. Cannot be used with -rate.',
      'off'
    ],
    [
      'i',
      '<image file>',
      'Mandatory argument. This option specifies the name of the input '
          'image file. Supported formats are raw PPM (P6) and raw PGM (P5).',
      null
    ],
    [
      'o',
      '<file name>',
      'Mandatory argument. This option specifies the name of the output '
          'file to which the codestream will be written.',
      null
    ],
    [
      'rate',
      '<output bitrate in bpp>',
      'This is the output bitrate of the codestream in bits per pixel. '
          'When equal to -1, no image information (beside quantization '
          'effects) is discarded during compression.',
      '-1'
    ],
    [
      'tiles',
      '<nominal tile width> <nominal tile height>',
      'This option specifies the maximum tile dimensions to use. If both '
          'dimensions are 0 then no tiling is used.',
      '0 0'
    ],
    [
      'ref',
      '<x> <y>',
      'Sets the origin of the image in the canvas system. It sets the '
          'coordinate of the top-left corner of the image reference grid, '
          'with respect to the canvas origin',
      '0 0'
    ],
    [
      'tref',
      '<x> <y>',
      'Sets the origin of the tile partitioning on the reference grid, '
          'with respect to the canvas origin. The value of \'x\' (\'y\') '
          'specified can not be larger than the \'x\' one specified in the '
          'ref option.',
      '0 0'
    ],
    [
      'verbose',
      '[on|off]',
      'Prints information about the obtained bit stream.',
      'on'
    ],
    ['v', '[on|off]', 'Prints version and copyright information.', 'off'],
    ['u', '[on|off]', 'Prints usage information.', 'off'],
  ];

  /// Builds the default parameter list from the parameter information of
  /// all the modules in the encoding chain (mirrors JJ2000's
  /// `CmdLnEncoder` default handling).
  static ParameterList buildDefaultParameterList() {
    final defaults = ParameterList();
    final allPinfo = <List<List<String?>>>[
      pinfo,
      ForwCompTransf.getParameterInfo(),
      AnWTFilter.getParameterInfo(),
      ForwardWT.getParameterInfo()
          .map((e) => e.cast<String?>())
          .toList(growable: false),
      Quantizer.getParameterInfo(),
      ROIScaler.getParameterInfo(),
      EntropyCoder.getParameterInfo(),
      HeaderEncoder.pinfo,
      PktEncoder.pinfo.map((e) => e.cast<String?>()).toList(growable: false),
      PostCompRateAllocator.getParameterInfo(),
    ];
    for (final moduleInfo in allPinfo) {
      for (final option in moduleInfo) {
        if (option.length > 3 &&
            option[0] != null &&
            option[0]!.isNotEmpty &&
            option[3] != null &&
            option[3]!.isNotEmpty) {
          defaults.put(option[0]!, option[3]!);
        }
      }
    }
    return defaults;
  }

  MsgLogger get _logger => FacilityManager.getMsgLogger();

  void _error(String message, int code) {
    exitCode = code;
    _logger.printmsg(MsgLogger.error, message);
  }

  /// Runs the encoder. When it ends [exitCode] holds 0 on success, a
  /// non-zero value otherwise.
  void run() {
    try {
      _runInternal();
    } catch (e, st) {
      if (exitCode == 0) {
        exitCode = 2;
      }
      _logger.printmsg(
          MsgLogger.error, 'An uncaught exception has occurred: $e');
      if (pl.getParameter('debug') == 'on') {
        _logger.printmsg(MsgLogger.error, st.toString());
      } else {
        _logger.printmsg(
            MsgLogger.error, "Use '-debug' option for more details");
      }
    }
  }

  void _runInternal() {
    final verbose = pl.getParameter('verbose') == 'on';

    // **** Get general parameters ****
    final inputPath = pl.getParameter('i');
    if (inputPath == null || inputPath.isEmpty) {
      _error("Input file ('-i' option) has not been specified", 1);
      return;
    }
    if (inputPath.contains(',')) {
      _error('Multiple input files are not supported by this port yet', 1);
      return;
    }

    final outname = pl.getParameter('o');
    if (outname == null || outname.isEmpty) {
      _error("Output file ('-o' option) has not been specified", 1);
      return;
    }

    final useFileFormat = pl.getBooleanParameter('file_format');

    // Lossless and rate are mutually exclusive (as in JJ2000).
    if (pl.getBooleanParameter('lossless') &&
        pl.getParameter('rate') != null &&
        pl.getFloatParameter('rate') != -1) {
      _error("Cannot use '-rate' and '-lossless' option at the same time.", 2);
      return;
    }

    if (pl.getParameter('rate') == null) {
      _error('Target bitrate not specified', 2);
      return;
    }
    var rate = pl.getFloatParameter('rate');
    if (rate == -1) {
      rate = double.maxFinite;
    }

    // **** ImgReader ****
    final lower = inputPath.toLowerCase();
    final ImgReader imreader;
    var ppminput = false;
    if (lower.endsWith('.ppm')) {
      imreader = ImgReaderPPM(inputPath);
      ppminput = true;
    } else if (lower.endsWith('.pgm')) {
      imreader = ImgReaderPGM(inputPath);
    } else {
      _error(
          'Input file $inputPath must be raw PPM (.ppm) or raw PGM (.pgm) '
          '(PGX not supported by this port yet)',
          2);
      return;
    }

    final BlkImgDataSrc imgsrc = imreader;
    final ncomp = imgsrc.getNumComps();
    final imsigned =
        List<bool>.generate(ncomp, imreader.isOrigSigned, growable: false);

    try {
      // **** Tiler ****
      final tileSpec = pl.getParameter('tiles') ?? '0 0';
      final tileTokens = tileSpec.trim().split(RegExp(r'\s+'));
      if (tileTokens.length != 2) {
        _error("'tiles' option needs two arguments", 2);
        return;
      }
      final tw = int.parse(tileTokens[0]);
      final th = int.parse(tileTokens[1]);

      final refTokens =
          (pl.getParameter('ref') ?? '0 0').trim().split(RegExp(r'\s+'));
      final refx = int.parse(refTokens[0]);
      final refy = int.parse(refTokens[1]);
      if (refx < 0 || refy < 0) {
        _error("Invalid reference grid origin: has to be at least (0,0)", 2);
        return;
      }

      final trefTokens =
          (pl.getParameter('tref') ?? '0 0').trim().split(RegExp(r'\s+'));
      final trefx = int.parse(trefTokens[0]);
      final trefy = int.parse(trefTokens[1]);
      if (trefx < 0 || trefy < 0 || trefx > refx || trefy > refy) {
        _error(
            'Invalid tiling origin: has to be at least (0,0) and no larger '
            'than the reference grid origin',
            2);
        return;
      }

      final imgtiler = Tiler(imgsrc, refx, refy, trefx, trefy, tw, th);
      final ntiles = imgtiler.getNumTiles();

      // **** Encoder specifications ****
      final encSpec = EncoderSpecs(ntiles, ncomp, imgsrc, pl);

      // **** Component transformation ****
      if (ppminput &&
          pl.getParameter('Mct') != null &&
          pl.getParameter('Mct') == 'off') {
        _logger.printmsg(
            MsgLogger.warning,
            'Input image is RGB and no color transform has been specified. '
            'Compression performance and image quality might be greatly '
            "degraded. Use the 'Mct' option to specify a color transform");
      }
      final fctransf = ForwCompTransf(imgtiler, encSpec);

      // **** ImgDataConverter ****
      final converter = ImgDataConverter(fctransf);

      // **** ForwardWT ****
      final dwt = ForwardWT.createInstance(converter, pl, encSpec);

      // **** Quantizer ****
      final quant = Quantizer.createInstance(dwt, encSpec);

      // **** ROIScaler ****
      final rois = ROIScaler.createInstance(quant, pl, encSpec);

      // **** EntropyCoder ****
      final ecoder = EntropyCoder.createInstance(
          rois,
          pl,
          encSpec.cblks,
          encSpec.pss,
          encSpec.bms,
          encSpec.mqrs,
          encSpec.rts,
          encSpec.css,
          encSpec.sss,
          encSpec.lcs,
          encSpec.tts);

      // **** CodestreamWriter ****
      // Rely on the rate allocator to limit the amount of data.
      final bwriter = FileCodestreamWriter.fromPath(outname, 0x7FFFFFFF);

      // **** Rate allocator ****
      final ralloc = PostCompRateAllocator.createInstance(
          ecoder, pl, rate, bwriter, encSpec);

      // **** HeaderEncoder ****
      final headenc = HeaderEncoder(
          imgsrc, imsigned, dwt, imgtiler, encSpec, rois, ralloc, pl);
      ralloc.setHeaderEncoder(headenc);

      // **** Write header to be able to estimate header overhead ****
      headenc.encodeMainHeader();

      // **** Initialize rate allocator, with proper header overhead. This
      // will also encode all the data ****
      ralloc.initialize();

      // **** Write header (final) ****
      headenc.reset();
      headenc.encodeMainHeader();

      // Insert header into the codestream
      bwriter.commitBitstreamHeader(headenc);

      // **** Report info ****
      if (verbose && pl.getFloatParameter('rate') != -1) {
        _logger.printmsg(
            MsgLogger.info,
            'Target bitrate = $rate bpp (i.e. '
            '${(rate * imgsrc.getImgWidth() * imgsrc.getImgHeight() / 8).toInt()} bytes)');
      }

      // **** Now do the rate-allocation and write result ****
      ralloc.runAndWrite();

      // **** Done ****
      bwriter.close();

      // **** Calculate file length ****
      var fileLength = bwriter.getLength();

      // **** File Format ****
      if (useFileFormat) {
        final nc = imgsrc.getNumComps();
        final bpc =
            List<int>.generate(nc, imgsrc.getNomRangeBits, growable: false);
        final ffw = FileFormatWriter(outname, imgsrc.getImgHeight(),
            imgsrc.getImgWidth(), nc, bpc, fileLength);
        fileLength += ffw.writeFileFormat();
      }

      // **** Report results ****
      if (verbose) {
        _logger.printmsg(
            MsgLogger.info,
            'Achieved bitrate = '
            '${8.0 * fileLength / (imgsrc.getImgWidth() * imgsrc.getImgHeight())} '
            'bpp (i.e. $fileLength bytes)');
      }
    } finally {
      imreader.close();
    }
  }
}

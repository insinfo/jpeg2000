import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/util/DecoderDebugConfig.dart';

import '../codestream/HeaderInfo.dart';
import '../codestream/reader/BitstreamReaderAgent.dart';
import '../codestream/reader/HeaderDecoder.dart';
import '../../colorspace/ColorSpace.dart';
import '../../colorspace/ColorSpaceMapper.dart';
import '../entropy/decoder/EntropyDecoder.dart';
import '../entropy/decoder/StdEntropyDecoder.dart';
import '../fileformat/FileFormatReader.dart';
import '../io/BeBufferedRandomAccessFile.dart';
import '../io/RandomAccessIO.dart';
import '../quantization/dequantizer/Dequantizer.dart';
import '../quantization/dequantizer/StdDequantizer.dart';
import '../roi/RoiDeScaler.dart';
import '../util/DecoderInstrumentation.dart';

import '../util/FacilityManager.dart';
import '../util/MsgLogger.dart';
import '../util/ParameterList.dart';
import '../util/StringFormatException.dart';
import '../wavelet/synthesis/InverseWT.dart';
import '../wavelet/synthesis/SynWTFilterFloatLift9x7.dart';
import '../wavelet/synthesis/SynWTFilterIntLift5x3.dart';
import '../wavelet/synthesis/SynWTFilter.dart';
import '../image/BlkImgDataSrc.dart';
import '../image/DataBlk.dart';
import '../image/DataBlkFloat.dart';
import '../image/DataBlkInt.dart';
import '../image/ImgDataConverter.dart';
import '../image/invcomptransf/InvComponentTransformer.dart';
import '../image/invcomptransf/InvCompTransf.dart';
import '../image/output/CompositeImgWriter.dart';
import '../image/output/ImgWriter.dart';
import '../image/output/ImgWriterBmp.dart';
import '../image/output/ImgWriterPgm.dart';
import '../image/output/ImgWriterPgx.dart';
import '../image/output/ImgWriterPpm.dart';
import 'DecoderSpecs.dart';

/// Minimal port of JJ2000's `Decoder` orchestration.
///
/// TODO The Dart version currently instantiates the core decoding stages up to
/// the inverse wavelet transform and sample conversion. Future work should wire
/// colour management, component transforms beyond reversible/irreversible
/// lifting, output image writers, and full tile decoding to produce raster
/// imagery.
class Decoder implements Runnable {
  Decoder(this.pl)
      : defpl = pl.getDefaultParameterList(),
        hi = HeaderInfo();

  /// The parameter list used to configure the decoder.
  final ParameterList pl;

  /// Default parameter list inherited from the caller.
  final ParameterList? defpl;

  /// Aggregated codestream metadata captured during header parsing.
  final HeaderInfo hi;

  /// Exit code produced by [run]; zero indicates success.
  int exitCode = 0;

  /// Decoder specifications populated from the main header.
  DecoderSpecs? decSpec;

  /// Header decoder responsible for parsing marker segments.
  HeaderDecoder? headerDecoder;

  /// Bit-stream reader responsible for delivering coded code-block data.
  BitstreamReaderAgent? bitstreamReader;

  /// Entropy decoder instantiated for the current codestream.
  StdEntropyDecoder? entropyDecoder;

  /// ROI de-scaler responsible for restoring background sample magnitude.
  ROIDeScaler? roiDeScaler;

  /// Dequantizer producing inverse-quantized coefficients.
  StdDequantizer? dequantizer;

  /// Inverse wavelet transform reconstructing spatial samples from coefficients.
  InverseWT? inverseWT;

  /// Component/sample type converter applied after the inverse wavelet stage.
  ImgDataConverter? imageDataConverter;

  /// Optional inverse component transform stage (ICT/RCT).
  InvCompTransfImgDataSrc? componentTransformer;
  ColorSpace? _colorSpace;
  BlkImgDataSrc? _channelDefinitionMapper;
  BlkImgDataSrc? _resamplerStage;
  BlkImgDataSrc? _palettizedMapper;
  BlkImgDataSrc? _colorSpaceMapperStage;
  ImgDataConverter? writerDataConverter;
  IOSink? _mqTraceSink;
  TraceBlockFilter? _traceFilter;
  String? _llSnapshotBasePath;
  int _llSnapshotTileIndex = 0;
  int _llSnapshotComponent = 0;
  bool _captureLlPre = false;
  bool _captureLlPost = false;
  bool _llPostSnapshotWritten = false;

  /// Active codestream handle retained for downstream stages.
  RandomAccessIO? _codestream;
  bool _jp2WrapperUsed = false;

  /// Provides the current image data source after all instantiated stages.
    BlkImgDataSrc? get imageDataSource =>
      writerDataConverter ??
      _colorSpaceMapperStage ??
      _palettizedMapper ??
      _resamplerStage ??
      _channelDefinitionMapper ??
      componentTransformer ??
      imageDataConverter ??
      inverseWT;

  /// Static option descriptors used by command-line front ends.
  static const List<List<String?>> pinfo = <List<String?>>[
    <String?>['u', '[on|off]', 'Prints usage information.', 'off'],
    <String?>['v', '[on|off]', 'Prints version information.', 'off'],
    <String?>['verbose', '[on|off]', 'Emits codestream diagnostics.', 'on'],
    <String?>[
      'pfile',
      '<filename>',
      'Loads decoder arguments from a text file (one key=value pair per line; lines ending with '
          'a backslash continue). Command line options override file entries.\n'
          'Nested pfile declarations inside the file are ignored.',
      null,
    ],
    <String?>[
      'res',
      '<resolution level index>',
      'Reconstructs up to the specified resolution level (0 = lowest available).',
      null,
    ],
    <String?>['i', '<filename or url>', 'Input JPEG 2000 codestream/JP2.', null],
    <String?>['o', '<filename>', 'Output image filename.', null],
    <String?>[
      'rate',
      '<decoding rate in bpp>',
      'Target decoding rate (bits per pixel). Use -1 to decode the full codestream. '
          'Use -nbytes to specify the target in bytes.',
      '-1',
    ],
    <String?>[
      'nbytes',
      '<decoding rate in bytes>',
      'Target decoding rate (bytes). Use -1 to decode the full codestream. '
          'Use -rate to specify the target in bits per pixel.',
      '-1',
    ],
    <String?>[
      'parsing',
      '[on|off]',
      'Controls whether virtual parsing is used when truncating the codestream '
          'with -rate or -nbytes.',
      'on',
    ],
    <String?>[
      'ncb_quit',
      '<max number of code blocks>',
      'Maximum number of code-blocks to parse before quitting when paired with lbody limits.',
      '-1',
    ],
    <String?>[
      'l_quit',
      '<max number of layers>',
      'Maximum layer index to decode for any code-block.',
      '-1',
    ],
    <String?>[
      'm_quit',
      '<max number of bit planes>',
      'Maximum bit-plane index to decode for any code-block.',
      '-1',
    ],
    <String?>[
      'poc_quit',
      '[on|off]',
      'If enabled, decoding stops after the first progression order completes.',
      'off',
    ],
    <String?>[
      'one_tp',
      '[on|off]',
      'If enabled, only the first tile-part of each tile is decoded.',
      'off',
    ],
    <String?>[
      'comp_transf',
      '[on|off]',
      'Applies the inverse component transform (RCT/ICT) indicated by the codestream metadata.',
      'on',
    ],
    <String?>['debug', '[on|off]', 'Print debugging stack traces.', 'off'],
    <String?>[
      'cdstr_info',
      '[on|off]',
      'Prints codestream marker segments, tile-part lengths, and offsets while parsing.',
      'off',
    ],
    <String?>[
      'nocolorspace',
      '[on|off]',
      'Ignore JP2 color specification boxes and emit raw components.',
      'off',
    ],
    <String?>[
      'colorspace_debug',
      '[on|off]',
      'Print debugging messages when the JP2 colorspace mapper is configured.',
      'off',
    ],
    <String?>['instrument', '[on|off]', 'Emits decoder instrumentation logs.', 'off'],
    <String?>[
      'inst_block',
      '<tile,comp,res,band,cblkY,cblkX>',
      'Restricts instrumentation to a single code-block (use -1 as wildcard).',
      null,
    ],
    <String?>[
      'inst_mq_log',
      '<path>',
      'Appends MQ trace dumps to <path> when instrumentation is enabled.',
      null,
    ],
    <String?>[
      'inst_ll_dump',
      '<path>',
      'Writes LL band snapshots (JSON) using <path> as the filename prefix.',
      null,
    ],
    <String?>[
      'inst_ll_tile_index',
      '<index>',
      'Tile index used for LL snapshots (default 0).',
      '0',
    ],
    <String?>[
      'inst_ll_component',
      '<index>',
      'Component index used for LL snapshots (default 0).',
      '0',
    ],
    <String?>[
      'inst_ll_stage',
      '[pre|post|both]',
      'Stage where LL snapshots are captured (StdDequantizer, InvWTFull, or both).',
      'post',
    ],
  ];

  static final List<int> vprfxs = <int>[
    BitstreamReaderAgent.optPrefix.codeUnitAt(0),
    EntropyDecoder.optionPrefix.codeUnitAt(0),
    ROIDeScaler.optionPrefix.codeUnitAt(0),
    Dequantizer.optionPrefix.codeUnitAt(0),
    InvCompTransf.optionPrefix.codeUnitAt(0),
    HeaderDecoder.optionPrefix.codeUnitAt(0),
    ColorSpaceMapper.OPT_PREFIX.codeUnitAt(0),
  ];

  MsgLogger get _logger => FacilityManager.getMsgLogger();

  static List<List<String?>> getParameterInfo() => pinfo;

  /// Builds a ParameterList populated with this decoder's default option values.
  static ParameterList buildDefaultParameterList() {
    final defaults = ParameterList();
    for (final option in pinfo) {
      if (option.isEmpty) {
        continue;
      }
      final name = option[0];
      if (name == null || name.isEmpty) {
        continue;
      }
      final hasDefault = option.length > 3;
      if (!hasDefault) {
        continue;
      }
      final defaultValue = option[3];
      if (defaultValue == null || defaultValue.isEmpty) {
        continue;
      }
      defaults.put(name, defaultValue);
    }
    return defaults;
  }

  @override
  void run() {
    try {
      _runInternal();
    } on StringFormatException catch (error, stackTrace) {
      _error('Invalid arguments: ${error.message}', 1, error, stackTrace);
    } on IOException catch (error, stackTrace) {
      _error('I/O error: $error', 2, error, stackTrace);
    } on Exception catch (error, stackTrace) {
      _error('Unexpected error: $error', 3, error, stackTrace);
    }
  }

  void _runInternal() {
    pl.checkList(vprfxs, ParameterList.toNameArray(pinfo));

    var instrumentationEnabled = false;
    final instrumentValue = pl.getParameter('instrument');
    if (instrumentValue != null) {
      instrumentationEnabled = pl.getBooleanParameter('instrument');
    }
    DecoderInstrumentation.configure(instrumentationEnabled);
    if (instrumentationEnabled) {
      DecoderInstrumentation.log('Decoder', 'Instrumentation enabled');
    }

    _traceFilter = _parseTraceFilter(pl.getParameter('inst_block'));
    _initialiseMqTraceSink(pl.getParameter('inst_mq_log'));
    _configureLlSnapshotOptions();

    if (pl.getParameter('u') == 'on') {
      _printUsage();
      exitCode = 0;
      return;
    }

    if (pl.getParameter('v') == 'on') {
      _printVersion();
    }

    final inputPath = pl.getParameter('i');
    if (inputPath == null || inputPath.isEmpty) {
      throw StateError("Input file ('-i') has not been specified");
    }

    final file = _openInput(inputPath);

    try {
      final ff = FileFormatReader(file);
      ff.readFileFormat();
      _jp2WrapperUsed = ff.JP2FFUsed;
      final codestreamOffset = ff.JP2FFUsed ? ff.getFirstCodeStreamPos() : 0;
      if (codestreamOffset > 0) {
        file.seek(codestreamOffset);
      }

      _logger.printmsg(MsgLogger.info,
          'JP2 wrapper: ${ff.JP2FFUsed ? 'present' : 'absent'}');

      headerDecoder = HeaderDecoder.readMainHeader(
        input: file,
        headerInfo: hi,
      );
      final decoder = headerDecoder!;
      decSpec = decoder.decSpec;

      _logger.printmsg(
        MsgLogger.info,
        'Parsed codestream main header: ${decoder.getNumComps()} component(s), '
        '${decoder.getImgWidth()}x${decoder.getImgHeight()} image.',
      );

      var tilePartCount = 0;
      final tilePartPerTile = <int, int>{};

      while (true) {
        final start = file.getPos();
        try {
          final sot = decoder.parseNextTilePart(file);
          tilePartCount++;
          tilePartPerTile[sot.isot] = (tilePartPerTile[sot.isot] ?? 0) + 1;

          final bodyLength = decoder.getTilePartBodyLength(sot.isot, sot.tpsot);
          final offset = decoder.getTilePartDataOffset(sot.isot, sot.tpsot);
          _logger.printmsg(
            MsgLogger.info,
            'Tile ${sot.isot} part ${sot.tpsot} Psot=${sot.psot} body=${bodyLength ?? -1} offset=${offset ?? -1}',
          );

          final psot = sot.psot;
          if (psot == 0) {
            _logger.printmsg(
              MsgLogger.warning,
              'Tile-part length unknown (Psot=0) for tile=${sot.isot} part=${sot.tpsot}; '
              'stopping tile scan after headers.',
            );
            break;
          }

          final expectedEnd = start + psot;
          if (expectedEnd < file.getPos()) {
            _logger.printmsg(
              MsgLogger.warning,
              'Tile-part length shorter than parsed header for tile=${sot.isot} part=${sot.tpsot}; '
              'aborting tile scan.',
            );
            break;
          }
          if (expectedEnd > file.length()) {
            _logger.printmsg(
              MsgLogger.warning,
              'Tile-part length exceeds codestream bounds for tile=${sot.isot} part=${sot.tpsot}; '
              'stopping at end of stream.',
            );
            file.seek(file.length());
            break;
          }

          file.seek(expectedEnd);
        } on StateError catch (error) {
          final message = error.message;
          if (message.contains(
              'Reached end of codestream before encountering tile-part header')) {
            break;
          }
          rethrow;
        }
      }

      if (tilePartCount == 0) {
        _logger.printmsg(MsgLogger.info, 'No tile-part headers encountered.');
      } else {
        final summaries = tilePartPerTile.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final entry in summaries) {
          _logger.printmsg(
            MsgLogger.info,
            'Tile ${entry.key} has ${entry.value} tile-part header(s).',
          );
        }
        _logger.printmsg(
            MsgLogger.info, 'Parsed $tilePartCount tile-part header(s).');
      }

      _initialiseCodestreamPipeline(file, decoder);
      if (_captureLlPost && _llSnapshotBasePath != null) {
        _capturePostLlSnapshot();
      }
      _executeOutputStage();
    } finally {
      if (_codestream != null) {
        dispose();
      } else {
        file.close();
      }
    }
  }

  RandomAccessIO _openInput(String pathOrUrl) {
    // Networking support is deferred; the current implementation only accepts
    // file system paths.
    final file = File(pathOrUrl);
    if (!file.existsSync()) {
      throw FileSystemException('Input file not found', pathOrUrl);
    }
    return BEBufferedRandomAccessFile.path(pathOrUrl, 'r');
  }

  void _initialiseCodestreamPipeline(
      RandomAccessIO input, HeaderDecoder decoder) {
    if (decSpec == null) {
      throw StateError(
          'Decoder specifications unavailable when initialising codestream pipeline');
    }

    _codestream = input;
    final emitCodestreamInfo = _getBooleanOption(pl, 'cdstr_info', false);
    bitstreamReader = BitstreamReaderAgent.createInstance(
      input,
      decoder,
      pl,
      decSpec!,
      emitCodestreamInfo,
      hi,
    );

    final entropyParams =
        _subsetParametersByPrefix(pl, EntropyDecoder.optionPrefix);
    entropyDecoder =
        decoder.createEntropyDecoder(bitstreamReader!, entropyParams);
    _logger.printmsg(
      MsgLogger.info,
      'Instantiated entropy decoder for ${decoder.getNumComps()} component(s).',
    );
    entropyDecoder?.configureDebug(
      traceFilter: _traceFilter,
      mqTraceSink: _mqTraceSink == null ? null : (line) => _mqTraceSink!.writeln(line),
    );

    final roiParams = _subsetParametersByPrefix(pl, ROIDeScaler.optionPrefix);
    roiDeScaler = decoder.createROIDeScaler(entropyDecoder!, roiParams);
    _logger.printmsg(
      MsgLogger.info,
      'Instantiated ROI de-scaler wrapper.',
    );

    final rangeBits = List<int>.generate(
      decoder.getNumComps(),
      decoder.getOriginalBitDepth,
      growable: false,
    );
    dequantizer = decoder.createDequantizer(roiDeScaler!, rangeBits);
    _logger.printmsg(
      MsgLogger.info,
      'Instantiated dequantizer using StdDequantizer.',
    );
    if (_captureLlPre && _llSnapshotBasePath != null) {
      dequantizer?.configureLlSnapshot(
        tileIndex: _llSnapshotTileIndex,
        component: _llSnapshotComponent,
        onSnapshot: (snapshot) => _writeLlSnapshot(snapshot, suffix: 'pre'),
      );
    }

    inverseWT = InverseWT.createInstance(dequantizer!, decSpec!);
    _logger.printmsg(
      MsgLogger.info,
      'Instantiated inverse wavelet transform.',
    );

    final targetResolution = bitstreamReader?.getImgRes() ?? 0;
    inverseWT!.setImgResLevel(targetResolution);
    _logger.printmsg(
      MsgLogger.info,
      'Configured inverse wavelet transform for resolution level $targetResolution.',
    );

    final initialFixedPoint = inverseWT!.getFixedPoint(0);
    imageDataConverter = ImgDataConverter(
      inverseWT!,
      initialFixedPoint,
      'core-img-data-converter',
    );
    _logger.printmsg(
      MsgLogger.info,
      'Instantiated image data converter (fixed-point=$initialFixedPoint).',
    );

    final componentTransformEnabled = _getBooleanOption(pl, 'comp_transf', true);
    if (decSpec!.cts.isCompTransfUsed()) {
      componentTransformer = InvCompTransfImgDataSrc(
        imageDataConverter!,
        decSpec!.cts,
        enableComponentTransforms: componentTransformEnabled,
      );
      final transform = decSpec!.cts.getSpec(0, 0) ?? InvCompTransf.none;
      final label = transform == InvCompTransf.invRct
          ? 'RCT'
          : (transform == InvCompTransf.invIct ? 'ICT' : 'custom');
      _logger.printmsg(
        MsgLogger.info,
        'Instantiated inverse component transform ($label)${componentTransformEnabled ? '' : ' [disabled via comp_transf=off]'}.',
      );
    }

    BlkImgDataSrc? pipelineSource;
    if (componentTransformer != null) {
      pipelineSource = componentTransformer;
    } else if (imageDataConverter != null) {
      pipelineSource = imageDataConverter;
    } else if (inverseWT != null) {
      pipelineSource = inverseWT;
    }

    _colorSpace = null;
    _resetColorPipelineStages();
    if (_shouldApplyColorSpace() && pipelineSource != null) {
      _logger.printmsg(
        MsgLogger.info,
        'JP2 colour metadata present; configuring colour pipeline.',
      );
      final colourSpace = _loadColorSpace(input, decoder);
      _colorSpace = colourSpace;

        var colourPipelineSource = pipelineSource;
        _channelDefinitionMapper =
          decoder.createChannelDefinitionMapper(colourPipelineSource, colourSpace);
        colourPipelineSource = _channelDefinitionMapper!;
      _logger.printmsg(
        MsgLogger.info,
        'Instantiated channel definition mapper.',
      );

      _resamplerStage = decoder.createResampler(colourPipelineSource, colourSpace);
      colourPipelineSource = _resamplerStage!;
      _logger.printmsg(
        MsgLogger.info,
        'Instantiated component resampler.',
      );

      if (colourSpace.isPalettized()) {
        final paletteInputComponents = colourPipelineSource.getNumComps();
        if (paletteInputComponents != 1) {
          _logger.printmsg(
            MsgLogger.warning,
            'Palette box present but pipeline has $paletteInputComponents component(s); skipping palette mapper.',
          );
          _palettizedMapper = null;
        } else {
          _palettizedMapper = decoder.createPalettizedColorSpaceMapper(
            colourPipelineSource,
            colourSpace,
          );
          colourPipelineSource = _palettizedMapper!;
          _logger.printmsg(
            MsgLogger.info,
            'Instantiated palette mapper.',
          );
        }
      } else {
        _palettizedMapper = null;
      }

      final mapped = decoder.createColorSpaceMapper(colourPipelineSource, colourSpace);
      if (mapped != null) {
        _colorSpaceMapperStage = mapped;
        colourPipelineSource = _colorSpaceMapperStage!;
        _logger.printmsg(
          MsgLogger.info,
          'Instantiated colour space mapper (${mapped.runtimeType}).',
        );
      } else {
        _colorSpaceMapperStage = null;
        _logger.printmsg(
          MsgLogger.info,
          'No enumerated/ICC color space mapper required.',
        );
      }

      pipelineSource = colourPipelineSource;

      if (colourSpace.debugging()) {
        _logger.printmsg(MsgLogger.info, '$colourSpace');
        if (_channelDefinitionMapper != null) {
          _logger.printmsg(MsgLogger.info, '$_channelDefinitionMapper');
        }
        if (_resamplerStage != null) {
          _logger.printmsg(MsgLogger.info, '$_resamplerStage');
        }
        if (_palettizedMapper != null) {
          _logger.printmsg(MsgLogger.info, '$_palettizedMapper');
        }
        if (_colorSpaceMapperStage != null) {
          _logger.printmsg(MsgLogger.info, '$_colorSpaceMapperStage');
        }
      }
    }

    if (pipelineSource != null) {
      writerDataConverter = ImgDataConverter(
        pipelineSource,
        0,
        'writer-img-data-converter',
      );
      _logger.printmsg(
        MsgLogger.info,
        'Instantiated writer data converter (ensuring integer samples).',
      );
    }

    _ensureWaveletFilters();
  }

  void _executeOutputStage() {
    final outputPath = pl.getParameter('o');
    if (outputPath == null || outputPath.isEmpty) {
      _logger.printmsg(
        MsgLogger.info,
        'No output filename specified; skipping raster export.',
      );
      return;
    }

    final writer = _createWriter(outputPath);
    try {
      _logger.printmsg(
        MsgLogger.info,
        'Writing decoded image to $outputPath (${writer.runtimeType}).',
      );
      writer.writeAll();
      writer.flush();
      _logger.printmsg(
        MsgLogger.info,
        'Completed writing $outputPath.',
      );
    } finally {
      writer.close();
    }
  }

  ImgWriter _createWriter(String outputPath) {
    final source = imageDataSource;
    if (source == null) {
      throw StateError('Image data source not initialised; cannot write output.');
    }

    final lower = outputPath.toLowerCase();
    if (lower.endsWith('.ppm')) {
      const requiredComponents = 3;
      if (source.getNumComps() < requiredComponents) {
        throw StateError(
          'PPM output expects at least $requiredComponents components; '
          'decoder produced ${source.getNumComps()}.',
        );
      }
      for (var c = 0; c < requiredComponents; c++) {
        final rangeBits = source.getNomRangeBits(c);
        if (rangeBits > 8) {
          throw StateError(
            'Component $c has $rangeBits-bit samples; PPM writer only supports up to 8 bits.',
          );
        }
        if (_isComponentSigned(source, c)) {
          throw StateError(
            'Component $c is signed; PPM writer expects unsigned samples.',
          );
        }
      }
      return ImgWriterPpm.fromPath(outputPath, source, 0, 1, 2);
    }

    if (lower.endsWith('.pgm')) {
      if (source.getNumComps() == 0) {
        throw StateError('Decoded image has no components to export.');
      }
      // For multi-component codestreams we match JJ2000 behaviour: emit one
      // file per component with a numeric suffix.
      if (source.getNumComps() == 1) {
        return ImgWriterPgm.fromPath(outputPath, source, 0);
      }
      final writers = <ImgWriter>[];
      for (var c = 0; c < source.getNumComps(); c++) {
        writers.add(
          ImgWriterPgm.fromPath(
            _componentPath(outputPath, c),
            source,
            c,
          ),
        );
      }
      return CompositeImgWriter(writers);
    }

    if (lower.endsWith('.pgx')) {
      if (source.getNumComps() == 0) {
        throw StateError('Decoded image has no components to export.');
      }
      if (source.getNumComps() == 1) {
        return ImgWriterPgx.fromPath(
          outputPath,
          source,
          0,
          _isComponentSigned(source, 0),
        );
      }
      final writers = <ImgWriter>[];
      for (var c = 0; c < source.getNumComps(); c++) {
        writers.add(
          ImgWriterPgx.fromPath(
            _componentPath(outputPath, c),
            source,
            c,
            _isComponentSigned(source, c),
          ),
        );
      }
      return CompositeImgWriter(writers);
    }

    if (lower.endsWith('.bmp')) {
      if (source.getNumComps() == 0) {
        throw StateError('Decoded image has no components to export.');
      }
      if (source.getNumComps() == 1 || source.getNumComps() >= 3) {
        return ImgWriterBmp.fromPath(outputPath, source);
      }
      throw StateError(
        'BMP output requires one component (grayscale) or at least three components; '
        'decoder produced ${source.getNumComps()}.',
      );
    }

    throw UnsupportedError(
      'Output format for "$outputPath" is not supported yet. Supported extensions: .ppm, .pgm, .pgx, .bmp.',
    );
  }

  String _componentPath(String basePath, int componentIndex) {
    final dot = basePath.lastIndexOf('.');
    if (dot <= 0) {
      return '${basePath}_c${componentIndex + 1}';
    }
    final stem = basePath.substring(0, dot);
    final ext = basePath.substring(dot);
    return '$stem-${componentIndex + 1}$ext';
  }

  bool _isComponentSigned(BlkImgDataSrc source, int component) {
    if (componentTransformer != null) {
      // Component transforms produce unsigned output for ICT/RCT scenarios.
      return false;
    }
    if (_colorSpace != null) {
      return _colorSpace!.isOutputSigned(component);
    }
    if (headerDecoder == null) {
      return false;
    }
    return headerDecoder!.isOriginalSigned(component);
  }

  void _resetColorPipelineStages() {
    _channelDefinitionMapper = null;
    _resamplerStage = null;
    _palettizedMapper = null;
    _colorSpaceMapperStage = null;
  }

  bool _shouldApplyColorSpace() {
    final toggle = pl.getParameter('nocolorspace');
    final disabled = toggle != null && toggle.toLowerCase() == 'on';
    return _jp2WrapperUsed && !disabled;
  }

  ColorSpace _loadColorSpace(RandomAccessIO input, HeaderDecoder decoder) {
    final bookmark = input.getPos();
    try {
      return ColorSpace(input, decoder, pl);
    } finally {
      input.seek(bookmark);
    }
  }

  void _ensureWaveletFilters() {
    final specs = decSpec;
    if (specs == null) {
      return;
    }

    final filtersSpec = specs.wfs;
    final tiles = filtersSpec.nTiles;
    final components = filtersSpec.nComp;

    for (var tile = 0; tile < tiles; tile++) {
      for (var component = 0; component < components; component++) {
        var filters = filtersSpec.getTileCompVal(tile, component);
        if (filters != null) {
          continue;
        }

        final levels = specs.dls.getTileCompVal(tile, component) ?? 0;
        final reversible = specs.qts.isReversible(tile, component);
        filters = _createDefaultFilters(levels, reversible);
        filtersSpec.setTileCompVal(tile, component, filters);
      }
    }
  }

  List<List<SynWTFilter>> _createDefaultFilters(int decompositionLevels, bool reversible) {
    final levelCount = decompositionLevels <= 0 ? 0 : decompositionLevels;
    if (levelCount == 0) {
      return <List<SynWTFilter>>[
        List<SynWTFilter>.empty(growable: false),
        List<SynWTFilter>.empty(growable: false),
      ];
    }

    SynWTFilter _factory() =>
        reversible ? SynWTFilterIntLift5x3() : SynWTFilterFloatLift9x7();

    final horizontal =
        List<SynWTFilter>.generate(levelCount, (_) => _factory(), growable: false);
    final vertical =
        List<SynWTFilter>.generate(levelCount, (_) => _factory(), growable: false);
    return <List<SynWTFilter>>[horizontal, vertical];
  }
  ParameterList _subsetParametersByPrefix(ParameterList source, String prefix) {
    ParameterList? filteredDefaults;
    final defaults = source.getDefaultParameterList();
    if (defaults != null) {
      final candidate = _subsetParametersByPrefix(defaults, prefix);
      if (!_parameterListIsEmpty(candidate)) {
        filteredDefaults = candidate;
      }
    }

    final subset = ParameterList(filteredDefaults);
    if (prefix.isEmpty) {
      return subset;
    }

    final prefixCode = prefix.codeUnitAt(0);
    for (final name in source.propertyNames()) {
      if (name.isEmpty || name.codeUnitAt(0) != prefixCode) {
        continue;
      }
      final value = source.getParameter(name);
      if (value != null) {
        subset.put(name, value);
      }
    }
    return subset;
  }

  bool _parameterListIsEmpty(ParameterList list) {
    for (final _ in list.propertyNames()) {
      return false;
    }
    return true;
  }

  bool _getBooleanOption(ParameterList list, String name, bool fallback) {
    final raw = list.getParameter(name);
    if (raw == null) {
      return fallback;
    }
    if (raw == 'on') {
      return true;
    }
    if (raw == 'off') {
      return false;
    }
    throw StringFormatException('Parameter "$name" is not boolean: $raw');
  }

  /// Releases the codestream resources attached to this decoder.
  void dispose() {
    try {
      _mqTraceSink?.close();
    } finally {
      _mqTraceSink = null;
    }
    try {
      _codestream?.close();
    } finally {
      _codestream = null;
    }
  }

  void _initialiseMqTraceSink(String? path) {
    if (path == null || path.isEmpty) {
      _mqTraceSink = null;
      return;
    }
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      _mqTraceSink = file.openWrite(mode: FileMode.write)
        ..writeln('# MQ trace generated ${DateTime.now().toUtc().toIso8601String()}');
      _logger.printmsg(MsgLogger.info, 'Writing MQ traces to ${file.path}.');
    } on IOException catch (error) {
      _logger.printmsg(
        MsgLogger.warning,
        'Unable to open MQ trace log "$path": $error',
      );
      _mqTraceSink = null;
    }
  }

  TraceBlockFilter? _parseTraceFilter(String? spec) {
    if (spec == null || spec.trim().isEmpty) {
      return null;
    }
    final parts = spec.split(',');
    if (parts.length != 6) {
      _logger.printmsg(
        MsgLogger.warning,
        'inst_block expects 6 comma-separated integers; received "$spec".',
      );
      return null;
    }

    int? parseToken(String token) {
      final trimmed = token.trim();
      if (trimmed.isEmpty || trimmed == '-1') {
        return null;
      }
      final value = int.tryParse(trimmed);
      if (value == null) {
        _logger.printmsg(
          MsgLogger.warning,
          'Unable to parse inst_block token "$trimmed"; ignoring filter.',
        );
      }
      return value;
    }

    final tileIndex = parseToken(parts[0]);
    final component = parseToken(parts[1]);
    final resLevel = parseToken(parts[2]);
    final band = parseToken(parts[3]);
    final cblkY = parseToken(parts[4]);
    final cblkX = parseToken(parts[5]);
    return TraceBlockFilter(
      tileIndex: tileIndex,
      component: component,
      resolutionLevel: resLevel,
      band: band,
      cblkY: cblkY,
      cblkX: cblkX,
    );
  }

  void _configureLlSnapshotOptions() {
    final base = pl.getParameter('inst_ll_dump');
    if (base == null || base.isEmpty) {
      _llSnapshotBasePath = null;
      _captureLlPre = false;
      _captureLlPost = false;
      return;
    }

    _llSnapshotBasePath = base;
    _llSnapshotTileIndex =
        _parseIntOption(pl.getParameter('inst_ll_tile_index'), 0, 'inst_ll_tile_index');
    _llSnapshotComponent =
        _parseIntOption(pl.getParameter('inst_ll_component'), 0, 'inst_ll_component');

    final stage = (pl.getParameter('inst_ll_stage') ?? 'post').toLowerCase();
    switch (stage) {
      case 'pre':
        _captureLlPre = true;
        _captureLlPost = false;
        break;
      case 'both':
        _captureLlPre = true;
        _captureLlPost = true;
        break;
      case 'post':
      default:
        _captureLlPre = false;
        _captureLlPost = true;
        break;
    }

    _logger.printmsg(
      MsgLogger.info,
      'LL snapshot capture configured (tileIndex=$_llSnapshotTileIndex, '
      'component=$_llSnapshotComponent, stages=${_captureLlPre && _captureLlPost ? 'both' : (_captureLlPre ? 'pre' : 'post')}).',
    );
  }

  int _parseIntOption(String? raw, int fallback, String optionName) {
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final value = int.tryParse(raw);
    if (value == null) {
      _logger.printmsg(
        MsgLogger.warning,
        'Parameter "$optionName" expected an integer but received "$raw"; using $fallback.',
      );
      return fallback;
    }
    return value;
  }

  void _capturePostLlSnapshot() {
    if (_llSnapshotBasePath == null || !_captureLlPost || _llPostSnapshotWritten) {
      return;
    }
    final inv = inverseWT;
    if (inv == null) {
      _logger.printmsg(
        MsgLogger.warning,
        'Cannot capture LL snapshot: inverse wavelet transform not initialised.',
      );
      return;
    }
    final totalTiles = inv.getNumTiles();
    if (_llSnapshotTileIndex < 0 || _llSnapshotTileIndex >= totalTiles) {
      _logger.printmsg(
        MsgLogger.warning,
        'LL snapshot tile index $_llSnapshotTileIndex outside available tile range ($totalTiles).',
      );
      return;
    }

    final tilesCoord = inv.getNumTilesCoord(null);
    final tilesX = tilesCoord.x <= 0 ? 1 : tilesCoord.x;
    final tileX = _llSnapshotTileIndex % tilesX;
    final tileY = _llSnapshotTileIndex ~/ tilesX;
    inv.setTile(tileX, tileY);
    final tileIdx = inv.getTileIdx();
    final width = inv.getTileCompWidth(tileIdx, _llSnapshotComponent);
    final height = inv.getTileCompHeight(tileIdx, _llSnapshotComponent);
    if (width <= 0 || height <= 0) {
      _logger.printmsg(
        MsgLogger.warning,
        'LL snapshot skipped: resolved tile has non-positive dimensions ($width x $height).',
      );
      return;
    }

    final reversible = inv.isReversible(tileIdx, _llSnapshotComponent);
    final DataBlk block = reversible
        ? DataBlkInt.withGeometry(0, 0, width, height)
        : DataBlkFloat.withGeometry(0, 0, width, height);
    final filled = inv.getCompData(block, _llSnapshotComponent);
    final snapshot = _buildLlSnapshot(
      filled,
      tileIdx: tileIdx,
      tileX: tileX,
      tileY: tileY,
    );
    _writeLlSnapshot(snapshot, suffix: 'post');
    _llPostSnapshotWritten = true;
  }

  Map<String, dynamic> _buildLlSnapshot(
    DataBlk block, {
    required int tileIdx,
    required int tileX,
    required int tileY,
  }) {
    final width = block.w;
    final height = block.h;
    final scanw = block.scanw == 0 ? width : block.scanw;
    final offset = block.offset;
    final data = block.getData();
    final values = List<num>.filled(width * height, 0, growable: false);
    var cursor = 0;

    void copyList(List<num> source) {
      for (var row = 0; row < height; row++) {
        final base = offset + row * scanw;
        for (var col = 0; col < width; col++) {
          values[cursor++] = source[base + col];
        }
      }
    }

    if (data is Float32List) {
      copyList(data); // Float32List implements List<num> via List<double>.
    } else if (data is List<int>) {
      for (var row = 0; row < height; row++) {
        final base = offset + row * scanw;
        for (var col = 0; col < width; col++) {
          values[cursor++] = data[base + col];
        }
      }
    } else if (data is List<double>) {
      copyList(data);
    } else {
      _logger.printmsg(
        MsgLogger.warning,
        'Unknown LL snapshot buffer type ${data.runtimeType}; values may be empty.',
      );
    }

    return <String, dynamic>{
      'tileIndex': tileIdx,
      'tileX': tileX,
      'tileY': tileY,
      'component': _llSnapshotComponent,
      'width': width,
      'height': height,
      'dataType': block.getDataType() == DataBlk.typeFloat ? 'float' : 'int',
      'values': values,
    };
  }

  void _writeLlSnapshot(Map<String, dynamic> snapshot, {required String suffix}) {
    final base = _llSnapshotBasePath;
    if (base == null || base.isEmpty) {
      return;
    }
    final path = _snapshotPathForSuffix(base, suffix);
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final encoder = const JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(snapshot));
      _logger.printmsg(MsgLogger.info, 'Wrote LL $suffix snapshot to ${file.path}.');
    } on IOException catch (error) {
      _logger.printmsg(
        MsgLogger.warning,
        'Failed to write LL $suffix snapshot to "$path": $error',
      );
    }
  }

  String _snapshotPathForSuffix(String base, String suffix) {
    if (base.toLowerCase().endsWith('.json')) {
      final stem = base.substring(0, base.length - 5);
      return '${stem}_$suffix.json';
    }
    return '${base}_$suffix.json';
  }

  void _printUsage() {
    final buffer = StringBuffer('JPEG 2000 decoder options:\n');
    for (final option in pinfo) {
      buffer.writeln(
          ' -${option[0]} : ${option[1]}\n    ${option[2]} (default: ${option[3]})');
    }
    _logger.println(buffer.toString(), 0, 2);
  }

  void _printVersion() {
    _logger.printmsg(
        MsgLogger.info, 'JJ2000 Decoder (Dart port) - preview build');
  }

  void _error(String message, int code, Object? error, StackTrace? stackTrace) {
    exitCode = code;
    _logger.printmsg(MsgLogger.error, message);
    if (pl.getParameter('debug') == 'on' && stackTrace != null) {
      _logger.printmsg(MsgLogger.error, stackTrace.toString());
    }
  }
}

/// Matches java.lang.Runnable so the decoder can be scheduled by utilities.
abstract class Runnable {
  void run();
}


import 'dart:typed_data';

import '../colorspace/boxes/channel_definition_box.dart';
import '../colorspace/color_space.dart';
import '../colorspace/color_space_mapper.dart';
import '../j2k/codestream/header_info.dart';
import '../j2k/codestream/markers.dart';
import '../j2k/codestream/reader/bitstream_reader_agent.dart';
import '../j2k/codestream/reader/header_decoder.dart';
import '../j2k/codestream/writer/header_encoder.dart';
import '../j2k/codestream/writer/pkt_encoder.dart';
import '../j2k/decoder/decoder_specs.dart';
import '../j2k/encoder/encoder_specs.dart';
import '../j2k/entropy/decoder/entropy_decoder.dart';
import '../j2k/entropy/encoder/entropy_coder.dart';
import '../j2k/entropy/encoder/post_comp_rate_allocator.dart';
import '../j2k/fileformat/file_format_boxes.dart';
import '../j2k/fileformat/file_format_reader.dart';
import '../j2k/image/blk_img_data_src.dart';
import '../j2k/image/data_blk_int.dart';
import '../j2k/image/forwcomptransf/forw_comp_transf.dart';
import '../j2k/image/img_data_converter.dart';
import '../j2k/image/input/img_reader.dart';
import '../j2k/image/invcomptransf/inv_component_transformer.dart';
import '../j2k/image/tiler.dart';
import '../j2k/io/exceptions.dart';
import '../j2k/platform/platform.dart' as platform;
import '../j2k/quantization/quantizer/quantizer.dart';
import '../j2k/roi/encoder/roi_scaler.dart';
import '../j2k/roi/roi_de_scaler.dart';
import '../j2k/util/facility_manager.dart';
import '../j2k/util/is_random_access_io.dart';
import '../j2k/util/msg_logger.dart';
import '../j2k/util/parameter_list.dart';
import '../j2k/wavelet/analysis/an_wt_filter.dart';
import '../j2k/wavelet/analysis/forward_wt.dart';
import '../j2k/wavelet/synthesis/inverse_wt.dart';
import '../j2k/wavelet/synthesis/syn_wt_filter.dart';
import '../j2k/wavelet/synthesis/syn_wt_filter_float_lift9x7.dart';
import '../j2k/wavelet/synthesis/syn_wt_filter_int_lift5x3.dart';
import '../jpeg2000_exceptions.dart';
import 'interleaved_memory_reader.dart';
import 'memory_codestream_writer.dart';
import 'pnm_parser.dart';

/// Channel layout of [Jpeg2000Image.pixels].
///
/// The sample width is a separate property, [Jpeg2000Image.bitsPerSample].
enum Jpeg2000PixelFormat {
  /// One luminance sample per pixel.
  gray,

  /// Luminance followed by alpha.
  grayAlpha,

  /// Red, green and blue.
  rgb,

  /// Red, green, blue and alpha.
  rgba,

  /// Every codestream component in order, with no colour interpretation.
  ///
  /// Used for CMYK, multispectral and other images whose colour channels are
  /// not one or three. [Jpeg2000Image.components] says how many there are.
  multiComponent,
}

/// Decoded interleaved pixels.
///
/// Samples are unsigned, row-major and tightly packed: pixel `(x, y)` starts
/// at sample index `(y * width + x) * components`. They are 8 bits wide by
/// default and 16 bits wide when [Jpeg2000DecodeOptions.outputBitDepth] asks
/// for it; [bitsPerSample] says which. Sources with a different depth are
/// rescaled, and the original depth is kept in [sourceBitsPerComponent].
class Jpeg2000Image {
  /// Creates a decoded image; normally produced by [decodeJpeg2000].
  Jpeg2000Image({
    required this.width,
    required this.height,
    required this.components,
    required this.colorComponents,
    required this.hasAlpha,
    required this.alphaIsPremultiplied,
    required this.sourceBitsPerComponent,
    required this.bitsPerSample,
    required this.pixels,
    required this.format,
  }) {
    if (bitsPerSample != 8 && bitsPerSample != 16) {
      throw ArgumentError.value(
        bitsPerSample,
        'bitsPerSample',
        'must be 8 or 16',
      );
    }
    final expected = width * height * components * (bitsPerSample ~/ 8);
    if (pixels.length != expected) {
      throw ArgumentError(
        'pixels holds ${pixels.length} bytes; ${width}x$height with '
        '$components channel(s) at $bitsPerSample bits needs $expected.',
      );
    }
  }

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Number of interleaved channels per pixel, alpha included.
  final int components;

  /// Number of colour channels: 1 for gray, 3 for RGB, or every channel for
  /// [Jpeg2000PixelFormat.multiComponent].
  final int colorComponents;

  /// Whether the last channel of every pixel is alpha.
  final bool hasAlpha;

  /// Whether the colour channels were stored already multiplied by alpha.
  ///
  /// Comes from the JP2 channel definition box (`cdef` type 2). Always false
  /// when [hasAlpha] is false.
  final bool alphaIsPremultiplied;

  /// Bit depth of each output channel in the codestream, in output order.
  final List<int> sourceBitsPerComponent;

  /// Width of every sample in [pixels]: 8 or 16.
  final int bitsPerSample;

  /// The sample bytes.
  ///
  /// With [bitsPerSample] 8 each byte is one sample. With 16 the buffer holds
  /// host-endian 16-bit samples and [pixels16] is the typed view of it.
  final Uint8List pixels;

  /// How to interpret the channels.
  final Jpeg2000PixelFormat format;

  /// [pixels] as 16-bit samples; only valid when [bitsPerSample] is 16.
  Uint16List get pixels16 {
    if (bitsPerSample != 16) {
      throw StateError('pixels16 needs bitsPerSample 16, got $bitsPerSample.');
    }
    return Uint16List.view(
      pixels.buffer,
      pixels.offsetInBytes,
      pixels.length ~/ 2,
    );
  }

  /// Bytes from one row to the next.
  int get rowStride => width * components * (bitsPerSample ~/ 8);

  @override
  String toString() => 'Jpeg2000Image(${width}x$height, $format, '
      'components=$components, bits=$bitsPerSample, alpha=$hasAlpha)';
}

/// What [probeJpeg2000] learns from the headers without decoding any pixel.
class Jpeg2000Info {
  /// Creates a header summary; normally produced by [probeJpeg2000].
  const Jpeg2000Info({
    required this.isJp2,
    required this.width,
    required this.height,
    required this.components,
    required this.colorComponents,
    required this.hasAlpha,
    required this.alphaIsPremultiplied,
    required this.bitsPerComponent,
    required this.isSigned,
    required this.subsamplingX,
    required this.subsamplingY,
    required this.tileWidth,
    required this.tileHeight,
    required this.tileColumns,
    required this.tileRows,
    required this.pixelFormat,
  });

  /// True for a JP2 container, false for a raw codestream.
  final bool isJp2;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Number of components in the codestream.
  final int components;

  /// Number of colour channels [decodeJpeg2000] would return.
  final int colorComponents;

  /// Whether [decodeJpeg2000] would return an alpha channel.
  final bool hasAlpha;

  /// Whether that alpha is premultiplied according to the `cdef` box.
  final bool alphaIsPremultiplied;

  /// Bit depth of each codestream component.
  final List<int> bitsPerComponent;

  /// Whether each codestream component is signed.
  final List<bool> isSigned;

  /// Horizontal subsampling factor of each codestream component.
  final List<int> subsamplingX;

  /// Vertical subsampling factor of each codestream component.
  final List<int> subsamplingY;

  /// Nominal tile width.
  final int tileWidth;

  /// Nominal tile height.
  final int tileHeight;

  /// Number of tile columns.
  final int tileColumns;

  /// Number of tile rows.
  final int tileRows;

  /// The layout [decodeJpeg2000] would produce with default options.
  final Jpeg2000PixelFormat pixelFormat;

  /// Total pixel count, `width * height`.
  int get pixelCount => width * height;

  /// Largest bit depth among the components.
  int get maxBitsPerComponent =>
      bitsPerComponent.fold(0, (max, bits) => bits > max ? bits : max);

  @override
  String toString() => 'Jpeg2000Info(${width}x$height, '
      'components=$components, $pixelFormat, jp2=$isJp2)';
}

/// Options for [decodeJpeg2000].
class Jpeg2000DecodeOptions {
  /// Creates decode options; every field has a safe default.
  const Jpeg2000DecodeOptions({
    this.applyColorSpace = true,
    this.applyComponentTransform = true,
    this.rate,
    this.bytes,
    this.resolution,
    this.parsing = true,
    this.outputBitDepth = 8,
    this.maxPixels,
    this.maxDimension,
    this.onWarning,
  });

  /// Apply the JP2 colour metadata (enumerated colour space, ICC profile,
  /// palette, channel definitions). Ignored for raw codestreams.
  final bool applyColorSpace;

  /// Apply the inverse multiple-component transform (RCT/ICT) signalled in
  /// the codestream. Turning it off returns the transformed components.
  final bool applyComponentTransform;

  /// Stop decoding once this many bits per pixel have been read.
  ///
  /// Mutually exclusive with [bytes]. Null decodes everything.
  final double? rate;

  /// Stop decoding once this many codestream bytes have been read.
  ///
  /// Mutually exclusive with [rate]. Null decodes everything.
  final int? bytes;

  /// Number of highest resolution levels to discard. Null keeps them all.
  final int? resolution;

  /// Parse packet headers even when rate limiting truncates the stream.
  final bool parsing;

  /// Sample width of the result: 8 (default) or 16.
  ///
  /// Sources deeper than the output are shifted down; shallower ones are
  /// rescaled to the full output range, so an 8-bit 255 becomes 65535.
  final int outputBitDepth;

  /// Refuse images with more than this many pixels.
  ///
  /// Checked from the SIZ marker before anything is allocated. Null means no
  /// limit; callers that decode untrusted data should set one.
  final int? maxPixels;

  /// Refuse images whose width or height exceeds this value.
  ///
  /// Checked from the SIZ marker before anything is allocated. Null means no
  /// limit.
  final int? maxDimension;

  /// Receives non-fatal diagnostics, such as an ICC profile that had to be
  /// ignored. Null discards them; the codec never writes to the console.
  final void Function(String message)? onWarning;
}

/// Options for [encodeJpeg2000] and [encodeJpeg2000Pixels].
class Jpeg2000EncodeOptions {
  /// Creates encode options; the default is a lossless single-tile
  /// codestream.
  const Jpeg2000EncodeOptions({
    this.lossless = true,
    this.rate,
    this.wrapInJp2 = false,
    this.tileWidth = 0,
    this.tileHeight = 0,
    this.extraParameters = const <String, String>{},
  });

  /// Use the reversible 5x3 wavelet and no quantization.
  ///
  /// Mutually exclusive with [rate].
  final bool lossless;

  /// Target bit rate in bits per pixel for lossy encoding.
  ///
  /// Mutually exclusive with [lossless].
  final double? rate;

  /// Wrap the codestream in a JP2 container with colour metadata (greyscale
  /// or sRGB, plus a channel definition box when there is alpha); false
  /// returns the raw J2K codestream.
  final bool wrapInJp2;

  /// Nominal tile width; 0 uses a single tile.
  final int tileWidth;

  /// Nominal tile height; 0 uses a single tile.
  final int tileHeight;

  /// Raw JJ2000 encoder parameters (for example `Clayers`, `Cblksiz`,
  /// `Aptype`) applied after the typed options. Meant for experiments; the
  /// names and syntax are those of the original JJ2000 command line and are
  /// not part of the stable API.
  final Map<String, String> extraParameters;
}

/// Reads the headers of JP2 or raw J2K [bytes] without decoding pixels.
///
/// Use it to apply size policies before [decodeJpeg2000] allocates anything,
/// or to tell callers what layout to expect. Throws a [Jpeg2000Exception]
/// subtype for input problems.
Jpeg2000Info probeJpeg2000(Uint8List bytes) {
  return _guardDecode(null, () {
    final input = ISRandomAccessIO(bytes);
    try {
      final opened = _open(input);
      final siz = opened.siz;
      ColorSpace? colorSpace;
      if (opened.isJp2) {
        input.seek(opened.codestreamStart);
        final headerDecoder = HeaderDecoder.readMainHeader(
          input: input,
          headerInfo: HeaderInfo(),
        );
        colorSpace = _loadColorSpace(
          input,
          headerDecoder,
          _buildDecodeParameters(const Jpeg2000DecodeOptions()),
          required: false,
        );
      }
      final layout = _channelLayout(siz.components, colorSpace);
      return Jpeg2000Info(
        isJp2: opened.isJp2,
        width: siz.width,
        height: siz.height,
        components: siz.components,
        colorComponents: layout.colorComponents,
        hasAlpha: layout.alpha != null,
        alphaIsPremultiplied: layout.alphaIsPremultiplied,
        bitsPerComponent: List<int>.unmodifiable(siz.bitDepths),
        isSigned: List<bool>.unmodifiable(siz.signed),
        subsamplingX: List<int>.unmodifiable(siz.subsamplingX),
        subsamplingY: List<int>.unmodifiable(siz.subsamplingY),
        tileWidth: siz.tileWidth,
        tileHeight: siz.tileHeight,
        tileColumns: siz.tileColumns,
        tileRows: siz.tileRows,
        pixelFormat: layout.format,
      );
    } finally {
      input.close();
    }
  });
}

/// Decodes JP2 or raw J2K [bytes] into interleaved pixels.
///
/// Throws a [Jpeg2000Exception] subtype for input problems and an
/// [ArgumentError] for invalid [options].
Jpeg2000Image decodeJpeg2000(
  Uint8List bytes, {
  Jpeg2000DecodeOptions options = const Jpeg2000DecodeOptions(),
}) {
  _validateDecodeOptions(options);
  final params = _buildDecodeParameters(options);

  return _guardDecode(options.onWarning, () {
    final input = ISRandomAccessIO(bytes);
    try {
      final opened = _open(input);
      _checkBudget(opened.siz, options);

      final headerInfo = HeaderInfo();
      input.seek(opened.codestreamStart);
      final headerDecoder = HeaderDecoder.readMainHeader(
        input: input,
        headerInfo: headerInfo,
      );
      final decoderSpecs = headerDecoder.decSpec;
      _scanTileParts(input, headerDecoder);

      ColorSpace? colorSpace;
      if (opened.isJp2) {
        colorSpace = _loadColorSpace(
          input,
          headerDecoder,
          params,
          required: options.applyColorSpace,
        );
      }

      final source = _buildDecodePipeline(
        input: input,
        params: params,
        headerInfo: headerInfo,
        headerDecoder: headerDecoder,
        decoderSpecs: decoderSpecs,
        colorSpace: options.applyColorSpace ? colorSpace : null,
        applyComponentTransform: options.applyComponentTransform,
      );
      return _collectImage(
        source,
        headerDecoder,
        options.applyColorSpace ? colorSpace : null,
        options.outputBitDepth,
      );
    } finally {
      input.close();
    }
  });
}

/// Loads bytes with the platform abstraction and decodes them.
///
/// On the VM [source] may be bytes, `List<int>`, `dart:io` `File`, or a path.
/// In browsers it may be bytes or a `package:web` `Blob`/`File`.
Future<Jpeg2000Image> decodeJpeg2000Source(
  Object source, {
  Jpeg2000DecodeOptions options = const Jpeg2000DecodeOptions(),
}) async {
  final bytes = await platform.readBinarySource(source);
  return decodeJpeg2000(bytes, options: options);
}

/// Encodes binary PGM (P5) or PPM (P6) [pnmBytes] to raw J2K or JP2 bytes.
///
/// Maximum values up to 255 give 8-bit samples; up to 65535 give 16-bit
/// samples (two bytes each, most significant first). Throws an
/// [ArgumentError] when the PNM header is invalid or the options contradict
/// each other.
Uint8List encodeJpeg2000(
  Uint8List pnmBytes, {
  Jpeg2000EncodeOptions options = const Jpeg2000EncodeOptions(),
}) {
  final reader = parsePnm(pnmBytes);
  return _encodeWithReader(reader, options, hasAlpha: false);
}

/// Encodes interleaved, unsigned, tightly packed [samples] to raw J2K or JP2
/// bytes.
///
/// Sample `(x, y)` of component `c` is `samples[(y * width + x) * components
/// + c]`. Use a [Uint8List] for up to 8 bits per sample and a [Uint16List]
/// above that. With 2 or 4 components the last one is treated as alpha
/// unless [hasAlpha] says otherwise; the JP2 wrapper records that in a
/// channel definition box so decoders return it as alpha again. The
/// multiple-component transform applies to the first three components when
/// there are at least three.
Uint8List encodeJpeg2000Pixels(
  List<int> samples, {
  required int width,
  required int height,
  required int components,
  int bitsPerSample = 8,
  bool? hasAlpha,
  Jpeg2000EncodeOptions options = const Jpeg2000EncodeOptions(),
}) {
  final reader = InterleavedMemoryReader(
    samples,
    width: width,
    height: height,
    components: components,
    bitsPerSample: bitsPerSample,
  );
  final alpha = hasAlpha ?? (components == 2 || components == 4);
  if (alpha && components != 2 && components != 4) {
    throw ArgumentError(
      'hasAlpha needs 2 (gray+alpha) or 4 (RGB+alpha) components; '
      'got $components.',
    );
  }
  return _encodeWithReader(reader, options, hasAlpha: alpha);
}

/// Loads PNM bytes with the platform abstraction and encodes them.
///
/// On the VM [source] may be bytes, `List<int>`, `dart:io` `File`, or a path.
/// In browsers it may be bytes or a `package:web` `Blob`/`File`.
Future<Uint8List> encodeJpeg2000Source(
  Object source, {
  Jpeg2000EncodeOptions options = const Jpeg2000EncodeOptions(),
}) async {
  final bytes = await platform.readBinarySource(source);
  return encodeJpeg2000(bytes, options: options);
}

Uint8List _encodeWithReader(
  ImgReader reader,
  Jpeg2000EncodeOptions options, {
  required bool hasAlpha,
}) {
  final params = _buildEncodeParameters(options);
  try {
    final codestream = _encodeReader(reader, params, options);
    if (!options.wrapInJp2) {
      return codestream;
    }
    final bitsPerComponent = List<int>.generate(
      reader.getNumComps(),
      reader.getNomRangeBits,
      growable: false,
    );
    return _wrapJp2(
      codestream,
      width: reader.getImgWidth(),
      height: reader.getImgHeight(),
      components: reader.getNumComps(),
      bitsPerComponent: bitsPerComponent,
      hasAlpha: hasAlpha,
    );
  } finally {
    reader.close();
  }
}

// ---------------------------------------------------------------------------
// Error translation and logging
// ---------------------------------------------------------------------------

/// Runs [body] with warnings routed to [onWarning] and every internal failure
/// translated into the public exception hierarchy.
T _guardDecode<T>(void Function(String)? onWarning, T Function() body) {
  try {
    return FacilityManager.runWithLogger(_CallbackMsgLogger(onWarning), body);
  } on Jpeg2000Exception {
    rethrow;
  } on EOFException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      Jpeg2000TruncatedException(
        'Data ends before the codestream is complete.',
        cause: error,
      ),
      stackTrace,
    );
  } on UnsupportedError catch (error, stackTrace) {
    Error.throwWithStackTrace(
      Jpeg2000UnsupportedException(
        error.message ?? 'Unsupported JPEG 2000 feature.',
        cause: error,
      ),
      stackTrace,
    );
  } on StateError catch (error, stackTrace) {
    Error.throwWithStackTrace(
      Jpeg2000CorruptedException(error.message, cause: error),
      stackTrace,
    );
  } on ArgumentError catch (error, stackTrace) {
    // RangeError and IndexError included: inside the decoder they mean the
    // data pointed somewhere it should not have.
    Error.throwWithStackTrace(
      Jpeg2000CorruptedException(
        error.message?.toString() ?? 'Invalid value in codestream.',
        cause: error,
      ),
      stackTrace,
    );
  } on Exception catch (error, stackTrace) {
    Error.throwWithStackTrace(
      Jpeg2000CorruptedException(error.toString(), cause: error),
      stackTrace,
    );
  }
}

class _CallbackMsgLogger implements MsgLogger {
  const _CallbackMsgLogger(this.onWarning);

  final void Function(String)? onWarning;

  @override
  void printmsg(int severity, String message) {
    final callback = onWarning;
    if (callback == null || severity < MsgLogger.warning) {
      return;
    }
    callback(message);
  }

  @override
  void println(String message, int firstLineIndent, int indent) {}

  @override
  void flush() {}
}

void _validateDecodeOptions(Jpeg2000DecodeOptions options) {
  if (options.rate != null && options.bytes != null) {
    throw ArgumentError('rate and bytes are mutually exclusive.');
  }
  final rate = options.rate;
  if (rate != null && (rate.isNaN || rate <= 0)) {
    throw ArgumentError.value(rate, 'rate', 'must be positive');
  }
  final bytes = options.bytes;
  if (bytes != null && bytes <= 0) {
    throw ArgumentError.value(bytes, 'bytes', 'must be positive');
  }
  final resolution = options.resolution;
  if (resolution != null && resolution < 0) {
    throw ArgumentError.value(resolution, 'resolution', 'must not be negative');
  }
  if (options.outputBitDepth != 8 && options.outputBitDepth != 16) {
    throw ArgumentError.value(
      options.outputBitDepth,
      'outputBitDepth',
      'must be 8 or 16',
    );
  }
  final maxPixels = options.maxPixels;
  if (maxPixels != null && maxPixels <= 0) {
    throw ArgumentError.value(maxPixels, 'maxPixels', 'must be positive');
  }
  final maxDimension = options.maxDimension;
  if (maxDimension != null && maxDimension <= 0) {
    throw ArgumentError.value(maxDimension, 'maxDimension', 'must be positive');
  }
}

// ---------------------------------------------------------------------------
// Container and SIZ marker
// ---------------------------------------------------------------------------

/// Geometry read straight from the SIZ marker, before the full header parser
/// allocates its per-tile and per-component tables.
class _SizSummary {
  _SizSummary({
    required this.width,
    required this.height,
    required this.components,
    required this.bitDepths,
    required this.signed,
    required this.subsamplingX,
    required this.subsamplingY,
    required this.tileWidth,
    required this.tileHeight,
    required this.tileColumns,
    required this.tileRows,
  });

  final int width;
  final int height;
  final int components;
  final List<int> bitDepths;
  final List<bool> signed;
  final List<int> subsamplingX;
  final List<int> subsamplingY;
  final int tileWidth;
  final int tileHeight;
  final int tileColumns;
  final int tileRows;
}

({bool isJp2, int codestreamStart, _SizSummary siz}) _open(
  ISRandomAccessIO input,
) {
  final fileFormat = FileFormatReader(input)..readFileFormat();
  final isJp2 = fileFormat.jp2FfUsed;
  final codestreamStart = isJp2 ? fileFormat.getFirstCodeStreamPos() : 0;
  final siz = _readSizSummary(input, codestreamStart);
  input.seek(codestreamStart);
  return (isJp2: isJp2, codestreamStart: codestreamStart, siz: siz);
}

_SizSummary _readSizSummary(ISRandomAccessIO input, int codestreamStart) {
  input.seek(codestreamStart);
  if (input.readUnsignedShort() != Markers.soc) {
    throw const Jpeg2000CorruptedException(
      'Codestream does not start with the SOC marker.',
    );
  }
  if (input.readUnsignedShort() != Markers.siz) {
    throw const Jpeg2000CorruptedException(
      'The SIZ marker must follow SOC.',
    );
  }
  int readUint32() => input.readInt() & 0xffffffff;

  final lsiz = input.readUnsignedShort();
  input.readUnsignedShort(); // Rsiz: capabilities, not needed here.
  final xsiz = readUint32();
  final ysiz = readUint32();
  final x0siz = readUint32();
  final y0siz = readUint32();
  final xtsiz = readUint32();
  final ytsiz = readUint32();
  final xt0siz = readUint32();
  final yt0siz = readUint32();
  final csiz = input.readUnsignedShort();

  if (csiz < 1 || csiz > 16384) {
    throw Jpeg2000CorruptedException(
      'SIZ declares $csiz components; the standard allows 1 to 16384.',
    );
  }
  if (lsiz != 38 + 3 * csiz) {
    throw Jpeg2000CorruptedException(
      'SIZ length $lsiz does not match $csiz components.',
    );
  }
  if (xsiz <= x0siz || ysiz <= y0siz) {
    throw const Jpeg2000CorruptedException(
      'SIZ declares an empty image area.',
    );
  }
  if (xtsiz == 0 || ytsiz == 0) {
    throw const Jpeg2000CorruptedException('SIZ declares a zero tile size.');
  }
  if (xt0siz > x0siz ||
      yt0siz > y0siz ||
      xt0siz + xtsiz <= x0siz ||
      yt0siz + ytsiz <= y0siz) {
    throw const Jpeg2000CorruptedException(
      'SIZ tile grid does not cover the image origin.',
    );
  }

  final bitDepths = List<int>.filled(csiz, 0);
  final signed = List<bool>.filled(csiz, false);
  final subsamplingX = List<int>.filled(csiz, 1);
  final subsamplingY = List<int>.filled(csiz, 1);
  for (var c = 0; c < csiz; c++) {
    final ssiz = input.readUnsignedByte();
    final xrsiz = input.readUnsignedByte();
    final yrsiz = input.readUnsignedByte();
    if (xrsiz == 0 || yrsiz == 0) {
      throw Jpeg2000CorruptedException(
        'SIZ declares a zero subsampling factor for component $c.',
      );
    }
    bitDepths[c] = (ssiz & 0x7f) + 1;
    signed[c] = (ssiz & 0x80) != 0;
    subsamplingX[c] = xrsiz;
    subsamplingY[c] = yrsiz;
  }

  final tileColumns = (xsiz - xt0siz + xtsiz - 1) ~/ xtsiz;
  final tileRows = (ysiz - yt0siz + ytsiz - 1) ~/ ytsiz;
  return _SizSummary(
    width: xsiz - x0siz,
    height: ysiz - y0siz,
    components: csiz,
    bitDepths: bitDepths,
    signed: signed,
    subsamplingX: subsamplingX,
    subsamplingY: subsamplingY,
    tileWidth: xtsiz,
    tileHeight: ytsiz,
    tileColumns: tileColumns,
    tileRows: tileRows,
  );
}

void _checkBudget(_SizSummary siz, Jpeg2000DecodeOptions options) {
  final maxDimension = options.maxDimension;
  if (maxDimension != null) {
    final largest = siz.width > siz.height ? siz.width : siz.height;
    if (largest > maxDimension) {
      throw Jpeg2000BudgetException(
        budget: 'maxDimension',
        limit: maxDimension,
        actual: largest,
        message: 'Image is ${siz.width}x${siz.height}; '
            'maxDimension is $maxDimension.',
      );
    }
  }
  final maxPixels = options.maxPixels;
  if (maxPixels != null) {
    final pixels = siz.width * siz.height;
    if (pixels > maxPixels) {
      throw Jpeg2000BudgetException(
        budget: 'maxPixels',
        limit: maxPixels,
        actual: pixels,
        message: 'Image has $pixels pixels; maxPixels is $maxPixels.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Decode pipeline
// ---------------------------------------------------------------------------

BlkImgDataSrc _buildDecodePipeline({
  required ISRandomAccessIO input,
  required ParameterList params,
  required HeaderInfo headerInfo,
  required HeaderDecoder headerDecoder,
  required DecoderSpecs decoderSpecs,
  required ColorSpace? colorSpace,
  required bool applyComponentTransform,
}) {
  final bitstreamReader = BitstreamReaderAgent.createInstance(
    input,
    headerDecoder,
    params,
    decoderSpecs,
    false,
    headerInfo,
  );

  final entropyDecoder = headerDecoder.createEntropyDecoder(
    bitstreamReader,
    _subsetParametersByPrefix(params, EntropyDecoder.optionPrefix),
  );
  final roiDeScaler = headerDecoder.createROIDeScaler(
    entropyDecoder,
    _subsetParametersByPrefix(params, ROIDeScaler.optionPrefix),
  );
  final rangeBits = List<int>.generate(
    headerDecoder.getNumComps(),
    headerDecoder.getOriginalBitDepth,
    growable: false,
  );
  final dequantizer = headerDecoder.createDequantizer(roiDeScaler, rangeBits);
  final inverseWT = InverseWT.createInstance(dequantizer, decoderSpecs);
  final targetResolution = bitstreamReader.getImgRes();
  inverseWT.setImgResLevel(targetResolution);

  final imageDataConverter = ImgDataConverter(
    inverseWT,
    inverseWT.getFixedPoint(0),
    'public-core-img-data-converter',
  );

  BlkImgDataSrc pipelineSource = imageDataConverter;
  if (decoderSpecs.cts.isCompTransfUsed()) {
    pipelineSource = InvCompTransfImgDataSrc(
      imageDataConverter,
      decoderSpecs.cts,
      enableComponentTransforms: applyComponentTransform,
      originalBitDepths: rangeBits,
    );
  }

  if (colorSpace != null) {
    var colorSource = pipelineSource;
    colorSource = headerDecoder.createChannelDefinitionMapper(
      colorSource,
      colorSpace,
    );
    colorSource = headerDecoder.createResampler(colorSource, colorSpace);
    if (colorSpace.isPalettized()) {
      colorSource = headerDecoder.createPalettizedColorSpaceMapper(
        colorSource,
        colorSpace,
      );
    }
    final mapped = headerDecoder.createColorSpaceMapper(
      colorSource,
      colorSpace,
    );
    pipelineSource = mapped ?? colorSource;
  }

  _ensureWaveletFilters(decoderSpecs);
  return ImgDataConverter(
    pipelineSource,
    0,
    'public-writer-img-data-converter',
  );
}

/// Which source channels become colour and which one becomes alpha.
class _ChannelLayout {
  const _ChannelLayout({
    required this.channels,
    required this.colorComponents,
    required this.alpha,
    required this.alphaIsPremultiplied,
    required this.format,
  });

  /// Source channel index for each output channel, colour first, alpha last.
  final List<int> channels;

  /// Number of leading colour channels in [channels].
  final int colorComponents;

  /// Source index of the alpha channel, or null.
  final int? alpha;

  final bool alphaIsPremultiplied;

  final Jpeg2000PixelFormat format;
}

/// Decides the output layout from the JP2 channel definitions when present,
/// and from the component count otherwise.
///
/// Without a `cdef` box the standard says every channel is colour, but in
/// practice a 2-channel greyscale or 4-channel RGB file carries alpha in the
/// last channel; that reading is applied only when the colour space is a
/// known 1- or 3-channel space, so CMYK and multispectral images keep all
/// their channels.
_ChannelLayout _channelLayout(int components, ColorSpace? colorSpace) {
  final cdef = colorSpace?.cdbox;
  if (colorSpace != null && cdef != null && cdef.getNDefs() > 0) {
    final layout = _layoutFromChannelDefinitions(components, colorSpace, cdef);
    if (layout != null) {
      return layout;
    }
  }

  final knownSpace = colorSpace == null || _isKnownColourSpace(colorSpace);
  if (knownSpace && components == 2) {
    return _makeLayout(const <int>[0], alpha: 1, premultiplied: false);
  }
  if (knownSpace && components == 4) {
    return _makeLayout(const <int>[0, 1, 2], alpha: 3, premultiplied: false);
  }
  return _makeLayout(
    List<int>.generate(components, (i) => i, growable: false),
    alpha: null,
    premultiplied: false,
  );
}

_ChannelLayout? _layoutFromChannelDefinitions(
  int components,
  ColorSpace colorSpace,
  ChannelDefinitionBox cdef,
) {
  const colourType = 0;
  const opacityType = 1;
  const premultipliedOpacityType = 2;

  final colour = <int>[];
  int? alpha;
  var premultiplied = false;
  for (var c = 0; c < components; c++) {
    final sourceChannel = colorSpace.getChannelDefinition(c);
    if (sourceChannel < 0 || sourceChannel >= components) {
      return null;
    }
    final definition = cdef.definitions[sourceChannel];
    final type = definition == null ? colourType : definition[1];
    if (type == colourType) {
      colour.add(c);
    } else if ((type == opacityType || type == premultipliedOpacityType) &&
        alpha == null) {
      alpha = c;
      premultiplied = type == premultipliedOpacityType;
    }
  }
  if (colour.isEmpty) {
    return null;
  }
  return _makeLayout(colour, alpha: alpha, premultiplied: premultiplied);
}

_ChannelLayout _makeLayout(
  List<int> colour, {
  required int? alpha,
  required bool premultiplied,
}) {
  if (colour.length != 1 && colour.length != 3) {
    final all = <int>[...colour, if (alpha != null) alpha]..sort();
    return _ChannelLayout(
      channels: all,
      colorComponents: all.length,
      alpha: null,
      alphaIsPremultiplied: false,
      format: Jpeg2000PixelFormat.multiComponent,
    );
  }
  final channels = <int>[...colour, if (alpha != null) alpha];
  final Jpeg2000PixelFormat format;
  if (colour.length == 1) {
    format = alpha != null
        ? Jpeg2000PixelFormat.grayAlpha
        : Jpeg2000PixelFormat.gray;
  } else {
    format = alpha != null ? Jpeg2000PixelFormat.rgba : Jpeg2000PixelFormat.rgb;
  }
  return _ChannelLayout(
    channels: channels,
    colorComponents: colour.length,
    alpha: alpha,
    alphaIsPremultiplied: alpha != null && premultiplied,
    format: format,
  );
}

bool _isKnownColourSpace(ColorSpace colorSpace) {
  if (colorSpace.csbox == null) {
    return true;
  }
  try {
    if (colorSpace.getMethod() == ColorSpace.iccProfiled) {
      // Restricted ICC profiles are monochrome or three-component RGB.
      return true;
    }
    final space = colorSpace.getColorSpace();
    return space == ColorSpace.sRGB ||
        space == ColorSpace.greyScale ||
        space == ColorSpace.sYCC;
  } on Exception {
    return false;
  }
}

Jpeg2000Image _collectImage(
  BlkImgDataSrc source,
  HeaderDecoder headerDecoder,
  ColorSpace? colorSpace,
  int outputBitDepth,
) {
  final sourceComponents = source.getNumComps();
  if (sourceComponents <= 0) {
    throw const Jpeg2000CorruptedException('Decoded image has no components.');
  }

  final layout = _channelLayout(sourceComponents, colorSpace);
  final channels = layout.channels;
  final outputComponents = channels.length;
  final width = source.getImgWidth();
  final height = source.getImgHeight();

  for (final component in channels) {
    if (source.getCompImgWidth(component) != width ||
        source.getCompImgHeight(component) != height) {
      throw Jpeg2000UnsupportedException(
        'Component $component is subsampled and the file carries no JP2 '
        'colour metadata to resample it; subsampled raw codestreams are not '
        'supported yet.',
      );
    }
  }

  final sampleCount = width * height * outputComponents;
  final wide = outputBitDepth == 16;
  final Uint8List bytes;
  final Uint8List? pixels8;
  final Uint16List? pixels16;
  if (wide) {
    pixels16 = Uint16List(sampleCount);
    pixels8 = null;
    bytes = Uint8List.view(pixels16.buffer);
  } else {
    pixels8 = Uint8List(sampleCount);
    pixels16 = null;
    bytes = pixels8;
  }

  final bitDepths = List<int>.generate(
    outputComponents,
    (i) => source.getNomRangeBits(channels[i]),
    growable: false,
  );
  final signed = List<bool>.generate(
    outputComponents,
    (i) => headerDecoder.isOriginalSigned(channels[i]),
    growable: false,
  );

  final blocks = List<DataBlkInt>.generate(
    outputComponents,
    (_) => DataBlkInt(),
    growable: false,
  );
  final tileCount = source.getNumTilesCoord(null);
  for (var tileY = 0; tileY < tileCount.y; tileY++) {
    for (var tileX = 0; tileX < tileCount.x; tileX++) {
      source.setTile(tileX, tileY);
      final tileIndex = source.getTileIdx();
      final tileWidth = source.getTileCompWidth(tileIndex, channels[0]);
      final tileHeight = source.getTileCompHeight(tileIndex, channels[0]);
      // Every channel of the tile is fetched before any pixel is written:
      // each slot has its own block, so the decoded planes stay valid, and
      // the RGB case can then be written one pixel at a time instead of
      // three strided passes over the output.
      final tileData = List<Int32List?>.filled(outputComponents, null);
      final tileOffset = List<int>.filled(outputComponents, 0);
      final tileScanw = List<int>.filled(outputComponents, 0);
      final tileOffx = List<int>.filled(outputComponents, 0);
      final tileOffy = List<int>.filled(outputComponents, 0);
      final tileFixedPoint = List<int>.filled(outputComponents, 0);
      for (var slot = 0; slot < outputComponents; slot++) {
        final component = channels[slot];
        final block = blocks[slot]
          ..ulx = 0
          ..uly = 0
          ..w = tileWidth
          ..h = tileHeight;
        DataBlkInt dataBlock;
        do {
          dataBlock = source.getInternCompData(block, component) as DataBlkInt;
        } while (dataBlock.progressive);
        final data = dataBlock.getDataInt();
        if (data == null) {
          throw const Jpeg2000CorruptedException(
            'Decoded component block has no data.',
          );
        }
        tileData[slot] = data;
        tileOffset[slot] = dataBlock.offset;
        tileScanw[slot] = dataBlock.scanw;
        tileOffx[slot] = source.getCompULX(component) -
            (source.getImgULX() / source.getCompSubsX(component)).ceil();
        tileOffy[slot] = source.getCompULY(component) -
            (source.getImgULY() / source.getCompSubsY(component)).ceil();
        tileFixedPoint[slot] = source.getFixedPoint(component);
      }

      if (pixels8 != null &&
          outputComponents == 3 &&
          bitDepths.every((depth) => depth == outputBitDepth) &&
          tileOffx.every((v) => v == tileOffx[0]) &&
          tileOffy.every((v) => v == tileOffy[0])) {
        _writeRgb8Tile(
          pixels8,
          width,
          tileWidth,
          tileHeight,
          tileOffx[0],
          tileOffy[0],
          tileData[0]!,
          tileData[1]!,
          tileData[2]!,
          tileOffset,
          tileScanw,
          tileFixedPoint,
          signed,
          outputBitDepth,
        );
        continue;
      }

      for (var slot = 0; slot < outputComponents; slot++) {
        _writePlane(
          pixels8,
          pixels16,
          tileData[slot]!,
          tileOffset[slot],
          tileScanw[slot],
          tileFixedPoint[slot],
          bitDepths[slot],
          signed[slot],
          outputBitDepth,
          width,
          tileWidth,
          tileHeight,
          tileOffx[slot],
          tileOffy[slot],
          outputComponents,
          slot,
        );
      }
    }
  }

  return Jpeg2000Image(
    width: width,
    height: height,
    components: outputComponents,
    colorComponents: layout.colorComponents,
    hasAlpha: layout.alpha != null,
    alphaIsPremultiplied: layout.alphaIsPremultiplied,
    sourceBitsPerComponent: List<int>.unmodifiable(bitDepths),
    bitsPerSample: outputBitDepth,
    pixels: bytes,
    format: layout.format,
  );
}

/// Writes one decoded plane into channel [slot] of the interleaved output.
///
/// [data] is read from [dataOffset] with stride [scanw]; samples are shifted
/// right by [fixedPoint], level-shifted unless [isSigned], clamped to
/// [bitDepth] bits and converted to [outputBitDepth]. The plane is a typed
/// parameter on purpose: taking it out of a `List<Int32List?>` inside the
/// loop function made the AOT build treat every element read as a
/// polymorphic call, two and a half times slower.
void _writePlane(
  Uint8List? pixels8,
  Uint16List? pixels16,
  Int32List data,
  int dataOffset,
  int scanw,
  int fixedPoint,
  int bitDepth,
  bool isSigned,
  int outputBitDepth,
  int width,
  int tileWidth,
  int tileHeight,
  int tOffx,
  int tOffy,
  int outputComponents,
  int slot,
) {
  final levelShift = isSigned ? 0 : 1 << (bitDepth - 1);
  final maxValue = (1 << bitDepth) - 1;
  final outputMax = (1 << outputBitDepth) - 1;
  final wide = pixels16 != null;
  for (var row = 0; row < tileHeight; row++) {
    var sourceIndex = dataOffset + row * scanw;
    var targetIndex = ((row + tOffy) * width + tOffx) * outputComponents + slot;
    if (bitDepth == outputBitDepth) {
      // The common case. A shift by a variable count is slow in AOT
      // code, so the usual fixed point of zero gets its own loop, and
      // the two output widths are separated as well.
      if (pixels8 != null && fixedPoint == 0) {
        for (var x = 0; x < tileWidth; x++) {
          var sample = data[sourceIndex] + levelShift;
          if (sample < 0) {
            sample = 0;
          } else if (sample > maxValue) {
            sample = maxValue;
          }
          pixels8[targetIndex] = sample;
          sourceIndex++;
          targetIndex += outputComponents;
        }
      } else if (pixels8 != null) {
        for (var x = 0; x < tileWidth; x++) {
          var sample = (data[sourceIndex] >> fixedPoint) + levelShift;
          if (sample < 0) {
            sample = 0;
          } else if (sample > maxValue) {
            sample = maxValue;
          }
          pixels8[targetIndex] = sample;
          sourceIndex++;
          targetIndex += outputComponents;
        }
      } else {
        for (var x = 0; x < tileWidth; x++) {
          var sample = (fixedPoint == 0
                  ? data[sourceIndex]
                  : data[sourceIndex] >> fixedPoint) +
              levelShift;
          if (sample < 0) {
            sample = 0;
          } else if (sample > maxValue) {
            sample = maxValue;
          }
          pixels16![targetIndex] = sample;
          sourceIndex++;
          targetIndex += outputComponents;
        }
      }
    } else if (bitDepth > outputBitDepth) {
      final downShift = bitDepth - outputBitDepth;
      for (var x = 0; x < tileWidth; x++) {
        var sample = (fixedPoint == 0
                ? data[sourceIndex]
                : data[sourceIndex] >> fixedPoint) +
            levelShift;
        if (sample < 0) {
          sample = 0;
        } else if (sample > maxValue) {
          sample = maxValue;
        }
        sample >>= downShift;
        if (wide) {
          pixels16[targetIndex] = sample;
        } else {
          pixels8![targetIndex] = sample;
        }
        sourceIndex++;
        targetIndex += outputComponents;
      }
    } else {
      // Shallower source: rescale so the source maximum maps to the
      // output maximum (255 -> 65535), not to a shifted 65280.
      final half = maxValue ~/ 2;
      for (var x = 0; x < tileWidth; x++) {
        var sample = (fixedPoint == 0
                ? data[sourceIndex]
                : data[sourceIndex] >> fixedPoint) +
            levelShift;
        if (sample < 0) {
          sample = 0;
        } else if (sample > maxValue) {
          sample = maxValue;
        }
        sample = (sample * outputMax + half) ~/ maxValue;
        if (wide) {
          pixels16[targetIndex] = sample;
        } else {
          pixels8![targetIndex] = sample;
        }
        sourceIndex++;
        targetIndex += outputComponents;
      }
    }
  }
}

/// Writes one tile of three 8-bit planes as interleaved RGB, pixel by pixel.
///
/// [d0], [d1] and [d2] are the decoded planes (offset [tileOffset], stride
/// [tileScanw], samples shifted right by [tileFixedPoint]); [signed] says
/// which planes carry no level shift. The output is clamped to
/// `bitDepth` bits, which here equals the output depth. The planes are
/// typed parameters on purpose, see [_writePlane].
void _writeRgb8Tile(
  Uint8List pixels,
  int imageWidth,
  int tileWidth,
  int tileHeight,
  int tOffx,
  int tOffy,
  Int32List d0,
  Int32List d1,
  Int32List d2,
  List<int> tileOffset,
  List<int> tileScanw,
  List<int> tileFixedPoint,
  List<bool> signed,
  int bitDepth,
) {
  final int fp0 = tileFixedPoint[0];
  final int fp1 = tileFixedPoint[1];
  final int fp2 = tileFixedPoint[2];
  final int shift0 = signed[0] ? 0 : 1 << (bitDepth - 1);
  final int shift1 = signed[1] ? 0 : 1 << (bitDepth - 1);
  final int shift2 = signed[2] ? 0 : 1 << (bitDepth - 1);
  final int maxValue = (1 << bitDepth) - 1;
  // A shift by a variable count is a slow generic operation in AOT code
  // (three times the cost of this loop); the usual fixed point of zero
  // gets a loop without it.
  if (fp0 == 0 && fp1 == 0 && fp2 == 0) {
    for (var row = 0; row < tileHeight; row++) {
      var s0 = tileOffset[0] + row * tileScanw[0];
      var s1 = tileOffset[1] + row * tileScanw[1];
      var s2 = tileOffset[2] + row * tileScanw[2];
      var t = ((row + tOffy) * imageWidth + tOffx) * 3;
      for (var x = 0; x < tileWidth; x++, s0++, s1++, s2++, t += 3) {
        var r = d0[s0] + shift0;
        var g = d1[s1] + shift1;
        var b = d2[s2] + shift2;
        if (r < 0) {
          r = 0;
        } else if (r > maxValue) {
          r = maxValue;
        }
        if (g < 0) {
          g = 0;
        } else if (g > maxValue) {
          g = maxValue;
        }
        if (b < 0) {
          b = 0;
        } else if (b > maxValue) {
          b = maxValue;
        }
        pixels[t] = r;
        pixels[t + 1] = g;
        pixels[t + 2] = b;
      }
    }
    return;
  }
  for (var row = 0; row < tileHeight; row++) {
    var s0 = tileOffset[0] + row * tileScanw[0];
    var s1 = tileOffset[1] + row * tileScanw[1];
    var s2 = tileOffset[2] + row * tileScanw[2];
    var t = ((row + tOffy) * imageWidth + tOffx) * 3;
    for (var x = 0; x < tileWidth; x++, s0++, s1++, s2++, t += 3) {
      var r = (d0[s0] >> fp0) + shift0;
      var g = (d1[s1] >> fp1) + shift1;
      var b = (d2[s2] >> fp2) + shift2;
      if (r < 0) {
        r = 0;
      } else if (r > maxValue) {
        r = maxValue;
      }
      if (g < 0) {
        g = 0;
      } else if (g > maxValue) {
        g = maxValue;
      }
      if (b < 0) {
        b = 0;
      } else if (b > maxValue) {
        b = maxValue;
      }
      pixels[t] = r;
      pixels[t + 1] = g;
      pixels[t + 2] = b;
    }
  }
}

// ---------------------------------------------------------------------------
// Encode pipeline
// ---------------------------------------------------------------------------

Uint8List _encodeReader(
  ImgReader reader,
  ParameterList params,
  Jpeg2000EncodeOptions options,
) {
  if (options.lossless && options.rate != null) {
    throw ArgumentError('lossless and rate are mutually exclusive.');
  }
  final rate = options.rate ?? double.maxFinite;
  final tileWidth = options.tileWidth;
  final tileHeight = options.tileHeight;
  if (tileWidth < 0 || tileHeight < 0) {
    throw ArgumentError('Tile dimensions must be zero or positive.');
  }

  final imgSource = reader as BlkImgDataSrc;
  final imageTiler = Tiler(imgSource, 0, 0, 0, 0, tileWidth, tileHeight);
  final encoderSpecs = EncoderSpecs(
    imageTiler.getNumTiles(),
    imgSource.getNumComps(),
    imgSource,
    params,
  );

  final transformed = ForwCompTransf(imageTiler, encoderSpecs);
  final converter = ImgDataConverter(transformed);
  final dwt = ForwardWT.createInstance(converter, params, encoderSpecs);
  final quantizer = Quantizer.createInstance(dwt, encoderSpecs);
  final roiScaler = ROIScaler.createInstance(quantizer, params, encoderSpecs);
  final entropyCoder = EntropyCoder.createInstance(
    roiScaler,
    params,
    encoderSpecs.cblks,
    encoderSpecs.pss,
    encoderSpecs.bms,
    encoderSpecs.mqrs,
    encoderSpecs.rts,
    encoderSpecs.css,
    encoderSpecs.sss,
    encoderSpecs.lcs,
    encoderSpecs.tts,
  );
  final writer = MemoryCodestreamWriter(0x7fffffff);
  final allocator = PostCompRateAllocator.createInstance(
    entropyCoder,
    params,
    rate,
    writer,
    encoderSpecs,
  );
  final signed = List<bool>.generate(
    imgSource.getNumComps(),
    reader.isOrigSigned,
    growable: false,
  );
  final headerEncoder = HeaderEncoder(
    imgSource,
    signed,
    dwt,
    imageTiler,
    encoderSpecs,
    roiScaler,
    allocator,
    params,
  );
  allocator.setHeaderEncoder(headerEncoder);
  headerEncoder.encodeMainHeader();
  allocator.initialize();
  headerEncoder.reset();
  headerEncoder.encodeMainHeader();
  writer.commitBitstreamHeader(headerEncoder);
  allocator.runAndWrite();
  writer.close();
  return writer.toBytes();
}

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

ParameterList _buildDecodeParameters(Jpeg2000DecodeOptions options) {
  final defaults = ParameterList();
  _putDefaults(defaults, _decodePinfo);
  _putDefaults(defaults, EntropyDecoder.parameterInfo);
  _putDefaults(defaults, ROIDeScaler.parameterInfo);
  _putDefaults(defaults, ColorSpaceMapper.getParameterInfo());

  final params = ParameterList(defaults)
    ..put('rate', options.rate?.toString() ?? '-1')
    ..put('nbytes', options.bytes?.toString() ?? '-1')
    ..put('parsing', options.parsing ? 'on' : 'off')
    ..put('comp_transf', options.applyComponentTransform ? 'on' : 'off')
    ..put('nocolorspace', options.applyColorSpace ? 'off' : 'on')
    ..put('verbose', 'off');
  final resolution = options.resolution;
  if (resolution != null) {
    params.put('res', resolution.toString());
  }
  return params;
}

ParameterList _buildEncodeParameters(Jpeg2000EncodeOptions options) {
  final defaults = ParameterList();
  _putDefaults(defaults, _encodePinfo);
  _putDefaults(defaults, ForwCompTransf.getParameterInfo());
  _putDefaults(defaults, AnWTFilter.getParameterInfo());
  _putDefaults(defaults, ForwardWT.getParameterInfo());
  _putDefaults(defaults, Quantizer.getParameterInfo());
  _putDefaults(defaults, ROIScaler.getParameterInfo());
  _putDefaults(defaults, EntropyCoder.getParameterInfo());
  _putDefaults(defaults, HeaderEncoder.pinfo);
  _putDefaults(defaults, PktEncoder.pinfo);
  _putDefaults(defaults, PostCompRateAllocator.getParameterInfo());

  final params = ParameterList(defaults)
    ..put('lossless', options.lossless ? 'on' : 'off')
    ..put('rate', options.rate?.toString() ?? '-1')
    ..put('tiles', '${options.tileWidth} ${options.tileHeight}')
    ..put('ref', '0 0')
    ..put('tref', '0 0')
    ..put('verbose', 'off');
  for (final entry in options.extraParameters.entries) {
    params.put(entry.key, entry.value);
  }
  return params;
}

void _putDefaults(ParameterList target, List<List<Object?>>? parameterInfo) {
  if (parameterInfo == null) {
    return;
  }
  for (final option in parameterInfo) {
    if (option.length <= 3) {
      continue;
    }
    final name = option[0];
    final value = option[3];
    if (name is String &&
        name.isNotEmpty &&
        value is String &&
        value.isNotEmpty) {
      target.put(name, value);
    }
  }
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

// ---------------------------------------------------------------------------
// Codestream helpers
// ---------------------------------------------------------------------------

void _scanTileParts(ISRandomAccessIO input, HeaderDecoder decoder) {
  while (true) {
    final start = input.getPos();
    try {
      final sot = decoder.parseNextTilePart(input);
      final psot = sot.psot;
      if (psot == 0) {
        break;
      }
      final expectedEnd = start + psot;
      if (expectedEnd < input.getPos()) {
        break;
      }
      if (expectedEnd > input.length()) {
        input.seek(input.length());
        break;
      }
      input.seek(expectedEnd);
    } on StateError catch (error) {
      if (error.message.contains(
        'Reached end of codestream before encountering tile-part header',
      )) {
        break;
      }
      rethrow;
    }
  }
}

/// Parses the JP2 header boxes that describe colour.
///
/// When [required] is false, a container without usable colour metadata
/// yields null instead of failing, so callers that only want the channel
/// definitions (or asked not to apply colour) still get what exists.
ColorSpace? _loadColorSpace(
  ISRandomAccessIO input,
  HeaderDecoder decoder,
  ParameterList params, {
  required bool required,
}) {
  final bookmark = input.getPos();
  try {
    input.seek(0);
    return ColorSpace(input, decoder, params);
  } on Exception {
    if (required) {
      rethrow;
    }
    return null;
  } finally {
    input.seek(bookmark);
  }
}

void _ensureWaveletFilters(DecoderSpecs specs) {
  final filtersSpec = specs.wfs;
  for (var tile = 0; tile < filtersSpec.nTiles; tile++) {
    for (var component = 0; component < filtersSpec.nComp; component++) {
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

List<List<SynWTFilter>> _createDefaultFilters(
  int decompositionLevels,
  bool reversible,
) {
  final levelCount = decompositionLevels <= 0 ? 0 : decompositionLevels;
  if (levelCount == 0) {
    return <List<SynWTFilter>>[
      List<SynWTFilter>.empty(growable: false),
      List<SynWTFilter>.empty(growable: false),
    ];
  }

  SynWTFilter factory() =>
      reversible ? SynWTFilterIntLift5x3() : SynWTFilterFloatLift9x7();

  return <List<SynWTFilter>>[
    List<SynWTFilter>.generate(levelCount, (_) => factory(), growable: false),
    List<SynWTFilter>.generate(levelCount, (_) => factory(), growable: false),
  ];
}

// ---------------------------------------------------------------------------
// JP2 wrapper
// ---------------------------------------------------------------------------

Uint8List _wrapJp2(
  Uint8List codestream, {
  required int width,
  required int height,
  required int components,
  required List<int> bitsPerComponent,
  required bool hasAlpha,
}) {
  final writer = _ByteWriter();
  final bitsVary = !_hasUniformBits(bitsPerComponent);
  final colourChannels = hasAlpha ? components - 1 : components;
  const colourSpecificationBoxLength = 15;
  const fileTypeBoxLength = 20;
  const imageHeaderBoxLength = 22;
  const bitsPerComponentBoxBaseLength = 8;
  final channelDefinitionBoxLength = hasAlpha ? 8 + 2 + 6 * components : 0;
  final jp2HeaderLength = 8 +
      imageHeaderBoxLength +
      colourSpecificationBoxLength +
      (bitsVary ? bitsPerComponentBoxBaseLength + components : 0) +
      channelDefinitionBoxLength;

  writer
    ..writeInt(0x0000000c)
    ..writeInt(FileFormatBoxes.jp2SignatureBox)
    ..writeInt(0x0d0a870a)
    ..writeInt(fileTypeBoxLength)
    ..writeInt(FileFormatBoxes.fileTypeBox)
    ..writeInt(FileFormatBoxes.ftBr)
    ..writeInt(0)
    ..writeInt(FileFormatBoxes.ftBr)
    ..writeInt(jp2HeaderLength)
    ..writeInt(FileFormatBoxes.jp2HeaderBox)
    ..writeInt(imageHeaderBoxLength)
    ..writeInt(FileFormatBoxes.imageHeaderBox)
    ..writeInt(height)
    ..writeInt(width)
    ..writeShort(components)
    ..writeByte(bitsVary ? 0xff : bitsPerComponent.first - 1)
    ..writeByte(FileFormatBoxes.imbC)
    ..writeByte(FileFormatBoxes.imbUnkC)
    ..writeByte(FileFormatBoxes.imbIpr)
    ..writeInt(colourSpecificationBoxLength)
    ..writeInt(FileFormatBoxes.colourSpecificationBox)
    ..writeByte(FileFormatBoxes.csbMeth)
    ..writeByte(FileFormatBoxes.csbPrec)
    ..writeByte(FileFormatBoxes.csbApprox)
    ..writeInt(colourChannels > 1
        ? FileFormatBoxes.csbEnumSrgb
        : FileFormatBoxes.csbEnumGrey);

  if (bitsVary) {
    writer
      ..writeInt(bitsPerComponentBoxBaseLength + components)
      ..writeInt(FileFormatBoxes.bitsPerComponentBox);
    for (final value in bitsPerComponent) {
      writer.writeByte(value - 1);
    }
  }

  if (hasAlpha) {
    // cdef: colour channel i is associated with colour i + 1; the last
    // channel is straight (non-premultiplied) opacity for the whole image.
    writer
      ..writeInt(channelDefinitionBoxLength)
      ..writeInt(FileFormatBoxes.channelDefinitionBox)
      ..writeShort(components);
    for (var channel = 0; channel < colourChannels; channel++) {
      writer
        ..writeShort(channel)
        ..writeShort(0)
        ..writeShort(channel + 1);
    }
    writer
      ..writeShort(components - 1)
      ..writeShort(1)
      ..writeShort(0);
  }

  writer
    ..writeInt(codestream.length + 8)
    ..writeInt(FileFormatBoxes.contiguousCodestreamBox)
    ..writeBytes(codestream);

  return writer.toBytes();
}

bool _hasUniformBits(List<int> values) {
  if (values.isEmpty) {
    return true;
  }
  final first = values.first;
  for (var i = 1; i < values.length; i++) {
    if (values[i] != first) {
      return false;
    }
  }
  return true;
}

class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeByte(int value) {
    _builder.addByte(value & 0xff);
  }

  void writeShort(int value) {
    writeByte(value >> 8);
    writeByte(value);
  }

  void writeInt(int value) {
    writeByte(value >> 24);
    writeByte(value >> 16);
    writeByte(value >> 8);
    writeByte(value);
  }

  void writeBytes(Uint8List bytes) {
    _builder.add(bytes);
  }

  Uint8List toBytes() => _builder.toBytes();
}

const List<List<String?>> _decodePinfo = <List<String?>>[
  <String?>['rate', '<decoding rate in bpp>', '', '-1'],
  <String?>['nbytes', '<decoding rate in bytes>', '', '-1'],
  <String?>['parsing', '[on|off]', '', 'on'],
  <String?>['ncb_quit', '<max number of code blocks>', '', '-1'],
  <String?>['l_quit', '<max number of layers>', '', '-1'],
  <String?>['m_quit', '<max number of bit planes>', '', '-1'],
  <String?>['poc_quit', '[on|off]', '', 'off'],
  <String?>['one_tp', '[on|off]', '', 'off'],
  <String?>['comp_transf', '[on|off]', '', 'on'],
  <String?>['nocolorspace', '[on|off]', '', 'off'],
  <String?>['colorspace_debug', '[on|off]', '', 'off'],
];

const List<List<String?>> _encodePinfo = <List<String?>>[
  <String?>['debug', '[on|off]', '', 'off'],
  <String?>['file_format', '[on|off]', '', 'off'],
  <String?>['lossless', '[on|off]', '', 'off'],
  <String?>['rate', '<output bitrate in bpp>', '', '-1'],
  <String?>['tiles', '<nominal tile width> <nominal tile height>', '', '0 0'],
  <String?>['ref', '<x> <y>', '', '0 0'],
  <String?>['tref', '<x> <y>', '', '0 0'],
  <String?>['verbose', '[on|off]', '', 'off'],
];

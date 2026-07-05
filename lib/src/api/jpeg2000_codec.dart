import 'dart:math' as math;
import 'dart:typed_data';

import '../colorspace/color_space.dart';
import '../colorspace/color_space_mapper.dart';
import '../j2k/codestream/header_info.dart';
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
import '../j2k/platform/platform.dart' as platform;
import '../j2k/quantization/quantizer/quantizer.dart';
import '../j2k/roi/encoder/roi_scaler.dart';
import '../j2k/roi/roi_de_scaler.dart';
import '../j2k/util/decoder_instrumentation.dart';
import '../j2k/util/parameter_list.dart';
import '../j2k/util/is_random_access_io.dart';
import '../j2k/wavelet/analysis/an_wt_filter.dart';
import '../j2k/wavelet/analysis/forward_wt.dart';
import '../j2k/wavelet/synthesis/inverse_wt.dart';
import '../j2k/wavelet/synthesis/syn_wt_filter.dart';
import '../j2k/wavelet/synthesis/syn_wt_filter_float_lift9x7.dart';
import '../j2k/wavelet/synthesis/syn_wt_filter_int_lift5x3.dart';
import 'memory_codestream_writer.dart';
import 'pnm_memory_reader.dart';

/// Pixel layout returned by [decodeJpeg2000].
enum Jpeg2000PixelFormat {
  gray8,
  rgb8,
  multiComponent8,
}

/// Decoded 8-bit interleaved image pixels.
class Jpeg2000Image {
  const Jpeg2000Image({
    required this.width,
    required this.height,
    required this.components,
    required this.bitsPerComponent,
    required this.pixels,
    required this.format,
  });

  final int width;
  final int height;
  final int components;
  final List<int> bitsPerComponent;
  final Uint8List pixels;
  final Jpeg2000PixelFormat format;

  int get rowStride => width * components;
}

/// Options for byte-based JPEG 2000 decoding.
class Jpeg2000DecodeOptions {
  const Jpeg2000DecodeOptions({
    this.applyColorSpace = true,
    this.applyComponentTransform = true,
    this.rate,
    this.bytes,
    this.resolution,
    this.parsing = true,
  });

  final bool applyColorSpace;
  final bool applyComponentTransform;
  final double? rate;
  final int? bytes;
  final int? resolution;
  final bool parsing;
}

/// Options for byte-based PNM to JPEG 2000 encoding.
class Jpeg2000EncodeOptions {
  const Jpeg2000EncodeOptions({
    this.lossless = true,
    this.rate,
    this.wrapInJp2 = false,
    this.tileWidth = 0,
    this.tileHeight = 0,
    this.extraParameters = const <String, String>{},
  });

  final bool lossless;
  final double? rate;
  final bool wrapInJp2;
  final int tileWidth;
  final int tileHeight;
  final Map<String, String> extraParameters;
}

/// Synchronous byte-oriented facade for JPEG 2000.
class Jpeg2000Codec {
  const Jpeg2000Codec();

  Jpeg2000Image decode(
    Uint8List bytes, {
    Jpeg2000DecodeOptions options = const Jpeg2000DecodeOptions(),
  }) {
    return decodeJpeg2000(bytes, options: options);
  }

  Future<Jpeg2000Image> decodeSource(
    Object source, {
    Jpeg2000DecodeOptions options = const Jpeg2000DecodeOptions(),
  }) {
    return decodeJpeg2000Source(source, options: options);
  }

  Uint8List encodePnm(
    Uint8List bytes, {
    Jpeg2000EncodeOptions options = const Jpeg2000EncodeOptions(),
  }) {
    return encodeJpeg2000(bytes, options: options);
  }

  Future<Uint8List> encodePnmSource(
    Object source, {
    Jpeg2000EncodeOptions options = const Jpeg2000EncodeOptions(),
  }) {
    return encodeJpeg2000Source(source, options: options);
  }
}

/// Decodes JP2 or raw J2K bytes into 8-bit interleaved pixels.
Jpeg2000Image decodeJpeg2000(
  Uint8List bytes, {
  Jpeg2000DecodeOptions options = const Jpeg2000DecodeOptions(),
}) {
  final input = ISRandomAccessIO(bytes);
  final params = _buildDecodeParameters(options);
  DecoderInstrumentation.configure(false);

  try {
    final headerInfo = HeaderInfo();
    final fileFormat = FileFormatReader(input)..readFileFormat();
    final jp2WrapperUsed = fileFormat.JP2FFUsed;
    if (jp2WrapperUsed) {
      input.seek(fileFormat.getFirstCodeStreamPos());
    }

    final headerDecoder = HeaderDecoder.readMainHeader(
      input: input,
      headerInfo: headerInfo,
    );
    final decoderSpecs = headerDecoder.decSpec;
    _scanTileParts(input, headerDecoder);

    final source = _buildDecodePipeline(
      input: input,
      params: params,
      headerInfo: headerInfo,
      headerDecoder: headerDecoder,
      decoderSpecs: decoderSpecs,
      jp2WrapperUsed: jp2WrapperUsed,
      applyColorSpace: options.applyColorSpace,
      applyComponentTransform: options.applyComponentTransform,
    );
    return _collectImage(source, headerDecoder);
  } finally {
    input.close();
  }
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

/// Encodes binary PGM (P5) or PPM (P6) bytes to raw J2K or JP2 bytes.
Uint8List encodeJpeg2000(
  Uint8List pnmBytes, {
  Jpeg2000EncodeOptions options = const Jpeg2000EncodeOptions(),
}) {
  final params = _buildEncodeParameters(options);
  final reader = PnmMemoryReader(pnmBytes);

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
    );
  } finally {
    reader.close();
  }
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

BlkImgDataSrc _buildDecodePipeline({
  required ISRandomAccessIO input,
  required ParameterList params,
  required HeaderInfo headerInfo,
  required HeaderDecoder headerDecoder,
  required DecoderSpecs decoderSpecs,
  required bool jp2WrapperUsed,
  required bool applyColorSpace,
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
      originalBitDepths: List<int>.generate(
        headerDecoder.getNumComps(),
        headerDecoder.getOriginalBitDepth,
        growable: false,
      ),
    );
  }

  if (jp2WrapperUsed && applyColorSpace) {
    final colorSpace = _loadColorSpace(input, headerDecoder, params);
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

Jpeg2000Image _collectImage(
  BlkImgDataSrc source,
  HeaderDecoder headerDecoder,
) {
  final components = source.getNumComps();
  if (components <= 0) {
    throw StateError('Decoded image has no components.');
  }

  final outputComponents = components == 1 ? 1 : math.min(components, 3);
  final width = source.getImgWidth();
  final height = source.getImgHeight();
  final pixels = Uint8List(width * height * outputComponents);
  final bitDepths = List<int>.generate(
    outputComponents,
    source.getNomRangeBits,
    growable: false,
  );
  final signed = List<bool>.generate(
    outputComponents,
    (component) => headerDecoder.isOriginalSigned(component),
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
      final tileWidth = source.getTileCompWidth(tileIndex, 0);
      final tileHeight = source.getTileCompHeight(tileIndex, 0);
      for (var row = 0; row < tileHeight; row++) {
        for (var component = 0; component < outputComponents; component++) {
          final block = blocks[component]
            ..ulx = 0
            ..uly = row
            ..w = tileWidth
            ..h = 1;
          DataBlkInt dataBlock;
          do {
            dataBlock =
                source.getInternCompData(block, component) as DataBlkInt;
          } while (dataBlock.progressive);

          final data = dataBlock.getDataInt();
          if (data == null) {
            throw StateError('Decoded component block has no data.');
          }
          final tOffx = source.getCompULX(component) -
              (source.getImgULX() / source.getCompSubsX(component)).ceil();
          final tOffy = source.getCompULY(component) -
              (source.getImgULY() / source.getCompSubsY(component)).ceil();
          final imageRow = row + tOffy;
          final imageCol = tOffx;
          final base =
              (imageRow * width + imageCol) * outputComponents + component;
          final fixedPoint = source.getFixedPoint(component);
          final bitDepth = bitDepths[component];
          final levelShift = signed[component] ? 0 : 1 << (bitDepth - 1);
          final maxValue = (1 << bitDepth) - 1;
          final downShift = bitDepth > 8 ? bitDepth - 8 : 0;
          var sourceIndex = dataBlock.offset;
          var targetIndex = base;
          for (var x = 0; x < tileWidth; x++) {
            var sample = fixedPoint == 0
                ? data[sourceIndex]
                : data[sourceIndex] >> fixedPoint;
            sample += levelShift;
            if (sample < 0) {
              sample = 0;
            } else if (sample > maxValue) {
              sample = maxValue;
            }
            pixels[targetIndex] = downShift == 0 ? sample : sample >> downShift;
            sourceIndex++;
            targetIndex += outputComponents;
          }
        }
      }
    }
  }

  return Jpeg2000Image(
    width: width,
    height: height,
    components: outputComponents,
    bitsPerComponent: bitDepths,
    pixels: pixels,
    format: outputComponents == 1
        ? Jpeg2000PixelFormat.gray8
        : outputComponents == 3
            ? Jpeg2000PixelFormat.rgb8
            : Jpeg2000PixelFormat.multiComponent8,
  );
}

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

ColorSpace _loadColorSpace(
  ISRandomAccessIO input,
  HeaderDecoder decoder,
  ParameterList params,
) {
  final bookmark = input.getPos();
  try {
    input.seek(0);
    return ColorSpace(input, decoder, params);
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

Uint8List _wrapJp2(
  Uint8List codestream, {
  required int width,
  required int height,
  required int components,
  required List<int> bitsPerComponent,
}) {
  final writer = _ByteWriter();
  final bitsVary = !_hasUniformBits(bitsPerComponent);
  const colourSpecificationBoxLength = 15;
  const fileTypeBoxLength = 20;
  const imageHeaderBoxLength = 22;
  const bitsPerComponentBoxBaseLength = 8;
  final jp2HeaderLength = 8 +
      imageHeaderBoxLength +
      colourSpecificationBoxLength +
      (bitsVary ? bitsPerComponentBoxBaseLength + components : 0);

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
    ..writeInt(components > 1
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

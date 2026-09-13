/// Helpers that build JPEG 2000 data with subsampled components.
///
/// No fixture in `test/fixtures` carries `XRsiz`/`YRsiz` other than 1, and the
/// public encoder only takes interleaved samples of one size, so the tests
/// build such images here: a planar [ImgReader] that reports per-component
/// subsampling factors, plus the encoder pipeline wired by hand the way
/// `_encodeReader` in `lib/src/api/jpeg2000_codec.dart` wires it.
library;

import 'dart:typed_data';

import 'package:j2k/src/api/memory_codestream_writer.dart';
import 'package:j2k/src/j2k/codestream/writer/header_encoder.dart';
import 'package:j2k/src/j2k/codestream/writer/pkt_encoder.dart';
import 'package:j2k/src/j2k/encoder/encoder_specs.dart';
import 'package:j2k/src/j2k/entropy/encoder/entropy_coder.dart';
import 'package:j2k/src/j2k/entropy/encoder/post_comp_rate_allocator.dart';
import 'package:j2k/src/j2k/fileformat/file_format_boxes.dart';
import 'package:j2k/src/j2k/image/blk_img_data_src.dart';
import 'package:j2k/src/j2k/image/data_blk.dart';
import 'package:j2k/src/j2k/image/data_blk_float.dart';
import 'package:j2k/src/j2k/image/data_blk_int.dart';
import 'package:j2k/src/j2k/image/forwcomptransf/forw_comp_transf.dart';
import 'package:j2k/src/j2k/image/img_data_converter.dart';
import 'package:j2k/src/j2k/image/input/img_reader.dart';
import 'package:j2k/src/j2k/image/tiler.dart';
import 'package:j2k/src/j2k/quantization/quantizer/quantizer.dart';
import 'package:j2k/src/j2k/roi/encoder/roi_scaler.dart';
import 'package:j2k/src/j2k/util/parameter_list.dart';
import 'package:j2k/src/j2k/wavelet/analysis/an_wt_filter.dart';
import 'package:j2k/src/j2k/wavelet/analysis/forward_wt.dart';

int ceilDiv(int value, int divisor) => (value + divisor - 1) ~/ divisor;

/// A source of separate component planes, each one subsampled by its own
/// `(XRsiz, YRsiz)` pair.
///
/// Plane sizes follow ISO/IEC 15444-1 equation B-1 with an image origin of
/// (0, 0): component `c` is `ceil(width / XRsiz_c)` by
/// `ceil(height / YRsiz_c)` samples.
class PlanarSubsampledSource extends ImgReader {
  PlanarSubsampledSource({
    required int width,
    required int height,
    required this.planes,
    required this.subsX,
    required this.subsY,
    this.bitsPerSample = 8,
  }) {
    if (planes.length != subsX.length || planes.length != subsY.length) {
      throw ArgumentError('One subsampling pair is needed per plane.');
    }
    w = width;
    h = height;
    nc = planes.length;
    for (var c = 0; c < nc; c++) {
      final expected = planeWidth(c) * planeHeight(c);
      if (planes[c].length != expected) {
        throw ArgumentError(
          'Plane $c should hold $expected samples, got ${planes[c].length}.',
        );
      }
    }
  }

  /// Builds planes whose samples are a reproducible function of their index.
  factory PlanarSubsampledSource.synthetic({
    required int width,
    required int height,
    required List<int> subsX,
    required List<int> subsY,
    int bitsPerSample = 8,
  }) {
    final planes = <List<int>>[];
    for (var c = 0; c < subsX.length; c++) {
      final pw = ceilDiv(width, subsX[c]);
      final ph = ceilDiv(height, subsY[c]);
      final max = (1 << bitsPerSample) - 1;
      planes.add(
        List<int>.generate(pw * ph, (i) => (c * 37 + i * 11) % (max + 1)),
      );
    }
    return PlanarSubsampledSource(
      width: width,
      height: height,
      planes: planes,
      subsX: subsX,
      subsY: subsY,
      bitsPerSample: bitsPerSample,
    );
  }

  final List<List<int>> planes;
  final List<int> subsX;
  final List<int> subsY;
  final int bitsPerSample;

  int planeWidth(int c) => ceilDiv(w, subsX[c]);

  int planeHeight(int c) => ceilDiv(h, subsY[c]);

  /// The sample of component [c] that covers reference grid point ([x], [y]).
  int sampleAt(int c, int x, int y) =>
      planes[c][(y ~/ subsY[c]) * planeWidth(c) + (x ~/ subsX[c])];

  @override
  void close() {}

  @override
  bool isOrigSigned(int c) => false;

  @override
  int getNomRangeBits(int c) => bitsPerSample;

  @override
  int getFixedPoint(int c) => 0;

  @override
  int getCompSubsX(int c) => subsX[c];

  @override
  int getCompSubsY(int c) => subsY[c];

  @override
  int getCompImgWidth(int c) => planeWidth(c);

  @override
  int getCompImgHeight(int c) => planeHeight(c);

  @override
  int getTileCompWidth(int t, int c) => planeWidth(c);

  @override
  int getTileCompHeight(int t, int c) => planeHeight(c);

  @override
  DataBlk getCompData(DataBlk blk, int c) => getInternCompData(blk, c);

  @override
  DataBlk getInternCompData(DataBlk blk, int c) {
    if (blk.getDataType() == DataBlk.typeFloat) {
      return _floatBlock(blk as DataBlkFloat, c);
    }
    if (blk.getDataType() != DataBlk.typeInt) {
      throw ArgumentError('Only integer and float blocks are produced.');
    }
    final out = blk as DataBlkInt;
    var data = out.getDataInt();
    if (data == null || data.length < out.w * out.h) {
      data = Int32List(out.w * out.h);
      out.setData(data);
    }
    final pw = planeWidth(c);
    final dcOffset = 1 << (bitsPerSample - 1);
    for (var y = 0; y < out.h; y++) {
      for (var x = 0; x < out.w; x++) {
        data[y * out.w + x] =
            planes[c][(out.uly + y) * pw + out.ulx + x] - dcOffset;
      }
    }
    out
      ..offset = 0
      ..scanw = out.w
      ..progressive = false;
    return out;
  }

  DataBlkFloat _floatBlock(DataBlkFloat out, int c) {
    var data = out.getDataFloat();
    if (data == null || data.length < out.w * out.h) {
      data = Float32List(out.w * out.h);
      out.setData(data);
    }
    final pw = planeWidth(c);
    final dcOffset = 1 << (bitsPerSample - 1);
    for (var y = 0; y < out.h; y++) {
      for (var x = 0; x < out.w; x++) {
        data[y * out.w + x] =
            (planes[c][(out.uly + y) * pw + out.ulx + x] - dcOffset).toDouble();
      }
    }
    out
      ..offset = 0
      ..scanw = out.w
      ..progressive = false;
    return out;
  }
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

/// Losslessly encodes [source] into a raw codestream whose SIZ marker segment
/// carries the per-component `XRsiz`/`YRsiz` of the source.
///
/// The multiple component transform is off: it is only defined for components
/// of equal size (T.800 G.2).
Uint8List encodeSubsampledCodestream(
  PlanarSubsampledSource source, {
  int tileWidth = 0,
  int tileHeight = 0,
}) {
  final defaults = ParameterList();
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
    ..put('lossless', 'on')
    ..put('rate', '-1')
    ..put('Mct', 'off')
    ..put('tiles', '$tileWidth $tileHeight')
    ..put('ref', '0 0')
    ..put('tref', '0 0')
    ..put('verbose', 'off');

  final BlkImgDataSrc imgSource = source;
  final tiler = Tiler(imgSource, 0, 0, 0, 0, tileWidth, tileHeight);
  final specs = EncoderSpecs(
    tiler.getNumTiles(),
    imgSource.getNumComps(),
    imgSource,
    params,
  );
  final transformed = ForwCompTransf(tiler, specs);
  final converter = ImgDataConverter(transformed);
  final dwt = ForwardWT.createInstance(converter, params, specs);
  final quantizer = Quantizer.createInstance(dwt, specs);
  final roiScaler = ROIScaler.createInstance(quantizer, params, specs);
  final entropyCoder = EntropyCoder.createInstance(
    roiScaler,
    params,
    specs.cblks,
    specs.pss,
    specs.bms,
    specs.mqrs,
    specs.rts,
    specs.css,
    specs.sss,
    specs.lcs,
    specs.tts,
  );
  final writer = MemoryCodestreamWriter(0x7fffffff);
  final allocator = PostCompRateAllocator.createInstance(
    entropyCoder,
    params,
    double.maxFinite,
    writer,
    specs,
  );
  final signed = List<bool>.generate(
    imgSource.getNumComps(),
    source.isOrigSigned,
    growable: false,
  );
  final headerEncoder = HeaderEncoder(
    imgSource,
    signed,
    dwt,
    tiler,
    specs,
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

/// Wraps [codestream] in the smallest JP2 file that names a colour space, so
/// that the decoder takes the JP2 colour pipeline instead of the raw one.
Uint8List wrapInJp2(
  Uint8List codestream, {
  required int width,
  required int height,
  required int components,
  required int bitsPerComponent,
}) {
  final bytes = BytesBuilder();
  void writeInt(int value) {
    final buffer = ByteData(4)..setUint32(0, value);
    bytes.add(buffer.buffer.asUint8List());
  }

  const fileTypeBoxLength = 20;
  const imageHeaderBoxLength = 22;
  const colourSpecificationBoxLength = 15;
  const jp2HeaderLength =
      8 + imageHeaderBoxLength + colourSpecificationBoxLength;

  writeInt(0x0000000c);
  writeInt(FileFormatBoxes.jp2SignatureBox);
  writeInt(0x0d0a870a);
  writeInt(fileTypeBoxLength);
  writeInt(FileFormatBoxes.fileTypeBox);
  writeInt(FileFormatBoxes.ftBr);
  writeInt(0);
  writeInt(FileFormatBoxes.ftBr);
  writeInt(jp2HeaderLength);
  writeInt(FileFormatBoxes.jp2HeaderBox);
  writeInt(imageHeaderBoxLength);
  writeInt(FileFormatBoxes.imageHeaderBox);
  writeInt(height);
  writeInt(width);
  bytes.add(Uint8List.fromList(<int>[
    (components >> 8) & 0xff,
    components & 0xff,
    bitsPerComponent - 1,
    FileFormatBoxes.imbC,
    FileFormatBoxes.imbUnkC,
    FileFormatBoxes.imbIpr,
  ]));
  writeInt(colourSpecificationBoxLength);
  writeInt(FileFormatBoxes.colourSpecificationBox);
  bytes.add(Uint8List.fromList(<int>[
    FileFormatBoxes.csbMeth,
    FileFormatBoxes.csbPrec,
    FileFormatBoxes.csbApprox,
  ]));
  writeInt(components > 1
      ? FileFormatBoxes.csbEnumSrgb
      : FileFormatBoxes.csbEnumGrey);
  writeInt(codestream.length + 8);
  writeInt(FileFormatBoxes.contiguousCodestreamBox);
  bytes.add(codestream);
  return bytes.toBytes();
}

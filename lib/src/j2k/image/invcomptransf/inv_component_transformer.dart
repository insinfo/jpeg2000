import 'dart:math' as math;
import 'dart:typed_data';

import '../../util/decoder_instrumentation.dart';
import '../blk_img_data_src.dart';
import '../comp_transf_spec.dart';
import '../data_blk.dart';
import '../data_blk_float.dart';
import '../data_blk_int.dart';
import '../img_data_adapter.dart';
import 'inv_comp_transf.dart';

/// Applies inverse component transforms (ICT/RCT) to reconstructed samples.
class InvCompTransfImgDataSrc extends ImgDataAdapter implements BlkImgDataSrc {
  static const String _logSource = 'InvCompTransf';
  InvCompTransfImgDataSrc(
    BlkImgDataSrc super.source,
    this.compTransfSpec, {
    bool enableComponentTransforms = true,
    List<int>? originalBitDepths,
  })  : _source = source,
        _componentTransformEnabled = enableComponentTransforms,
        _utdepth = originalBitDepths == null
            ? null
            : List<int>.from(originalBitDepths, growable: false);

  static final List<int> _componentDebugCountdown = <int>[5, 5, 5];

  final BlkImgDataSrc _source;
  final CompTransfSpec compTransfSpec;
  final bool _componentTransformEnabled;

  /// Original (untransformed) component bit depths from the SIZ marker.
  /// Mirrors JJ2000's `InvCompTransf.utdepth`: after the inverse component
  /// transform the samples are back in their original range, so this class
  /// must report the original depths, not the mixed depths of the source.
  final List<int>? _utdepth;

  @override
  int getNomRangeBits(int component) {
    final utdepth = _utdepth;
    if (utdepth != null && component < utdepth.length) {
      return utdepth[component];
    }
    return _source.getNomRangeBits(component);
  }

  final List<DataBlkInt?> _intScratch = List<DataBlkInt?>.filled(3, null);
  final List<DataBlkFloat?> _floatScratch = List<DataBlkFloat?>.filled(3, null);

  // ICT constants exactly as in JJ2000's InvCompTransf (float literals).
  static final double _ictRedCrFactor = _asFloat32(1.402);
  static final double _ictGreenCbFactor = _asFloat32(0.34413);
  static final double _ictGreenCrFactor = _asFloat32(0.71414);
  static final double _ictBlueCbFactor = _asFloat32(1.772);

  static final Float32List _f32Scratch = Float32List(2);

  /// A 16-byte aligned SIMD view over [list], covering its whole-vector
  /// prefix. Decoder buffers are allocated directly, so the offset is zero;
  /// a misaligned view would throw, and then the scalar path is used alone.
  static Float32x4List _asFloat32x4List(Float32List list) {
    if (list.offsetInBytes & 15 != 0) {
      return Float32x4List(0);
    }
    return list.buffer.asFloat32x4List(list.offsetInBytes, list.length >> 2);
  }

  /// Rounds [value] to float32 precision, mirroring Java `float` arithmetic.
  static double _asFloat32(double value) {
    _f32Scratch[0] = value;
    return _f32Scratch[0];
  }

  int get _numComponents => _source.getNumComps();

  @override
  int getFixedPoint(int component) => _source.getFixedPoint(component);

  @override
  DataBlk getInternCompData(DataBlk block, int component) {
    final result = _maybeTransform(block, component, true);
    return result;
  }

  @override
  DataBlk getCompData(DataBlk block, int component) {
    final result = _maybeTransform(block, component, false);
    if (!identical(result, block) &&
        result.getDataType() == block.getDataType()) {
      block
        ..ulx = result.ulx
        ..uly = result.uly
        ..w = result.w
        ..h = result.h
        ..offset = result.offset
        ..scanw = result.scanw
        ..progressive = result.progressive
        ..setData(result.getData());
      return block;
    }
    // As in JJ2000, the returned block may be of a different type than the
    // one passed in (the ICT always produces integer samples); callers must
    // use the returned instance.
    return result;
  }

  DataBlk _maybeTransform(DataBlk block, int component, bool intern) {
    if (!_componentTransformEnabled) {
      return intern
          ? _source.getInternCompData(block, component)
          : _source.getCompData(block, component);
    }
    final tileIdx = getTileIdx();
    final transform =
        compTransfSpec.getSpec(tileIdx, component) ?? InvCompTransf.none;
    if (component < _componentDebugCountdown.length &&
        _componentDebugCountdown[component] > 0) {
      _componentDebugCountdown[component]--;
      _log(
          'InvCompTransf: tile=$tileIdx component=$component transform=$transform');
    }
    if (transform == InvCompTransf.none ||
        _numComponents < 3 ||
        component >= 3) {
      return intern
          ? _source.getInternCompData(block, component)
          : _source.getCompData(block, component);
    }

    switch (transform) {
      case InvCompTransf.invRct:
        return _applyRCT(block, component, intern);
      case InvCompTransf.invIct:
        return _applyICT(block, component, intern);
      default:
        throw StateError('Unsupported inverse component transform: $transform');
    }
  }

  DataBlk _applyRCT(DataBlk block, int component, bool intern) {
    final DataBlkInt target = block is DataBlkInt ? block : DataBlkInt();
    if (!identical(target, block)) {
      target
        ..ulx = block.ulx
        ..uly = block.uly
        ..w = block.w
        ..h = block.h
        ..progressive = block.progressive;
    }
    final DataBlkInt y =
        _fetchIntBlock(component: 0, template: target, intern: intern);
    final DataBlkInt cb =
        _fetchIntBlock(component: 1, template: target, intern: intern);
    final DataBlkInt cr =
        _fetchIntBlock(component: 2, template: target, intern: intern);

    final int width = y.w;
    final int height = y.h;
    target
      ..ulx = y.ulx
      ..uly = y.uly
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = y.progressive;

    final required = width * height;
    final existing = target.getDataInt();
    late final Int32List buffer;
    if (existing == null || existing.length < required) {
      final newData = Int32List(required);
      target.setDataInt(newData);
      buffer = newData;
    } else {
      buffer = existing;
    }

    final yData = y.getDataInt();
    final cbData = cb.getDataInt();
    final crData = cr.getDataInt();
    if (yData == null || cbData == null || crData == null) {
      throw StateError('RCT requires integer data in all coefficient blocks');
    }

    final bool isR = component == 0;
    final bool isG = component == 1;

    var yIndex = y.offset;
    var cbIndex = cb.offset;
    var crIndex = cr.offset;
    var destIndex = 0;

    for (var row = 0; row < height; row++) {
      final yRowEnd = yIndex + width;
      var yPos = yIndex;
      var cbPos = cbIndex;
      var crPos = crIndex;
      while (yPos < yRowEnd) {
        final int yVal = yData[yPos];
        final int cbVal = cbData[cbPos];
        final int crVal = crData[crPos];

        final int g = yVal - ((cbVal + crVal) >> 2);
        // For the reversible transform the chroma components are defined
        // relative to green, so rebuild red/blue from the recovered green.
        final int r = g + crVal;
        final int b = g + cbVal;

        buffer[destIndex++] = isR ? r : (isG ? g : b);

        yPos++;
        cbPos++;
        crPos++;
      }
      yIndex += y.scanw;
      cbIndex += cb.scanw;
      crIndex += cr.scanw;
    }

    return target;
  }

  DataBlk _applyICT(DataBlk block, int component, bool intern) {
    // JJ2000's invICT always produces integer samples, rounding each float
    // result with `(int)(x + 0.5f)` and float32 arithmetic throughout.
    final DataBlkInt target = block is DataBlkInt ? block : DataBlkInt();
    if (!identical(target, block)) {
      target
        ..ulx = block.ulx
        ..uly = block.uly
        ..w = block.w
        ..h = block.h
        ..progressive = block.progressive;
    }
    final DataBlkFloat y =
        _fetchFloatBlock(component: 0, template: target, intern: intern);
    final DataBlkFloat cb =
        _fetchFloatBlock(component: 1, template: target, intern: intern);
    final DataBlkFloat cr =
        _fetchFloatBlock(component: 2, template: target, intern: intern);

    final int width = y.w;
    final int height = y.h;
    target
      ..ulx = y.ulx
      ..uly = y.uly
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = y.progressive || cb.progressive || cr.progressive;

    final required = width * height;
    final existing = target.getDataInt();
    late final Int32List buffer;
    if (existing == null || existing.length < required) {
      final newData = Int32List(required);
      target.setDataInt(newData);
      buffer = newData;
    } else {
      buffer = existing;
    }

    final yData = y.getDataFloat();
    final cbData = cb.getDataFloat();
    final crData = cr.getDataFloat();
    if (yData == null || cbData == null || crData == null) {
      throw StateError(
          'ICT requires floating-point data in all coefficient blocks');
    }

    final bool isR = component == 0;
    final bool isG = component == 1;

    var yIndex = y.offset;
    var cbIndex = cb.offset;
    var crIndex = cr.offset;
    var destIndex = 0;

    // Mirrors: (int)(y + K*c + 0.5f) with float32 rounding at every step.
    // The rounding is a store to and load from a one-element Float32List,
    // done inline: through a helper it was a call plus a lazy static check
    // per operation, four to six times per sample, and showed up as 16% of
    // the decode of a 9/7 image.
    final Float32List f32 = _f32Scratch;
    final double kRedCr = _ictRedCrFactor;
    final double kGreenCb = _ictGreenCbFactor;
    final double kGreenCr = _ictGreenCrFactor;
    final double kBlueCb = _ictBlueCbFactor;
    // Four samples per step on SIMD lanes. Float32x4 arithmetic is single
    // precision at every operation, so each lane follows Java's `float`
    // chain exactly; the scalar head and tail emulate the same rounding with
    // the scratch buffer. The lanes are read through Float32x4List views,
    // which need 16-byte alignment: a row is processed on SIMD from its
    // first aligned sample, and only when the three planes share that
    // alignment. Building a Float32x4 from four scalar loads was measured
    // slower than the scalar loop.
    final Float32x4 kRedCr4 = Float32x4.splat(kRedCr);
    final Float32x4 kGreenCb4 = Float32x4.splat(kGreenCb);
    final Float32x4 kGreenCr4 = Float32x4.splat(kGreenCr);
    final Float32x4 kBlueCb4 = Float32x4.splat(kBlueCb);
    final Float32x4 half4 = Float32x4.splat(0.5);
    final Float32x4List y4List = _asFloat32x4List(yData);
    final Float32x4List cb4List = _asFloat32x4List(cbData);
    final Float32x4List cr4List = _asFloat32x4List(crData);

    for (var row = 0; row < height; row++) {
      final yRowEnd = yIndex + width;
      var yPos = yIndex;
      var cbPos = cbIndex;
      var crPos = crIndex;
      final int lead = math.min((-yPos) & 3, width);
      final int simdEnd = (cbPos - yPos) & 3 == 0 && (crPos - yPos) & 3 == 0
          ? yPos + lead + ((width - lead) & ~3)
          : yPos;
      if (isR) {
        for (; yPos < yIndex + lead; yPos++, crPos++) {
          f32[0] = kRedCr * crData[crPos];
          f32[0] = yData[yPos] + f32[0];
          f32[0] = f32[0] + 0.5;
          buffer[destIndex++] = f32[0].truncate();
        }
        final int vR = (simdEnd - yPos) >> 2;
        _ictRowRed(y4List, yPos >> 2, cr4List, crPos >> 2, vR, buffer,
            destIndex, kRedCr4, half4);
        yPos += vR << 2;
        crPos += vR << 2;
        destIndex += vR << 2;
        cbPos += yPos - yIndex;
      } else if (isG) {
        for (; yPos < yIndex + lead; yPos++, cbPos++, crPos++) {
          f32[0] = kGreenCb * cbData[cbPos];
          f32[0] = yData[yPos] - f32[0];
          f32[1] = kGreenCr * crData[crPos];
          f32[0] = f32[0] - f32[1];
          f32[0] = f32[0] + 0.5;
          buffer[destIndex++] = f32[0].truncate();
        }
        final int vG = (simdEnd - yPos) >> 2;
        _ictRowGreen(y4List, yPos >> 2, cb4List, cbPos >> 2, cr4List,
            crPos >> 2, vG, buffer, destIndex, kGreenCb4, kGreenCr4, half4);
        yPos += vG << 2;
        cbPos += vG << 2;
        crPos += vG << 2;
        destIndex += vG << 2;
      } else {
        for (; yPos < yIndex + lead; yPos++, cbPos++) {
          f32[0] = kBlueCb * cbData[cbPos];
          f32[0] = yData[yPos] + f32[0];
          f32[0] = f32[0] + 0.5;
          buffer[destIndex++] = f32[0].truncate();
        }
        final int vB = (simdEnd - yPos) >> 2;
        _ictRowBlue(y4List, yPos >> 2, cb4List, cbPos >> 2, vB, buffer,
            destIndex, kBlueCb4, half4);
        yPos += vB << 2;
        cbPos += vB << 2;
        destIndex += vB << 2;
        crPos += yPos - yIndex;
      }
      if (isR) {
        while (yPos < yRowEnd) {
          f32[0] = kRedCr * crData[crPos];
          f32[0] = yData[yPos] + f32[0];
          f32[0] = f32[0] + 0.5;
          buffer[destIndex++] = f32[0].truncate();
          yPos++;
          crPos++;
        }
      } else if (isG) {
        while (yPos < yRowEnd) {
          f32[0] = kGreenCb * cbData[cbPos];
          f32[0] = yData[yPos] - f32[0];
          final double partial = f32[0];
          f32[0] = kGreenCr * crData[crPos];
          f32[0] = partial - f32[0];
          f32[0] = f32[0] + 0.5;
          buffer[destIndex++] = f32[0].truncate();
          yPos++;
          cbPos++;
          crPos++;
        }
      } else {
        while (yPos < yRowEnd) {
          f32[0] = kBlueCb * cbData[cbPos];
          f32[0] = yData[yPos] + f32[0];
          f32[0] = f32[0] + 0.5;
          buffer[destIndex++] = f32[0].truncate();
          yPos++;
          cbPos++;
        }
      }
      yIndex += y.scanw;
      cbIndex += cb.scanw;
      crIndex += cr.scanw;
    }

    return target;
  }

  /// `vectors` groups of four red samples: `(int)(y + kRedCr*cr + 0.5f)`.
  ///
  /// The row kernels are separate small functions so the compiler keeps
  /// the vectors unboxed in registers; inside the large transform method
  /// the same loop ran two to three times slower.
  static void _ictRowRed(
      Float32x4List y4List,
      int y4,
      Float32x4List cr4List,
      int cr4,
      int vectors,
      Int32List buffer,
      int destIndex,
      Float32x4 kRedCr4,
      Float32x4 half4) {
    for (var v = 0; v < vectors; v++, y4++, cr4++, destIndex += 4) {
      final Float32x4 out4 = (y4List[y4] + kRedCr4 * cr4List[cr4]) + half4;
      buffer[destIndex] = out4.x.truncate();
      buffer[destIndex + 1] = out4.y.truncate();
      buffer[destIndex + 2] = out4.z.truncate();
      buffer[destIndex + 3] = out4.w.truncate();
    }
  }

  /// `vectors` groups of four green samples:
  /// `(int)(y - kGreenCb*cb - kGreenCr*cr + 0.5f)`.
  static void _ictRowGreen(
      Float32x4List y4List,
      int y4,
      Float32x4List cb4List,
      int cb4,
      Float32x4List cr4List,
      int cr4,
      int vectors,
      Int32List buffer,
      int destIndex,
      Float32x4 kGreenCb4,
      Float32x4 kGreenCr4,
      Float32x4 half4) {
    for (var v = 0; v < vectors; v++, y4++, cb4++, cr4++, destIndex += 4) {
      final Float32x4 out4 =
          ((y4List[y4] - kGreenCb4 * cb4List[cb4]) - kGreenCr4 * cr4List[cr4]) +
              half4;
      buffer[destIndex] = out4.x.truncate();
      buffer[destIndex + 1] = out4.y.truncate();
      buffer[destIndex + 2] = out4.z.truncate();
      buffer[destIndex + 3] = out4.w.truncate();
    }
  }

  /// `vectors` groups of four blue samples: `(int)(y + kBlueCb*cb + 0.5f)`.
  static void _ictRowBlue(
      Float32x4List y4List,
      int y4,
      Float32x4List cb4List,
      int cb4,
      int vectors,
      Int32List buffer,
      int destIndex,
      Float32x4 kBlueCb4,
      Float32x4 half4) {
    for (var v = 0; v < vectors; v++, y4++, cb4++, destIndex += 4) {
      final Float32x4 out4 = (y4List[y4] + kBlueCb4 * cb4List[cb4]) + half4;
      buffer[destIndex] = out4.x.truncate();
      buffer[destIndex + 1] = out4.y.truncate();
      buffer[destIndex + 2] = out4.z.truncate();
      buffer[destIndex + 3] = out4.w.truncate();
    }
  }

  DataBlkInt _fetchIntBlock({
    required int component,
    required DataBlkInt template,
    required bool intern,
  }) {
    final cache = _intScratch[component] ?? DataBlkInt();
    cache
      ..ulx = template.ulx
      ..uly = template.uly
      ..w = template.w
      ..h = template.h
      ..progressive = template.progressive;

    final DataBlk result = intern
        ? _source.getInternCompData(cache, component)
        : _source.getCompData(cache, component);
    if (result is! DataBlkInt) {
      throw StateError('Expected integer block for RCT component $component');
    }
    _intScratch[component] = result;
    return result;
  }

  DataBlkFloat _fetchFloatBlock({
    required int component,
    required DataBlk template,
    required bool intern,
  }) {
    final cache = _floatScratch[component] ?? DataBlkFloat();
    cache
      ..ulx = template.ulx
      ..uly = template.uly
      ..w = template.w
      ..h = template.h
      ..progressive = template.progressive;

    final DataBlk result = intern
        ? _source.getInternCompData(cache, component)
        : _source.getCompData(cache, component);
    if (result is! DataBlkFloat) {
      throw StateError('Expected float block for ICT component $component');
    }
    _floatScratch[component] = result;
    return result;
  }

  static bool _isInstrumentationEnabled() => DecoderInstrumentation.isEnabled();

  void _log(String message) {
    if (_isInstrumentationEnabled()) {
      DecoderInstrumentation.log(_logSource, message);
    }
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'blk_img_data_src.dart';
import 'data_blk.dart';
import 'data_blk_float.dart';
import 'data_blk_int.dart';
import 'img_data_adapter.dart';

/// Brings every subsampled component back to the resolution of the reference
/// grid, so that all components of the image share one sample lattice.
///
/// ISO/IEC 15444-1 (ITU-T T.800) B.2 says the samples of component `c` sit on
/// the reference grid at integer multiples of `(XRsiz_c, YRsiz_c)`, the image
/// component running from `x0 = ceil(XOsiz / XRsiz_c)` to
/// `x1 = ceil(Xsiz / XRsiz_c)` (equation B-1). The nearest component sample to
/// reference grid point `x` is therefore `x ~/ XRsiz_c`, which is what this
/// class replicates: output sample `x` takes the value of input sample
/// `x ~/ XRsiz_c`, so a chroma sample covers the `XRsiz_c` grid points that
/// start at its own position and nothing is shifted by half a pixel.
///
/// Any integer factor from 1 to 255 is handled, which covers every `XRsiz` and
/// `YRsiz` the SIZ marker segment can carry (A.5.1), not just the 2:1 of
/// 4:2:0 and 4:2:2.
///
/// This is the single resampling implementation of the package: the JP2 colour
/// pipeline reaches it through `Resampler`, and raw codestreams — which have
/// no JP2 boxes and therefore no `ColorSpace` — use it directly.
class ComponentUpsampler extends ImgDataAdapter implements BlkImgDataSrc {
  ComponentUpsampler(this.src) : super(src) {
    _initialize();
  }

  /// The source of subsampled component data.
  final BlkImgDataSrc src;

  /// Number of components of the source image.
  late final int ncomps;

  /// Smallest horizontal subsampling factor across all components.
  late final int minCompSubsX;

  /// Smallest vertical subsampling factor across all components.
  late final int minCompSubsY;

  /// Largest horizontal subsampling factor across all components.
  late final int maxCompSubsX;

  /// Largest vertical subsampling factor across all components.
  late final int maxCompSubsY;

  /// Whether [src] has at least one component that needs upsampling.
  ///
  /// Wrapping a source whose components are all at full resolution only adds a
  /// forwarding layer, so callers can skip it.
  static bool isNeeded(BlkImgDataSrc src) {
    final ncomps = src.getNumComps();
    for (var c = 0; c < ncomps; c++) {
      if (src.getCompSubsX(c) != 1 || src.getCompSubsY(c) != 1) {
        return true;
      }
    }
    return false;
  }

  void _initialize() {
    ncomps = src.getNumComps();
    if (ncomps <= 0) {
      throw ArgumentError('Image has no components to resample');
    }
    var minX = src.getCompSubsX(0);
    var minY = src.getCompSubsY(0);
    var maxX = minX;
    var maxY = minY;
    for (var component = 0; component < ncomps; component++) {
      final compSubsX = src.getCompSubsX(component);
      final compSubsY = src.getCompSubsY(component);
      if (compSubsX < 1 || compSubsY < 1) {
        throw ArgumentError(
          'Component $component has a non-positive subsampling factor '
          '($compSubsX, $compSubsY)',
        );
      }
      if (compSubsX < minX) minX = compSubsX;
      if (compSubsY < minY) minY = compSubsY;
      if (compSubsX > maxX) maxX = compSubsX;
      if (compSubsY > maxY) maxY = compSubsY;
    }
    minCompSubsX = minX;
    minCompSubsY = minY;
    maxCompSubsX = maxX;
    maxCompSubsY = maxY;
  }

  @override
  int getFixedPoint(int component) => src.getFixedPoint(component);

  @override
  DataBlk getCompData(DataBlk out, int component) =>
      getInternCompData(out, component);

  @override
  DataBlk getInternCompData(DataBlk out, int component) {
    final wfactor = src.getCompSubsX(component);
    final hfactor = src.getCompSubsY(component);
    if (wfactor == 1 && hfactor == 1) {
      return src.getInternCompData(out, component);
    }

    final y0Out = out.uly;
    final x0Out = out.ulx;
    final y1Out = y0Out + out.h - 1;
    final x1Out = x0Out + out.w - 1;

    final y0In = _floorDiv(y0Out, hfactor);
    final y1In = _floorDiv(y1Out, hfactor);
    final x0In = _floorDiv(x0Out, wfactor);
    final x1In = _floorDiv(x1Out, wfactor);
    final reqW = x1In - x0In + 1;
    final reqH = y1In - y0In + 1;

    switch (out.getDataType()) {
      case DataBlk.typeInt:
        final inblk = DataBlkInt.withGeometry(x0In, y0In, reqW, reqH);
        final sourceBlock =
            src.getInternCompData(inblk, component) as DataBlkInt;
        final dst = _prepareInt(out as DataBlkInt);
        _upsampleInt(
            out, dst, sourceBlock, x0Out, y0Out, x0In, y0In, wfactor, hfactor);
        out.progressive = sourceBlock.progressive;
        break;
      case DataBlk.typeFloat:
        final inblk = DataBlkFloat.withGeometry(x0In, y0In, reqW, reqH);
        final sourceBlock =
            src.getInternCompData(inblk, component) as DataBlkFloat;
        final dst = _prepareFloat(out as DataBlkFloat);
        _upsampleFloat(
            out, dst, sourceBlock, x0Out, y0Out, x0In, y0In, wfactor, hfactor);
        out.progressive = sourceBlock.progressive;
        break;
      default:
        throw ArgumentError('invalid source datablock type');
    }
    return out;
  }

  Int32List _prepareInt(DataBlkInt out) {
    final existing = out.getDataInt();
    if (existing == null || existing.length < out.w * out.h) {
      out.setData(Int32List(out.w * out.h));
    }
    out
      ..offset = 0
      ..scanw = out.w;
    return out.getDataInt()!;
  }

  Float32List _prepareFloat(DataBlkFloat out) {
    final existing = out.getDataFloat();
    if (existing == null || existing.length < out.w * out.h) {
      out.setData(Float32List(out.w * out.h));
    }
    out
      ..offset = 0
      ..scanw = out.w;
    return out.getDataFloat()!;
  }

  void _upsampleInt(
    DataBlkInt out,
    Int32List dst,
    DataBlkInt inblk,
    int x0Out,
    int y0Out,
    int x0In,
    int y0In,
    int wfactor,
    int hfactor,
  ) {
    final srcData = inblk.getDataInt()!;
    for (var row = 0; row < out.h; row++) {
      final inRow = inblk.offset +
          _clampRow(y0Out + row, hfactor, y0In, inblk) * inblk.scanw;
      var target = out.offset + row * out.scanw;
      if (wfactor == 1) {
        final start = inRow + _clampCol(x0Out, 1, x0In, inblk);
        dst.setRange(target, target + out.w, srcData, start);
        continue;
      }
      var xOut = x0Out;
      final xEnd = x0Out + out.w;
      while (xOut < xEnd) {
        final xIn = _floorDiv(xOut, wfactor);
        final runEnd = math.min((xIn + 1) * wfactor, xEnd);
        final value = srcData[inRow + _clampIndex(xIn - x0In, inblk.w)];
        for (var x = xOut; x < runEnd; x++) {
          dst[target++] = value;
        }
        xOut = runEnd;
      }
    }
  }

  void _upsampleFloat(
    DataBlkFloat out,
    Float32List dst,
    DataBlkFloat inblk,
    int x0Out,
    int y0Out,
    int x0In,
    int y0In,
    int wfactor,
    int hfactor,
  ) {
    final srcData = inblk.getDataFloat()!;
    for (var row = 0; row < out.h; row++) {
      final inRow = inblk.offset +
          _clampRow(y0Out + row, hfactor, y0In, inblk) * inblk.scanw;
      var target = out.offset + row * out.scanw;
      if (wfactor == 1) {
        final start = inRow + _clampCol(x0Out, 1, x0In, inblk);
        dst.setRange(target, target + out.w, srcData, start);
        continue;
      }
      var xOut = x0Out;
      final xEnd = x0Out + out.w;
      while (xOut < xEnd) {
        final xIn = _floorDiv(xOut, wfactor);
        final runEnd = math.min((xIn + 1) * wfactor, xEnd);
        final value = srcData[inRow + _clampIndex(xIn - x0In, inblk.w)];
        for (var x = xOut; x < runEnd; x++) {
          dst[target++] = value;
        }
        xOut = runEnd;
      }
    }
  }

  static int _clampRow(int yOut, int hfactor, int y0In, DataBlk inblk) =>
      _clampIndex(_floorDiv(yOut, hfactor) - y0In, inblk.h);

  static int _clampCol(int xOut, int wfactor, int x0In, DataBlk inblk) =>
      _clampIndex(_floorDiv(xOut, wfactor) - x0In, inblk.w);

  /// Keeps an index inside `[0, extent)`.
  ///
  /// A tile whose origin on the reference grid is not a multiple of the
  /// subsampling factor gives the source one sample less than the naive
  /// `ceil(w / factor)`; replicating the edge sample keeps the output complete
  /// instead of reading out of bounds.
  static int _clampIndex(int index, int extent) {
    if (index < 0) return 0;
    if (index >= extent) return extent > 0 ? extent - 1 : 0;
    return index;
  }

  static int _floorDiv(int value, int divisor) {
    final quotient = value ~/ divisor;
    return (value < 0 && quotient * divisor != value) ? quotient - 1 : quotient;
  }

  static int _ceilDiv(int value, int divisor) =>
      (value + divisor - 1) ~/ divisor;

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  // Every component now covers the whole image area of the reference grid
  // (T.800 B-2), which is what `getImgWidth`/`getImgHeight` already report.
  // Multiplying the component size by its subsampling factor, as JJ2000 does,
  // overshoots whenever the image size is not a multiple of that factor.

  @override
  int getCompImgWidth(int component) => src.getImgWidth();

  @override
  int getCompImgHeight(int component) => src.getImgHeight();

  @override
  int getTileCompWidth(int tile, int component) {
    if (tile == src.getTileIdx()) {
      return src.getTileWidth();
    }
    return src.getTileCompWidth(tile, component) * src.getCompSubsX(component);
  }

  @override
  int getTileCompHeight(int tile, int component) {
    if (tile == src.getTileIdx()) {
      return src.getTileHeight();
    }
    return src.getTileCompHeight(tile, component) * src.getCompSubsY(component);
  }

  @override
  int getCompULX(int component) {
    final subsX = src.getCompSubsX(component);
    if (subsX == 1) {
      return src.getCompULX(component);
    }
    final imgULX = src.getImgULX();
    final offset = src.getCompULX(component) - _ceilDiv(imgULX, subsX);
    return imgULX + offset * subsX;
  }

  @override
  int getCompULY(int component) {
    final subsY = src.getCompSubsY(component);
    if (subsY == 1) {
      return src.getCompULY(component);
    }
    final imgULY = src.getImgULY();
    final offset = src.getCompULY(component) - _ceilDiv(imgULY, subsY);
    return imgULY + offset * subsY;
  }

  @override
  String toString() {
    final rep = StringBuffer('[ComponentUpsampler: ncomps=$ncomps');
    for (var c = 0; c < ncomps; c++) {
      rep.write(', comp[$c] ${src.getCompSubsX(c)}:${src.getCompSubsY(c)}');
    }
    rep.write(']');
    return rep.toString();
  }
}

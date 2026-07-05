import 'dart:math' as math;
import 'dart:typed_data';

import '../../image/DataBlkInt.dart';
import '../../image/input/ImgReaderPGM.dart';
import '../../quantization/quantizer/Quantizer.dart';
import '../../wavelet/subband.dart';
import 'ROIMaskGenerator.dart';
import 'roi.dart';

/// Encoder-side ROI mask generator for circular and arbitrary-shape ROIs.
///
/// This is the generic path from JJ2000: it first builds a pixel-domain mask
/// for the whole tile-component, then decomposes that mask with the same
/// subband tree supports used by the wavelet transform.
class ArbROIMaskGenerator extends ROIMaskGenerator {
  ArbROIMaskGenerator(List<ROI> rois, int numComponents, this.src)
      : roiMasks = List<Int32List?>.filled(numComponents, null),
        super(rois, numComponents);

  final Quantizer src;
  final List<Int32List?> roiMasks;

  Int32List? _maskLineLow;
  Int32List? _maskLineHigh;
  Int32List? _paddedMaskLine;
  bool _roiInTile = false;

  @override
  bool getRoiMask(
    DataBlkInt block,
    Subband subband,
    int magnitudeBits,
    int componentIndex,
  ) {
    final x = block.ulx;
    final y = block.uly;
    final width = block.w;
    final height = block.h;
    final tileWidth = subband.w;

    if (!tileMaskComputed[componentIndex]) {
      buildMask(subband, magnitudeBits, componentIndex);
      tileMaskComputed[componentIndex] = true;
    }

    var maskData = block.getDataInt();
    final required = width * height;
    if (maskData == null || maskData.length < required) {
      maskData = Int32List(required);
      block.setDataInt(maskData);
    }
    block
      ..offset = 0
      ..scanw = width;

    if (!_roiInTile) {
      for (var i = 0; i < required; i++) {
        maskData[i] = 0;
      }
      return false;
    }

    final mask = roiMasks[componentIndex];
    if (mask == null) {
      for (var i = 0; i < required; i++) {
        maskData[i] = 0;
      }
      return false;
    }

    var srcIndex = (y + height - 1) * tileWidth + x + width - 1;
    var dstIndex = required - 1;
    final wrap = tileWidth - width;
    for (var row = height; row > 0; row--) {
      for (var col = width; col > 0; col--, srcIndex--, dstIndex--) {
        maskData[dstIndex] = mask[srcIndex];
      }
      srcIndex -= wrap;
    }
    return true;
  }

  @override
  void buildMask(Subband subband, int magnitudeBits, int componentIndex) {
    final tileULX = subband.ulcx;
    final tileULY = subband.ulcy;
    final tileWidth = subband.w;
    final tileHeight = subband.h;
    final lineLength = math.max(tileWidth, tileHeight);

    var mask = roiMasks[componentIndex];
    final maskLength = tileWidth * tileHeight;
    if (mask == null || mask.length < maskLength) {
      mask = Int32List(maskLength);
      roiMasks[componentIndex] = mask;
    } else {
      for (var i = 0; i < maskLength; i++) {
        mask[i] = 0;
      }
    }

    if (_maskLineLow == null || _maskLineLow!.length < (lineLength + 1) ~/ 2) {
      _maskLineLow = Int32List((lineLength + 1) ~/ 2);
    }
    if (_maskLineHigh == null ||
        _maskLineHigh!.length < (lineLength + 1) ~/ 2) {
      _maskLineHigh = Int32List((lineLength + 1) ~/ 2);
    }

    _roiInTile = false;
    for (var r = rois.length - 1; r >= 0; r--) {
      final roi = rois[r];
      if (roi.component != componentIndex) {
        continue;
      }

      if (roi.isArbitrary) {
        _rasterizeArbitraryRoi(
          roi,
          mask,
          magnitudeBits,
          tileULX,
          tileULY,
          tileWidth,
          tileHeight,
        );
      } else if (roi.isRectangular) {
        _rasterizeRectangularRoi(
          roi,
          mask,
          magnitudeBits,
          tileULX,
          tileULY,
          tileWidth,
          tileHeight,
        );
      } else {
        _rasterizeCircularRoi(
          roi,
          mask,
          magnitudeBits,
          tileULX,
          tileULY,
          tileWidth,
          tileHeight,
        );
      }
    }

    if (subband.isNode) {
      final vFilter = subband.getVerWFilter();
      final hFilter = subband.getHorWFilter();
      var support = math.max(
        vFilter.getSynLowNegSupport() + vFilter.getSynLowPosSupport(),
        vFilter.getSynHighNegSupport() + vFilter.getSynHighPosSupport(),
      );
      support = math.max(
        support,
        hFilter.getSynLowNegSupport() + hFilter.getSynLowPosSupport(),
      );
      support = math.max(
        support,
        hFilter.getSynHighNegSupport() + hFilter.getSynHighPosSupport(),
      );
      _paddedMaskLine = Int32List(lineLength + support);

      if (_roiInTile) {
        _decompose(subband, tileWidth, componentIndex);
      }
    }

    roiInTile = _roiInTile;
  }

  void _rasterizeArbitraryRoi(
    ROI roi,
    Int32List mask,
    int scaleValue,
    int tileULX,
    int tileULY,
    int tileWidth,
    int tileHeight,
  ) {
    final maskPGM = roi.mask;
    if (maskPGM == null) {
      throw StateError('Arbitrary ROI is missing its PGM mask');
    }
    if (src.getImgWidth() != maskPGM.getImgWidth() ||
        src.getImgHeight() != maskPGM.getImgHeight()) {
      throw ArgumentError('Input image and ROI mask must have the same size');
    }

    var x = src.getImgULX();
    var y = src.getImgULY();
    var lrx = x + src.getImgWidth() - 1;
    var lry = y + src.getImgHeight() - 1;
    if (x > tileULX + tileWidth ||
        y > tileULY + tileHeight ||
        lrx < tileULX ||
        lry < tileULY) {
      return;
    }

    x -= tileULX;
    lrx -= tileULX;
    y -= tileULY;
    lry -= tileULY;

    var offX = 0;
    var offY = 0;
    if (x < 0) {
      offX = -x;
      x = 0;
    }
    if (y < 0) {
      offY = -y;
      y = 0;
    }

    final width = lrx > tileWidth - 1 ? tileWidth - x : lrx + 1 - x;
    final height = lry > tileHeight - 1 ? tileHeight - y : lry + 1 - y;
    if (width <= 0 || height <= 0) {
      return;
    }

    final srcBlock = DataBlkInt()
      ..ulx = offX
      ..w = width
      ..h = 1;
    const maskDcOffset = -ImgReaderPGM.DC_OFFSET;
    var roiCoefficients = 0;

    var maskIndex = (y + height - 1) * tileWidth + x + width - 1;
    final wrap = tileWidth - width;
    for (var row = height; row > 0; row--) {
      srcBlock.uly = offY + row - 1;
      final filled = maskPGM.getInternCompData(srcBlock, 0) as DataBlkInt;
      final srcData = filled.getDataInt();
      if (srcData == null) {
        throw StateError('ROI mask reader returned no data');
      }
      final base = filled.offset;
      for (var col = width; col > 0; col--, maskIndex--) {
        if (srcData[base + col - 1] != maskDcOffset) {
          mask[maskIndex] = scaleValue;
          roiCoefficients++;
        }
      }
      maskIndex -= wrap;
    }

    if (roiCoefficients != 0) {
      _roiInTile = true;
    }
  }

  void _rasterizeRectangularRoi(
    ROI roi,
    Int32List mask,
    int scaleValue,
    int tileULX,
    int tileULY,
    int tileWidth,
    int tileHeight,
  ) {
    var x = roi.upperLeftX!;
    var y = roi.upperLeftY!;
    var lrx = x + roi.width! - 1;
    var lry = y + roi.height! - 1;
    if (x > tileULX + tileWidth ||
        y > tileULY + tileHeight ||
        lrx < tileULX ||
        lry < tileULY) {
      return;
    }

    _roiInTile = true;
    x -= tileULX;
    lrx -= tileULX;
    y -= tileULY;
    lry -= tileULY;

    if (x < 0) {
      x = 0;
    }
    if (y < 0) {
      y = 0;
    }
    final width = lrx > tileWidth - 1 ? tileWidth - x : lrx + 1 - x;
    final height = lry > tileHeight - 1 ? tileHeight - y : lry + 1 - y;
    if (width <= 0 || height <= 0) {
      return;
    }

    var maskIndex = (y + height - 1) * tileWidth + x + width - 1;
    final wrap = tileWidth - width;
    for (var row = height; row > 0; row--) {
      for (var col = width; col > 0; col--, maskIndex--) {
        mask[maskIndex] = scaleValue;
      }
      maskIndex -= wrap;
    }
  }

  void _rasterizeCircularRoi(
    ROI roi,
    Int32List mask,
    int scaleValue,
    int tileULX,
    int tileULY,
    int tileWidth,
    int tileHeight,
  ) {
    final cx = roi.centerX! - tileULX;
    final cy = roi.centerY! - tileULY;
    final radius = roi.radius!;
    final radiusSquared = radius * radius;
    var maskIndex = tileHeight * tileWidth - 1;
    for (var row = tileHeight - 1; row >= 0; row--) {
      for (var col = tileWidth - 1; col >= 0; col--, maskIndex--) {
        final dx = col - cx;
        final dy = row - cy;
        if (dx * dx + dy * dy < radiusSquared) {
          mask[maskIndex] = scaleValue;
          _roiInTile = true;
        }
      }
    }
  }

  void _decompose(Subband subband, int tileWidth, int componentIndex) {
    if (!subband.isNode) {
      return;
    }

    final mask = roiMasks[componentIndex]!;
    final low = _maskLineLow!;
    final high = _maskLineHigh!;
    final padLine = _paddedMaskLine!;

    _decomposeHorizontal(subband, tileWidth, mask, low, high, padLine);
    _decomposeVertical(subband, tileWidth, mask, low, high, padLine);

    _decompose(subband.getHH(), tileWidth, componentIndex);
    _decompose(subband.getLH(), tileWidth, componentIndex);
    _decompose(subband.getHL(), tileWidth, componentIndex);
    _decompose(subband.getLL(), tileWidth, componentIndex);
  }

  void _decomposeHorizontal(
    Subband subband,
    int tileWidth,
    Int32List mask,
    Int32List low,
    Int32List high,
    Int32List padLine,
  ) {
    final ulx = subband.ulx;
    final uly = subband.uly;
    final width = subband.w;
    final height = subband.h;
    final filter = subband.getHorWFilter();
    final lnSup = filter.getSynLowNegSupport();
    final hnSup = filter.getSynHighNegSupport();
    final lpSup = filter.getSynLowPosSupport();
    final hpSup = filter.getSynHighPosSupport();
    final lowSupport = lnSup + lpSup + 1;
    final highSupport = hnSup + hpSup + 1;
    final highFirst = subband.ulcx % 2;

    final int lowMax;
    final int highMax;
    if (width % 2 == 0) {
      lowMax = width ~/ 2 - 1;
      highMax = lowMax;
    } else if (highFirst == 0) {
      lowMax = (width + 1) ~/ 2 - 1;
      highMax = width ~/ 2 - 1;
    } else {
      highMax = (width + 1) ~/ 2 - 1;
      lowMax = width ~/ 2 - 1;
    }

    final maxNegSupport = math.max(lnSup, hnSup);
    final maxPosSupport = math.max(lpSup, hpSup);
    for (var pin = maxNegSupport - 1; pin >= 0; pin--) {
      padLine[pin] = 0;
    }
    for (var pin = maxNegSupport + width - 1 + maxPosSupport;
        pin >= width;
        pin--) {
      padLine[pin] = 0;
    }

    var lineOffset = (uly + height) * tileWidth + ulx + width - 1;
    for (var row = height - 1; row >= 0; row--) {
      lineOffset -= tileWidth;
      var maskIndex = lineOffset;
      var pin = width - 1 + maxNegSupport;
      for (var col = width; col > 0; col--, maskIndex--, pin--) {
        padLine[pin] = mask[maskIndex];
      }

      var lastPin = maxNegSupport + highFirst + 2 * lowMax + lpSup;
      for (var col = lowMax; col >= 0; col--, lastPin -= 2) {
        low[col] = _maxOverSupport(padLine, lastPin, lowSupport);
      }

      lastPin = maxNegSupport - highFirst + 2 * highMax + 1 + hpSup;
      for (var col = highMax; col >= 0; col--, lastPin -= 2) {
        high[col] = _maxOverSupport(padLine, lastPin, highSupport);
      }

      maskIndex = lineOffset;
      for (var col = highMax; col >= 0; col--, maskIndex--) {
        mask[maskIndex] = high[col];
      }
      for (var col = lowMax; col >= 0; col--, maskIndex--) {
        mask[maskIndex] = low[col];
      }
    }
  }

  void _decomposeVertical(
    Subband subband,
    int tileWidth,
    Int32List mask,
    Int32List low,
    Int32List high,
    Int32List padLine,
  ) {
    final ulx = subband.ulx;
    final uly = subband.uly;
    final width = subband.w;
    final height = subband.h;
    final filter = subband.getVerWFilter();
    final lnSup = filter.getSynLowNegSupport();
    final hnSup = filter.getSynHighNegSupport();
    final lpSup = filter.getSynLowPosSupport();
    final hpSup = filter.getSynHighPosSupport();
    final lowSupport = lnSup + lpSup + 1;
    final highSupport = hnSup + hpSup + 1;
    final highFirst = subband.ulcy % 2;

    final int lowMax;
    final int highMax;
    if (height % 2 == 0) {
      lowMax = height ~/ 2 - 1;
      highMax = lowMax;
    } else if (highFirst == 0) {
      lowMax = (height + 1) ~/ 2 - 1;
      highMax = height ~/ 2 - 1;
    } else {
      highMax = (height + 1) ~/ 2 - 1;
      lowMax = height ~/ 2 - 1;
    }

    final maxNegSupport = math.max(lnSup, hnSup);
    final maxPosSupport = math.max(lpSup, hpSup);
    for (var pin = maxNegSupport - 1; pin >= 0; pin--) {
      padLine[pin] = 0;
    }
    for (var pin = maxNegSupport + height - 1 + maxPosSupport;
        pin >= height;
        pin--) {
      padLine[pin] = 0;
    }

    var lineOffset = (uly + height - 1) * tileWidth + ulx + width;
    for (var col = width - 1; col >= 0; col--) {
      lineOffset--;
      var maskIndex = lineOffset;
      var pin = height - 1 + maxNegSupport;
      for (var row = height; row > 0; row--, maskIndex -= tileWidth, pin--) {
        padLine[pin] = mask[maskIndex];
      }

      var lastPin = maxNegSupport + highFirst + 2 * lowMax + lpSup;
      for (var row = lowMax; row >= 0; row--, lastPin -= 2) {
        low[row] = _maxOverSupport(padLine, lastPin, lowSupport);
      }

      lastPin = maxNegSupport - highFirst + 2 * highMax + 1 + hpSup;
      for (var row = highMax; row >= 0; row--, lastPin -= 2) {
        high[row] = _maxOverSupport(padLine, lastPin, highSupport);
      }

      maskIndex = lineOffset;
      for (var row = highMax; row >= 0; row--, maskIndex -= tileWidth) {
        mask[maskIndex] = high[row];
      }
      for (var row = lowMax; row >= 0; row--, maskIndex -= tileWidth) {
        mask[maskIndex] = low[row];
      }
    }
  }

  int _maxOverSupport(Int32List line, int lastPin, int support) {
    var maxValue = 0;
    var pin = lastPin;
    for (var i = support; i > 0; i--, pin--) {
      final value = line[pin];
      if (value > maxValue) {
        maxValue = value;
      }
    }
    return maxValue;
  }

  @override
  String toString() => 'Generic ROI mask generator';
}

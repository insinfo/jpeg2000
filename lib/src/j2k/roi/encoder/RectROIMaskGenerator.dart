import 'dart:typed_data';

import '../../image/DataBlkInt.dart';
import '../../wavelet/subband.dart';
import 'roi.dart';
import 'RoiMaskGenerator.dart';
import 'SubbandRectRoiMask.dart';

/// Encoder-side mask generator optimized for purely rectangular ROIs.
class RectROIMaskGenerator extends ROIMaskGenerator {
  RectROIMaskGenerator(List<ROI> rois, int numComponents)
      : roiCountPerComponent = List<int>.filled(numComponents, 0),
        subbandMasks = List<SubbandRectROIMask?>.filled(numComponents, null),
        super(rois, numComponents) {
    for (final roi in rois) {
      roiCountPerComponent[roi.component]++;
    }
  }

  final List<int> roiCountPerComponent;
  final List<SubbandRectROIMask?> subbandMasks;

  List<int> _ulxs = const <int>[];
  List<int> _ulys = const <int>[];
  List<int> _lrxs = const <int>[];
  List<int> _lrys = const <int>[];

  @override
  bool getRoiMask(
    DataBlkInt block,
    Subband subband,
    int magnitudeBits,
    int componentIndex,
  ) {
    if (block.w == 0 || block.h == 0) {
      return false;
    }

    if (!tileMaskComputed[componentIndex]) {
      buildMask(subband, magnitudeBits, componentIndex);
      tileMaskComputed[componentIndex] = true;
    }

    final int totalSamples = block.w * block.h;
    final Int32List maskData;
    final existing = block.getDataInt();
    if (existing == null || existing.length < totalSamples) {
      maskData = Int32List(totalSamples);
      block.setDataInt(maskData);
      block.offset = 0;
      block.scanw = block.w;
    } else {
      maskData = existing;
      for (var i = 0; i < totalSamples; i++) {
        maskData[i] = 0;
      }
    }

    if (!roiInTile) {
      return false;
    }

    final SubbandRectROIMask? maskRoot = subbandMasks[componentIndex];
    if (maskRoot == null) {
      return false;
    }

    final maskCandidate = maskRoot.locateSubband(block.ulx, block.uly);
    if (maskCandidate is! SubbandRectROIMask) {
      throw StateError('Expected SubbandRectROIMask but found $maskCandidate');
    }
    final SubbandRectROIMask maskNode = maskCandidate;

    final int width = block.w;
    final int height = block.h;
    final int localXOffset = block.ulx - maskNode.ulx;
    final int localYOffset = block.uly - maskNode.uly;

    final List<int> leftEdges = maskNode.ulxs;
    final List<int> topEdges = maskNode.ulys;
    final List<int> rightEdges = maskNode.lrxs;
    final List<int> bottomEdges = maskNode.lrys;
    final int roiCount = leftEdges.length;

    if (roiCount == 0) {
      return false;
    }

    for (var index = roiCount - 1; index >= 0; index--) {
      var left = leftEdges[index] - localXOffset;
      if (left < 0) {
        left = 0;
      } else if (left >= width) {
        left = width;
      }

      var top = topEdges[index] - localYOffset;
      if (top < 0) {
        top = 0;
      } else if (top >= height) {
        top = height;
      }

      var right = rightEdges[index] - localXOffset;
      if (right < 0) {
        right = -1;
      } else if (right >= width) {
        right = width - 1;
      }

      var bottom = bottomEdges[index] - localYOffset;
      if (bottom < 0) {
        bottom = -1;
      } else if (bottom >= height) {
        bottom = height - 1;
      }

      if (left > right || top > bottom) {
        continue;
      }

      var writerIndex = bottom * width + right;
      final int roiWidth = right - left;
      final int wrap = width - roiWidth - 1;
      final int rows = bottom - top;

      for (var row = rows; row >= 0; row--) {
        for (var col = roiWidth; col >= 0; col--, writerIndex--) {
          maskData[writerIndex] = magnitudeBits;
        }
        writerIndex -= wrap;
      }
    }

    return true;
  }

  @override
  void buildMask(Subband subband, int magnitudeBits, int componentIndex) {
    final int expected = roiCountPerComponent[componentIndex];
    _ulxs = List<int>.filled(expected, 0);
    _ulys = List<int>.filled(expected, 0);
    _lrxs = List<int>.filled(expected, -1);
    _lrys = List<int>.filled(expected, -1);

    var count = 0;
    final int tileStartX = subband.ulcx;
    final int tileStartY = subband.ulcy;
    final int tileWidth = subband.w;
    final int tileHeight = subband.h;
    final int tileEndX = tileStartX + tileWidth - 1;
    final int tileEndY = tileStartY + tileHeight - 1;

    for (final roi in rois) {
      if (roi.component != componentIndex) {
        continue;
      }
      if (!roi.isRectangular) {
        // TODO: add support for circular and arbitrary shapes.
        continue;
      }
      final int roiLeft = roi.upperLeftX!;
      final int roiTop = roi.upperLeftY!;
      final int roiRight = roiLeft + roi.width! - 1;
      final int roiBottom = roiTop + roi.height! - 1;

      if (roiLeft > tileEndX ||
          roiTop > tileEndY ||
          roiRight < tileStartX ||
          roiBottom < tileStartY) {
        continue;
      }

      var clampedLeft = roiLeft - tileStartX;
      var clampedTop = roiTop - tileStartY;
      var clampedRight = roiRight - tileStartX;
      var clampedBottom = roiBottom - tileStartY;

      if (clampedLeft < 0) {
        clampedLeft = 0;
      }
      if (clampedTop < 0) {
        clampedTop = 0;
      }
      if (clampedRight >= tileWidth) {
        clampedRight = tileWidth - 1;
      }
      if (clampedBottom >= tileHeight) {
        clampedBottom = tileHeight - 1;
      }

      if (count >= _ulxs.length) {
        continue;
      }

      _ulxs[count] = clampedLeft;
      _ulys[count] = clampedTop;
      _lrxs[count] = clampedRight;
      _lrys[count] = clampedBottom;
      count++;
    }

    roiInTile = count > 0;
    subbandMasks[componentIndex] = SubbandRectROIMask(
      subband,
      _ulxs,
      _ulys,
      _lrxs,
      _lrys,
      count,
    );
  }

  @override
  String toString() => 'Fast rectangular ROI mask generator';
}


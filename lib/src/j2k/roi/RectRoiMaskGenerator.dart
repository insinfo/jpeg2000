import '../image/DataBlk.dart';
import 'RectRoiSpec.dart';
import 'RoiMaskGenerator.dart';
import 'RectangularRoi.dart';

/// Applies rectangular ROI definitions per tile/component.
class RectROIMaskGenerator extends ROIMaskGenerator {
  RectROIMaskGenerator({
    Map<int, Map<int, RectangularROI>>? perTileComponent,
    RectangularROI? defaultROI,
    RectROISpec? spec,
  })  : _perTileComponent = perTileComponent,
        _defaultROI = defaultROI,
        _spec = spec;

  final Map<int, Map<int, RectangularROI>>? _perTileComponent;
  final RectangularROI? _defaultROI;
  final RectROISpec? _spec;

  /// Returns the ROI associated with [tileIndex] and [component], or `null`.
  RectangularROI? _lookup(int tileIndex, int component) {
    final spec = _spec;
    if (spec != null) {
      return spec.roiFor(tileIndex, component);
    }
    final perTile = _perTileComponent?[tileIndex];
    if (perTile == null) {
      return _defaultROI;
    }
    return perTile[component] ?? perTile[-1] ?? _defaultROI;
  }

  @override
  void fillMask({
    required int tileIndex,
    required int component,
    required DataBlk block,
    required List<int> mask,
  }) {
    final roi = _lookup(tileIndex, component);
    final effectiveROI = roi;

    final width = block.w;
    final height = block.h;
    final startX = block.ulx;
    final startY = block.uly;

    if (effectiveROI == null ||
        !effectiveROI.intersectsBlock(startX, startY, width, height)) {
      mask.fillRange(0, mask.length, 0);
      return;
    }

    var index = 0;
    for (var row = 0; row < height; row++) {
      final y = startY + row;
      for (var col = 0; col < width; col++, index++) {
        final x = startX + col;
        mask[index] = effectiveROI.contains(x, y) ? 1 : 0;
      }
    }
  }
}


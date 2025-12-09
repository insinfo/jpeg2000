import '../image/DataBlk.dart';

/// Produces binary masks indicating which samples belong to the ROI.
abstract class ROIMaskGenerator {
  const ROIMaskGenerator();

  /// Populates [mask] with ROI markers for the region described by [block].
  ///
  /// A non-zero value means the corresponding sample belongs to the ROI and
  /// should remain scaled, whereas zero marks samples that require de-scaling.
  void fillMask({
    required int tileIndex,
    required int component,
    required DataBlk block,
    required List<int> mask,
  });
}

/// Default implementation that declares no region of interest.
class NoOpROIMaskGenerator extends ROIMaskGenerator {
  const NoOpROIMaskGenerator();

  @override
  void fillMask({
    required int tileIndex,
    required int component,
    required DataBlk block,
    required List<int> mask,
  }) {
    mask.fillRange(0, mask.length, 0);
  }
}


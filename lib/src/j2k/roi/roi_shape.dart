/// Describes a geometric region of interest in image (tile-relative) coordinates.
abstract class ROIShape {
  const ROIShape();

  /// Returns `true` when the point (`x`, `y`) belongs to the region.
  bool contains(int x, int y);
}

import 'RoiShape.dart';

/// Simple axis-aligned rectangular ROI shape.
class RectangularROI extends ROIShape {
  RectangularROI({
    required this.x0,
    required this.y0,
    required this.width,
    required this.height,
  })  : assert(width >= 0, 'width must be non-negative'),
        assert(height >= 0, 'height must be non-negative');

  final int x0;
  final int y0;
  final int width;
  final int height;

  int get x1 => x0 + width;
  int get y1 => y0 + height;

  @override
  bool contains(int x, int y) {
    return x >= x0 && x < x1 && y >= y0 && y < y1;
  }

  /// Returns `true` if any point of the block starting at (`blockX`, `blockY`)
  /// with dimensions (`blockWidth`, `blockHeight`) overlaps the ROI.
  bool intersectsBlock(int blockX, int blockY, int blockWidth, int blockHeight) {
    if (width == 0 || height == 0 || blockWidth == 0 || blockHeight == 0) {
      return false;
    }
    final blockX1 = blockX + blockWidth;
    final blockY1 = blockY + blockHeight;
    return blockX1 > x0 && blockX < x1 && blockY1 > y0 && blockY < y1;
  }
}


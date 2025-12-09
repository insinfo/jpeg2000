import '../../image/input/ImgReaderPgm.dart';

/// Describes a single region of interest used by the encoder.
///
/// The Java implementation supports rectangular, circular and arbitrary
/// shapes loaded from a PGM mask. For now we only exercise the rectangular
/// branch but we model all variants so the remaining logic can be ported
/// without changing the public surface.
class ROI {
  ROI.arbitrary({
    required this.component,
    required this.mask,
  })  : shape = ROIShapeType.arbitrary,
        upperLeftX = null,
        upperLeftY = null,
        width = null,
        height = null,
        centerX = null,
        centerY = null,
        radius = null;

  ROI.rectangular({
    required this.component,
    required int ulx,
    required int uly,
    required int w,
    required int h,
  })  : shape = ROIShapeType.rectangle,
        upperLeftX = ulx,
        upperLeftY = uly,
        width = w,
        height = h,
        centerX = null,
        centerY = null,
        radius = null,
        mask = null;

  ROI.circular({
    required this.component,
    required int x,
    required int y,
    required int radius,
  })  : shape = ROIShapeType.circle,
        upperLeftX = null,
        upperLeftY = null,
        width = null,
        height = null,
        centerX = x,
        centerY = y,
        radius = radius,
        mask = null;

  /// Component index that owns this ROI.
  final int component;

  /// Indicates which kind of geometry the ROI uses.
  final ROIShapeType shape;

  /// Optional PGM mask for arbitrary shapes.
  final ImgReaderPGM? mask;

  /// Upper-left x coordinate for rectangular ROIs.
  final int? upperLeftX;

  /// Upper-left y coordinate for rectangular ROIs.
  final int? upperLeftY;

  /// Width of the rectangular ROI.
  final int? width;

  /// Height of the rectangular ROI.
  final int? height;

  /// Center x coordinate for circular ROIs.
  final int? centerX;

  /// Center y coordinate for circular ROIs.
  final int? centerY;

  /// Radius for circular ROIs.
  final int? radius;

  bool get isArbitrary => shape == ROIShapeType.arbitrary;
  bool get isRectangular => shape == ROIShapeType.rectangle;
  bool get isCircular => shape == ROIShapeType.circle;

  @override
  String toString() {
    switch (shape) {
      case ROIShapeType.arbitrary:
        return 'ROI(shape=arbitrary, component=$component, mask=$mask)';
      case ROIShapeType.rectangle:
        return 'ROI(shape=rectangle, component=$component, '
            'ulx=$upperLeftX, uly=$upperLeftY, w=$width, h=$height)';
      case ROIShapeType.circle:
        return 'ROI(shape=circle, component=$component, '
            'cx=$centerX, cy=$centerY, radius=$radius)';
    }
  }
}

/// Enumerates the supported ROI geometries.
enum ROIShapeType { arbitrary, rectangle, circle }


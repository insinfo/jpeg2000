import '../icc_profile.dart';
import 'icc_tag.dart';

/// A tag containing a triplet.
class ICCXYZType extends ICCTag {
  /// x component
  final int x;

  /// y component
  final int y;

  /// z component
  final int z;

  /// Normalization utility
  static int doubleToXYZ(double x) {
    return (x * 65536.0 + 0.5).floor();
  }

  /// Normalization utility
  static double xyzToDouble(int x) {
    return x / 65536.0;
  }

  /// Construct this tag from its constituant parts
  ICCXYZType(super.signature, super.data, super.offset, super.length)
      : x = ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size),
        y = ICCProfile.getInt(data, offset + 3 * ICCProfile.int_size),
        z = ICCProfile.getInt(data, offset + 4 * ICCProfile.int_size);

  /// Constructor for subclasses that need to specify values manually
  ICCXYZType.fromValues(super.signature, super.data, super.offset, super.length,
      this.x, this.y, this.z);

  /// Return the string rep of this tag.
  @override
  String toString() {
    return "[${super.toString()}($x, $y, $z)]";
  }
}

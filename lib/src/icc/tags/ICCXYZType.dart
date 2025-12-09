import 'dart:typed_data';
import '../ICCProfile.dart';
import 'ICCTag.dart';

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
  ICCXYZType(int signature, Uint8List data, int offset, int length)
      : x = ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size),
        y = ICCProfile.getInt(data, offset + 3 * ICCProfile.int_size),
        z = ICCProfile.getInt(data, offset + 4 * ICCProfile.int_size),
        super(signature, data, offset, length);

  /// Constructor for subclasses that need to specify values manually
  ICCXYZType.fromValues(
      int signature, Uint8List data, int offset, int length, this.x, this.y, this.z)
      : super(signature, data, offset, length);

  /// Return the string rep of this tag.
  @override
  String toString() {
    return "[${super.toString()}($x, $y, $z)]";
  }
}


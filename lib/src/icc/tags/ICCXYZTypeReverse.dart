import 'dart:typed_data';
import '../ICCProfile.dart';
import 'ICCXYZType.dart';

/// A tag containing a triplet.
class ICCXYZTypeReverse extends ICCXYZType {
  /// Construct this tag from its constituant parts
  ICCXYZTypeReverse(int signature, Uint8List data, int offset, int length)
      : super.fromValues(
            signature,
            data,
            offset,
            length,
            ICCProfile.getInt(data, offset + 4 * ICCProfile.int_size),
            ICCProfile.getInt(data, offset + 3 * ICCProfile.int_size),
            ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size));

  /// Return the string rep of this tag.
  @override
  String toString() {
    return "[${super.toString()}($x, $y, $z)]";
  }
}


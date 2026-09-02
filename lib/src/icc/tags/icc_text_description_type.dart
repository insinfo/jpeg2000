import 'dart:typed_data';
import '../icc_profile.dart';
import 'icc_tag.dart';

/// A text based ICC tag
class ICCTextDescriptionType extends ICCTag {
  /// Tag fields
  final int reserved;

  /// Tag fields
  final int size;

  /// Tag fields
  final Uint8List ascii;

  /// Construct this tag from its constituant parts
  ICCTextDescriptionType(int signature, Uint8List data, int offset, int length)
      : reserved = ICCProfile.getInt(data, offset + ICCProfile.intSize),
        size = ICCProfile.getInt(data, offset + 2 * ICCProfile.intSize),
        ascii = Uint8List(
            ICCProfile.getInt(data, offset + 2 * ICCProfile.intSize) - 1),
        super(signature, data, offset, length) {
    int currentOffset = offset + 3 * ICCProfile.intSize;
    // System.arraycopy (data,offset,ascii,0,size-1);
    // In Dart:
    for (int i = 0; i < size - 1; i++) {
      ascii[i] = data[currentOffset + i];
    }
  }

  /// Return the string rep of this tag.
  @override
  String toString() {
    return "[${super.toString()} \"${String.fromCharCodes(ascii)}\"]";
  }
}

import 'dart:typed_data';
import '../ICCProfile.dart';
import 'ICCTag.dart';

/// A text based ICC tag
class ICCTextDescriptionType extends ICCTag {
  /// Tag fields
  final int type;

  /// Tag fields
  final int reserved;

  /// Tag fields
  final int size;

  /// Tag fields
  final Uint8List ascii;

  /// Construct this tag from its constituant parts
  ICCTextDescriptionType(int signature, Uint8List data, int offset, int length)
      : type = ICCProfile.getInt(data, offset),
        reserved = ICCProfile.getInt(data, offset + ICCProfile.int_size),
        size = ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size),
        ascii = Uint8List(ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size) - 1),
        super(signature, data, offset, length) {
    
    int currentOffset = offset + 3 * ICCProfile.int_size;
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


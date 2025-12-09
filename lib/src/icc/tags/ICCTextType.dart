import 'dart:typed_data';
import '../ICCProfile.dart';
import 'ICCTag.dart';

/// A text based ICC tag
class ICCTextType extends ICCTag {
  /// Tag fields
  final int type;

  /// Tag fields
  final int reserved;

  /// Tag fields
  final Uint8List ascii;

  /// Construct this tag from its constituant parts
  ICCTextType(int signature, Uint8List data, int offset, int length)
      : type = ICCProfile.getInt(data, offset),
        reserved = ICCProfile.getInt(data, offset + ICCProfile.int_size),
        ascii = _readAscii(data, offset + 2 * ICCProfile.int_size),
        super(signature, data, offset, length);

  static Uint8List _readAscii(Uint8List data, int offset) {
    int size = 0;
    while (data[offset + size] != 0) {
      ++size;
    }
    Uint8List ascii = Uint8List(size);
    for (int i = 0; i < size; i++) {
      ascii[i] = data[offset + i];
    }
    return ascii;
  }

  /// Return the string rep of this tag.
  @override
  String toString() {
    return "[${super.toString()} \"${String.fromCharCodes(ascii)}\"]";
  }
}


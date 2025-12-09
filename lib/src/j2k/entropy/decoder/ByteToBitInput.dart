import 'dart:typed_data';

import 'ByteInputBuffer.dart';

/// Bit-level reader that wraps a [ByteInputBuffer] and performs JPEG 2000
/// bit unstuffing exactly like the Java JJ2000 implementation.
class ByteToBitInput {
  ByteToBitInput(this._input);

  final ByteInputBuffer _input;
  int _bitBuffer = 0;
  int _bitPosition = -1;

  /// Reads one bit from the stream, applying the selective arithmetic coding
  /// bit unstuffing rule when the previous byte was 0xFF.
  int readBit() {
    if (_bitPosition < 0) {
      if ((_bitBuffer & 0xFF) != 0xFF) {
        _bitBuffer = _input.read();
        _bitPosition = 7;
      } else {
        _bitBuffer = _input.read();
        _bitPosition = 6;
      }
    }
    return (_bitBuffer >> _bitPosition--) & 0x01;
  }

  /// Verifies that dangling bits follow the alternating 0101… padding pattern.
  bool checkBytePadding() {
    if (_bitPosition < 0 && (_bitBuffer & 0xFF) == 0xFF) {
      _bitBuffer = _input.read();
      _bitPosition = 6;
    }

    if (_bitPosition >= 0) {
      final remainingMask = (1 << (_bitPosition + 1)) - 1;
      final sequence = _bitBuffer & remainingMask;
      if (sequence != (0x55 >> (7 - _bitPosition))) {
        return true;
      }
    }

    if (_bitBuffer != -1) {
      if (_bitBuffer == 0xFF && _bitPosition == 0) {
        final next = _input.read();
        if ((next & 0xFF) >= 0x80) {
          return true;
        }
      } else {
        if (_input.read() != -1) {
          return true;
        }
      }
    }

    return false;
  }

  /// Clears the bit buffer so the next read starts on a byte boundary.
  void flush() {
    _bitBuffer = 0;
    _bitPosition = -1;
  }

  /// Resets the underlying byte buffer to a new segment and flushes state.
  void setByteArray(Uint8List? buffer, int offset, int length) {
    _input.setByteArray(buffer, offset, length);
    _bitBuffer = 0;
    _bitPosition = -1;
  }
}


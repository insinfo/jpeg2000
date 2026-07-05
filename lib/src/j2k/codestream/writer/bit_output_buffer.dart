import 'dart:typed_data';

/// This class implements a buffer for writing bits, with the required bit
/// stuffing policy for the packet headers. The bits are stored in a byte array
/// in the order in which they are written. The byte array is automatically
/// reallocated and enlarged whenever necessary. A BitOutputBuffer object may
/// be reused by calling its 'reset()' method.
///
/// NOTE: The methods implemented in this class are intended to be used only
/// in writing packet heads, since a special bit stuffing procedure is used, as
/// required for the packet heads.
class BitOutputBuffer {
  /// The increment size for the buffer, 16 bytes. This is the
  /// number of bytes that are added to the buffer each time it is
  /// needed to enlarge it.
  static const int SZ_INCR = 16;

  /// The initial size for the buffer, 32 bytes.
  static const int SZ_INIT = 32;

  /// The buffer where we store the data
  Uint8List _buf;

  /// The position of the current byte to write
  int _curbyte = 0;

  /// The number of available bits in the current byte
  int _avbits = 8;

  /// Creates a new BitOutputBuffer width a buffer of length 'SZ_INIT'.
  BitOutputBuffer() : _buf = Uint8List(SZ_INIT);

  /// Resets the buffer. This rewinds the current position to the start of
  /// the buffer and sets all tha data to 0. Note that no new buffer is
  /// allocated, so this will affect any data that was returned by the
  /// 'getBuffer()' method.
  void reset() {
    _curbyte = 0;
    _avbits = 8;
    _buf.fillRange(0, _buf.length, 0);
  }

  /// Writes a bit to the buffer at the current position. The value 'bit'
  /// must be either 0 or 1, otherwise it corrupts the bits that have been
  /// already written. The buffer is enlarged, by 'SZ_INCR' bytes, if
  /// necessary.
  void writeBit(int bit) {
    _buf[_curbyte] |= bit << --_avbits;
    if (_avbits > 0) {
      // There is still place in current byte for next bit
      return;
    } else {
      // End of current byte => goto next
      if (_buf[_curbyte] != 0xFF) {
        // We don't need bit stuffing
        _avbits = 8;
      } else {
        // We need to stuff a bit (next MSBit is 0)
        _avbits = 7;
      }
      _curbyte++;
      if (_curbyte == _buf.length) {
        // We are at end of 'buf' => extend it
        final oldBuf = _buf;
        _buf = Uint8List(oldBuf.length + SZ_INCR);
        _buf.setRange(0, oldBuf.length, oldBuf);
      }
    }
  }

  /// Writes the n least significant bits of 'bits' to the buffer at the
  /// current position. The least significant bit is written last. The 32-n
  /// most significant bits of 'bits' must be 0, otherwise corruption of the
  /// buffer will result. The buffer is enlarged, by 'SZ_INCR' bytes, if
  /// necessary.
  void writeBits(int bits, int n) {
    // Check that we have enough place in 'buf' for n bits, and that we do
    // not fill last byte, taking into account possibly stuffed bits (max
    // 2)
    if (((_buf.length - _curbyte) << 3) - 8 + _avbits <= n + 2) {
      // Not enough place, extend it
      final oldBuf = _buf;
      _buf = Uint8List(oldBuf.length + SZ_INCR);
      _buf.setRange(0, oldBuf.length, oldBuf);
      // SZ_INCR is always 6 or more, so it is enough to hold all the
      // new bits plus the ones to come after
    }
    // Now write the bits
    if (n >= _avbits) {
      // Complete the current byte
      n -= _avbits;
      _buf[_curbyte] |= bits >> n;
      if (_buf[_curbyte] != 0xFF) {
        // We don't need bit stuffing
        _avbits = 8;
      } else {
        // We need to stuff a bit (next MSBit is 0)
        _avbits = 7;
      }
      _curbyte++;
      // Write whole bytes
      while (n >= _avbits) {
        n -= _avbits;
        _buf[_curbyte] |= (bits >> n) & (~(1 << _avbits));
        if (_buf[_curbyte] != 0xFF) {
          // We don't need bit stuffing
          _avbits = 8;
        } else {
          // We need to stuff a bit (next MSBit is 0)
          _avbits = 7;
        }
        _curbyte++;
      }
    }
    // Finish last byte (we know that now n < avbits)
    if (n > 0) {
      _avbits -= n;
      _buf[_curbyte] |= (bits & ((1 << n) - 1)) << _avbits;
    }
    if (_avbits == 0) {
      // Last byte is full
      if (_buf[_curbyte] != 0xFF) {
        // We don't need bit stuffing
        _avbits = 8;
      } else {
        // We need to stuff a bit (next MSBit is 0)
        _avbits = 7;
      }
      _curbyte++; // We already ensured that we have enough place
    }
  }

  /// Returns the current length of the buffer, in bytes.
  int getLength() {
    if (_avbits == 8) {
      // A integral number of bytes
      return _curbyte;
    } else {
      // Some bits in last byte
      return _curbyte + 1;
    }
  }

  /// Returns the byte buffer. This is the internal byte buffer so it should
  /// not be modified. Only the first N elements have valid data, where N is
  /// the value returned by 'getLength()'
  Uint8List getBuffer() {
    return _buf;
  }

  /// Returns the byte buffer data in a new array. This is a copy of the
  /// internal byte buffer. If 'data' is non-null it is used to return the
  /// data. This array should be large enough to contain all the data,
  /// otherwise a IndexOutOfBoundsException is thrown by the Java system. The
  /// number of elements returned is what 'getLength()' returns.
  Uint8List toByteArray([Uint8List? data]) {
    final len = (_avbits == 8) ? _curbyte : _curbyte + 1;
    if (data == null) {
      data = Uint8List(len);
    }
    data.setRange(0, len, _buf);
    return data;
  }

  @override
  String toString() {
    return "bits written = ${(_curbyte * 8 + (8 - _avbits))}, curbyte = $_curbyte, avbits = $_avbits";
  }
}

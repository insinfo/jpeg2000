import 'ByteOutputBuffer.dart';

/// This class provides an adapter to perform bit based output on byte based
/// output objects that inherit from a 'ByteOutputBuffer' class. This class
/// implements the bit stuffing policy needed for the 'selective arithmetic
/// coding bypass' mode of the entropy coder. This class also delays the output
/// of a trailing 0xFF, since they are synthetized be the decoder.
class BitToByteOutput {
  /// Whether or not predictable termination is requested. This value is
  /// important when the last byte before termination is an 0xFF
  bool _isPredTerm = false;

  /// The alternating sequence of 0's and 1's used for byte padding
  static const int PAD_SEQ = 0x2A;

  /// Flag that indicates if an FF has been delayed
  bool _delFF = false;

  /// The byte based output
  ByteOutputBuffer out;

  /// The bit buffer
  int _bbuf = 0;

  /// The position of the next bit to put in the bit buffer. When it is 7
  /// the bit buffer 'bbuf' is empty. The value should always be between 7
  /// and 0 (i.e. if it gets to -1, the bit buffer should be immediately
  /// written to the byte output).
  int _bpos = 7;

  /// The number of written bytes (excluding the bit buffer)
  int _nb = 0;

  /// Instantiates a new 'BitToByteOutput' object that uses 'out' as the
  /// underlying byte based output.
  ///
  /// [out] The underlying byte based output
  BitToByteOutput(this.out);

  /// Writes to the bit stream the symbols contained in the 'symbuf'
  /// buffer. The least significant bit of each element in 'symbuf'is
  /// written.
  ///
  /// [symbuf] The symbols to write
  ///
  /// [nsym] The number of symbols in symbuf
  void writeBits(List<int> symbuf, int nsym) {
    int i;
    int bbuf, bpos;
    bbuf = this._bbuf;
    bpos = this._bpos;
    // Write symbol by symbol to bit buffer
    for (i = 0; i < nsym; i++) {
      bbuf |= (symbuf[i] & 0x01) << (bpos--);
      if (bpos < 0) {
        // Bit buffer is full, write it
        if (bbuf != 0xFF) {
          // No bit-stuffing needed
          if (_delFF) {
            // Output delayed 0xFF if any
            out.write(0xFF);
            _nb++;
            _delFF = false;
          }
          out.write(bbuf);
          _nb++;
          bpos = 7;
        } else {
          // We need to do bit stuffing on next byte
          _delFF = true;
          bpos = 6; // One less bit in next byte
        }
        bbuf = 0;
      }
    }
    this._bbuf = bbuf;
    this._bpos = bpos;
  }

  /// Write a bit to the output. The least significant bit of 'bit' is
  /// written to the output.
  ///
  /// [bit]
  void writeBit(int bit) {
    _bbuf |= (bit & 0x01) << (_bpos--);
    if (_bpos < 0) {
      if (_bbuf != 0xFF) {
        // No bit-stuffing needed
        if (_delFF) {
          // Output delayed 0xFF if any
          out.write(0xFF);
          _nb++;
          _delFF = false;
        }
        // Output the bit buffer
        out.write(_bbuf);
        _nb++;
        _bpos = 7;
      } else {
        // We need to do bit stuffing on next byte
        _delFF = true;
        _bpos = 6; // One less bit in next byte
      }
      _bbuf = 0;
    }
  }

  /// Writes the contents of the bit buffer and byte aligns the output by
  /// filling bits with an alternating sequence of 0's and 1's.
  void flush() {
    if (_delFF) {
      // There was a bit stuffing
      if (_bpos != 6) {
        // Bit buffer is not empty
        // Output delayed 0xFF
        out.write(0xFF);
        _nb++;
        _delFF = false;
        // Pad to byte boundary with an alternating sequence of 0's
        // and 1's.
        _bbuf |= (PAD_SEQ >>> (6 - _bpos));
        // Output the bit buffer
        out.write(_bbuf);
        _nb++;
        _bpos = 7;
        _bbuf = 0;
      } else if (_isPredTerm) {
        out.write(0xFF);
        _nb++;
        out.write(0x2A);
        _nb++;
        _bpos = 7;
        _bbuf = 0;
        _delFF = false;
      }
    } else {
      // There was no bit stuffing
      if (_bpos != 7) {
        // Bit buffer is not empty
        // Pad to byte boundary with an alternating sequence of 0's and
        // 1's.
        _bbuf |= (PAD_SEQ >>> (6 - _bpos));
        // Output the bit buffer (bbuf can not be 0xFF)
        out.write(_bbuf);
        _nb++;
        _bpos = 7;
        _bbuf = 0;
      }
    }
  }

  /// Terminates the bit stream by calling 'flush()' and then
  /// 'reset()'. Finally, it returns the number of bytes effectively written.
  ///
  /// @return The number of bytes effectively written.
  int terminate() {
    flush();
    int savedNb = _nb;
    reset();
    return savedNb;
  }

  /// Resets the bit buffer to empty, without writing anything to the
  /// underlying byte output, and resets the byte count. The underlying byte
  /// output is NOT reset.
  void reset() {
    _delFF = false;
    _bpos = 7;
    _bbuf = 0;
    _nb = 0;
  }

  /// Returns the length, in bytes, of the output bit stream as written by
  /// this object. If the output bit stream does not have an integer number
  /// of bytes in length then it is rounded to the next integer.
  ///
  /// @return The length, in bytes, of the output bit stream.
  int length() {
    if (_delFF) {
      // If bit buffer is empty we just need 'nb' bytes. If not we need
      // the delayed FF and the padded bit buffer.
      return _nb + 2;
    } else {
      // If the bit buffer is empty, we just need 'nb' bytes. If not, we
      // add length of the padded bit buffer
      return _nb + ((_bpos == 7) ? 0 : 1);
    }
  }

  /// Set the flag according to whether or not the predictable termination is
  /// requested.
  ///
  /// [isPredTerm] Whether or not predictable termination is requested.
  void setPredTerm(bool isPredTerm) {
    this._isPredTerm = isPredTerm;
  }
}


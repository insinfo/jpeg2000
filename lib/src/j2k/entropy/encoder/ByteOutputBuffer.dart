import 'dart:typed_data';

/// This class provides a buffering output stream similar to
/// ByteArrayOutputStream, with some additional methods.
///
/// Once an array has been written to an output stream or to a byte array,
/// the object can be reused as a new stream if the reset() method is
/// called.
///
/// Unlike the ByteArrayOutputStream class, this class is not thread
/// safe.
///
/// @see #reset
class ByteOutputBuffer {
  /// The buffer where the data is stored
  late Uint8List _buf;

  /// The number of valid bytes in the buffer
  int _count = 0;

  /// The buffer increase size
  static const int BUF_INC = 512;

  /// The default initial buffer size
  static const int BUF_DEF_LEN = 256;

  /// Creates a new byte array output stream. The buffer capacity is
  /// initially BUF_DEF_LEN bytes, though its size increases if necessary.
  ByteOutputBuffer([int size = BUF_DEF_LEN]) {
    _buf = Uint8List(size);
  }

  /// Writes the specified byte to this byte array output stream. The
  /// functionality provided by this implementation is the same as for the
  /// one in the superclass, however this method is not synchronized and
  /// therefore not safe thread, but faster.
  ///
  /// [b] The byte to write
  void write(int b) {
    if (_count == _buf.length) {
      // Resize buffer
      final tmpbuf = _buf;
      _buf = Uint8List(_buf.length + BUF_INC);
      _buf.setRange(0, _count, tmpbuf);
    }
    _buf[_count++] = b;
  }

  /// Copies the specified part of the stream to the 'outbuf' byte array.
  ///
  /// [off] The index of the first element in the stream to copy.
  ///
  /// [len] The number of elements of the array to copy
  ///
  /// [outbuf] The destination array
  ///
  /// [outoff] The index of the first element in 'outbuf' where to write
  /// the data.
  void toByteArray(int off, int len, Uint8List outbuf, int outoff) {
    // Copy the data
    for (int i = 0; i < len; i++) {
      outbuf[outoff + i] = _buf[off + i];
    }
  }

  /// Returns the number of valid bytes in the output buffer (count class
  /// variable).
  ///
  /// @return The number of bytes written to the buffer
  int size() {
    return _count;
  }

  /// Discards all the buffered data, by resetting the counter of written
  /// bytes to 0.
  void reset() {
    _count = 0;
  }

  /// Returns the byte buffered at the given position in the buffer. The
  /// position in the buffer is the index of the 'write()' method call after
  /// the last call to 'reset()'.
  ///
  /// [pos] The position of the byte to return
  ///
  /// @return The value (betweeb 0-255) of the byte at position 'pos'.
  int getByte(int pos) {
    if (pos >= _count) {
      throw ArgumentError();
    }
    return _buf[pos];
  }
}

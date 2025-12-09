import 'dart:typed_data';

import '../../io/exceptions.dart';

/// Byte buffer that supports incremental reads and appends for entropy decoding.
class ByteInputBuffer {
  ByteInputBuffer(Uint8List buffer)
      : _buffer = buffer,
        _count = buffer.length;

  ByteInputBuffer.view(Uint8List buffer, int offset, int length)
      : assert(offset >= 0 && length >= 0 && offset + length <= buffer.length),
        _buffer = buffer,
        _pos = offset,
        _count = offset + length;

  late Uint8List _buffer;
  int _count;
  int _pos = 0;

  /// Resets the accessible window on the underlying buffer.
  void setByteArray(Uint8List? buffer, int offset, int length) {
    if (buffer == null) {
      if (length < 0 || _count + length > _buffer.length) {
        throw ArgumentError(
          'Invalid length $length for existing buffer (count=$_count, bufferLength=${_buffer.length})',
        );
      }
      if (offset < 0) {
        _pos = _count;
        _count += length;
      } else {
        _pos = offset;
        _count = offset + length;
      }
      return;
    }

    if (offset < 0 || length < 0 || offset + length > buffer.length) {
      throw ArgumentError('Invalid offset/length ($offset,$length) for new buffer');
    }
    _buffer = buffer;
    _pos = offset;
    _count = offset + length;
  }

  /// Appends [length] bytes starting at [offset] from [data] to this stream.
  void addByteArray(Uint8List data, int offset, int length) {
    if (length < 0 || offset < 0 || offset + length > data.length) {
      throw ArgumentError('Invalid source slice');
    }
    if (_count + length <= _buffer.length) {
      _buffer.setRange(_count, _count + length, data, offset);
      _count += length;
      return;
    }

    final unread = _count - _pos;
    if (unread + length <= _buffer.length) {
      _buffer.setRange(0, unread, _buffer, _pos);
    } else {
      final newBuffer = Uint8List(unread + length);
      newBuffer.setRange(0, unread, _buffer, _pos);
      _buffer = newBuffer;
    }
    _count = unread;
    _pos = 0;
    _buffer.setRange(_count, _count + length, data, offset);
    _count += length;
  }

  /// Reads the next byte and throws if none remain.
  int readChecked() {
    final value = read();
    if (value == -1) {
      throw EOFException('ByteInputBuffer: end of buffer');
    }
    return value;
  }

  /// Reads the next byte or returns -1 when exhausted.
  int read() {
    if (_pos < _count) {
      return _buffer[_pos++] & 0xFF;
    }
    return -1;
  }
}

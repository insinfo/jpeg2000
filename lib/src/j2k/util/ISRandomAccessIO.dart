import 'dart:async';
import 'dart:typed_data';

import '../io/EndianType.dart';
import '../io/exceptions.dart';
import '../io/RandomAccessIO.dart';
import 'Int32Utils.dart';

/// Read-only implementation that mirrors JJ2000's `ISRandomAccessIO`.
class ISRandomAccessIO implements RandomAccessIO {
  ISRandomAccessIO(Uint8List data)
      : _buffer = data,
        _pos = 0,
        _closed = false;

  /// Creates an instance by eagerly reading all bytes from [stream].
  static Future<ISRandomAccessIO> fromStream(Stream<List<int>> stream) async {
    // TODO(jj2000): Implement incremental buffering to avoid loading full streams in memory.
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return ISRandomAccessIO(Uint8List.fromList(builder.takeBytes()));
  }

  Uint8List _buffer;
  int _pos;
  bool _closed;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('ISRandomAccessIO is closed');
    }
  }

  void _ensureAvailable(int length) {
    if (_pos + length > _buffer.length) {
      if (_pos == _buffer.length) {
        throw EOFException();
      }
      throw EOFException('Requested $length bytes from $_pos but only '
          '${_buffer.length - _pos} remain');
    }
  }

  int _readUnsigned(int length) {
    _ensureOpen();
    _ensureAvailable(length);
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | _buffer[_pos++];
    }
    return value;
  }

  @override
  void close() {
    _buffer = Uint8List(0);
    _pos = 0;
    _closed = true;
  }

  @override
  int getPos() {
    _ensureOpen();
    return _pos;
  }

  @override
  int length() {
    _ensureOpen();
    return _buffer.length;
  }

  @override
  void seek(int offset) {
    _ensureOpen();
    if (offset < 0 || offset > _buffer.length) {
      throw EOFException('Seek beyond range: $offset');
    }
    _pos = offset;
  }

  @override
  int read() {
    _ensureOpen();
    _ensureAvailable(1);
    return _buffer[_pos++];
  }

  @override
  void readFully(List<int> buffer, int offset, int length) {
    _ensureOpen();
    RangeError.checkValidRange(offset, offset + length, buffer.length);
    _ensureAvailable(length);
    buffer.setRange(offset, offset + length, _buffer, _pos);
    _pos += length;
  }

  @override
  void write(int value) {
    throw UnsupportedError('ISRandomAccessIO is read-only');
  }

  @override
  int getByteOrdering() => EndianType.bigEndian;

  @override
  int readByte() {
    final value = read();
    return value >= 0x80 ? value - 0x100 : value;
  }

  @override
  int readUnsignedByte() => read();

  @override
  int readShort() => _readUnsigned(2).toSigned(16);

  @override
  int readUnsignedShort() => _readUnsigned(2);

  @override
  int readInt() => Int32Utils.asInt32(_readUnsigned(4));

  @override
  int readUnsignedInt() => _readUnsigned(4);

  @override
  int readLong() => _readUnsigned(8).toSigned(64);

  @override
  double readFloat() => _byteData(4).getFloat32(0, Endian.big);

  @override
  double readDouble() => _byteData(8).getFloat64(0, Endian.big);

  ByteData _byteData(int count) {
    _ensureOpen();
    _ensureAvailable(count);
    final data = ByteData.view(
      _buffer.buffer,
      _buffer.offsetInBytes + _pos,
      count,
    );
    _pos += count;
    return data;
  }

  @override
  int skipBytes(int count) {
    _ensureOpen();
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Cannot skip negative bytes');
    }
    final remaining = _buffer.length - _pos;
    final skipped = count < remaining ? count : remaining;
    _pos += skipped;
    return skipped;
  }

  @override
  void flush() {
    // No-op for read-only implementation.
  }

  @override
  void writeByte(int value) => throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeShort(int value) => throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeInt(int value) => throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeLong(int value) => throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeFloat(double value) => throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeDouble(double value) => throw UnsupportedError('ISRandomAccessIO is read-only');
}


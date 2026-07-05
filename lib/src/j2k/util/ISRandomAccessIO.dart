import 'dart:async';
import 'dart:typed_data';

import '../io/EndianType.dart';
import '../io/exceptions.dart';
import '../io/RandomAccessIO.dart';
import 'Int32Utils.dart';

/// Read-only implementation that mirrors JJ2000's `ISRandomAccessIO`.
class ISRandomAccessIO implements RandomAccessIO {
  ISRandomAccessIO(Uint8List data)
      : _storage = _ContiguousInputStorage(data),
        _pos = 0,
        _closed = false;

  ISRandomAccessIO._withStorage(_InputStorage storage)
      : _storage = storage,
        _pos = 0,
        _closed = false;

  /// Creates a seekable instance from [stream] without requiring `dart:io`.
  ///
  /// Stream chunks are retained as separate byte arrays instead of being
  /// concatenated into a single large [Uint8List]. This keeps the synchronous
  /// [RandomAccessIO] contract intact on Dart VM and Dart Web, while avoiding
  /// the extra full-buffer copy that a `BytesBuilder.takeBytes()` path needs.
  static Future<ISRandomAccessIO> fromStream(Stream<List<int>> stream) async {
    final chunks = <Uint8List>[];
    var totalLength = 0;
    await for (final chunk in stream) {
      if (chunk.isEmpty) {
        continue;
      }
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      chunks.add(bytes);
      totalLength += bytes.length;
    }
    return ISRandomAccessIO._withStorage(
      _ChunkedInputStorage(chunks, totalLength),
    );
  }

  _InputStorage? _storage;
  int _pos;
  bool _closed;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('ISRandomAccessIO is closed');
    }
  }

  void _ensureAvailable(int length) {
    final storage = _storage!;
    if (_pos + length > storage.length) {
      if (_pos == storage.length) {
        throw EOFException();
      }
      throw EOFException('Requested $length bytes from $_pos but only '
          '${storage.length - _pos} remain');
    }
  }

  int _readUnsigned(int length) {
    _ensureOpen();
    _ensureAvailable(length);
    var value = 0;
    final storage = _storage!;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | storage.readByte(_pos++);
    }
    return value;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _storage?.close();
    _storage = null;
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
    return _storage!.length;
  }

  @override
  void seek(int offset) {
    _ensureOpen();
    if (offset < 0 || offset > _storage!.length) {
      throw EOFException('Seek beyond range: $offset');
    }
    _pos = offset;
  }

  @override
  int read() {
    _ensureOpen();
    _ensureAvailable(1);
    final value = _storage!.readByte(_pos);
    _pos++;
    return value;
  }

  @override
  void readFully(List<int> buffer, int offset, int length) {
    _ensureOpen();
    RangeError.checkValidRange(offset, offset + length, buffer.length);
    _ensureAvailable(length);
    _storage!.readRange(_pos, buffer, offset, length);
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
    final bytes = Uint8List(count);
    readFully(bytes, 0, count);
    return ByteData.view(bytes.buffer);
  }

  @override
  int skipBytes(int count) {
    _ensureOpen();
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Cannot skip negative bytes');
    }
    final remaining = _storage!.length - _pos;
    final skipped = count < remaining ? count : remaining;
    _pos += skipped;
    return skipped;
  }

  @override
  void flush() {
    // No-op for read-only implementation.
  }

  @override
  void writeByte(int value) =>
      throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeShort(int value) =>
      throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeInt(int value) =>
      throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeLong(int value) =>
      throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeFloat(double value) =>
      throw UnsupportedError('ISRandomAccessIO is read-only');

  @override
  void writeDouble(double value) =>
      throw UnsupportedError('ISRandomAccessIO is read-only');
}

abstract class _InputStorage {
  int get length;

  int readByte(int position);

  void readRange(int position, List<int> target, int offset, int length);

  void close();
}

class _ContiguousInputStorage implements _InputStorage {
  _ContiguousInputStorage(this._bytes);

  Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  int readByte(int position) => _bytes[position];

  @override
  void readRange(int position, List<int> target, int offset, int length) {
    target.setRange(offset, offset + length, _bytes, position);
  }

  @override
  void close() {
    _bytes = Uint8List(0);
  }
}

class _ChunkedInputStorage implements _InputStorage {
  _ChunkedInputStorage(this._chunks, this.length)
      : _starts = List<int>.filled(_chunks.length, 0) {
    var offset = 0;
    for (var i = 0; i < _chunks.length; i++) {
      _starts[i] = offset;
      offset += _chunks[i].length;
    }
  }

  List<Uint8List> _chunks;
  List<int> _starts;
  int _lastChunkIndex = 0;

  @override
  final int length;

  @override
  int readByte(int position) {
    final chunkIndex = _findChunk(position);
    return _chunks[chunkIndex][position - _starts[chunkIndex]];
  }

  @override
  void readRange(int position, List<int> target, int offset, int length) {
    var remaining = length;
    var sourcePosition = position;
    var targetOffset = offset;

    while (remaining > 0) {
      final chunkIndex = _findChunk(sourcePosition);
      final chunk = _chunks[chunkIndex];
      final chunkOffset = sourcePosition - _starts[chunkIndex];
      final count = remaining < chunk.length - chunkOffset
          ? remaining
          : chunk.length - chunkOffset;
      target.setRange(
        targetOffset,
        targetOffset + count,
        chunk,
        chunkOffset,
      );
      remaining -= count;
      sourcePosition += count;
      targetOffset += count;
    }
  }

  int _findChunk(int position) {
    if (_lastChunkIndex < _chunks.length) {
      final start = _starts[_lastChunkIndex];
      final end = start + _chunks[_lastChunkIndex].length;
      if (position >= start && position < end) {
        return _lastChunkIndex;
      }
    }

    var low = 0;
    var high = _starts.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final start = _starts[mid];
      final end = start + _chunks[mid].length;
      if (position < start) {
        high = mid - 1;
      } else if (position >= end) {
        low = mid + 1;
      } else {
        _lastChunkIndex = mid;
        return mid;
      }
    }
    throw EOFException('Position beyond range: $position');
  }

  @override
  void close() {
    _chunks = <Uint8List>[];
    _starts = <int>[];
    _lastChunkIndex = 0;
  }
}

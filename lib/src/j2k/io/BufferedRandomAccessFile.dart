import 'dart:io';
import 'dart:typed_data';

import 'exceptions.dart';
import 'RandomAccessIO.dart';

/// Buffered random-access I/O wrapper that mirrors JJ2000's
/// [BufferedRandomAccessFile].
///
/// The implementation keeps a sliding in-memory window over the underlying
/// file so repeated small reads and writes avoid syscalls. Subclasses define
/// the endianness-specific decoding/encoding helpers.
abstract class BufferedRandomAccessFile implements RandomAccessIO {
  BufferedRandomAccessFile.file(
    File file,
    String mode, {
    int bufferSize = _defaultBufferSize,
  }) {
    if (bufferSize <= 0) {
      throw ArgumentError.value(bufferSize, 'bufferSize', 'Must be positive');
    }
    _fileName = file.path;
    _isReadOnly = _parseMode(mode) == _FileMode.readOnly;
    _file = _openFile(file, mode);
    _byteBuffer = Uint8List(bufferSize);
    _readNewBuffer(0);
  }

  BufferedRandomAccessFile.path(
    String path,
    String mode, {
    int bufferSize = _defaultBufferSize,
  }) : this.file(File(path), mode, bufferSize: bufferSize);

  static const int _defaultBufferSize = 512;

  late final RandomAccessFile _file;
  late Uint8List _byteBuffer;
  late final bool _isReadOnly;
  late final String _fileName;

  bool _byteBufferChanged = false;
  bool _isEOFInBuffer = false;
  bool _closed = false;
  int _offset = 0;
  int _pos = 0;
  int _maxByte = 0;
  int byteOrdering = 0;

  static _FileMode _parseMode(String mode) {
    switch (mode) {
      case 'r':
        return _FileMode.readOnly;
      case 'rw':
        return _FileMode.readWriteTruncate;
      case 'rw+':
        return _FileMode.readWrite;
      default:
        throw ArgumentError.value(mode, 'mode', 'Unsupported mode');
    }
  }

  static RandomAccessFile _openFile(File file, String mode) {
    final parsed = _parseMode(mode);
    switch (parsed) {
      case _FileMode.readOnly:
        if (!file.existsSync()) {
          throw FileSystemException('File not found', file.path);
        }
        return file.openSync(mode: FileMode.read);
      case _FileMode.readWriteTruncate:
        file.createSync(recursive: true);
        // Truncate any existing content while keeping metadata.
        file.writeAsBytesSync(const <int>[]);
        return file.openSync(mode: FileMode.write);
      case _FileMode.readWrite:
        file.createSync(recursive: true);
        // Append mode keeps the existing contents while allowing both read and
        // write operations once the position is adjusted by callers.
        return file.openSync(mode: FileMode.append);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('BufferedRandomAccessFile is closed');
    }
  }

  void _readNewBuffer(int off) {
    _ensureOpen();
    if (_byteBufferChanged) {
      flush();
    }

    if (_isReadOnly && off > _file.lengthSync()) {
      throw EOFException();
    }

    _offset = off;
    _file.setPositionSync(_offset);

    final bytesRead = _file.readIntoSync(_byteBuffer, 0, _byteBuffer.length);
    _maxByte = bytesRead < 0 ? 0 : bytesRead;
    _pos = 0;
    _isEOFInBuffer = _maxByte < _byteBuffer.length;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    flush();
    _byteBuffer = Uint8List(0);
    _file.closeSync();
    _closed = true;
  }

  @override
  int getPos() {
    _ensureOpen();
    return _offset + _pos;
  }

  @override
  int length() {
    _ensureOpen();
    final fileLength = _file.lengthSync();
    final bufferedLength = _offset + _maxByte;
    return bufferedLength > fileLength ? bufferedLength : fileLength;
  }

  @override
  void seek(int offset) {
    _ensureOpen();
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Cannot seek to negative positions');
    }

    if (offset >= _offset && offset < _offset + _byteBuffer.length) {
      if (_isReadOnly && _isEOFInBuffer && offset > _offset + _maxByte) {
        throw EOFException();
      }
      _pos = offset - _offset;
      return;
    }

    _readNewBuffer(offset);
  }

  @override
  int read() {
    _ensureOpen();
    if (_pos < _maxByte) {
      return _byteBuffer[_pos++] & 0xff;
    }
    if (_isEOFInBuffer) {
      _pos = _maxByte + 1;
      throw EOFException();
    }
    _readNewBuffer(_offset + _pos);
    return read();
  }

  @override
  void readFully(List<int> buffer, int offset, int length) {
    _ensureOpen();
    RangeError.checkValidRange(offset, offset + length, buffer.length);
    var remaining = length;
    var dest = offset;
    while (remaining > 0) {
      if (_pos < _maxByte) {
        var chunk = _maxByte - _pos;
        if (chunk > remaining) {
          chunk = remaining;
        }
        buffer.setRange(dest, dest + chunk, _byteBuffer, _pos);
        _pos += chunk;
        dest += chunk;
        remaining -= chunk;
      } else if (_isEOFInBuffer) {
        _pos = _maxByte + 1;
        throw EOFException();
      } else {
        _readNewBuffer(_offset + _pos);
      }
    }
  }

  @override
  void write(int value) {
    _ensureOpen();
    if (_isReadOnly) {
      throw FileSystemException('File is read only', _fileName);
    }

    if (_pos < _byteBuffer.length) {
      _byteBuffer[_pos] = value & 0xff;
      if (_pos >= _maxByte) {
        _maxByte = _pos + 1;
      }
      _pos++;
      _byteBufferChanged = true;
      _isEOFInBuffer = _maxByte < _byteBuffer.length;
    } else {
      _readNewBuffer(_offset + _pos);
      write(value);
    }
  }

  void writeByteRaw(int value) => write(value);

  void writeBytes(List<int> values, int offset, int length) {
    RangeError.checkValidRange(offset, offset + length, values.length);
    for (var i = offset; i < offset + length; i++) {
      write(values[i]);
    }
  }

  @override
  void writeByte(int value) => writeByteRaw(value);

  @override
  void flush() {
    _ensureOpen();
    if (!_byteBufferChanged) {
      return;
    }
    _file
      ..setPositionSync(_offset)
      ..writeFromSync(_byteBuffer, 0, _maxByte);
    _byteBufferChanged = false;
  }

  @override
  int skipBytes(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Cannot skip negative bytes');
    }
    _ensureOpen();
    if (count <= _maxByte - _pos) {
      _pos += count;
      return count;
    }
    seek(_offset + _pos + count);
    return count;
  }

  @override
  int readByte() {
    final value = read();
    return value >= 0x80 ? value - 0x100 : value;
  }

  @override
  int readUnsignedByte() => read();

  @override
  int getByteOrdering() => byteOrdering;

  @override
  String toString() =>
      'BufferedRandomAccessFile($_fileName, ${_isReadOnly ? 'read-only' : 'read/write'})';
}

enum _FileMode {
  readOnly,
  readWriteTruncate,
  readWrite,
}


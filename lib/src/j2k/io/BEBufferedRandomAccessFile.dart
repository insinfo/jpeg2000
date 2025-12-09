import 'dart:io';
import 'dart:typed_data';

import '../util/Int32Utils.dart';
import 'BufferedRandomAccessFile.dart';
import 'EndianType.dart';

/// Big-endian implementation of [BufferedRandomAccessFile].
class BEBufferedRandomAccessFile extends BufferedRandomAccessFile {
  BEBufferedRandomAccessFile.file(
    File file,
    String mode, {
    int bufferSize = 512,
  }) : super.file(file, mode, bufferSize: bufferSize) {
    byteOrdering = EndianType.bigEndian;
  }

  BEBufferedRandomAccessFile.path(
    String path,
    String mode, {
    int bufferSize = 512,
  }) : super.path(path, mode, bufferSize: bufferSize) {
    byteOrdering = EndianType.bigEndian;
  }

  @override
  void writeShort(int value) {
    writeByte((value >> 8) & 0xff);
    writeByte(value & 0xff);
  }

  @override
  void writeInt(int value) {
    writeByte((value >> 24) & 0xff);
    writeByte((value >> 16) & 0xff);
    writeByte((value >> 8) & 0xff);
    writeByte(value & 0xff);
  }

  @override
  void writeLong(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.big);
    final bytes = data.buffer.asUint8List();
    writeBytes(bytes, 0, bytes.length);
  }

  @override
  void writeFloat(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.big);
    final bytes = data.buffer.asUint8List();
    writeBytes(bytes, 0, bytes.length);
  }

  @override
  void writeDouble(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.big);
    final bytes = data.buffer.asUint8List();
    writeBytes(bytes, 0, bytes.length);
  }

  @override
  int readShort() {
    final msb = read();
    final lsb = read();
    final value = (msb << 8) | lsb;
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  @override
  int readUnsignedShort() => (read() << 8) | read();

  @override
  int readInt() {
    final b1 = read();
    final b2 = read();
    final b3 = read();
    final b4 = read();
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  @override
  int readUnsignedInt() {
    final value = readInt();
    return Int32Utils.mask32(value);
  }

  @override
  int readLong() {
    final data = ByteData(8);
    for (var i = 0; i < 8; i++) {
      data.setUint8(i, read());
    }
    return data.getInt64(0, Endian.big);
  }

  @override
  double readFloat() {
    final data = ByteData(4);
    for (var i = 0; i < 4; i++) {
      data.setUint8(i, read());
    }
    return data.getFloat32(0, Endian.big);
  }

  @override
  double readDouble() {
    final data = ByteData(8);
    for (var i = 0; i < 8; i++) {
      data.setUint8(i, read());
    }
    return data.getFloat64(0, Endian.big);
  }
}


import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../BlkImgDataSrc.dart';
import '../DataBlkInt.dart';
import 'DataPacker.dart';
import 'ImgWriter.dart';

/// Emits component samples to the JJ2000 PGX format (big-endian, ML order).
class ImgWriterPgx extends ImgWriter {
  ImgWriterPgx(
    File output,
    BlkImgDataSrc source,
    int componentIndex,
    bool isSigned,
  ) {
    if (componentIndex < 0 || componentIndex >= source.getNumComps()) {
      throw ArgumentError.value(
        componentIndex,
        'componentIndex',
        'Component index out of range.',
      );
    }

    src = source;
    width = source.getImgWidth();
    height = source.getImgHeight();

    _component = componentIndex;
    _isSigned = isSigned;
    _fixedPoint = source.getFixedPoint(componentIndex);
    _bitDepth = source.getNomRangeBits(componentIndex);
    if (_bitDepth <= 0 || _bitDepth > 31) {
      throw ArgumentError('PGX supports bit depths between 1 and 31.');
    }
    _bytesPerSample = _bitDepth <= 8 ? 1 : (_bitDepth <= 16 ? 2 : 4);
    _maxValue = _isSigned
        ? (1 << (_bitDepth - 1)) - 1
        : (1 << _bitDepth) - 1;
    _minValue = _isSigned ? -(1 << (_bitDepth - 1)) : 0;
    _levelShift = _isSigned ? 0 : 1 << (_bitDepth - 1);

    output.parent.createSync(recursive: true);
    _file = output.openSync(mode: FileMode.write);
    _writeHeader();
  }

  factory ImgWriterPgx.fromPath(
    String outputPath,
    BlkImgDataSrc source,
    int componentIndex,
    bool isSigned,
  ) {
    return ImgWriterPgx(File(outputPath), source, componentIndex, isSigned);
  }

  late final int _component;
  late final bool _isSigned;
  late final int _bitDepth;
  late final int _bytesPerSample;
  late final int _levelShift;
  late final int _maxValue;
  late final int _minValue;
  late final int _fixedPoint;

  final DataBlkInt _block = DataBlkInt();
  RandomAccessFile? _file;
  Uint8List? _buffer;
  int _pixelDataOffset = 0;

  @override
  void close() {
    final writer = _file;
    if (writer == null) {
      return;
    }
    final expectedLength = width * height * _bytesPerSample + _pixelDataOffset;
    var currentLength = writer.lengthSync();
    if (currentLength < expectedLength) {
      writer.setPositionSync(currentLength);
      final padding = expectedLength - currentLength;
      final zeros = Uint8List(math.min(padding, 4096));
      var remaining = padding;
      while (remaining > 0) {
        final limit = remaining < zeros.length ? remaining : zeros.length;
        writer.writeFromSync(zeros, 0, limit);
        remaining -= limit;
      }
    }
    writer.closeSync();
    _file = null;
    _buffer = null;
  }

  @override
  void flush() {
    _buffer = null;
  }

  @override
  void writeTile() {
    final tileIdx = src.getTileIdx();
    final tileWidth = src.getTileCompWidth(tileIdx, _component);
    final tileHeight = src.getTileCompHeight(tileIdx, _component);
    var row = 0;
    while (row < tileHeight) {
      final stripHeight = math.min(ImgWriter.defStripHeight, tileHeight - row);
      writeRegion(0, row, tileWidth, stripHeight);
      row += stripHeight;
    }
  }

  @override
  void writeRegion(int ulx, int uly, int regionWidth, int regionHeight) {
    final writer = _file;
    if (writer == null) {
      throw StateError('Writer closed.');
    }
    final bufferSize = regionWidth * _bytesPerSample;
    _buffer ??= Uint8List(bufferSize);
    if (_buffer!.length < bufferSize) {
      _buffer = Uint8List(bufferSize);
    }

    final tOffx = src.getCompULX(_component) -
        (src.getImgULX() / src.getCompSubsX(_component)).ceil();
    final tOffy = src.getCompULY(_component) -
        (src.getImgULY() / src.getCompSubsY(_component)).ceil();

    for (var line = 0; line < regionHeight; line++) {
      _block
        ..ulx = ulx
        ..uly = uly + line
        ..w = regionWidth
        ..h = 1;

      DataBlkInt block;
      do {
        block = src.getInternCompData(_block, _component) as DataBlkInt;
      } while (block.progressive);

      final data = block.data;
      if (data == null) {
        throw StateError('Data block is empty for component $_component.');
      }

      var sourceIndex = block.offset;
      var targetIndex = 0;
      for (var x = 0; x < regionWidth; x++) {
        var sample = _fixedPoint == 0
            ? data[sourceIndex] + _levelShift
            : (data[sourceIndex] >> _fixedPoint) + _levelShift;
        if (sample < _minValue) {
          sample = _minValue;
        } else if (sample > _maxValue) {
          sample = _maxValue;
        }
        DataPacker.packBigEndian(_buffer!, targetIndex, _bytesPerSample, sample);
        sourceIndex++;
        targetIndex += _bytesPerSample;
      }

      final imageRow = uly + tOffy + line;
      final imageCol = ulx + tOffx;
      final offset = _pixelDataOffset +
          (width * imageRow + imageCol) * _bytesPerSample;
      writer.setPositionSync(offset);
      writer.writeFromSync(_buffer!, 0, bufferSize);
    }
  }

  void _writeHeader() {
    final signToken = _isSigned ? '-' : '+';
    final header = ascii.encode('PG ML $signToken $_bitDepth $width $height\n');
    _file!.setPositionSync(0);
    _file!.writeFromSync(header);
    _pixelDataOffset = header.length;
  }
}


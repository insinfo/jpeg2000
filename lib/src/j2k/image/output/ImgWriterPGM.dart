import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../util/DecoderInstrumentation.dart';
import '../BlkImgDataSrc.dart';
import '../DataBlkInt.dart';
import 'ImgWriter.dart';

/// Writes a single component to the raw binary PGM (P5) format.
class ImgWriterPgm extends ImgWriter {
  static const String _logSource = 'ImgWriterPGM';
  ImgWriterPgm(File output, BlkImgDataSrc source, int componentIndex) {
    final numComps = source.getNumComps();
    if (componentIndex < 0 || componentIndex >= numComps) {
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
    _fixedPoint = source.getFixedPoint(componentIndex);
    _bitDepth = source.getNomRangeBits(componentIndex);
    _levelShift = _bitDepth > 0 ? 1 << (_bitDepth - 1) : 0;
    if (_bitDepth > 8) {
      _downShift = _bitDepth - 8;
    }

    output.parent.createSync(recursive: true);
    _file = output.openSync(mode: FileMode.write);
    _writeHeader();
  }

  factory ImgWriterPgm.fromPath(
    String outputPath,
    BlkImgDataSrc source,
    int componentIndex,
  ) {
    return ImgWriterPgm(File(outputPath), source, componentIndex);
  }

  late final int _component;
  late final int _fixedPoint;
  late final int _bitDepth;
  late final int _levelShift;
  int _downShift = 0;

  final DataBlkInt _block = DataBlkInt();
  RandomAccessFile? _file;
  Uint8List? _lineBuffer;
  int _pixelDataOffset = 0;
  static const int debugSamples = 8;
  static int _debugLines = 2;
  static final List<int> _rawDebug = List<int>.filled(debugSamples, 0);
  static final List<int> _shiftedDebug = List<int>.filled(debugSamples, 0);

  @override
  void close() {
    final writer = _file;
    if (writer == null) {
      return;
    }
    final expectedLength = width * height + _pixelDataOffset;
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
    _lineBuffer = null;
  }

  @override
  void flush() {
    _lineBuffer = null;
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
    final bufferSize = regionWidth;
    _lineBuffer ??= Uint8List(bufferSize);
    if (_lineBuffer!.length < bufferSize) {
      _lineBuffer = Uint8List(bufferSize);
    }

    final tOffx = src.getCompULX(_component) -
        (src.getImgULX() / src.getCompSubsX(_component)).ceil();
    final tOffy = src.getCompULY(_component) -
        (src.getImgULY() / src.getCompSubsY(_component)).ceil();

    for (var line = 0; line < regionHeight; line++) {
      final captureDebug = _isInstrumentationEnabled() && _debugLines > 0;
      var debugCount = 0;
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
      for (var x = 0; x < regionWidth; x++) {
        final rawSample = _fixedPoint == 0
            ? data[sourceIndex]
            : (data[sourceIndex] >> _fixedPoint);
        var sample = rawSample + _levelShift;
        if (sample < 0) {
          sample = 0;
        } else {
          final maxValue = 1 << _bitDepth;
          if (sample >= maxValue) {
            sample = maxValue - 1;
          }
        }
        _lineBuffer![x] = (sample >> _downShift) & 0xff;
        if (captureDebug && debugCount < debugSamples) {
          _rawDebug[debugCount] = rawSample;
          _shiftedDebug[debugCount] = sample;
          debugCount++;
        }
        sourceIndex++;
      }

      if (captureDebug) {
        final tuples = <String>[];
        for (var i = 0; i < debugCount; i++) {
          tuples.add('${_rawDebug[i]}->${_shiftedDebug[i]}');
        }
        _log('PGM writer debug line $_debugLines: ${tuples.join(' ')}');
        _debugLines--;
      }

      final imageRow = uly + tOffy + line;
      final imageCol = ulx + tOffx;
      final offset = _pixelDataOffset + width * imageRow + imageCol;
      writer.setPositionSync(offset);
      writer.writeFromSync(_lineBuffer!, 0, bufferSize);
    }
  }

  void _writeHeader() {
    final header = ascii.encode('P5\n$width $height\n255\n');
    _file!.setPositionSync(0);
    _file!.writeFromSync(header);
    _pixelDataOffset = header.length;
  }

  static bool _isInstrumentationEnabled() => DecoderInstrumentation.isEnabled();

  static void _log(String message) {
    if (_isInstrumentationEnabled()) {
      DecoderInstrumentation.log(_logSource, message);
    }
  }
}


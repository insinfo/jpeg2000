import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../util/DecoderInstrumentation.dart';
import '../../util/Int32Utils.dart';
import '../BlkImgDataSrc.dart';
import '../DataBlkInt.dart';
import 'ImgWriter.dart';

/// Writes three-component image data to a binary PPM (P6) file.
class ImgWriterPpm extends ImgWriter {
  static const String _logSource = 'ImgWriterPPM';

  ImgWriterPpm(
    File output,
    BlkImgDataSrc imageSource,
    int firstComponent,
    int secondComponent,
    int thirdComponent,
  ) {
    final numComps = imageSource.getNumComps();
    if (firstComponent < 0 || firstComponent >= numComps) {
      throw ArgumentError.value(firstComponent, 'firstComponent',
          'Component index out of range');
    }
    if (secondComponent < 0 || secondComponent >= numComps) {
      throw ArgumentError.value(secondComponent, 'secondComponent',
          'Component index out of range');
    }
    if (thirdComponent < 0 || thirdComponent >= numComps) {
      throw ArgumentError.value(thirdComponent, 'thirdComponent',
          'Component index out of range');
    }
    final range1 = imageSource.getNomRangeBits(firstComponent);
    final range2 = imageSource.getNomRangeBits(secondComponent);
    final range3 = imageSource.getNomRangeBits(thirdComponent);
    if (range1 > 8 || range2 > 8 || range3 > 8) {
      throw ArgumentError('PPM writer supports components up to 8 bits.');
    }

    final compWidth = imageSource.getCompImgWidth(firstComponent);
    final compHeight = imageSource.getCompImgHeight(firstComponent);
    if (compWidth != imageSource.getCompImgWidth(secondComponent) ||
        compWidth != imageSource.getCompImgWidth(thirdComponent) ||
        compHeight != imageSource.getCompImgHeight(secondComponent) ||
        compHeight != imageSource.getCompImgHeight(thirdComponent)) {
      throw ArgumentError(
        'PPM components must have identical dimensions and subsampling.',
      );
    }

    src = imageSource;
    width = imageSource.getImgWidth();
    height = imageSource.getImgHeight();

    _components[0] = firstComponent;
    _components[1] = secondComponent;
    _components[2] = thirdComponent;
    _fixedPoint[0] = imageSource.getFixedPoint(firstComponent);
    _fixedPoint[1] = imageSource.getFixedPoint(secondComponent);
    _fixedPoint[2] = imageSource.getFixedPoint(thirdComponent);
    _levelShift[0] = 1 << (range1 - 1);
    _levelShift[1] = 1 << (range2 - 1);
    _levelShift[2] = 1 << (range3 - 1);

    output.parent.createSync(recursive: true);
    _file = output.openSync(mode: FileMode.write);
    _writeHeader();
  }

  factory ImgWriterPpm.fromPath(
    String outputPath,
    BlkImgDataSrc imageSource,
    int firstComponent,
    int secondComponent,
    int thirdComponent,
  ) {
    return ImgWriterPpm(
      File(outputPath),
      imageSource,
      firstComponent,
      secondComponent,
      thirdComponent,
    );
  }

  final List<int> _levelShift = List<int>.filled(3, 0);
  final List<int> _components = List<int>.filled(3, 0);
  final List<int> _fixedPoint = List<int>.filled(3, 0);
  final DataBlkInt _block = DataBlkInt();
  bool _fixedPointLogged = false;

  RandomAccessFile? _file;
  Uint8List? _buffer;
  int _pixelDataOffset = 0;

  @override
  void close() {
    final writer = _file;
    if (writer == null) {
      return;
    }
    final expectedLength = 3 * width * height + _pixelDataOffset;
    var currentLength = writer.lengthSync();
    if (currentLength < expectedLength) {
      writer.setPositionSync(currentLength);
      final padding = expectedLength - currentLength;
      final zeroChunk = Uint8List(math.min(padding, 4096));
      var remaining = padding;
      while (remaining > 0) {
        final limit = remaining < zeroChunk.length ? remaining : zeroChunk.length;
        writer.writeFromSync(zeroChunk, 0, limit);
        remaining -= limit;
      }
      currentLength = writer.lengthSync();
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
    final tileIndex = src.getTileIdx();
    final referenceComponent = _components[0];
    final tileWidth = src.getTileCompWidth(tileIndex, referenceComponent);
    final tileHeight = src.getTileCompHeight(tileIndex, referenceComponent);
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
    final bufferSize = 3 * regionWidth;
    _buffer ??= Uint8List(bufferSize);
    if (_buffer!.length < bufferSize) {
      _buffer = Uint8List(bufferSize);
    }

    if (!_fixedPointLogged && _isInstrumentationEnabled()) {
      _fixedPointLogged = true;
      _log('PPM writer fixed-point: R=${_fixedPoint[0]} '
          'G=${_fixedPoint[1]} B=${_fixedPoint[2]}');
    }

    final compIndex0 = _components[0];
    final tOffx = src.getCompULX(compIndex0) -
        (src.getImgULX() / src.getCompSubsX(compIndex0)).ceil();
    final tOffy = src.getCompULY(compIndex0) -
        (src.getImgULY() / src.getCompSubsY(compIndex0)).ceil();

    for (var line = 0; line < regionHeight; line++) {
      for (var channel = 0; channel < 3; channel++) {
        final component = _components[channel];

        _block
          ..ulx = ulx
          ..uly = uly + line
          ..w = regionWidth
          ..h = 1; // request one scanline at a time

        DataBlkInt block;
        do {
          block = src.getInternCompData(_block, component) as DataBlkInt;
        } while (block.progressive);

        final data = block.data;
        if (data == null) {
          throw StateError('Data block for component $component is empty.');
        }

        final fracBits = _fixedPoint[channel];
        final maxValue = (1 << src.getNomRangeBits(component)) - 1;
        final shift = _levelShift[channel];

        var sourceIndex = block.offset + regionWidth - 1;
        var targetIndex = 3 * regionWidth - 1 + channel - 2;
        final captureDebug = _isInstrumentationEnabled() && _debugLines > 0;
        var debugRemaining = captureDebug ? debugSamples : 0;
        while (targetIndex >= 0) {
            var sample = fracBits == 0
              ? data[sourceIndex] + shift
              : Int32Utils.logicalShiftRight(data[sourceIndex], fracBits) +
                shift;
          if (sample < 0) {
            sample = 0;
          } else if (sample > maxValue) {
            sample = maxValue;
          }
          _buffer![targetIndex] = sample;
          if (debugRemaining > 0) {
            _debugTuple[channel][debugSamples - debugRemaining] = sample;
          }
          targetIndex -= 3;
          sourceIndex--;
          if (debugRemaining > 0 && targetIndex < 0) {
            debugRemaining = 0;
          }
        }
        if (debugRemaining > 0) {
          debugRemaining = 0;
        }
      }

      if (_isInstrumentationEnabled() && _debugLines > 0) {
        final tuples = <String>[];
        for (var i = 0; i < debugSamples; i++) {
          tuples.add('(${_debugTuple[0][i]},${_debugTuple[1][i]},${_debugTuple[2][i]})');
        }
        _log('PPM writer debug line $_debugLines: ${tuples.join(' ')}');
        _debugLines--;
      }

      final imageRow = uly + tOffy + line;
      final imageCol = ulx + tOffx;
      final offset =
          _pixelDataOffset + 3 * (width * imageRow + imageCol);
      writer.setPositionSync(offset);
      writer.writeFromSync(_buffer!, 0, bufferSize);
    }
  }

  void _writeHeader() {
    final header = ascii.encode('P6\n$width $height\n255\n');
    _file!.setPositionSync(0);
    _file!.writeFromSync(header);
    _pixelDataOffset = header.length;
  }

  static const int debugSamples = 4;
  static int _debugLines = 2;
  static final List<List<int>> _debugTuple =
      List<List<int>>.generate(3, (_) => List<int>.filled(debugSamples, 0));

  static bool _isInstrumentationEnabled() => DecoderInstrumentation.isEnabled();

  static void _log(String message) {
    if (_isInstrumentationEnabled()) {
      DecoderInstrumentation.log(_logSource, message);
    }
  }
}


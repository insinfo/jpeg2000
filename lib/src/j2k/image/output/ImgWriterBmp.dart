import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../util/DecoderInstrumentation.dart';
import '../BlkImgDataSrc.dart';
import '../DataBlkInt.dart';
import 'ImgWriter.dart';

/// Writes decoded samples to an uncompressed bitmap (BMP) file.
///
/// The implementation supports 8-bit grayscale and 24-bit RGB images. For
/// colour images the first three components of the codestream are used in
/// RGB order and written as BGR triplets, mirroring JJ2000's component
/// selection for PPM output.
class ImgWriterBmp extends ImgWriter {
  static const String _logSource = 'ImgWriterBMP';
  ImgWriterBmp(File output, BlkImgDataSrc source) {
    if (source.getImgWidth() <= 0 || source.getImgHeight() <= 0) {
      throw ArgumentError('Image dimensions must be positive for BMP output.');
    }

    src = source;
    width = source.getImgWidth();
    height = source.getImgHeight();

    if (source.getNumComps() == 1) {
      _isGrayscale = true;
      _components = <int>[0];
    } else if (source.getNumComps() >= 3) {
      _isGrayscale = false;
      _components = <int>[0, 1, 2];
      final refWidth = source.getCompImgWidth(0);
      final refHeight = source.getCompImgHeight(0);
      for (var i = 1; i < 3; i++) {
        final comp = _components[i];
        if (source.getCompImgWidth(comp) != refWidth ||
            source.getCompImgHeight(comp) != refHeight) {
          throw ArgumentError(
            'BMP writer requires the first three components to share the same dimensions.',
          );
        }
      }
    } else {
      throw ArgumentError(
        'BMP writer requires either a single component or at least three components.',
      );
    }

    final componentCount = _components.length;
    _fixedPoint = List<int>.filled(componentCount, 0);
    _levelShift = List<int>.filled(componentCount, 0);
    _downShift = List<int>.filled(componentCount, 0);
    _maxValues = List<int>.filled(componentCount, 0);
    _blocks = List<DataBlkInt>.generate(componentCount, (_) => DataBlkInt());

    for (var i = 0; i < componentCount; i++) {
      final component = _components[i];
      final rangeBits = source.getNomRangeBits(component);
      if (_debugNomRangePrinted < 1 && _isInstrumentationEnabled()) {
        _debugNomRangePrinted++;
        final buffer = StringBuffer('BMP writer nominal range bits:');
        for (var j = 0; j < componentCount; j++) {
          final compIdx = _components[j];
          final bits = source.getNomRangeBits(compIdx);
          buffer.write(' c$compIdx=$bits');
        }
        _log(buffer.toString());
      }
      if (rangeBits <= 0) {
        throw ArgumentError('Component $component has invalid bit depth.');
      }
      _fixedPoint[i] = source.getFixedPoint(component);
      _levelShift[i] = 1 << (rangeBits - 1);
      _maxValues[i] = (1 << rangeBits) - 1;
      if (rangeBits > 8) {
        _downShift[i] = rangeBits - 8;
      }
    }

    _bytesPerPixel = _isGrayscale ? 1 : 3;
    _bitsPerPixel = _isGrayscale ? 8 : 24;
    _rowStride = ((_bytesPerPixel * width + 3) ~/ 4) * 4;
    _imageSize = _rowStride * height;
    _pixelDataOffset = _isGrayscale ? _paletteOffset : _pixelOffset;

    output.parent.createSync(recursive: true);
    _file = output.openSync(mode: FileMode.write);
    _writeHeader();
  }

  factory ImgWriterBmp.fromPath(String outputPath, BlkImgDataSrc source) {
    return ImgWriterBmp(File(outputPath), source);
  }

  static const int _fileHeaderSize = 14;
  static const int _infoHeaderSize = 40;
  static const int _paletteEntries = 256;
  static const int _pixelOffset = _fileHeaderSize + _infoHeaderSize;
  static const int _paletteOffset =
      _fileHeaderSize + _infoHeaderSize + _paletteEntries * 4;

  late final List<int> _components;
  late final List<int> _fixedPoint;
  late final List<int> _levelShift;
  late final List<int> _downShift;
  late final List<int> _maxValues;
  late final List<DataBlkInt> _blocks;
  late final bool _isGrayscale;
  late final int _bytesPerPixel;
  late final int _bitsPerPixel;
  late final int _rowStride;
  late final int _imageSize;
  late final int _pixelDataOffset;

  final List<List<int>> _lineData = <List<int>>[];
  final List<int> _lineOffsets = <int>[];

  RandomAccessFile? _file;
  Uint8List? _buffer;

  @override
  void writeTile() {
    final tileIdx = src.getTileIdx();
    final reference = _components.first;
    final tileWidth = src.getTileCompWidth(tileIdx, reference);
    final tileHeight = src.getTileCompHeight(tileIdx, reference);
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
    final bufferLength = _bytesPerPixel * regionWidth;
    _buffer ??= Uint8List(bufferLength);
    if (_buffer!.length < bufferLength) {
      _buffer = Uint8List(bufferLength);
    }

    if (_lineData.length != _components.length) {
      _lineData
        ..clear()
        ..addAll(List<List<int>>.filled(_components.length, const <int>[]));
    }
    if (_lineOffsets.length != _components.length) {
      _lineOffsets
        ..clear()
        ..addAll(List<int>.filled(_components.length, 0));
    }

    final refComponent = _components.first;
    final tOffx = src.getCompULX(refComponent) -
        (src.getImgULX() / src.getCompSubsX(refComponent)).ceil();
    final tOffy = src.getCompULY(refComponent) -
        (src.getImgULY() / src.getCompSubsY(refComponent)).ceil();

    for (var line = 0; line < regionHeight; line++) {
      for (var channel = 0; channel < _components.length; channel++) {
        final component = _components[channel];
        final block = _blocks[channel]
          ..ulx = ulx
          ..uly = uly + line
          ..w = regionWidth
          ..h = 1;

        DataBlkInt dataBlock;
        do {
          dataBlock = src.getInternCompData(block, component) as DataBlkInt;
        } while (dataBlock.progressive);

        final data = dataBlock.data;
        if (data == null) {
          throw StateError('Data block is empty for component $component.');
        }
        _lineData[channel] = data;
        _lineOffsets[channel] = dataBlock.offset;
      }

      if (_isGrayscale) {
        _writeGrayscaleLine(regionWidth);
      } else {
        _writeColourLine(regionWidth);
      }

      final imageRow = uly + tOffy + line;
      final imageCol = ulx + tOffx;
      final offset =
          _pixelDataOffset + _rowStride * imageRow + _bytesPerPixel * imageCol;
      writer.setPositionSync(offset);
      writer.writeFromSync(_buffer!, 0, bufferLength);
    }
  }

  void _writeGrayscaleLine(int regionWidth) {
    final data = _lineData[0];
    final offset = _lineOffsets[0];
    final fixedPoint = _fixedPoint[0];
    final levelShift = _levelShift[0];
    final maxValue = _maxValues[0];
    final downShift = _downShift[0];
    var sourceIndex = offset;
    for (var x = 0; x < regionWidth; x++) {
      var sample = fixedPoint == 0
          ? data[sourceIndex] + levelShift
          : (data[sourceIndex] >> fixedPoint) + levelShift;
      if (sample < 0) {
        sample = 0;
      } else if (sample > maxValue) {
        sample = maxValue;
      }
      _buffer![x] = downShift == 0 ? sample : (sample >> downShift);
      sourceIndex++;
    }
  }

  void _writeColourLine(int regionWidth) {
    final redData = _lineData[0];
    final greenData = _lineData[1];
    final blueData = _lineData[2];
    final redOffset = _lineOffsets[0];
    final greenOffset = _lineOffsets[1];
    final blueOffset = _lineOffsets[2];

    final redFixed = _fixedPoint[0];
    final greenFixed = _fixedPoint[1];
    final blueFixed = _fixedPoint[2];

    if (_debugFixedPointPrinted < 1 && _isInstrumentationEnabled()) {
      _debugFixedPointPrinted++;
      _log('BMP writer fixed-point: R=$redFixed G=$greenFixed B=$blueFixed');
    }

    final redLevel = _levelShift[0];
    final greenLevel = _levelShift[1];
    final blueLevel = _levelShift[2];

    final redMax = _maxValues[0];
    final greenMax = _maxValues[1];
    final blueMax = _maxValues[2];

    final redDown = _downShift[0];
    final greenDown = _downShift[1];
    final blueDown = _downShift[2];

    var rIndex = redOffset;
    var gIndex = greenOffset;
    var bIndex = blueOffset;
    var target = 0;
    const int debugSamples = 4;
    final captureDebug = _isInstrumentationEnabled() && _debugLines > 0;
    var debugRemaining = captureDebug ? debugSamples : 0;
    for (var x = 0; x < regionWidth; x++) {
      var red = redFixed == 0
          ? redData[rIndex] + redLevel
          : (redData[rIndex] >> redFixed) + redLevel;
      if (red < 0) {
        red = 0;
      } else if (red > redMax) {
        red = redMax;
      }
      red = redDown == 0 ? red : (red >> redDown);

      var green = greenFixed == 0
          ? greenData[gIndex] + greenLevel
          : (greenData[gIndex] >> greenFixed) + greenLevel;
      if (green < 0) {
        green = 0;
      } else if (green > greenMax) {
        green = greenMax;
      }
      green = greenDown == 0 ? green : (green >> greenDown);

      var blue = blueFixed == 0
          ? blueData[bIndex] + blueLevel
          : (blueData[bIndex] >> blueFixed) + blueLevel;
      if (blue < 0) {
        blue = 0;
      } else if (blue > blueMax) {
        blue = blueMax;
      }
      blue = blueDown == 0 ? blue : (blue >> blueDown);

      if (debugRemaining > 0) {
        _debugRemainingBuffer ??= <String>[];
        _debugRemainingBuffer!.add('($red,$green,$blue)');
        debugRemaining--;
        if (debugRemaining == 0) {
          _log('BMP writer debug line ${_debugLines}: '
              '${_debugRemainingBuffer!.join(' ')}');
          _debugRemainingBuffer!.clear();
          _debugLines--;
        }
      }

      _buffer![target] = blue;
      _buffer![target + 1] = green;
      _buffer![target + 2] = red;

      target += 3;
      rIndex++;
      gIndex++;
      bIndex++;
    }
  }

  static int _debugLines = 2;
  static List<String>? _debugRemainingBuffer;
  static int _debugFixedPointPrinted = 0;
  static int _debugNomRangePrinted = 0;

  static bool _isInstrumentationEnabled() => DecoderInstrumentation.isEnabled();

  static void _log(String message) {
    if (_isInstrumentationEnabled()) {
      DecoderInstrumentation.log(_logSource, message);
    }
  }

  @override
  void flush() {
    _buffer = null;
  }

  @override
  void close() {
    final writer = _file;
    if (writer == null) {
      return;
    }
    final expectedLength = _pixelDataOffset + _imageSize;
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
      currentLength = writer.lengthSync();
    }
    writer.closeSync();
    _file = null;
    _buffer = null;
  }

  void _writeHeader() {
    final fileHeader = ByteData(_fileHeaderSize);
    fileHeader.setUint16(0, 0x4d42, Endian.little); // 'BM'
    fileHeader.setUint32(
      2,
      _pixelDataOffset + _imageSize,
      Endian.little,
    );
    fileHeader.setUint16(6, 0, Endian.little);
    fileHeader.setUint16(8, 0, Endian.little);
    fileHeader.setUint32(10, _pixelDataOffset, Endian.little);

    final infoHeader = ByteData(_infoHeaderSize);
    infoHeader.setUint32(0, _infoHeaderSize, Endian.little);
    infoHeader.setInt32(4, width, Endian.little);
    infoHeader.setInt32(8, -height, Endian.little); // top-down bitmap
    infoHeader.setUint16(12, 1, Endian.little); // colour planes
    infoHeader.setUint16(14, _bitsPerPixel, Endian.little);
    infoHeader.setUint32(16, 0, Endian.little); // BI_RGB (no compression)
    infoHeader.setUint32(20, _imageSize, Endian.little);
    infoHeader.setInt32(24, 0, Endian.little); // pixels per metre (default)
    infoHeader.setInt32(28, 0, Endian.little);
    infoHeader.setUint32(
      32,
      _isGrayscale ? _paletteEntries : 0,
      Endian.little,
    );
    infoHeader.setUint32(
      36,
      _isGrayscale ? _paletteEntries : 0,
      Endian.little,
    );

    final writer = _file!;
    writer.setPositionSync(0);
    writer.writeFromSync(fileHeader.buffer.asUint8List());
    writer.writeFromSync(infoHeader.buffer.asUint8List());

    if (_isGrayscale) {
      final palette = Uint8List(_paletteEntries * 4);
      for (var i = 0; i < _paletteEntries; i++) {
        final base = 4 * i;
        palette[base] = i; // blue
        palette[base + 1] = i; // green
        palette[base + 2] = i; // red
        // palette[base + 3] remains zero (reserved)
      }
      writer.writeFromSync(palette);
    }
  }
}


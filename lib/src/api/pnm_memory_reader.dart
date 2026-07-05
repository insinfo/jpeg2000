import 'dart:typed_data';

import '../j2k/image/data_blk.dart';
import '../j2k/image/data_blk_int.dart';
import '../j2k/image/input/img_reader.dart';

/// In-memory P5/P6 reader used by the public byte-based encoder API.
class PnmMemoryReader extends ImgReader {
  PnmMemoryReader(Uint8List bytes) : _bytes = bytes {
    _parseHeader();
  }

  static const int _dcOffset = 128;

  final Uint8List _bytes;
  int _offset = 0;
  int _pixelOffset = 0;
  int _rangeBits = 8;

  final List<Int32List?> _componentCache = List<Int32List?>.filled(3, null);
  final DataBlkInt _cachedBlock = DataBlkInt();
  DataBlkInt? _intBlock;

  bool get isPpm => nc == 3;

  @override
  void close() {
    for (var i = 0; i < _componentCache.length; i++) {
      _componentCache[i] = null;
    }
  }

  @override
  int getNomRangeBits(int c) {
    _checkComponent(c);
    return _rangeBits;
  }

  @override
  int getFixedPoint(int c) {
    _checkComponent(c);
    return 0;
  }

  @override
  bool isOrigSigned(int c) {
    _checkComponent(c);
    return false;
  }

  @override
  DataBlk getInternCompData(DataBlk blk, int c) {
    _checkComponent(c);
    if (blk.getDataType() != DataBlk.typeInt) {
      _intBlock ??= DataBlkInt();
      _intBlock!
        ..ulx = blk.ulx
        ..uly = blk.uly
        ..w = blk.w
        ..h = blk.h;
      blk = _intBlock!;
    }

    if (nc == 1) {
      return _readPgmBlock(blk, c);
    }
    return _readPpmBlock(blk, c);
  }

  @override
  DataBlk getCompData(DataBlk blk, int c) {
    if (blk.getDataType() != DataBlk.typeInt) {
      blk = DataBlkInt.withGeometry(blk.ulx, blk.uly, blk.w, blk.h);
    }
    final width = blk.w;
    final height = blk.h;
    var output = blk.getData() as Int32List?;
    if (output == null || output.length < width * height) {
      output = Int32List(width * height);
    }
    final internal = getInternCompData(blk, c) as DataBlkInt;
    final source = internal.getDataInt();
    if (source == null) {
      throw StateError('PNM block has no data');
    }
    if (internal.offset == 0 && internal.scanw == width) {
      output.setRange(0, width * height, source);
    } else {
      for (var row = 0; row < height; row++) {
        output.setRange(
          row * width,
          row * width + width,
          source,
          internal.offset + row * internal.scanw,
        );
      }
    }
    internal
      ..setData(output)
      ..offset = 0
      ..scanw = width;
    return internal;
  }

  DataBlk _readPgmBlock(DataBlk blk, int c) {
    var data = blk.getData() as Int32List?;
    if (data == null || data.length < blk.w * blk.h) {
      data = Int32List(blk.w * blk.h);
      blk.setData(data);
    }

    for (var row = 0; row < blk.h; row++) {
      final sourceBase = _pixelOffset + (blk.uly + row) * w + blk.ulx;
      final targetBase = row * blk.w;
      for (var col = 0; col < blk.w; col++) {
        data[targetBase + col] = _bytes[sourceBase + col] - _dcOffset;
      }
    }

    blk
      ..progressive = false
      ..offset = 0
      ..scanw = blk.w;
    return blk;
  }

  DataBlk _readPpmBlock(DataBlk blk, int c) {
    final sampleCount = blk.w * blk.h;
    for (var component = 0; component < 3; component++) {
      final current = _componentCache[component];
      if (current == null || current.length < sampleCount) {
        _componentCache[component] = Int32List(sampleCount);
      }
    }

    final red = _componentCache[0]!;
    final green = _componentCache[1]!;
    final blue = _componentCache[2]!;

    for (var row = 0; row < blk.h; row++) {
      var sourceIndex = _pixelOffset + ((blk.uly + row) * w + blk.ulx) * 3;
      final targetBase = row * blk.w;
      for (var col = 0; col < blk.w; col++) {
        final target = targetBase + col;
        red[target] = _bytes[sourceIndex++] - _dcOffset;
        green[target] = _bytes[sourceIndex++] - _dcOffset;
        blue[target] = _bytes[sourceIndex++] - _dcOffset;
      }
    }

    _cachedBlock
      ..ulx = blk.ulx
      ..uly = blk.uly
      ..w = blk.w
      ..h = blk.h
      ..offset = 0
      ..scanw = blk.w
      ..progressive = false
      ..setData(_componentCache[c]);
    return _cachedBlock;
  }

  void _parseHeader() {
    final magic0 = _readByte();
    final magic1 = _readByte();
    if (magic0 != 0x50 || (magic1 != 0x35 && magic1 != 0x36)) {
      throw ArgumentError('Expected binary PGM (P5) or PPM (P6) bytes.');
    }
    nc = magic1 == 0x36 ? 3 : 1;
    w = _readTokenInt('width');
    h = _readTokenInt('height');
    final maxValue = _readTokenInt('maxValue');
    if (w <= 0 || h <= 0) {
      throw ArgumentError('PNM dimensions must be positive.');
    }
    if (maxValue != 255) {
      throw ArgumentError('Only 8-bit PNM input is supported.');
    }
    _rangeBits = 8;
    _pixelOffset = _offset;

    final expected = _pixelOffset + w * h * nc;
    if (_bytes.length < expected) {
      throw ArgumentError('PNM payload is shorter than declared dimensions.');
    }
  }

  int _readTokenInt(String label) {
    _skipWhitespaceAndComments();
    if (_offset >= _bytes.length) {
      throw ArgumentError('Missing PNM $label.');
    }
    var value = 0;
    var sawDigit = false;
    while (_offset < _bytes.length) {
      final byte = _bytes[_offset];
      if (_isWhitespace(byte)) {
        _offset++;
        break;
      }
      if (byte < 0x30 || byte > 0x39) {
        throw ArgumentError('Invalid PNM $label.');
      }
      sawDigit = true;
      value = value * 10 + byte - 0x30;
      _offset++;
    }
    if (!sawDigit) {
      throw ArgumentError('Missing PNM $label.');
    }
    return value;
  }

  void _skipWhitespaceAndComments() {
    while (_offset < _bytes.length) {
      final byte = _bytes[_offset];
      if (_isWhitespace(byte)) {
        _offset++;
        continue;
      }
      if (byte == 0x23) {
        while (_offset < _bytes.length &&
            _bytes[_offset] != 0x0a &&
            _bytes[_offset] != 0x0d) {
          _offset++;
        }
        continue;
      }
      return;
    }
  }

  int _readByte() {
    if (_offset >= _bytes.length) {
      throw ArgumentError('Unexpected end of PNM header.');
    }
    return _bytes[_offset++];
  }

  bool _isWhitespace(int byte) =>
      byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0x20;

  void _checkComponent(int c) {
    if (c < 0 || c >= nc) {
      throw ArgumentError.value(c, 'component', 'Component index out of range');
    }
  }
}

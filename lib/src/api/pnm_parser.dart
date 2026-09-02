import 'dart:typed_data';

import 'interleaved_memory_reader.dart';

/// Parses binary PGM (P5) or PPM (P6) bytes into an encoder input.
///
/// Sample depth follows the header's maximum value: up to 255 gives one byte
/// per sample, up to 65535 gives two bytes per sample, most significant byte
/// first, as the Netpbm specification requires.
InterleavedMemoryReader parsePnm(Uint8List bytes) {
  final parser = _PnmHeader(bytes);
  final width = parser.width;
  final height = parser.height;
  final components = parser.components;
  final bitsPerSample = parser.bitsPerSample;
  final count = width * height * components;
  final start = parser.dataOffset;

  final List<int> samples;
  if (bitsPerSample <= 8) {
    if (bytes.length < start + count) {
      throw ArgumentError('PNM payload is shorter than declared dimensions.');
    }
    samples = Uint8List.sublistView(bytes, start, start + count);
  } else {
    if (bytes.length < start + count * 2) {
      throw ArgumentError('PNM payload is shorter than declared dimensions.');
    }
    final words = Uint16List(count);
    var index = start;
    for (var i = 0; i < count; i++) {
      words[i] = (bytes[index] << 8) | bytes[index + 1];
      index += 2;
    }
    samples = words;
  }

  return InterleavedMemoryReader(
    samples,
    width: width,
    height: height,
    components: components,
    bitsPerSample: bitsPerSample,
  );
}

class _PnmHeader {
  _PnmHeader(this._bytes) {
    final magic0 = _readByte();
    final magic1 = _readByte();
    if (magic0 != 0x50 || (magic1 != 0x35 && magic1 != 0x36)) {
      throw ArgumentError('Expected binary PGM (P5) or PPM (P6) bytes.');
    }
    components = magic1 == 0x36 ? 3 : 1;
    width = _readTokenInt('width');
    height = _readTokenInt('height');
    final maxValue = _readTokenInt('maxValue');
    if (width <= 0 || height <= 0) {
      throw ArgumentError('PNM dimensions must be positive.');
    }
    if (maxValue <= 0 || maxValue > 65535) {
      throw ArgumentError('PNM maximum value must be between 1 and 65535.');
    }
    bitsPerSample = maxValue.bitLength;
    dataOffset = _offset;
  }

  final Uint8List _bytes;
  int _offset = 0;

  late final int width;
  late final int height;
  late final int components;
  late final int bitsPerSample;
  late final int dataOffset;

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

  static bool _isWhitespace(int byte) =>
      byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0x20;
}

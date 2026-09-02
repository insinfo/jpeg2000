import 'dart:typed_data';

import '../j2k/image/data_blk.dart';
import '../j2k/image/data_blk_int.dart';
import '../j2k/image/input/img_reader.dart';

/// Feeds an in-memory buffer of interleaved, unsigned, tightly packed samples
/// to the encoder pipeline as an [ImgReader].
///
/// Sample `(x, y)` of component `c` lives at `(y * width + x) * components +
/// c`. Samples up to 8 bits come from a [Uint8List], wider ones from a
/// [Uint16List]; any other `List<int>` is accepted through the slow path.
/// The encoder wants level-shifted signed data, so `1 << (bitsPerSample - 1)`
/// is subtracted on the way out, exactly as the file readers of JJ2000 do.
class InterleavedMemoryReader extends ImgReader {
  InterleavedMemoryReader(
    List<int> samples, {
    required int width,
    required int height,
    required int components,
    required int bitsPerSample,
  })  : _samples = samples,
        _bytes = samples is Uint8List ? samples : null,
        _words = samples is Uint16List ? samples : null,
        _bitsPerSample = bitsPerSample,
        _dcOffset = 1 << (bitsPerSample - 1) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image dimensions must be positive.');
    }
    if (components < 1 || components > 16384) {
      throw ArgumentError.value(
        components,
        'components',
        'must be between 1 and 16384',
      );
    }
    if (bitsPerSample < 1 || bitsPerSample > 16) {
      throw ArgumentError.value(
        bitsPerSample,
        'bitsPerSample',
        'must be between 1 and 16',
      );
    }
    if (bitsPerSample > 8 && _bytes != null) {
      throw ArgumentError(
        'Samples wider than 8 bits must come in a Uint16List, not Uint8List.',
      );
    }
    final expected = width * height * components;
    if (samples.length < expected) {
      throw ArgumentError(
        'Expected at least $expected samples for ${width}x$height with '
        '$components component(s); got ${samples.length}.',
      );
    }
    w = width;
    h = height;
    nc = components;
  }

  final List<int> _samples;
  final Uint8List? _bytes;
  final Uint16List? _words;
  final int _bitsPerSample;
  final int _dcOffset;

  DataBlkInt? _intBlock;

  @override
  void close() {}

  @override
  int getNomRangeBits(int c) {
    _checkComponent(c);
    return _bitsPerSample;
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

    var data = blk.getData() as Int32List?;
    if (data == null || data.length < blk.w * blk.h) {
      data = Int32List(blk.w * blk.h);
      blk.setData(data);
    }

    final stride = nc;
    final bytes = _bytes;
    final words = _words;
    for (var row = 0; row < blk.h; row++) {
      var sourceIndex = ((blk.uly + row) * w + blk.ulx) * stride + c;
      final targetBase = row * blk.w;
      if (bytes != null) {
        for (var col = 0; col < blk.w; col++) {
          data[targetBase + col] = bytes[sourceIndex] - _dcOffset;
          sourceIndex += stride;
        }
      } else if (words != null) {
        for (var col = 0; col < blk.w; col++) {
          data[targetBase + col] = words[sourceIndex] - _dcOffset;
          sourceIndex += stride;
        }
      } else {
        for (var col = 0; col < blk.w; col++) {
          data[targetBase + col] = _samples[sourceIndex] - _dcOffset;
          sourceIndex += stride;
        }
      }
    }

    blk
      ..progressive = false
      ..offset = 0
      ..scanw = blk.w;
    return blk;
  }

  @override
  DataBlk getCompData(DataBlk blk, int c) {
    if (blk.getDataType() != DataBlk.typeInt) {
      blk = DataBlkInt.withGeometry(blk.ulx, blk.uly, blk.w, blk.h);
    }
    // The internal block is already a private, tightly packed copy, so it can
    // be handed out as-is.
    final internal = getInternCompData(blk, c);
    return internal;
  }

  void _checkComponent(int c) {
    if (c < 0 || c >= nc) {
      throw ArgumentError.value(c, 'component', 'Component index out of range');
    }
  }
}

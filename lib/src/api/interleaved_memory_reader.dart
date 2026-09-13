import 'dart:typed_data';

import '../j2k/image/data_blk.dart';
import '../j2k/image/data_blk_int.dart';
import '../j2k/image/input/img_reader.dart';

/// Feeds an in-memory buffer of interleaved, tightly packed samples to the
/// encoder pipeline as an [ImgReader].
///
/// Sample `(x, y)` of component `c` lives at `(y * width + x) * components +
/// c`. Samples up to 8 bits come from a [Uint8List], wider ones from a
/// [Uint16List]; any other `List<int>` is accepted through the slow path.
/// The encoder wants level-shifted data, so for an unsigned component
/// `1 << (bits - 1)` is subtracted on the way out, exactly as the file readers
/// of JJ2000 do; a signed component is already centred on zero and is passed
/// through (ISO/IEC 15444-1 A.5.1 records the choice in the sign bit of
/// `Ssiz`).
///
/// [bitsPerComponent] and [signedComponents] give each component its own
/// depth and sign; without them every component takes `bitsPerSample` and is
/// unsigned.
class InterleavedMemoryReader extends ImgReader {
  InterleavedMemoryReader(
    List<int> samples, {
    required int width,
    required int height,
    required int components,
    required int bitsPerSample,
    List<int>? bitsPerComponent,
    List<bool>? signedComponents,
  })  : _samples = samples,
        _bytes = samples is Uint8List ? samples : null,
        _words = samples is Uint16List ? samples : null,
        _bits = List<int>.unmodifiable(
          bitsPerComponent ?? List<int>.filled(components, bitsPerSample),
        ),
        _signed = List<bool>.unmodifiable(
          signedComponents ?? List<bool>.filled(components, false),
        ) {
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
    if (_bits.length != components) {
      throw ArgumentError.value(
        bitsPerComponent,
        'bitsPerComponent',
        'must hold one depth per component ($components)',
      );
    }
    if (_signed.length != components) {
      throw ArgumentError.value(
        signedComponents,
        'signedComponents',
        'must hold one flag per component ($components)',
      );
    }
    var maxBits = 0;
    for (final bits in _bits) {
      if (bits < 1 || bits > 16) {
        throw ArgumentError.value(
          bits,
          'bitsPerSample',
          'must be between 1 and 16',
        );
      }
      if (bits > maxBits) {
        maxBits = bits;
      }
    }
    if (maxBits > 8 && _bytes != null) {
      throw ArgumentError(
        'Samples wider than 8 bits must come in a Uint16List, not Uint8List.',
      );
    }
    if (_signed.contains(true) && (_bytes != null || _words != null)) {
      throw ArgumentError(
        'Signed components cannot be read from an unsigned typed list; pass '
        'an Int8List, an Int16List or a plain List<int>.',
      );
    }
    _dcOffsets = List<int>.unmodifiable(
      List<int>.generate(
        components,
        (c) => _signed[c] ? 0 : 1 << (_bits[c] - 1),
      ),
    );
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
  final List<int> _bits;
  final List<bool> _signed;
  late final List<int> _dcOffsets;

  DataBlkInt? _intBlock;

  @override
  void close() {}

  @override
  int getNomRangeBits(int c) {
    _checkComponent(c);
    return _bits[c];
  }

  @override
  int getFixedPoint(int c) {
    _checkComponent(c);
    return 0;
  }

  @override
  bool isOrigSigned(int c) {
    _checkComponent(c);
    return _signed[c];
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
    final dcOffset = _dcOffsets[c];
    for (var row = 0; row < blk.h; row++) {
      var sourceIndex = ((blk.uly + row) * w + blk.ulx) * stride + c;
      final targetBase = row * blk.w;
      if (bytes != null) {
        for (var col = 0; col < blk.w; col++) {
          data[targetBase + col] = bytes[sourceIndex] - dcOffset;
          sourceIndex += stride;
        }
      } else if (words != null) {
        for (var col = 0; col < blk.w; col++) {
          data[targetBase + col] = words[sourceIndex] - dcOffset;
          sourceIndex += stride;
        }
      } else {
        for (var col = 0; col < blk.w; col++) {
          data[targetBase + col] = _samples[sourceIndex] - dcOffset;
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

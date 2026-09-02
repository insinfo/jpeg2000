@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:j2k/j2k.dart';
import 'package:test/test.dart';

/// Precinct partitions through the public encoder and decoder.
///
/// Two decoder bugs hid behind "no precincts" fixtures: the Lblock state was
/// indexed by the code-block's row inside the precinct instead of inside the
/// subband, so precincts stacked in a column shared it; and the per-resolution
/// precinct sizes were read from COD in codestream order while the lookup
/// expects highest resolution first, so unequal sizes were mirrored. Both
/// only surface with several precincts per subband, several layers, and
/// sizes that differ between levels, which is what a Kakadu or OpenJPEG file
/// with `Cprecincts` looks like.
void main() {
  Uint8List gradient(int width, int height, int components) {
    final samples = Uint8List(width * height * components);
    for (var i = 0; i < width * height; i++) {
      final x = i % width;
      final y = i ~/ width;
      for (var c = 0; c < components; c++) {
        samples[i * components + c] = switch (c) {
          0 => (x * 255 ~/ width) & 0xff,
          1 => (y * 255 ~/ height) & 0xff,
          _ => ((x * 7 + y * 13) ^ (x * y)) & 0xff,
        };
      }
    }
    return samples;
  }

  void expectLosslessRoundTrip(
    String label,
    Uint8List samples, {
    required int width,
    required int height,
    required int components,
    int tile = 0,
    Map<String, String> extra = const <String, String>{},
  }) {
    final bytes = encodeJpeg2000Pixels(
      samples,
      width: width,
      height: height,
      components: components,
      options: Jpeg2000EncodeOptions(
        tileWidth: tile,
        tileHeight: tile,
        extraParameters: extra,
      ),
    );
    final image = decodeJpeg2000(bytes);
    expect(image.pixels, samples, reason: label);
  }

  test(
      'several precincts per subband across many layers (Lblock per '
      'subband, not per precinct)', () {
    // 64x40, one level: the r1 subbands are 32x20 with 16x16 precincts, so
    // precincts 2 and 3 sit below 0 and 1 and used to share their Lblock.
    final gray = Uint8List.fromList(
      List<int>.generate(64 * 40, (i) => (i * 7) & 0xff),
    );
    expectLosslessRoundTrip(
      'gray 32x32 precincts, one level',
      gray,
      width: 64,
      height: 40,
      components: 1,
      extra: const <String, String>{'Cpp': '32 32', 'Wlev': '1'},
    );
  });

  test('precinct sizes that differ between resolution levels', () {
    final rgb = gradient(700, 500, 3);
    expectLosslessRoundTrip(
      '256 at the top level, 128 below',
      rgb,
      width: 700,
      height: 500,
      components: 3,
      extra: const <String, String>{'Cpp': '256 256 128 128'},
    );
    expectLosslessRoundTrip(
      '64 at the top level, 256 below',
      rgb,
      width: 700,
      height: 500,
      components: 3,
      extra: const <String, String>{'Cpp': '64 64 256 256'},
    );
  });

  test('precincts with tiles, SOP, EPH, segmentation symbols and layers', () {
    final rgb = gradient(700, 500, 3);
    expectLosslessRoundTrip(
      'everything at once',
      rgb,
      width: 700,
      height: 500,
      components: 3,
      tile: 512,
      extra: const <String, String>{
        'Cpp': '256 256 128 128',
        'Psop': 'on',
        'Peph': 'on',
        'Cseg_symbol': 'on',
        'Alayers': '0.2 +1 0.5 +1 1.0 +1',
      },
    );
  });

  test('lossy precinct streams still decode to the right geometry', () {
    final rgb = gradient(300, 220, 3);
    final bytes = encodeJpeg2000Pixels(
      rgb,
      width: 300,
      height: 220,
      components: 3,
      options: const Jpeg2000EncodeOptions(
        lossless: false,
        rate: 2.0,
        extraParameters: <String, String>{'Cpp': '128 128', 'Peph': 'on'},
      ),
    );
    final image = decodeJpeg2000(bytes);
    expect(image.width, 300);
    expect(image.height, 220);
    var maxDiff = 0;
    for (var i = 0; i < rgb.length; i++) {
      final diff = (image.pixels[i] - rgb[i]).abs();
      if (diff > maxDiff) maxDiff = diff;
    }
    // Two bits per pixel of a noisy pattern is coarse but must stay far from
    // the garbage a desynchronised packet header produces.
    expect(maxDiff, lessThan(200));
    final info = probeJpeg2000(bytes);
    expect(info.tileColumns, 1);
  });
}

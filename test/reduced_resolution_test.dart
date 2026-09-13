@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:j2k/j2k.dart';
import 'package:test/test.dart';

import 'subsampled_support.dart';

/// Decoding at a reduced resolution level (`Jpeg2000DecodeOptions.resolution`).
///
/// ISO/IEC 15444-1 (ITU-T T.800) B.5 defines the coordinates of resolution
/// level `r` of a tile-component by dividing the reference-grid coordinates by
/// `2^(NL - r)` and taking the ceiling, so an image whose origin is (0, 0) and
/// which was coded with `NL` decomposition levels is
/// `ceil(Xsiz / 2^(NL - r))` by `ceil(Ysiz / 2^(NL - r))` samples at level `r`.
/// The same division applies to every tile origin, which is what puts each
/// tile in the right place inside the smaller image.
void main() {
  int ceilDiv(int value, int divisor) => (value + divisor - 1) ~/ divisor;

  /// Expected size of [length] reference-grid columns (or rows) after
  /// discarding [discarded] resolution levels, with an image origin of 0.
  int reducedExtent(int length, int discarded) =>
      ceilDiv(length, 1 << discarded);

  Uint8List readFixture(String name) => Uint8List.fromList(
        File('test/fixtures/test_images/$name').readAsBytesSync(),
      );

  /// Builds an image whose every pixel carries [colour].
  Uint8List flatPixels(int width, int height, List<int> colour) {
    final pixels = Uint8List(width * height * colour.length);
    for (var i = 0; i < width * height; i++) {
      for (var c = 0; c < colour.length; c++) {
        pixels[i * colour.length + c] = colour[c];
      }
    }
    return pixels;
  }

  /// The number of decomposition levels the encoder uses by default; the
  /// codestreams built here never override `Cdecomp`.
  const defaultLevels = 5;

  group('reduced resolution geometry', () {
    test('decodes file1.jp2 at every available resolution level', () {
      final bytes = readFixture('file1.jp2');
      final info = probeJpeg2000(bytes);
      expect(info.width, 768);
      expect(info.height, 512);

      for (var level = 0; level <= defaultLevels; level++) {
        final image = decodeJpeg2000(
          bytes,
          options: Jpeg2000DecodeOptions(resolution: level),
        );
        final discarded = defaultLevels - level;
        expect(image.width, reducedExtent(info.width, discarded),
            reason: 'width at resolution $level');
        expect(image.height, reducedExtent(info.height, discarded),
            reason: 'height at resolution $level');
        expect(image.pixels.length, image.width * image.height * 3,
            reason: 'buffer at resolution $level');
      }
    });

    test('decodes relax.jp2 at every available resolution level', () {
      final bytes = readFixture('relax.jp2');
      final info = probeJpeg2000(bytes);

      for (var level = 0; level <= defaultLevels; level++) {
        final image = decodeJpeg2000(
          bytes,
          options: Jpeg2000DecodeOptions(resolution: level),
        );
        final discarded = defaultLevels - level;
        expect(image.width, reducedExtent(info.width, discarded));
        expect(image.height, reducedExtent(info.height, discarded));
      }
    });

    test('clamps a resolution level above the maximum to the full image', () {
      final bytes = readFixture('file1.jp2');
      final full = decodeJpeg2000(bytes);
      final clamped = decodeJpeg2000(
        bytes,
        options: const Jpeg2000DecodeOptions(resolution: defaultLevels + 3),
      );
      expect(clamped.width, full.width);
      expect(clamped.height, full.height);
      expect(clamped.pixels, full.pixels);
    });

    test('rejects a negative resolution level', () {
      final bytes = readFixture('file1.jp2');
      expect(
        () => decodeJpeg2000(
          bytes,
          options: const Jpeg2000DecodeOptions(resolution: -1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('reduced resolution pixels', () {
    test('keeps a flat colour flat at every level, single tile', () {
      const width = 320;
      const height = 256;
      const colour = <int>[200, 30, 90];
      final codestream = encodeJpeg2000Pixels(
        flatPixels(width, height, colour),
        width: width,
        height: height,
        components: 3,
        options: const Jpeg2000EncodeOptions(lossless: true, wrapInJp2: true),
      );

      for (var level = 0; level <= defaultLevels; level++) {
        final image = decodeJpeg2000(
          codestream,
          options: Jpeg2000DecodeOptions(resolution: level),
        );
        final discarded = defaultLevels - level;
        expect(image.width, reducedExtent(width, discarded));
        expect(image.height, reducedExtent(height, discarded));
        for (var i = 0; i < image.width * image.height; i++) {
          expect(image.pixels.sublist(i * 3, i * 3 + 3), colour,
              reason: 'pixel $i at resolution $level');
        }
      }
    });

    test('keeps a flat colour flat at every level, many tiles', () {
      const width = 320;
      const height = 256;
      const colour = <int>[17, 240, 128];
      final codestream = encodeJpeg2000Pixels(
        flatPixels(width, height, colour),
        width: width,
        height: height,
        components: 3,
        options: const Jpeg2000EncodeOptions(
          lossless: true,
          wrapInJp2: true,
          tileWidth: 128,
          tileHeight: 128,
        ),
      );

      for (var level = 0; level <= defaultLevels; level++) {
        final image = decodeJpeg2000(
          codestream,
          options: Jpeg2000DecodeOptions(resolution: level),
        );
        for (var i = 0; i < image.width * image.height; i++) {
          expect(image.pixels.sublist(i * 3, i * 3 + 3), colour,
              reason: 'pixel $i at resolution $level');
        }
      }
    });

    test('places every tile at the reduced grid coordinates of B.5', () {
      // Each tile is painted a single colour. Tiles are transformed
      // independently, so a flat tile stays exactly flat at every resolution
      // level and the reduced image must be a mosaic of the same colours,
      // with tile `t` occupying columns `ceil(tx0 / 2^d)` to
      // `ceil(tx1 / 2^d)`. Any error in the tile offsets shows up as a
      // colour landing in the wrong cell rather than as a rounding
      // difference.
      const width = 256;
      const height = 192;
      const tile = 64;
      final columns = ceilDiv(width, tile);
      final rows = ceilDiv(height, tile);

      int colourOf(int tileX, int tileY, int band) => switch (band) {
            0 => 20 + 60 * tileX,
            1 => 40 + 50 * tileY,
            _ => 200 - 30 * (tileX + tileY),
          };

      final pixels = Uint8List(width * height * 3);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          for (var band = 0; band < 3; band++) {
            pixels[(y * width + x) * 3 + band] =
                colourOf(x ~/ tile, y ~/ tile, band);
          }
        }
      }

      final codestream = encodeJpeg2000Pixels(
        pixels,
        width: width,
        height: height,
        components: 3,
        options: const Jpeg2000EncodeOptions(
          lossless: true,
          wrapInJp2: true,
          tileWidth: tile,
          tileHeight: tile,
        ),
      );

      for (var level = 0; level <= defaultLevels; level++) {
        final image = decodeJpeg2000(
          codestream,
          options: Jpeg2000DecodeOptions(resolution: level),
        );
        final divisor = 1 << (defaultLevels - level);
        expect(image.width, ceilDiv(width, divisor));
        expect(image.height, ceilDiv(height, divisor));

        for (var tileY = 0; tileY < rows; tileY++) {
          for (var tileX = 0; tileX < columns; tileX++) {
            final x0 = ceilDiv(tileX * tile, divisor);
            final x1 = ceilDiv(((tileX + 1) * tile).clamp(0, width), divisor);
            final y0 = ceilDiv(tileY * tile, divisor);
            final y1 = ceilDiv(((tileY + 1) * tile).clamp(0, height), divisor);
            for (var y = y0; y < y1; y++) {
              for (var x = x0; x < x1; x++) {
                for (var band = 0; band < 3; band++) {
                  expect(
                    image.pixels[(y * image.width + x) * 3 + band],
                    colourOf(tileX, tileY, band),
                    reason: 'resolution $level, tile ($tileX, $tileY), '
                        'pixel ($x, $y), band $band',
                  );
                }
              }
            }
          }
        }
      }
    });

    test('level r is the decimation of level r + 1 on a smooth ramp', () {
      // The reversible 5/3 low-pass keeps the even samples of a linear signal,
      // so dropping one level must reproduce every other pixel of the level
      // above. Only the samples reconstructed from the boundary extension
      // drift, and only by a couple of counts.
      const width = 128;
      const height = 96;
      final pixels = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          pixels[y * width + x] = (x + y) & 0xff;
        }
      }
      final codestream = encodeJpeg2000Pixels(
        pixels,
        width: width,
        height: height,
        components: 1,
        options: const Jpeg2000EncodeOptions(lossless: true, wrapInJp2: true),
      );

      final levels = <int, Jpeg2000Image>{
        for (var level = 0; level <= defaultLevels; level++)
          level: decodeJpeg2000(
            codestream,
            options: Jpeg2000DecodeOptions(resolution: level),
          ),
      };

      expect(levels[defaultLevels]!.pixels, pixels,
          reason: 'the full level must still be lossless');

      for (var level = 0; level < defaultLevels; level++) {
        final small = levels[level]!;
        final big = levels[level + 1]!;
        expect(small.width, ceilDiv(big.width, 2));
        expect(small.height, ceilDiv(big.height, 2));
        for (var y = 0; y < small.height; y++) {
          for (var x = 0; x < small.width; x++) {
            final got = small.pixels[y * small.width + x];
            final want = big.pixels[(y * 2) * big.width + x * 2];
            expect((got - want).abs(), lessThanOrEqualTo(10),
                reason: 'resolution $level at ($x, $y)');
          }
        }
      }
    });
  });

  group('reduced resolution across output paths', () {
    // `_collectImage` has a fast path for three 8-bit channels and a generic
    // one for everything else; both take the tile geometry from the same
    // place, so both have to be exercised.
    const width = 130;
    const height = 70;

    Uint8List interleaved(int components) {
      final pixels = Uint8List(width * height * components);
      for (var i = 0; i < width * height; i++) {
        for (var c = 0; c < components; c++) {
          pixels[i * components + c] = (i * (c + 3)) & 0xff;
        }
      }
      return pixels;
    }

    void expectEveryLevel(
      Uint8List codestream, {
      required int components,
      required int outputBitDepth,
    }) {
      for (var level = 0; level <= defaultLevels; level++) {
        final image = decodeJpeg2000(
          codestream,
          options: Jpeg2000DecodeOptions(
            resolution: level,
            outputBitDepth: outputBitDepth,
          ),
        );
        final discarded = defaultLevels - level;
        expect(image.width, reducedExtent(width, discarded));
        expect(image.height, reducedExtent(height, discarded));
        expect(
          image.pixels.length,
          image.width * image.height * components * (outputBitDepth ~/ 8),
          reason: 'buffer at resolution $level',
        );
      }
    }

    test('greyscale, 8-bit and 16-bit output', () {
      final codestream = encodeJpeg2000Pixels(
        interleaved(1),
        width: width,
        height: height,
        components: 1,
        options: const Jpeg2000EncodeOptions(lossless: true, wrapInJp2: true),
      );
      expectEveryLevel(codestream, components: 1, outputBitDepth: 8);
      expectEveryLevel(codestream, components: 1, outputBitDepth: 16);
    });

    test('RGBA, 8-bit and 16-bit output', () {
      final codestream = encodeJpeg2000Pixels(
        interleaved(4),
        width: width,
        height: height,
        components: 4,
        options: const Jpeg2000EncodeOptions(lossless: true, wrapInJp2: true),
      );
      expectEveryLevel(codestream, components: 4, outputBitDepth: 8);
      expectEveryLevel(codestream, components: 4, outputBitDepth: 16);
    });

    test('raw J2K codestream without JP2 boxes', () {
      final codestream = encodeJpeg2000Pixels(
        interleaved(1),
        width: width,
        height: height,
        components: 1,
        options: const Jpeg2000EncodeOptions(lossless: true, wrapInJp2: false),
      );
      expectEveryLevel(codestream, components: 1, outputBitDepth: 8);
    });

    test('subsampled components are resampled onto the reduced grid', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 32,
        height: 32,
        subsX: const <int>[1, 2, 2],
        subsY: const <int>[1, 2, 2],
      );
      final codestream = encodeSubsampledCodestream(source);
      for (var level = 0; level <= defaultLevels; level++) {
        final image = decodeJpeg2000(
          codestream,
          options: Jpeg2000DecodeOptions(resolution: level),
        );
        final discarded = defaultLevels - level;
        expect(image.width, reducedExtent(32, discarded));
        expect(image.height, reducedExtent(32, discarded));
        expect(image.pixels.length, image.width * image.height * 3);
      }
    });
  });
}

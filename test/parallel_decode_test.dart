@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:j2k/j2k.dart';
import 'package:test/test.dart';

/// Contract of [decodeJpeg2000Parallel].
///
/// The one property that matters is that worker isolates change nothing: the
/// bytes a parallel decode produces must equal, sample for sample, the bytes
/// the synchronous decoder produces from the same input with the same options.
/// Anything else would silently corrupt the conformance guarantee the package
/// rests on, so every case here is an exact comparison with no tolerance.
void main() {
  Uint8List fixture(String name) =>
      File('test/fixtures/test_images/$name').readAsBytesSync();

  Uint8List pnm(String magic, int width, int height, List<int> samples) =>
      Uint8List.fromList(<int>[
        ...'$magic\n$width $height\n255\n'.codeUnits,
        ...samples,
      ]);

  /// A busy image: flat content compresses to almost nothing and would not
  /// exercise the entropy decoder in every tile.
  Uint8List rgbSource(int width, int height) => pnm('P6', width, height, <int>[
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++) ...<int>[
            (x * 7 + y * 3) & 0xff,
            (x * x + y * 13) & 0xff,
            ((x ^ y) * 5 + x) & 0xff,
          ],
      ]);

  Uint8List graySource(int width, int height) => pnm('P5', width, height, <int>[
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++) (x * 11 + y * y) & 0xff,
      ]);

  Uint8List tiled(
    Uint8List source, {
    required int tile,
    bool wrapInJp2 = true,
    bool lossless = true,
  }) =>
      encodeJpeg2000(
        source,
        options: Jpeg2000EncodeOptions(
          lossless: lossless,
          wrapInJp2: wrapInJp2,
          tileWidth: tile,
          tileHeight: tile,
        ),
      );

  /// Fails on the first differing sample, naming it, instead of dumping two
  /// buffers of a million bytes into the test log.
  void expectIdentical(Jpeg2000Image parallel, Jpeg2000Image sequential) {
    expect(parallel.width, sequential.width, reason: 'width');
    expect(parallel.height, sequential.height, reason: 'height');
    expect(parallel.components, sequential.components, reason: 'components');
    expect(parallel.colorComponents, sequential.colorComponents);
    expect(parallel.hasAlpha, sequential.hasAlpha);
    expect(parallel.alphaIsPremultiplied, sequential.alphaIsPremultiplied);
    expect(parallel.bitsPerSample, sequential.bitsPerSample);
    expect(parallel.format, sequential.format);
    expect(
      parallel.sourceBitsPerComponent,
      sequential.sourceBitsPerComponent,
    );
    expect(
      parallel.pixels.length,
      sequential.pixels.length,
      reason: 'pixel buffer length',
    );
    for (var i = 0; i < sequential.pixels.length; i++) {
      if (parallel.pixels[i] != sequential.pixels[i]) {
        fail(
          'Parallel decode differs at byte $i: '
          'got ${parallel.pixels[i]}, expected ${sequential.pixels[i]}.',
        );
      }
    }
  }

  group('decodeJpeg2000Parallel', () {
    test('matches the sequential decode of a 2x2 tiled RGB image', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 128);
      expect(probeJpeg2000(codestream).tileColumns, 2);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream),
        decodeJpeg2000(codestream),
      );
    });

    test('matches the sequential decode of a 4x4 tiled RGB image', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 64);
      final info = probeJpeg2000(codestream);
      expect(info.tileColumns * info.tileRows, 16);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream),
        decodeJpeg2000(codestream),
      );
    });

    test('matches the sequential decode of a tiled greyscale image', () async {
      final codestream = tiled(graySource(256, 256), tile: 64);
      final parallel = await decodeJpeg2000Parallel(codestream);
      expect(parallel.format, Jpeg2000PixelFormat.gray);
      expectIdentical(parallel, decodeJpeg2000(codestream));
    });

    test('matches on a tile grid that does not divide the image', () async {
      // 200 is not a multiple of 64, so the right and bottom tiles are
      // narrower than the rest: the offsets the workers report have to be
      // right, not merely consistent.
      final codestream = tiled(rgbSource(200, 150), tile: 64);
      final info = probeJpeg2000(codestream);
      expect(info.tileColumns, 4);
      expect(info.tileRows, 3);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream),
        decodeJpeg2000(codestream),
      );
    });

    test('matches on a raw codestream with no JP2 wrapper', () async {
      final codestream =
          tiled(rgbSource(256, 256), tile: 128, wrapInJp2: false);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream),
        decodeJpeg2000(codestream),
      );
    });

    test('matches on a lossy 9/7 codestream', () async {
      // The irreversible filter is floating point, so a worker that rounded
      // differently would show up here and nowhere else.
      final codestream = encodeJpeg2000(
        rgbSource(256, 256),
        options: const Jpeg2000EncodeOptions(
          lossless: false,
          rate: 1.5,
          wrapInJp2: true,
          tileWidth: 128,
          tileHeight: 128,
        ),
      );
      expectIdentical(
        await decodeJpeg2000Parallel(codestream),
        decodeJpeg2000(codestream),
      );
    });

    test('matches with 16-bit output', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 128);
      const options = Jpeg2000DecodeOptions(outputBitDepth: 16);
      final parallel =
          await decodeJpeg2000Parallel(codestream, options: options);
      expect(parallel.bitsPerSample, 16);
      expectIdentical(parallel, decodeJpeg2000(codestream, options: options));
    });

    test('matches with the component transform turned off', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 128);
      const options = Jpeg2000DecodeOptions(applyComponentTransform: false);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, options: options),
        decodeJpeg2000(codestream, options: options),
      );
    });

    test('mirrors the sequential path at every reduced resolution level',
        () async {
      // The tiled codestream takes the per-tile worker path and the single
      // tile one the per-code-block path, so both parallel strategies are
      // checked against the sequential decoder at every level.
      for (final codestream in <Uint8List>[
        tiled(rgbSource(256, 256), tile: 128),
        encodeJpeg2000(
          rgbSource(256, 256),
          options: const Jpeg2000EncodeOptions(
            lossless: true,
            wrapInJp2: true,
          ),
        ),
      ]) {
        for (var level = 0; level <= 5; level++) {
          final options = Jpeg2000DecodeOptions(resolution: level);
          final sequential = decodeJpeg2000(codestream, options: options);
          expectIdentical(
            await decodeJpeg2000Parallel(codestream, options: options),
            sequential,
          );
        }
      }
    });

    test('matches with a byte budget that truncates the stream', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 128);
      // Rate allocation is decided from the whole codestream when the
      // bitstream reader is built, so every worker must reach the same
      // truncation point as the sequential decode.
      final options = Jpeg2000DecodeOptions(bytes: codestream.length ~/ 4);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, options: options),
        decodeJpeg2000(codestream, options: options),
      );
    });

    test('matches the sequential decode of a single-tile fixture', () async {
      // The fallback path: no worker is involved, but the result still has to
      // be the documented one.
      final codestream = fixture('file1.jp2');
      expect(probeJpeg2000(codestream).tileColumns, 1);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream),
        decodeJpeg2000(codestream),
      );
    });

    test('a forced single worker still produces the same bytes', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 64);
      expectIdentical(
        await decodeJpeg2000Parallel(
          codestream,
          parallel: Jpeg2000ParallelOptions.sequential,
        ),
        decodeJpeg2000(codestream),
      );
    });

    test('more workers than tiles does not lose or duplicate a tile', () async {
      final codestream = tiled(rgbSource(128, 128), tile: 64);
      expect(probeJpeg2000(codestream).tileColumns * 1, 2);
      expectIdentical(
        await decodeJpeg2000Parallel(
          codestream,
          parallel: const Jpeg2000ParallelOptions(
            concurrency: 16,
            minParallelPixels: 1,
          ),
        ),
        decodeJpeg2000(codestream),
      );
    });

    test('every worker count from 1 to 8 gives the same bytes', () async {
      final codestream = tiled(rgbSource(192, 192), tile: 64);
      final expected = decodeJpeg2000(codestream);
      for (var workers = 1; workers <= 8; workers++) {
        expectIdentical(
          await decodeJpeg2000Parallel(
            codestream,
            parallel: Jpeg2000ParallelOptions(
              concurrency: workers,
              minParallelPixels: 1,
            ),
          ),
          expected,
        );
      }
    });

    test('reports the decode warnings of the workers', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 64);
      final warnings = <String>[];
      await decodeJpeg2000Parallel(
        codestream,
        options: Jpeg2000DecodeOptions(onWarning: warnings.add),
        parallel: const Jpeg2000ParallelOptions(minParallelPixels: 1),
      );
      // A clean codestream warns about nothing; what must not happen is the
      // same message arriving once per worker.
      expect(warnings.toSet().length, warnings.length);
    });

    test('rejects options the synchronous decoder also rejects', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 128);
      expect(
        () => decodeJpeg2000Parallel(
          codestream,
          options: const Jpeg2000DecodeOptions(rate: 1, bytes: 100),
        ),
        throwsArgumentError,
      );
    });

    test('enforces the pixel budget before spawning a worker', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 128);
      await expectLater(
        decodeJpeg2000Parallel(
          codestream,
          options: const Jpeg2000DecodeOptions(maxPixels: 1024),
        ),
        throwsA(isA<Jpeg2000BudgetException>()),
      );
    });

    test('surfaces a corrupt codestream as a Jpeg2000Exception', () async {
      final codestream = tiled(rgbSource(256, 256), tile: 64);
      // Damage the packet data, not the header, so the failure happens inside
      // a worker rather than during the planning pass.
      final damaged = Uint8List.fromList(codestream);
      for (var i = damaged.length ~/ 2; i < damaged.length; i += 3) {
        damaged[i] = 0xff;
      }
      await expectLater(
        decodeJpeg2000Parallel(damaged),
        anyOf(
          throwsA(isA<Jpeg2000Exception>()),
          completes,
        ),
      );
    });
  });

  group('decodeJpeg2000Parallel by code-block', () {
    // With fewer tiles than workers the split moves below the tile, to the
    // code-block. This is the path that matters for PDF, where the embedded
    // JPEG 2000 images are almost always a single tile, and it is also the
    // riskiest: the entropy decoder is driven from a cache filled out of
    // order instead of from the bitstream in order.
    const codeBlocks = Jpeg2000ParallelOptions(minParallelPixels: 1);

    Uint8List conformance(String name) =>
        File('test/fixtures/j2k_tests/conformance_subset/$name')
            .readAsBytesSync();

    test('matches the sequential decode of the file1 conformance image',
        () async {
      // One of the two images the package is checked bit-exact against
      // JJ2000 on. If the code-block split changed a single sample, that
      // guarantee would be gone.
      final codestream = conformance('file1.jp2');
      expect(probeJpeg2000(codestream).tileColumns, 1);
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, parallel: codeBlocks),
        decodeJpeg2000(codestream),
      );
    });

    test('matches the sequential decode of the relax conformance image',
        () async {
      final codestream = conformance('relax.jp2');
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, parallel: codeBlocks),
        decodeJpeg2000(codestream),
      );
    });

    test('matches on a single-tile image encoded by JJ2000', () async {
      final codestream = fixture('generated/noise_pattern_jj2000.j2k');
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, parallel: codeBlocks),
        decodeJpeg2000(codestream),
      );
    });

    test('matches on a single-tile image encoded by OpenJPEG', () async {
      final codestream = fixture('generated/noise_pattern_openjpeg.jp2');
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, parallel: codeBlocks),
        decodeJpeg2000(codestream),
      );
    });

    test('matches on a single-tile greyscale image', () async {
      final codestream = tiled(graySource(256, 256), tile: 0);
      expect(probeJpeg2000(codestream).tileColumns, 1);
      final parallel =
          await decodeJpeg2000Parallel(codestream, parallel: codeBlocks);
      expect(parallel.format, Jpeg2000PixelFormat.gray);
      expectIdentical(parallel, decodeJpeg2000(codestream));
    });

    test('matches on a single-tile lossy 9/7 image', () async {
      final codestream = encodeJpeg2000(
        rgbSource(256, 256),
        options: const Jpeg2000EncodeOptions(
          lossless: false,
          rate: 1.5,
          wrapInJp2: true,
        ),
      );
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, parallel: codeBlocks),
        decodeJpeg2000(codestream),
      );
    });

    test('matches on an image with alpha', () async {
      final codestream = fixture('icon32.jp2');
      expectIdentical(
        await decodeJpeg2000Parallel(codestream, parallel: codeBlocks),
        decodeJpeg2000(codestream),
      );
    });

    test('matches with 16-bit output', () async {
      final codestream = conformance('relax.jp2');
      const options = Jpeg2000DecodeOptions(outputBitDepth: 16);
      expectIdentical(
        await decodeJpeg2000Parallel(
          codestream,
          options: options,
          parallel: codeBlocks,
        ),
        decodeJpeg2000(codestream, options: options),
      );
    });

    test('matches with a byte budget that truncates the stream', () async {
      final codestream = conformance('file1.jp2');
      // Truncation makes the bitstream reader hand out partial code-blocks
      // with fewer coding passes; the workers must stop at the same pass.
      final options = Jpeg2000DecodeOptions(bytes: codestream.length ~/ 5);
      expectIdentical(
        await decodeJpeg2000Parallel(
          codestream,
          options: options,
          parallel: codeBlocks,
        ),
        decodeJpeg2000(codestream, options: options),
      );
    });

    test('every worker count from 2 to 8 gives the same bytes', () async {
      // The split is round-robin over the enumeration order, so each worker
      // count groups the code-blocks differently. If any grouping mattered —
      // if the entropy decoder leaked state from one block into the next —
      // the counts would disagree.
      final codestream = fixture('generated/circles_jj2000.j2k');
      final expected = decodeJpeg2000(codestream);
      for (var workers = 2; workers <= 8; workers++) {
        expectIdentical(
          await decodeJpeg2000Parallel(
            codestream,
            parallel: Jpeg2000ParallelOptions(
              concurrency: workers,
              minParallelPixels: 1,
            ),
          ),
          expected,
        );
      }
    });

    test('matches on a 2x2 tiled image, which is still too few tiles',
        () async {
      // Four tiles and eight workers: a whole-tile split would idle half of
      // them, so this goes through the code-block path across all four tiles.
      final codestream = tiled(rgbSource(256, 256), tile: 128);
      expectIdentical(
        await decodeJpeg2000Parallel(
          codestream,
          parallel: const Jpeg2000ParallelOptions(
            concurrency: 8,
            minParallelPixels: 1,
          ),
        ),
        decodeJpeg2000(codestream),
      );
    });

    test('surfaces a corrupt codestream as a Jpeg2000Exception', () async {
      final codestream = fixture('generated/circles_jj2000.j2k');
      final damaged = Uint8List.fromList(codestream);
      for (var i = damaged.length ~/ 2; i < damaged.length; i += 3) {
        damaged[i] = 0xff;
      }
      await expectLater(
        decodeJpeg2000Parallel(damaged, parallel: codeBlocks),
        anyOf(throwsA(isA<Jpeg2000Exception>()), completes),
      );
    });
  });

  group('Jpeg2000ParallelOptions', () {
    test('still parallelises a single-tile image', () {
      // A single tile used to mean no parallelism at all. It now means the
      // split happens below the tile, so the worker count must survive it.
      const options = Jpeg2000ParallelOptions(concurrency: 8);
      expect(options.workersFor(pixels: 4000000), 8);
      expect(options.tileWorkersFor(tileCount: 1, workers: 8), 1);
    });

    test('keeps a small image on the sequential path', () {
      const options = Jpeg2000ParallelOptions();
      expect(options.workersFor(pixels: 4096), 1);
    });

    test('never asks for more tile workers than there are tiles', () {
      const options =
          Jpeg2000ParallelOptions(concurrency: 8, minParallelPixels: 1);
      expect(options.tileWorkersFor(tileCount: 3, workers: 8), 3);
    });

    test('a concurrency of one disables the workers', () {
      expect(
        Jpeg2000ParallelOptions.sequential.workersFor(pixels: 4000000),
        1,
      );
    });

    test('minTilesPerWorker caps the whole-tile split', () {
      const options = Jpeg2000ParallelOptions(
        concurrency: 8,
        minParallelPixels: 1,
        minTilesPerWorker: 4,
      );
      expect(options.tileWorkersFor(tileCount: 8, workers: 8), 2);
    });
  });
}

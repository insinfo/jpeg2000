@TestOn('vm')
library;

import 'package:j2k/j2k.dart';
import 'package:test/test.dart';

import 'subsampled_support.dart';

/// Decoding of images whose components carry `XRsiz`/`YRsiz` other than 1.
///
/// The samples of component `c` sit on the reference grid at integer multiples
/// of `(XRsiz_c, YRsiz_c)` (ISO/IEC 15444-1 B.2), so after resampling the pixel
/// at grid point `(x, y)` must be the component sample
/// `(x ~/ XRsiz_c, y ~/ YRsiz_c)`, with no half-pixel drift.
void main() {
  void expectResampledExactly(
    Jpeg2000Image image,
    PlanarSubsampledSource source, {
    required String reason,
  }) {
    expect(image.width, source.w, reason: reason);
    expect(image.height, source.h, reason: reason);
    expect(image.components, source.nc, reason: reason);
    for (var c = 0; c < source.nc; c++) {
      for (var y = 0; y < source.h; y++) {
        for (var x = 0; x < source.w; x++) {
          expect(
            image.pixels[(y * source.w + x) * source.nc + c],
            source.sampleAt(c, x, y),
            reason: '$reason: component $c at ($x, $y)',
          );
        }
      }
    }
  }

  group('raw codestream with subsampled components', () {
    test('decodes 4:2:0 chroma back onto the reference grid', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 16,
        height: 16,
        subsX: const <int>[1, 2, 2],
        subsY: const <int>[1, 2, 2],
      );
      final codestream = encodeSubsampledCodestream(source);
      final probe = probeJpeg2000(codestream);
      expect(probe.subsamplingX, <int>[1, 2, 2]);
      expect(probe.subsamplingY, <int>[1, 2, 2]);

      expectResampledExactly(
        decodeJpeg2000(codestream),
        source,
        reason: '4:2:0',
      );
    });

    test('decodes 4:2:2 chroma, subsampled horizontally only', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 16,
        height: 8,
        subsX: const <int>[1, 2, 2],
        subsY: const <int>[1, 1, 1],
      );
      expectResampledExactly(
        decodeJpeg2000(encodeSubsampledCodestream(source)),
        source,
        reason: '4:2:2',
      );
    });

    test('decodes a component subsampled vertically only', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 12,
        height: 12,
        subsX: const <int>[1, 1, 1],
        subsY: const <int>[1, 2, 2],
      );
      expectResampledExactly(
        decodeJpeg2000(encodeSubsampledCodestream(source)),
        source,
        reason: 'vertical only',
      );
    });

    test('handles subsampling factors beyond 2:1', () {
      for (final factor in <int>[3, 4, 5, 8]) {
        final source = PlanarSubsampledSource.synthetic(
          width: 24,
          height: 24,
          subsX: <int>[1, factor, factor],
          subsY: <int>[1, factor, factor],
        );
        final probe = probeJpeg2000(encodeSubsampledCodestream(source));
        expect(probe.subsamplingX, <int>[1, factor, factor]);
        expectResampledExactly(
          decodeJpeg2000(encodeSubsampledCodestream(source)),
          source,
          reason: 'factor $factor',
        );
      }
    });

    test('handles different factors per axis and per component', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 24,
        height: 24,
        subsX: const <int>[1, 4, 2],
        subsY: const <int>[1, 2, 3],
      );
      expectResampledExactly(
        decodeJpeg2000(encodeSubsampledCodestream(source)),
        source,
        reason: 'mixed factors',
      );
    });

    test('handles sizes that are not a multiple of the factor', () {
      for (final size in <List<int>>[
        <int>[9, 7],
        <int>[5, 5],
        <int>[13, 11],
      ]) {
        final source = PlanarSubsampledSource.synthetic(
          width: size[0],
          height: size[1],
          subsX: const <int>[1, 2, 2],
          subsY: const <int>[1, 2, 2],
        );
        expectResampledExactly(
          decodeJpeg2000(encodeSubsampledCodestream(source)),
          source,
          reason: '${size[0]}x${size[1]}',
        );
      }
    });

    test('resamples every tile of a tiled codestream', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 32,
        height: 24,
        subsX: const <int>[1, 2, 2],
        subsY: const <int>[1, 2, 2],
      );
      final codestream = encodeSubsampledCodestream(
        source,
        tileWidth: 16,
        tileHeight: 8,
      );
      expectResampledExactly(
        decodeJpeg2000(codestream),
        source,
        reason: 'tiled 16x8',
      );
    });

    test('keeps 16-bit output exact for a subsampled 12-bit source', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 8,
        height: 8,
        subsX: const <int>[1, 2],
        subsY: const <int>[1, 2],
        bitsPerSample: 12,
      );
      final image = decodeJpeg2000(
        encodeSubsampledCodestream(source),
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      expect(image.width, 8);
      expect(image.height, 8);
      expect(image.sourceBitsPerComponent, <int>[12, 12]);
      // 12 bits are rescaled so that 4095 maps to 65535, not shifted.
      int to16(int sample) => (sample * 65535 + 2047) ~/ 4095;
      for (var c = 0; c < source.nc; c++) {
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            expect(
              image.pixels16[(y * 8 + x) * source.nc + c],
              to16(source.sampleAt(c, x, y)),
              reason: 'component $c at ($x, $y)',
            );
          }
        }
      }
    });
  });

  group('JP2 file with subsampled components', () {
    test('resamples through the colour pipeline', () {
      final source = PlanarSubsampledSource.synthetic(
        width: 14,
        height: 10,
        subsX: const <int>[1, 2, 2],
        subsY: const <int>[1, 2, 2],
      );
      final file = wrapInJp2(
        encodeSubsampledCodestream(source),
        width: source.w,
        height: source.h,
        components: source.nc,
        bitsPerComponent: source.bitsPerSample,
      );
      final image = decodeJpeg2000(
        file,
        // The JP2 says sRGB while the planes are independent; without this the
        // enumerated colour space mapper would be the one under test.
        options: const Jpeg2000DecodeOptions(applyColorSpace: false),
      );
      expectResampledExactly(image, source, reason: 'JP2 4:2:0');
    });

    test('resamples by a factor beyond 2:1 through the colour pipeline', () {
      // Sizes that are not a multiple of the factor on purpose: the
      // component planes are then narrower than width / factor rounded up
      // times the factor, which the old JJ2000 geometry reported wrong.
      final source = PlanarSubsampledSource.synthetic(
        width: 14,
        height: 11,
        subsX: const <int>[1, 3, 4],
        subsY: const <int>[1, 4, 3],
      );
      final file = wrapInJp2(
        encodeSubsampledCodestream(source),
        width: source.w,
        height: source.h,
        components: source.nc,
        bitsPerComponent: source.bitsPerSample,
      );
      expectResampledExactly(
        decodeJpeg2000(
          file,
          options: const Jpeg2000DecodeOptions(applyColorSpace: false),
        ),
        source,
        reason: 'JP2 factor 3 and 4',
      );
    });
  });
}

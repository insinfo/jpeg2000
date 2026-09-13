@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:j2k/j2k.dart';
import 'package:test/test.dart';

/// Per-component bit depths and signed components in the pixel encoder.
///
/// `Ssiz` of the SIZ marker segment carries `depth - 1` in its seven low bits
/// and the sign of the component in the high bit (ISO/IEC 15444-1 A.5.1), so
/// each component is free to have its own depth and sign.
void main() {
  group('bitsPerComponent', () {
    test('writes one depth per component into SIZ', () {
      const width = 8;
      const height = 6;
      const depths = <int>[8, 12, 4];
      final samples = Uint16List(width * height * depths.length);
      for (var i = 0; i < width * height; i++) {
        samples[i * 3] = i % 256;
        samples[i * 3 + 1] = (i * 17) % 4096;
        samples[i * 3 + 2] = i % 16;
      }

      final codestream = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 3,
        bitsPerComponent: depths,
      );

      final info = probeJpeg2000(codestream);
      expect(info.bitsPerComponent, depths);
      expect(info.isSigned, <bool>[false, false, false]);
      expect(info.maxBitsPerComponent, 12);
    });

    test('round-trips mixed depths losslessly at 16-bit output', () {
      const width = 6;
      const height = 5;
      const depths = <int>[10, 6];
      final samples = Uint16List(width * height * 2);
      for (var i = 0; i < width * height; i++) {
        samples[i * 2] = (i * 7) % 1024;
        samples[i * 2 + 1] = (i * 5) % 64;
      }

      final codestream = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 2,
        bitsPerComponent: depths,
        hasAlpha: false,
      );
      final image = decodeJpeg2000(
        codestream,
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      expect(image.sourceBitsPerComponent, depths);
      for (var i = 0; i < width * height; i++) {
        for (var c = 0; c < 2; c++) {
          final max = (1 << depths[c]) - 1;
          expect(
            image.pixels16[i * 2 + c],
            (samples[i * 2 + c] * 65535 + max ~/ 2) ~/ max,
            reason: 'sample $i component $c',
          );
        }
      }
    });

    test('records mixed depths in the JP2 bits per component box', () {
      const width = 4;
      const height = 4;
      final file = encodeJpeg2000Pixels(
        Uint16List(width * height * 2),
        width: width,
        height: height,
        components: 2,
        bitsPerComponent: const <int>[9, 5],
        hasAlpha: false,
        options: const Jpeg2000EncodeOptions(wrapInJp2: true),
      );
      final info = probeJpeg2000(file);
      expect(info.isJp2, isTrue);
      expect(info.bitsPerComponent, <int>[9, 5]);
    });

    test('drops the component transform when the first three disagree', () {
      // G.2 and G.3 of T.800 allow the RCT and the ICT only on three
      // components of equal bit depth and equal separation on the reference
      // grid, so mixed depths must be coded without the transform — and the
      // result must still be lossless.
      const width = 8;
      const height = 8;
      const depths = <int>[8, 12, 8];
      final samples = Uint16List(width * height * 3);
      for (var i = 0; i < width * height; i++) {
        samples[i * 3] = (i * 3) % 256;
        samples[i * 3 + 1] = (i * 29) % 4096;
        samples[i * 3 + 2] = (i * 7) % 256;
      }

      final codestream = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 3,
        bitsPerComponent: depths,
      );
      final image = decodeJpeg2000(
        codestream,
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      expect(image.sourceBitsPerComponent, depths);
      for (var i = 0; i < width * height; i++) {
        for (var c = 0; c < 3; c++) {
          final max = (1 << depths[c]) - 1;
          expect(
            image.pixels16[i * 3 + c],
            (samples[i * 3 + c] * 65535 + max ~/ 2) ~/ max,
            reason: 'sample $i component $c',
          );
        }
      }
    });

    test('keeps the component transform when all three agree', () {
      const width = 8;
      const height = 8;
      final samples = Uint8List(width * height * 3);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = (i * 5) % 256;
      }
      final withoutList = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 3,
      );
      final withList = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 3,
        bitsPerComponent: const <int>[8, 8, 8],
      );
      expect(withList, withoutList);
    });

    test('rejects a depth list of the wrong length', () {
      expect(
        () => encodeJpeg2000Pixels(
          Uint8List(16),
          width: 4,
          height: 4,
          components: 1,
          bitsPerComponent: const <int>[8, 8],
        ),
        throwsArgumentError,
      );
    });
  });

  group('signedComponents', () {
    test('sets the sign bit of Ssiz and keeps the samples centred', () {
      const width = 8;
      const height = 4;
      final samples = Int16List(width * height * 2);
      for (var i = 0; i < width * height; i++) {
        samples[i * 2] = (i % 256) - 128;
        samples[i * 2 + 1] = i % 256;
      }

      final codestream = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 2,
        bitsPerSample: 8,
        signedComponents: const <bool>[true, false],
        hasAlpha: false,
      );

      final info = probeJpeg2000(codestream);
      expect(info.isSigned, <bool>[true, false]);
      expect(info.bitsPerComponent, <int>[8, 8]);
    });

    test('marks the sign in the JP2 bits per component box too', () {
      const width = 4;
      const height = 4;
      final file = encodeJpeg2000Pixels(
        List<int>.filled(width * height * 2, 0),
        width: width,
        height: height,
        components: 2,
        bitsPerSample: 8,
        signedComponents: const <bool>[true, false],
        hasAlpha: false,
        options: const Jpeg2000EncodeOptions(wrapInJp2: true),
      );
      final info = probeJpeg2000(file);
      expect(info.isJp2, isTrue);
      expect(info.isSigned, <bool>[true, false]);
    });

    test('refuses signed samples in a list that cannot hold them', () {
      expect(
        () => encodeJpeg2000Pixels(
          Uint8List(16),
          width: 4,
          height: 4,
          components: 1,
          signedComponents: const <bool>[true],
        ),
        throwsArgumentError,
      );
    });

    test('leaves unsigned encoding untouched by default', () {
      const width = 4;
      const height = 4;
      final samples = Uint8List.fromList(
        List<int>.generate(width * height, (i) => i * 3),
      );
      final withDefaults = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 1,
      );
      final withExplicitLists = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 1,
        bitsPerComponent: const <int>[8],
        signedComponents: const <bool>[false],
      );
      expect(withExplicitLists, withDefaults);
    });
  });
}

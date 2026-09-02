@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';
import 'package:test/test.dart';

/// 16-bit output and the pixel-buffer encoder.
void main() {
  Uint8List fixture(String name) =>
      File('test/fixtures/test_images/$name').readAsBytesSync();

  group('outputBitDepth 16', () {
    test('keeps the full range of a 16-bit source', () {
      final image = decodeJpeg2000(
        fixture('grad_final.jp2'),
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      expect(image.bitsPerSample, 16);
      expect(image.pixels.length, 32 * 32 * 3 * 2);
      expect(image.pixels16.length, 32 * 32 * 3);
      expect(image.rowStride, 32 * 3 * 2);
      final narrow = decodeJpeg2000(fixture('grad_final.jp2'));
      for (var i = 0; i < narrow.pixels.length; i++) {
        expect(image.pixels16[i] >> 8, narrow.pixels[i], reason: 'sample $i');
      }
      expect(image.pixels16.any((s) => s & 0xff != 0), isTrue,
          reason: 'the low byte must carry information the 8-bit path drops');
    });

    test('rescales an 8-bit source so 255 becomes 65535', () {
      final image = decodeJpeg2000(
        fixture('icon32.jp2'),
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      final narrow = decodeJpeg2000(fixture('icon32.jp2'));
      for (var i = 0; i < narrow.pixels.length; i++) {
        expect(image.pixels16[i], narrow.pixels[i] * 257, reason: 'sample $i');
      }
    });

    test('pixels16 is refused on an 8-bit image', () {
      final image = decodeJpeg2000(fixture('icon32.jp2'));
      expect(() => image.pixels16, throwsStateError);
    });

    test('other depths are rejected', () {
      expect(
        () => decodeJpeg2000(
          fixture('icon32.jp2'),
          options: const Jpeg2000DecodeOptions(outputBitDepth: 12),
        ),
        throwsArgumentError,
      );
    });
  });

  group('encodeJpeg2000Pixels', () {
    test('round-trips RGBA losslessly and records alpha in the JP2', () {
      const width = 12;
      const height = 9;
      final rgba = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        rgba[i * 4] = (i * 7) & 0xff;
        rgba[i * 4 + 1] = (255 - i * 3) & 0xff;
        rgba[i * 4 + 2] = (i * 11) & 0xff;
        rgba[i * 4 + 3] = i.isEven ? 255 : (i * 5) & 0xff;
      }
      final jp2 = encodeJpeg2000Pixels(
        rgba,
        width: width,
        height: height,
        components: 4,
        options: const Jpeg2000EncodeOptions(wrapInJp2: true),
      );
      final info = probeJpeg2000(jp2);
      expect(info.hasAlpha, isTrue);
      expect(info.pixelFormat, Jpeg2000PixelFormat.rgba);

      final image = decodeJpeg2000(jp2);
      expect(image.format, Jpeg2000PixelFormat.rgba);
      expect(image.hasAlpha, isTrue);
      expect(image.alphaIsPremultiplied, isFalse);
      expect(image.pixels, rgba);
    });

    test('round-trips gray+alpha through a raw codestream', () {
      const width = 5;
      const height = 4;
      final ga = Uint8List.fromList(
        List<int>.generate(width * height * 2, (i) => (i * 37) & 0xff),
      );
      final j2k = encodeJpeg2000Pixels(
        ga,
        width: width,
        height: height,
        components: 2,
      );
      final image = decodeJpeg2000(j2k);
      expect(image.format, Jpeg2000PixelFormat.grayAlpha);
      expect(image.pixels, ga);
    });

    test('round-trips 16-bit gray losslessly', () {
      const width = 8;
      const height = 8;
      final samples = Uint16List.fromList(
        List<int>.generate(width * height, (i) => (i * 1021) & 0xffff),
      );
      final j2k = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 1,
        bitsPerSample: 16,
      );
      expect(probeJpeg2000(j2k).bitsPerComponent, <int>[16]);
      final image = decodeJpeg2000(
        j2k,
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      expect(image.format, Jpeg2000PixelFormat.gray);
      expect(image.sourceBitsPerComponent, <int>[16]);
      expect(image.pixels16, samples);
    });

    test('round-trips 12-bit RGB losslessly', () {
      const width = 6;
      const height = 5;
      final samples = Uint16List.fromList(
        List<int>.generate(width * height * 3, (i) => (i * 131) & 0xfff),
      );
      final j2k = encodeJpeg2000Pixels(
        samples,
        width: width,
        height: height,
        components: 3,
        bitsPerSample: 12,
      );
      final image = decodeJpeg2000(
        j2k,
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      // 12-bit samples come back rescaled to 16 bits: round(s * 65535 / 4095).
      for (var i = 0; i < samples.length; i++) {
        expect(image.pixels16[i], (samples[i] * 65535 + 2047) ~/ 4095,
            reason: 'sample $i');
      }
    });

    test('lets the caller declare four components as colour', () {
      final cmyk = Uint8List.fromList(
        List<int>.generate(4 * 4 * 4, (i) => (i * 19) & 0xff),
      );
      final j2k = encodeJpeg2000Pixels(
        cmyk,
        width: 4,
        height: 4,
        components: 4,
        hasAlpha: false,
        options: const Jpeg2000EncodeOptions(wrapInJp2: true),
      );
      // Without a cdef box and with an sRGB colr box the decoder falls back
      // to the 4-channel convention, so the samples are still all there.
      final image = decodeJpeg2000(j2k);
      expect(image.components, 4);
      expect(image.pixels, cmyk);
    });

    test('rejects inconsistent input', () {
      expect(
        () => encodeJpeg2000Pixels(Uint8List(10),
            width: 4, height: 4, components: 1),
        throwsArgumentError,
      );
      expect(
        () => encodeJpeg2000Pixels(Uint8List(16),
            width: 4, height: 4, components: 1, bitsPerSample: 12),
        throwsArgumentError,
      );
      expect(
        () => encodeJpeg2000Pixels(Uint8List(48),
            width: 4, height: 4, components: 3, hasAlpha: true),
        throwsArgumentError,
      );
    });
  });

  group('16-bit PNM', () {
    test('encodes a two-byte PGM losslessly', () {
      const width = 4;
      const height = 3;
      final header = 'P5\n$width $height\n65535\n'.codeUnits;
      final samples = List<int>.generate(width * height, (i) => i * 5000);
      final bytes = Uint8List.fromList(<int>[
        ...header,
        for (final s in samples) ...<int>[s >> 8, s & 0xff],
      ]);
      final j2k = encodeJpeg2000(bytes);
      final image = decodeJpeg2000(
        j2k,
        options: const Jpeg2000DecodeOptions(outputBitDepth: 16),
      );
      expect(image.pixels16, samples);
    });
  });
}

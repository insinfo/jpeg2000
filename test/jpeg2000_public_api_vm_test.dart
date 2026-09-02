@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';
import 'package:test/test.dart';

/// Contract of the byte API against the versioned fixtures.
///
/// The browser-safe sibling `jpeg2000_public_api_test.dart` only round-trips
/// synthetic images; this file needs `dart:io` to read fixtures with alpha,
/// 16-bit samples and ICC profiles, so it runs on the VM only.
void main() {
  Uint8List fixture(String name) =>
      File('test/fixtures/test_images/$name').readAsBytesSync();

  group('probeJpeg2000', () {
    test('reads geometry from a JP2 without decoding', () {
      final info = probeJpeg2000(fixture('file1.jp2'));
      expect(info.isJp2, isTrue);
      expect(info.width, 768);
      expect(info.height, 512);
      expect(info.components, 3);
      expect(info.colorComponents, 3);
      expect(info.hasAlpha, isFalse);
      expect(info.bitsPerComponent, <int>[8, 8, 8]);
      expect(info.pixelFormat, Jpeg2000PixelFormat.rgb8);
      expect(info.tileColumns * info.tileRows, greaterThan(0));
    });

    test('reports alpha from the channel definition box', () {
      final info = probeJpeg2000(fixture('barras_rgb.jp2'));
      expect(info.components, 4);
      expect(info.colorComponents, 3);
      expect(info.hasAlpha, isTrue);
      expect(info.pixelFormat, Jpeg2000PixelFormat.rgba8);
    });

    test('reports 16-bit sources', () {
      final info = probeJpeg2000(fixture('grad_final.jp2'));
      expect(info.bitsPerComponent, <int>[16, 16, 16]);
    });

    test('works on a raw codestream', () {
      final pgm = _pnm('P5', 5, 3, List<int>.generate(15, (i) => i * 10));
      final j2k = encodeJpeg2000(pgm);
      final info = probeJpeg2000(j2k);
      expect(info.isJp2, isFalse);
      expect(info.width, 5);
      expect(info.height, 3);
      expect(info.components, 1);
      expect(info.pixelFormat, Jpeg2000PixelFormat.gray8);
    });
  });

  group('decodeJpeg2000 layout', () {
    test('keeps the alpha channel of a four-component JP2', () {
      final image = decodeJpeg2000(fixture('barras_rgb.jp2'));
      expect(image.format, Jpeg2000PixelFormat.rgba8);
      expect(image.components, 4);
      expect(image.colorComponents, 3);
      expect(image.hasAlpha, isTrue);
      expect(image.alphaIsPremultiplied, isFalse);
      expect(image.pixels.length, 32 * 32 * 4);
      expect(image.sourceBitsPerComponent, <int>[8, 8, 8, 8]);
      // The colour channels must match the RGB decode of the same file.
      final rgb = decodeJpeg2000(
        fixture('barras_rgb.jp2'),
        options: const Jpeg2000DecodeOptions(applyColorSpace: false),
      );
      expect(rgb.components, 4);
      for (var p = 0; p < 32 * 32; p++) {
        for (var c = 0; c < 3; c++) {
          expect(image.pixels[p * 4 + c], rgb.pixels[p * 4 + c]);
        }
      }
    });

    test('scales 16-bit sources to 8 bits and says so', () {
      final image = decodeJpeg2000(fixture('grad_final.jp2'));
      expect(image.format, Jpeg2000PixelFormat.rgb8);
      expect(image.sourceBitsPerComponent, <int>[16, 16, 16]);
      expect(image.pixels.length, 32 * 32 * 3);
    });

    test('forwards warnings instead of printing them', () {
      final warnings = <String>[];
      decodeJpeg2000(
        fixture('relax.jp2'),
        options: Jpeg2000DecodeOptions(onWarning: warnings.add),
      );
      expect(warnings, isNotEmpty);
      expect(warnings.join('\n'), contains('ICC'));
    });
  });

  group('decodeJpeg2000 budgets', () {
    test('rejects by pixel count before decoding', () {
      expect(
        () => decodeJpeg2000(
          fixture('file1.jp2'),
          options: const Jpeg2000DecodeOptions(maxPixels: 1000),
        ),
        throwsA(
          isA<Jpeg2000BudgetException>()
              .having((e) => e.budget, 'budget', 'maxPixels')
              .having((e) => e.actual, 'actual', 768 * 512),
        ),
      );
    });

    test('rejects by dimension before decoding', () {
      expect(
        () => decodeJpeg2000(
          fixture('file1.jp2'),
          options: const Jpeg2000DecodeOptions(maxDimension: 512),
        ),
        throwsA(
          isA<Jpeg2000BudgetException>()
              .having((e) => e.budget, 'budget', 'maxDimension')
              .having((e) => e.actual, 'actual', 768),
        ),
      );
    });

    test('rejects a hostile SIZ without allocating', () {
      // A raw codestream whose SIZ declares a 100000x100000 image.
      final siz = _sizMarker(width: 100000, height: 100000, components: 1);
      expect(
        () => decodeJpeg2000(
          siz,
          options: const Jpeg2000DecodeOptions(maxPixels: 1 << 24),
        ),
        throwsA(isA<Jpeg2000BudgetException>()),
      );
      expect(probeJpeg2000(siz).width, 100000);
    });

    test('accepts images within budget', () {
      final image = decodeJpeg2000(
        fixture('icon32.jp2'),
        options: const Jpeg2000DecodeOptions(maxPixels: 1024, maxDimension: 32),
      );
      expect(image.width, 32);
    });
  });

  group('decodeJpeg2000 errors', () {
    test('empty input is a format error', () {
      expect(
        () => decodeJpeg2000(Uint8List(0)),
        throwsA(isA<Jpeg2000FormatException>()),
      );
    });

    test('garbage is a format error', () {
      final garbage = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 37) & 0xff),
      );
      expect(
        () => decodeJpeg2000(garbage),
        throwsA(isA<Jpeg2000FormatException>()),
      );
      expect(
        () => probeJpeg2000(garbage),
        throwsA(isA<Jpeg2000FormatException>()),
      );
    });

    test('a codestream cut short is a truncation', () {
      final bytes = fixture('file1.jp2');
      expect(
        () =>
            decodeJpeg2000(Uint8List.sublistView(bytes, 0, bytes.length ~/ 2)),
        throwsA(isA<Jpeg2000TruncatedException>()),
      );
    });

    test('a JP2 cut inside its header is a truncation', () {
      final bytes = fixture('icon32.jp2');
      expect(
        () => decodeJpeg2000(Uint8List.sublistView(bytes, 0, 40)),
        throwsA(isA<Jpeg2000TruncatedException>()),
      );
    });

    test('an inconsistent SIZ is corruption', () {
      final siz = _sizMarker(width: 0, height: 16, components: 1);
      expect(
        () => decodeJpeg2000(siz),
        throwsA(isA<Jpeg2000CorruptedException>()),
      );
    });

    test('contradictory options are an ArgumentError, not a data error', () {
      expect(
        () => decodeJpeg2000(
          fixture('icon32.jp2'),
          options: const Jpeg2000DecodeOptions(rate: 1, bytes: 100),
        ),
        throwsArgumentError,
      );
      expect(
        () => decodeJpeg2000(
          fixture('icon32.jp2'),
          options: const Jpeg2000DecodeOptions(maxPixels: 0),
        ),
        throwsArgumentError,
      );
    });

    test('every fixture still decodes', () {
      for (final name in <String>[
        'barras_rgb.jp2',
        'file1.jp2',
        'grad_final.jp2',
        'icon32.jp2',
        'relax.jp2',
      ]) {
        final image = decodeJpeg2000(fixture(name));
        expect(
            image.pixels.length, image.width * image.height * image.components,
            reason: name);
      }
    });
  });
}

Uint8List _pnm(String magic, int width, int height, List<int> samples) {
  final header = '$magic\n$width $height\n255\n'.codeUnits;
  return Uint8List.fromList(<int>[...header, ...samples]);
}

/// SOC + SIZ only: enough for the probe and for budget checks, nothing else.
Uint8List _sizMarker({
  required int width,
  required int height,
  required int components,
}) {
  final builder = BytesBuilder();
  void u16(int v) => builder
    ..addByte((v >> 8) & 0xff)
    ..addByte(v & 0xff);
  void u32(int v) => builder
    ..addByte((v >> 24) & 0xff)
    ..addByte((v >> 16) & 0xff)
    ..addByte((v >> 8) & 0xff)
    ..addByte(v & 0xff);

  u16(0xff4f); // SOC
  u16(0xff51); // SIZ
  u16(38 + 3 * components); // Lsiz
  u16(0); // Rsiz
  u32(width); // Xsiz
  u32(height); // Ysiz
  u32(0); // XOsiz
  u32(0); // YOsiz
  u32(width == 0 ? 1 : width); // XTsiz
  u32(height == 0 ? 1 : height); // YTsiz
  u32(0); // XTOsiz
  u32(0); // YTOsiz
  u16(components); // Csiz
  for (var c = 0; c < components; c++) {
    builder
      ..addByte(7) // Ssiz: 8 bits, unsigned
      ..addByte(1) // XRsiz
      ..addByte(1); // YRsiz
  }
  return builder.toBytes();
}

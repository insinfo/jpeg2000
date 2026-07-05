import 'dart:convert';
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';
import 'package:test/test.dart';

void main() {
  group('public byte API', () {
    test('encodes and decodes PGM bytes losslessly', () async {
      final samples = List<int>.generate(16, (i) => i * 13);
      final pgm = _pnm('P5', 4, 4, samples);

      final codestream = encodeJpeg2000(pgm);
      expect(codestream.take(2), <int>[0xff, 0x4f]);

      final decoded = decodeJpeg2000(codestream);
      expect(decoded.width, 4);
      expect(decoded.height, 4);
      expect(decoded.components, 1);
      expect(decoded.format, Jpeg2000PixelFormat.gray8);
      expect(decoded.pixels, samples);

      final decodedAsync = await decodeJpeg2000Source(codestream);
      expect(decodedAsync.pixels, samples);
    });

    test('encodes and decodes PPM bytes losslessly', () {
      final samples = <int>[
        for (var i = 0; i < 16; i++) ...<int>[
          (i * 17) & 0xff,
          (255 - i * 11) & 0xff,
          (32 + i * 7) & 0xff,
        ],
      ];
      final ppm = _pnm('P6', 4, 4, samples);

      final codestream = encodeJpeg2000(ppm);
      final decoded = decodeJpeg2000(codestream);

      expect(decoded.width, 4);
      expect(decoded.height, 4);
      expect(decoded.components, 3);
      expect(decoded.format, Jpeg2000PixelFormat.rgb8);
      expect(decoded.pixels, samples);
    });

    test('can wrap encoded bytes in JP2 and decode them back', () {
      final samples = List<int>.generate(16, (i) => 255 - i * 9);
      final pgm = _pnm('P5', 4, 4, samples);

      final jp2 = encodeJpeg2000(
        pgm,
        options: const Jpeg2000EncodeOptions(wrapInJp2: true),
      );
      expect(jp2.take(12), <int>[
        0x00,
        0x00,
        0x00,
        0x0c,
        0x6a,
        0x50,
        0x20,
        0x20,
        0x0d,
        0x0a,
        0x87,
        0x0a,
      ]);

      final decoded = decodeJpeg2000(jp2);
      expect(decoded.pixels, samples);
    });
  });
}

Uint8List _pnm(String magic, int width, int height, List<int> samples) {
  final header = ascii.encode('$magic\n$width $height\n255\n');
  return Uint8List.fromList(<int>[...header, ...samples]);
}

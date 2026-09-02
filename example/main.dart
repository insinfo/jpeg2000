import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';

/// Decodes a JP2/J2K file given on the command line, then round-trips a
/// small synthetic image through the encoder.
///
/// ```
/// dart run example/main.dart path/to/image.jp2
/// ```
void main(List<String> args) {
  if (args.isNotEmpty) {
    decodeFile(args.first);
  }
  encodeRoundTrip();
}

void decodeFile(String path) {
  final Uint8List bytes = File(path).readAsBytesSync();

  // Look before you leap: the probe reads only the headers.
  final info = probeJpeg2000(bytes);
  print('$path: ${info.width}x${info.height}, '
      '${info.components} component(s), ${info.bitsPerComponent} bits, '
      'alpha=${info.hasAlpha}, jp2=${info.isJp2}');

  try {
    final image = decodeJpeg2000(
      bytes,
      options: Jpeg2000DecodeOptions(
        maxPixels: 64 * 1024 * 1024,
        onWarning: (message) => stderr.writeln('warning: $message'),
      ),
    );
    print('decoded ${image.format}: ${image.components} channel(s) per '
        'pixel, ${image.pixels.length} bytes, row stride ${image.rowStride}');
  } on Jpeg2000BudgetException catch (e) {
    print('refused: ${e.message}');
  } on Jpeg2000TruncatedException {
    print('the file is incomplete');
  } on Jpeg2000Exception catch (e) {
    print('cannot decode: $e');
  }
}

void encodeRoundTrip() {
  // A 16x16 greyscale ramp as a binary PGM (P5).
  const width = 16;
  const height = 16;
  final header = 'P5\n$width $height\n255\n'.codeUnits;
  final samples = List<int>.generate(width * height, (i) => i & 0xff);
  final pgm = Uint8List.fromList(<int>[...header, ...samples]);

  final j2k = encodeJpeg2000(pgm); // lossless raw codestream
  final jp2 = encodeJpeg2000(
    pgm,
    options: const Jpeg2000EncodeOptions(wrapInJp2: true),
  );
  final decoded = decodeJpeg2000(j2k);

  final lossless =
      List<int>.from(decoded.pixels).toString() == samples.toString();
  print('encoded $width x $height gray: ${j2k.length} bytes as J2K, '
      '${jp2.length} bytes as JP2, lossless round trip: $lossless');
}

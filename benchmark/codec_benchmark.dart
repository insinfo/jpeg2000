import 'dart:convert';
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';

void main() {
  const size = 32;
  const iterations = 8;
  final gray = _pnm(
    'P5',
    size,
    size,
    List<int>.generate(size * size, (i) => (i * 17 + i ~/ size * 11) & 0xff),
  );
  final rgb = _pnm(
    'P6',
    size,
    size,
    <int>[
      for (var i = 0; i < size * size; i++) ...<int>[
        (i * 13) & 0xff,
        (255 - i * 7) & 0xff,
        (32 + i * 5) & 0xff,
      ],
    ],
  );

  final grayCodestream = _time(
    'encode gray PGM -> J2K',
    iterations,
    () => encodeJpeg2000(gray),
  );
  _time(
    'decode gray J2K',
    iterations,
    () => decodeJpeg2000(grayCodestream),
  );

  final rgbCodestream = _time(
    'encode RGB PPM -> J2K',
    iterations,
    () => encodeJpeg2000(rgb),
  );
  _time(
    'decode RGB J2K',
    iterations,
    () => decodeJpeg2000(rgbCodestream),
  );

  print('gray bytes=${grayCodestream.length}');
  print('rgb bytes=${rgbCodestream.length}');
}

T _time<T>(String label, int iterations, T Function() run) {
  T? result;
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    result = run();
  }
  stopwatch.stop();
  final totalMicros = stopwatch.elapsedMicroseconds;
  final averageMicros = totalMicros / iterations;
  print('$label: ${averageMicros.toStringAsFixed(1)} us/op');
  return result as T;
}

Uint8List _pnm(String magic, int width, int height, List<int> samples) {
  final header = ascii.encode('$magic\n$width $height\n255\n');
  return Uint8List.fromList(<int>[...header, ...samples]);
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:j2k/j2k.dart';

Future<void> main(List<String> args) async {
  final options = _BenchmarkOptions.parse(args);
  final size = options.size;
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

  print(
    'benchmark size=${options.size} iterations=${options.iterations} '
    'warmup=${options.warmup}',
  );
  final parallelEngages =
      size * size >= Jpeg2000ParallelOptions.defaultMinParallelPixels;
  print(
    'parallel decode ${parallelEngages ? "engages" : "stays sequential"} at '
    '${size * size} samples '
    '(threshold ${Jpeg2000ParallelOptions.defaultMinParallelPixels})',
  );

  final grayCodestream = _time(
    'encode gray PGM -> J2K',
    options,
    () => encodeJpeg2000(gray),
  );
  _time(
    'decode gray J2K',
    options,
    () => decodeJpeg2000(grayCodestream),
  );
  await _timeAsync(
    'decode gray J2K (parallel)',
    options,
    () => decodeJpeg2000Parallel(grayCodestream, parallel: _parallel),
  );

  final rgbCodestream = _time(
    'encode RGB PPM -> J2K',
    options,
    () => encodeJpeg2000(rgb),
  );
  _time(
    'decode RGB J2K',
    options,
    () => decodeJpeg2000(rgbCodestream),
  );
  await _timeAsync(
    'decode RGB J2K (parallel)',
    options,
    () => decodeJpeg2000Parallel(rgbCodestream, parallel: _parallel),
  );

  print('gray bytes=${grayCodestream.length}');
  print('rgb bytes=${rgbCodestream.length}');
}

/// The production defaults, on purpose.
///
/// Forcing the workers on would flatter the small sizes into looking slower
/// than the codec ever is: below
/// [Jpeg2000ParallelOptions.defaultMinParallelPixels] samples a real decode
/// stays sequential, and then the two decode lines below should read the same.
/// Above it, the difference between them is the gain a caller actually gets.
///
/// Worker isolates need more warm-up than the sequential path, so compare the
/// two only with several warm-up rounds: try --warmup=5 --iterations=20.
const _parallel = Jpeg2000ParallelOptions();

Future<T> _timeAsync<T>(
  String label,
  _BenchmarkOptions options,
  Future<T> Function() run,
) async {
  T? result;
  for (var i = 0; i < options.warmup; i++) {
    result = await run();
  }

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < options.iterations; i++) {
    result = await run();
  }
  stopwatch.stop();
  final averageMicros = stopwatch.elapsedMicroseconds / options.iterations;
  print('$label: ${averageMicros.toStringAsFixed(1)} us/op');
  return result as T;
}

T _time<T>(String label, _BenchmarkOptions options, T Function() run) {
  T? result;
  for (var i = 0; i < options.warmup; i++) {
    result = run();
  }

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < options.iterations; i++) {
    result = run();
  }
  stopwatch.stop();
  final totalMicros = stopwatch.elapsedMicroseconds;
  final averageMicros = totalMicros / options.iterations;
  print('$label: ${averageMicros.toStringAsFixed(1)} us/op');
  return result as T;
}

Uint8List _pnm(String magic, int width, int height, List<int> samples) {
  final header = ascii.encode('$magic\n$width $height\n255\n');
  return Uint8List.fromList(<int>[...header, ...samples]);
}

class _BenchmarkOptions {
  const _BenchmarkOptions({
    required this.size,
    required this.iterations,
    required this.warmup,
  });

  static _BenchmarkOptions parse(List<String> args) {
    var size = const int.fromEnvironment(
      'jpeg2000.benchmark.size',
      defaultValue: 32,
    );
    var iterations = const int.fromEnvironment(
      'jpeg2000.benchmark.iterations',
      defaultValue: 8,
    );
    var warmup = const int.fromEnvironment(
      'jpeg2000.benchmark.warmup',
      defaultValue: 2,
    );

    for (final arg in args) {
      if (arg.startsWith('--size=')) {
        size = _positiveInt(arg, '--size=');
      } else if (arg.startsWith('--iterations=')) {
        iterations = _positiveInt(arg, '--iterations=');
      } else if (arg.startsWith('--warmup=')) {
        warmup = _nonNegativeInt(arg, '--warmup=');
      }
    }

    return _BenchmarkOptions(
      size: size,
      iterations: iterations,
      warmup: warmup,
    );
  }

  final int size;
  final int iterations;
  final int warmup;
}

int _positiveInt(String arg, String prefix) {
  final value = _nonNegativeInt(arg, prefix);
  if (value <= 0) {
    throw ArgumentError.value(value, prefix, 'must be positive');
  }
  return value;
}

int _nonNegativeInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    throw ArgumentError.value(arg, prefix, 'must be a non-negative integer');
  }
  return value;
}

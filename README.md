# jpeg2000

[![Dart CI](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml)

Pure Dart JPEG 2000 codec based on the JJ2000/JAI ImageIO implementation. The
package decodes JP2/J2K codestreams, provides a basic encoder for binary PGM and
PPM inputs, and ships bit-exact regression fixtures inside the repository.

## Status

- JP2/J2K decoder with codestream parsing, entropy decoding, ROI de-scaling,
  dequantization, inverse wavelet transform, inverse RCT/ICT, and JP2 color
  mapping.
- Encoder for binary PGM P5 and PPM P6 input, raw J2K output, and optional JP2
  wrapping.
- Public byte-oriented API in `package:jpeg2000/jpeg2000.dart`; it does not
  expose paths or `dart:io` types.
- Async source loading through conditional platform exports. Browser builds use
  `package:web` for `Blob`/`File` input.
- Fixtures are consolidated under `test/fixtures`; tests do not depend on local
  reference checkouts.
- CI runs formatting, analysis, VM tests, a Chrome test for the public browser
  API, a VM benchmark smoke run, and production JavaScript compilation.

## Installation

The package is not published on pub.dev yet. Use the Git repository:

```yaml
dependencies:
  jpeg2000:
    git:
      url: https://github.com/insinfo/jpeg2000.git
```

Then install dependencies:

```bash
dart pub get
```

## Public API

Import the stable facade:

```dart
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';

void main() {
  final Uint8List jp2OrJ2kBytes = loadSomehow();
  final image = decodeJpeg2000(jp2OrJ2kBytes);

  print('${image.width}x${image.height}');
  print(image.components);
  print(image.pixels); // 8-bit interleaved gray or RGB samples.
}
```

Encode binary PGM or PPM bytes without using file paths:

```dart
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';

void main() {
  final Uint8List ppmBytes = makeOrLoadBinaryPpm();

  final j2k = encodeJpeg2000(
    ppmBytes,
    options: const Jpeg2000EncodeOptions(lossless: true),
  );

  final jp2 = encodeJpeg2000(
    ppmBytes,
    options: const Jpeg2000EncodeOptions(
      lossless: true,
      wrapInJp2: true,
    ),
  );

  print('${j2k.length} raw codestream bytes');
  print('${jp2.length} JP2 bytes');
}
```

Use the async source helpers when the input may be a VM file/path or a browser
`package:web` `Blob`/`File`:

```dart
import 'package:jpeg2000/jpeg2000.dart';
import 'package:web/web.dart' as web;

Future<void> decodeBrowserFile(web.File file) async {
  final image = await decodeJpeg2000Source(file);
  print(image.pixels.length);
}
```

`decodeJpeg2000Source` and `encodeJpeg2000Source` accept bytes on every
platform. On the VM they also accept `dart:io` `File` and filesystem paths. In
the browser they accept `package:web` `Blob` and `File`.

## Command Line

Decode JP2/J2K to PPM, PGM, PGX, or BMP:

```bash
dart run jpeg2000:decode -i input.jp2 -o output.ppm
dart run jpeg2000:decode -i input.j2k -o output.bmp
```

Encode PPM/PGM to a lossless J2K codestream:

```bash
dart run jpeg2000:encode -i input.ppm -o output.j2k -lossless on
dart run jpeg2000:encode -i input.pgm -o output.j2k -lossless on
```

Encode with a JP2 wrapper:

```bash
dart run jpeg2000:encode -i input.ppm -o output.jp2 -lossless on -file_format on
```

Encode with a target bitrate:

```bash
dart run jpeg2000:encode -i input.ppm -o output.j2k -rate 1.0
```

## Development

Run the same checks as CI:

```bash
dart format --output=none --set-exit-if-changed lib test bin benchmark
dart analyze
dart test
dart test -p chrome test/jpeg2000_public_api_test.dart
dart run benchmark/codec_benchmark.dart
dart compile js -O2 -o build/codec_benchmark.js benchmark/codec_benchmark.dart
```

The JavaScript compile smoke uses `-O2`, Dart's safe production-oriented
optimization level. `-O4` is intentionally avoided in CI because it enables
aggressive unsafe optimizations and is better reserved for separate optimizer
experiments.

Fixtures live in:

- `test/fixtures/test_images`: synthetic JP2/J2K files and decoded references.
- `test/fixtures/j2k_tests`: conformance subset and bit-exact references.
- `test/fixtures/*.json`: small MQ/entropy/parity fixtures.

## Performance Roadmap

- Reduce allocations in code-blocks, wavelet buffers, color conversion, and
  writers by reusing `TypedData` across blocks.
- Profile and optimize MQ coder/decoder and entropy coder/decoder hot loops on
  the Dart VM and generated JavaScript.
- Expand automated benchmarks with larger fixture sets and a browser timing
  harness for Chrome.
- Evaluate tile/component parallelism with isolates on the VM and Web Workers
  in browsers.
- Implement true incremental reads for large inputs with configurable cache
  policies per platform.
- Expand the encoder to PGX, multiple independent input components, tile-parts,
  and packed packet headers.

## Notes

The source still contains many JJ2000-style internal names while the port is
being stabilized. The public API uses Dart-style names; internal cleanup is
tracked by the analyzer lints and can be done incrementally without changing
the byte-oriented facade.

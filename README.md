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
  API, a VM benchmark smoke run, production JavaScript compilation, and
  WebAssembly compilation/execution.

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
dart compile wasm -o build/codec_benchmark.wasm benchmark/codec_benchmark.dart
node benchmark/run_wasm_benchmark.mjs build/codec_benchmark.mjs build/codec_benchmark.wasm
```

The JavaScript compile smoke uses `-O2`, Dart's safe production-oriented
optimization level. `-O4` is intentionally avoided in CI because it enables
aggressive unsafe optimizations and is better reserved for separate optimizer
experiments.

Fixtures live in:

- `test/fixtures/test_images`: synthetic JP2/J2K files and decoded references.
- `test/fixtures/j2k_tests`: conformance subset and bit-exact references.
- `test/fixtures/*.json`: small MQ/entropy/parity fixtures.

## Performance Snapshot

These local measurements were taken on 2026-07-05 on Windows x64, Intel Core
i3-1215U (6 cores, 8 logical processors), Dart 3.6.2, Node 24.14.1, Go 1.26.4,
OpenJPEG 2.5.4 built from `referencias/openjpeg` with CMake 4.3.3, Ninja
1.13.2, and GCC 16.1.0 from `C:\w64devkit`.

The Dart and Go rows are in-process API benchmarks. The OpenJPEG row uses the
`opj_compress`/`opj_decompress` command line tools, so process startup and file
I/O are included and dominate this tiny 64x64 fixture. Lower is better.

| Codec/runtime | Execution model | Gray encode PGM->J2K | Gray decode J2K | RGB/RGBA encode | RGB/RGBA decode | Notes |
|---|---|---:|---:|---:|---:|---|
| Dart VM JIT | in-process | 2772.2 us/op | 4733.0 us/op | 3850.8 us/op | 9863.6 us/op | `dart run`, 64x64 PGM/PPM, 80 iterations |
| Dart AOT exe | in-process | 2525.4 us/op | 5137.8 us/op | 6168.0 us/op | 12435.5 us/op | `dart compile exe` |
| Dart JavaScript `-O2` | Node 24 | 7900.0 us/op | 3762.5 us/op | 17075.0 us/op | 8400.0 us/op | `dart compile js -O2` |
| Dart WasmGC | Node 24 | 5046.7 us/op | 6768.2 us/op | 10024.4 us/op | 12250.3 us/op | `dart compile wasm` |
| Go reference | in-process | 395.9 us/op | 1126.0 us/op | 819.7 us/op | 3271.2 us/op | `referencias/go-jpeg2000`; color case is RGBA |
| OpenJPEG C | CLI end-to-end | 11773.4 us/op | 12484.6 us/op | 12991.8 us/op | 15697.9 us/op | Native tools; includes startup and filesystem I/O |

Reproduce the Dart rows with:

```bash
dart run benchmark/codec_benchmark.dart --size=64 --iterations=80 --warmup=8
dart compile exe benchmark/codec_benchmark.dart -o build/codec_benchmark.exe
build/codec_benchmark.exe --size=64 --iterations=80 --warmup=8
dart compile js -O2 --define=jpeg2000.benchmark.size=64 --define=jpeg2000.benchmark.iterations=80 --define=jpeg2000.benchmark.warmup=8 -o build/codec_benchmark.js benchmark/codec_benchmark.dart
node build/codec_benchmark.js
dart compile wasm --define=jpeg2000.benchmark.size=64 --define=jpeg2000.benchmark.iterations=80 --define=jpeg2000.benchmark.warmup=8 -o build/codec_benchmark.wasm benchmark/codec_benchmark.dart
node benchmark/run_wasm_benchmark.mjs build/codec_benchmark.mjs build/codec_benchmark.wasm
```

JDeli and JAI ImageIO remain correctness references for the bit-exact fixtures.
They are not included in this table because the checked local JDeli CLI does not
accept PGM/PPM input directly, and the JAI ImageIO source tree does not provide a
checked-in performance harness comparable to the byte API benchmark.

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

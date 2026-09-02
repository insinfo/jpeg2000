# jpeg2000

[![Dart CI](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml)

Pure Dart JPEG 2000 codec. It decodes JP2 files and raw J2K codestreams to
8-bit pixels, encodes binary PGM/PPM input, and runs unchanged on the Dart VM,
dart2js and dart2wasm: the public API is byte-oriented and never imports
`dart:io`.

The decoder is a port of the JJ2000 reference implementation and is bit-exact
against it on the bundled conformance subset. See
[Origin and licenses](#origin-and-licenses).

## Features

- **Decoder:** codestream parsing, EBCOT/MQ entropy decoding, ROI de-scaling,
  dequantization, reversible 5x3 and irreversible 9x7 inverse wavelets, inverse
  RCT/ICT, and JP2 colour handling: enumerated sRGB/greyscale/sYCC, restricted
  ICC profiles, palettes, and channel definitions (alpha).
- **Output:** gray, gray+alpha, RGB, RGBA or raw multi-component samples,
  always 8 bits per channel, tightly packed and interleaved.
- **Header probe:** width, height, components, bit depths, tiling and alpha
  without decoding a pixel, so callers can apply size policies first.
- **Budgets:** `maxPixels` and `maxDimension` reject oversized images from the
  SIZ marker before any allocation.
- **Typed errors:** a sealed `Jpeg2000Exception` hierarchy separates "not a
  JPEG 2000 file", "truncated", "corrupted", "unsupported feature" and "over
  budget".
- **Encoder:** binary PGM (P5) and PPM (P6) bytes to raw J2K or JP2, lossless
  or rate-controlled, with optional tiling.
- **Command line:** `jp2dec` and `jp2enc`.

## Installation

```bash
dart pub add jpeg2000
```

## Decoding

```dart
import 'dart:typed_data';

import 'package:jpeg2000/jpeg2000.dart';

Jpeg2000Image decode(Uint8List jp2OrJ2kBytes) {
  final image = decodeJpeg2000(
    jp2OrJ2kBytes,
    options: Jpeg2000DecodeOptions(
      maxPixels: 64 * 1024 * 1024,
      onWarning: (message) => print('jpeg2000: $message'),
    ),
  );

  print('${image.width}x${image.height} ${image.format}');
  // image.pixels: Uint8List, row-major, `image.components` bytes per pixel.
  // Pixel (x, y) starts at (y * image.width + x) * image.components.
  // With image.hasAlpha the last channel is alpha; check
  // image.alphaIsPremultiplied before compositing.
  return image;
}
```

`Jpeg2000Image` fields:

| Field | Meaning |
|---|---|
| `format` | `gray8`, `grayAlpha8`, `rgb8`, `rgba8` or `multiComponent8` |
| `components` | channels per pixel in `pixels`, alpha included |
| `colorComponents` | leading colour channels (1 or 3; all channels for `multiComponent8`) |
| `hasAlpha`, `alphaIsPremultiplied` | from the JP2 `cdef` box, or the 2/4-channel convention when there is none |
| `sourceBitsPerComponent` | bit depth of each channel in the file; samples are scaled to 8 bits |

Decode options:

| Option | Default | Effect |
|---|---|---|
| `applyColorSpace` | `true` | apply JP2 colour metadata (ICC, palette, channel definitions) |
| `applyComponentTransform` | `true` | apply the inverse RCT/ICT signalled in the codestream |
| `rate` / `bytes` | none | stop after this many bits per pixel or bytes (progressive preview) |
| `resolution` | none | discard this many highest resolution levels |
| `maxPixels` / `maxDimension` | none | throw `Jpeg2000BudgetException` before allocating |
| `onWarning` | none | receive non-fatal diagnostics; nothing is ever printed |

## Probing without decoding

```dart
final info = probeJpeg2000(bytes);
if (info.pixelCount > budget) {
  throw StateError('too large: ${info.width}x${info.height}');
}
print('${info.components} components, ${info.bitsPerComponent} bits, '
    'alpha=${info.hasAlpha}, tiles=${info.tileColumns}x${info.tileRows}');
```

## Errors

All input problems are subtypes of the sealed `Jpeg2000Exception`; API misuse
is an `ArgumentError`.

```dart
try {
  decodeJpeg2000(bytes);
} on Jpeg2000FormatException {
  // Neither a JP2 container nor a J2K codestream.
} on Jpeg2000TruncatedException {
  // The data ends early; a retry with the complete file may work.
} on Jpeg2000CorruptedException {
  // The file violates the standard.
} on Jpeg2000UnsupportedException {
  // Valid, but uses a feature this codec does not implement yet.
} on Jpeg2000BudgetException catch (e) {
  // Larger than options.maxPixels / maxDimension: e.budget, e.limit, e.actual.
}
```

## Encoding

```dart
final j2k = encodeJpeg2000(ppmBytes); // lossless raw codestream

final jp2 = encodeJpeg2000(
  ppmBytes,
  options: const Jpeg2000EncodeOptions(
    lossless: false,
    rate: 1.0, // bits per pixel
    wrapInJp2: true,
    tileWidth: 256,
    tileHeight: 256,
  ),
);
```

The encoder takes binary PGM (P5) or PPM (P6) bytes, 8 bits per sample. A
pixel-buffer entry point is planned.

## Files, paths and browser blobs

`decodeJpeg2000Source` and `encodeJpeg2000Source` accept bytes everywhere. On
the VM they also accept a `dart:io` `File` or a path; in browsers they accept a
`package:web` `Blob` or `File`.

```dart
import 'package:jpeg2000/jpeg2000.dart';
import 'package:web/web.dart' as web;

Future<void> decodeBrowserFile(web.File file) async {
  final image = await decodeJpeg2000Source(file);
  print(image.pixels.length);
}
```

## Command line

```bash
dart run jpeg2000:decode -i input.jp2 -o output.ppm   # also .pgm, .pgx, .bmp
dart run jpeg2000:encode -i input.ppm -o output.j2k -lossless on
dart run jpeg2000:encode -i input.ppm -o output.jp2 -lossless on -file_format on
dart run jpeg2000:encode -i input.ppm -o output.j2k -rate 1.0
```

After `dart pub global activate jpeg2000` the tools are available as
`jp2dec` and `jp2enc`.

## Limitations

- Output is 8 bits per channel; 12- and 16-bit sources are scaled down (the
  original depth is reported in `sourceBitsPerComponent`).
- Raw codestreams with subsampled components and no JP2 colour metadata throw
  `Jpeg2000UnsupportedException`; JP2 files resample through the colour
  pipeline.
- Custom (non 5x3 / 9x7) wavelet kernels, progression orders outside the five
  standard ones, and Part 2 (JPX) extensions are not supported.
- The encoder reads PNM only, 8 bits, unsigned.
- Decoding is single-threaded and, for now, several times slower than native
  codecs; see [doc/BENCHMARKS.md](https://github.com/insinfo/jpeg2000/blob/main/doc/BENCHMARKS.md).
  Decode large images off the UI thread.

## Development

Run the same checks as CI:

```bash
dart format --output=none --set-exit-if-changed lib test bin benchmark example
dart analyze
dart test -j 1
dart test -p chrome test/jpeg2000_public_api_test.dart
dart run benchmark/codec_benchmark.dart
dart compile js -O2 -o build/codec_benchmark.js benchmark/codec_benchmark.dart
dart compile wasm -o build/codec_benchmark.wasm benchmark/codec_benchmark.dart
node benchmark/run_wasm_benchmark.mjs build/codec_benchmark.mjs build/codec_benchmark.wasm
```

`test/architecture/public_facade_imports_test.dart` walks the import graph
from `lib/jpeg2000.dart` the way pub.dev does and fails if `dart:io` becomes
reachable, which would cost the package its Web and Wasm support.

Fixtures live in `test/fixtures` (synthetic JP2/J2K files with decoded
references, a conformance subset with bit-exact references, and small MQ and
entropy fixtures). They are not published with the package.

## Origin and licenses

The Dart code is released under the MIT license (see `LICENSE`).

It is a port of **JJ2000**, the Java reference implementation of JPEG 2000
Part 1 written by EPFL, Ericsson and Canon Research Centre France. The JJ2000
license requires its copyright notice to accompany every copy or derivative
work; it is reproduced in `LICENSE-JJ2000.txt` and applies to the ported
algorithms alongside the MIT terms.

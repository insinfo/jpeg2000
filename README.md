# j2k

[![pub package](https://img.shields.io/pub/v/j2k.svg)](https://pub.dev/packages/j2k)
[![pub points](https://img.shields.io/pub/points/j2k)](https://pub.dev/packages/j2k/score)
[![Dart CI](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml)
[![AI Assisted](https://img.shields.io/badge/AI-Assisted-purple.svg)](https://github.com/insinfo/jpeg2000#how-this-package-was-built)

Pure Dart JPEG 2000 codec, published as `package:j2k`. It decodes JP2 files
and raw J2K codestreams to 8- or 16-bit pixels, encodes pixel buffers and
PGM/PPM, and runs unchanged on the Dart VM, dart2js and dart2wasm: the public
API is byte-oriented and never imports `dart:io`.

The decoder is a port of the JJ2000 reference implementation and is bit-exact
against it on the bundled conformance subset. See
[Origin and licenses](#origin-and-licenses).

## Features

- **Decoder:** codestream parsing, EBCOT/MQ entropy decoding, ROI de-scaling,
  dequantization, reversible 5x3 and irreversible 9x7 inverse wavelets,
  arbitrary lifting kernels signalled by the ATK marker, inverse RCT/ICT, and
  JP2 colour handling: enumerated sRGB/greyscale/sYCC, restricted ICC
  profiles, palettes, and channel definitions (alpha).
- **Subsampled components:** 4:2:0 and 4:2:2 chroma is resampled, in JP2 files
  and in raw codestreams alike, for factors from 1 to 255.
- **Output:** gray, gray+alpha, RGB, RGBA or raw multi-component samples,
  tightly packed and interleaved, 8 bits per sample by default or 16 on
  request.
- **Header probe:** width, height, components, bit depths, tiling and alpha
  without decoding a pixel, so callers can apply size policies first.
- **Budgets:** `maxPixels` and `maxDimension` reject oversized images from the
  SIZ marker before any allocation.
- **Typed errors:** a sealed `Jpeg2000Exception` hierarchy separates "not a
  JPEG 2000 file", "truncated", "corrupted", "unsupported feature" and "over
  budget".
- **Parallel decode:** `decodeJpeg2000Parallel` spreads the work over worker
  isolates on the VM, 2.6x to 3.8x faster above 0.2 megapixel, with the
  sequential path as the default and as the web fallback.
- **Encoder:** interleaved pixel buffers (1 to 16 bits per sample, with or
  without alpha) or binary PGM/PPM bytes to raw J2K or JP2, lossless or
  rate-controlled, with optional tiling.
- **Command line:** `jp2dec` and `jp2enc`.

## Installation

```bash
dart pub add j2k
```

## Decoding

```dart
import 'dart:typed_data';

import 'package:j2k/j2k.dart';

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
| `format` | `gray`, `grayAlpha`, `rgb`, `rgba` or `multiComponent` |
| `components` | channels per pixel, alpha included |
| `colorComponents` | leading colour channels (1 or 3; all channels for `multiComponent`) |
| `hasAlpha`, `alphaIsPremultiplied` | from the JP2 `cdef` box, or the 2/4-channel convention when there is none |
| `bitsPerSample` | 8 or 16, as requested by `outputBitDepth` |
| `pixels` | the sample bytes; with 16-bit samples use the `pixels16` view |
| `sourceBitsPerComponent` | bit depth of each channel in the file, before rescaling |

Decode options:

| Option | Default | Effect |
|---|---|---|
| `applyColorSpace` | `true` | apply JP2 colour metadata (ICC, palette, channel definitions) |
| `applyComponentTransform` | `true` | apply the inverse RCT/ICT signalled in the codestream |
| `outputBitDepth` | `8` | `8` or `16`; deeper sources are shifted down, shallower ones rescaled to the full range |
| `rate` / `bytes` | none | stop after this many bits per pixel or bytes (progressive preview) |
| `resolution` | none | resolution level to reconstruct: `0` is the coarsest, `NL` the full image |
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

## Decoding in parallel

On the Dart VM, `decodeJpeg2000Parallel` splits the decode across worker
isolates: by tile, or by code block when there are fewer tiles than workers.
Its output is bit-identical to `decodeJpeg2000` — the workers drive the same
entropy decoder, not a second implementation of it.

```dart
final image = await decodeJpeg2000Parallel(
  bytes,
  parallel: const Jpeg2000ParallelOptions(concurrency: 4),
);
```

Small images stay on the sequential path: below `minParallelPixels` (36864
samples by default) starting the workers costs more than it saves. In dart2js
and dart2wasm builds, where isolates are not available, the call falls back to
the sequential decode, so the same code compiles and runs everywhere.

## Encoding

From an interleaved pixel buffer (`Uint8List` up to 8 bits per sample,
`Uint16List` above that; with 2 or 4 components the last one is alpha unless
`hasAlpha: false`):

```dart
final jp2 = encodeJpeg2000Pixels(
  rgbaBytes,
  width: 640,
  height: 480,
  components: 4,
  options: const Jpeg2000EncodeOptions(wrapInJp2: true), // lossless
);

final j2k = encodeJpeg2000Pixels(
  gray16Samples, // Uint16List
  width: 512,
  height: 512,
  components: 1,
  bitsPerSample: 16,
  options: const Jpeg2000EncodeOptions(
    lossless: false,
    rate: 1.0, // bits per pixel
    tileWidth: 256,
    tileHeight: 256,
  ),
);
```

From binary PGM (P5) or PPM (P6) bytes, 8 or 16 bits per sample:

```dart
final j2k = encodeJpeg2000(ppmBytes);
```

The JP2 wrapper carries greyscale or sRGB colour metadata and, when there is
alpha, a channel definition box, so the file decodes back as `rgba` or
`grayAlpha`.

## Files, paths and browser blobs

`decodeJpeg2000Source` and `encodeJpeg2000Source` accept bytes everywhere. On
the VM they also accept a `dart:io` `File` or a path; in browsers they accept a
`package:web` `Blob` or `File`.

```dart
import 'package:j2k/j2k.dart';
import 'package:web/web.dart' as web;

Future<void> decodeBrowserFile(web.File file) async {
  final image = await decodeJpeg2000Source(file);
  print(image.pixels.length);
}
```

## Command line

```bash
dart run j2k:decode -i input.jp2 -o output.ppm   # also .pgm, .pgx, .bmp
dart run j2k:encode -i input.ppm -o output.j2k -lossless on
dart run j2k:encode -i input.ppm -o output.jp2 -lossless on -file_format on
dart run j2k:encode -i input.ppm -o output.j2k -rate 1.0
```

After `dart pub global activate j2k` the tools are available as
`jp2dec` and `jp2enc`.

## What is not implemented

This codec implements **Part 1** of the standard (ISO/IEC 15444-1, ITU-T
T.800), which is what JP2 files and the JPEG 2000 images embedded in PDF use.
Read this section before adopting the package: the gaps are real, not
hypothetical, and a file that needs one of them throws
`Jpeg2000UnsupportedException` rather than decoding badly.

### Part 2 / JPX is largely open work

Only one piece of Part 2 (ISO/IEC 15444-2) exists here: wavelet kernels
signalled through the ATK marker, synthesised by the generic lifting procedure
of Annex G. Everything else in Part 2 is missing, and closing it is a large
project rather than a set of small patches:

- **Arbitrary decomposition** (DFS and ADS markers): decomposition structures
  other than the dyadic Mallat tree of Part 1.
- **Multiple component transform** (MCT, MCC, MIC markers): the array-based
  and wavelet-based transforms across components, used for multispectral and
  hyperspectral imagery.
- **Extended precision**: coefficient types beyond the Part 1 range, including
  the 128-bit ATK coefficient type, which is rejected explicitly.
- **Variable DC level shift**: the per-component shift of Part 2, as opposed
  to the fixed one of Part 1.
- **Arbitrary ROI shapes**: Part 1 MAXSHIFT de-scaling is implemented; the
  arbitrary region shapes of Part 2 are not.
- The **arbitrary filter category of Annex H**, which uses a different
  synthesis procedure from the lifting one, is rejected with the clause cited
  in the message.

The JPX container boxes that carry this metadata are not parsed either. A JPX
file that stays within Part 1 coding will decode; one that uses the extensions
above will not.

### Also missing

- **HTJ2000** (Part 15, the high-throughput block coder) is not implemented.
- **JPIP** (Part 9, interactive streaming) is out of scope; the API takes
  complete byte buffers.
- **Motion JPEG 2000** (Part 3) is out of scope.
- The **encoder is Part 1 only**: unsigned samples through the public API, the
  two standard kernels, no ATK output.
- Output is 8 or 16 bits per sample; other source depths are rescaled, with
  the original depth reported in `sourceBitsPerComponent`.
- Progression orders outside the five standard ones are rejected.
- Decoding is several times slower than a native codec even in parallel; see
  [doc/BENCHMARKS.md](https://github.com/insinfo/jpeg2000/blob/main/doc/BENCHMARKS.md).
  Decode large images off the UI thread.

## Development

Run the same checks as CI:

```bash
dart format --output=none --set-exit-if-changed lib test bin benchmark example
dart analyze
dart test
dart test -p chrome test/jpeg2000_public_api_test.dart
dart doc --output build/apidoc
dart pub publish --dry-run
dart run benchmark/codec_benchmark.dart
```

`test/architecture/public_facade_imports_test.dart` walks the import graph
from `lib/j2k.dart` the way pub.dev does and fails if `dart:io` becomes
reachable, which would cost the package its Web and Wasm support.

Fixtures live in `test/fixtures` (synthetic JP2/J2K files with decoded
references, a conformance subset with bit-exact references, and small MQ and
entropy fixtures). They are not published with the package.

Where the port deliberately differs from the JJ2000 reference, the reason is
recorded in
[doc/DIVERGENCIAS_JJ2000.md](https://github.com/insinfo/jpeg2000/blob/main/doc/DIVERGENCIAS_JJ2000.md),
so that a divergence is not "fixed" back as if it were a regression.

## How this package was built

Parts of the code, the tests and the documentation in this repository were
written with the help of LLM tools. Everything goes through the test suite
(428 tests, including bit-exact comparison against JJ2000 and OpenJPEG
references) and through `dart analyze` with `package:lints/recommended`
before it lands, and CI runs the same checks on every push. Whoever depends
on this package has a right to know how it was produced; judge it by the
tests and by the code.

## Origin and licenses

The Dart code is released under the MIT license (see `LICENSE`).

It is a port of **JJ2000**, the Java reference implementation of JPEG 2000
Part 1 written by EPFL, Ericsson and Canon Research Centre France. The JJ2000
license requires its copyright notice to accompany every copy or derivative
work; it is reproduced in `LICENSE-JJ2000.txt`, ships inside the published
package, and applies to the ported algorithms alongside the MIT terms. The
same notice is also available at runtime as `JJ2KInfo.copyright`.

JJ2000's own terms carry two conditions worth reading before you adopt the
package: they grant no license for products that do not conform to the JPEG
2000 standard, and they warn that implementing the standard may infringe
existing patents. They are not a copyleft license and do not require you to
release your own source.

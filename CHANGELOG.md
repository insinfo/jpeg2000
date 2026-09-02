## 0.9.0

First release, published as `j2k` because the name `jpeg2000` was already
taken on pub.dev. The API is the same: `decodeJpeg2000`, `probeJpeg2000`,
`encodeJpeg2000Pixels`, `encodeJpeg2000`.

- JP2 and raw J2K decoder ported from JJ2000: codestream parsing, EBCOT/MQ
  entropy decoding, ROI de-scaling, dequantization, 5x3 and 9x7 inverse
  wavelets, inverse RCT/ICT, and JP2 colour handling (enumerated colour spaces,
  restricted ICC profiles, palettes, channel definitions). Bit-exact against
  the JJ2000 reference on the bundled conformance subset.
- `decodeJpeg2000` returns interleaved pixels as gray, gray+alpha, RGB, RGBA
  or raw multi-component data, 8 bits per sample by default or 16 with
  `outputBitDepth: 16`, with `hasAlpha`, `alphaIsPremultiplied` and the
  source bit depths.
- `probeJpeg2000` reads geometry, bit depths, tiling and alpha from the
  headers without decoding.
- `Jpeg2000DecodeOptions.maxPixels` and `maxDimension` reject oversized
  images before any allocation; `onWarning` receives non-fatal diagnostics.
- Sealed `Jpeg2000Exception` hierarchy: format, truncated, corrupted,
  unsupported and budget errors.
- `encodeJpeg2000Pixels` encodes interleaved pixel buffers, 1 to 16 bits per
  sample, with alpha recorded in the JP2 channel definition box;
  `encodeJpeg2000` takes binary PGM (P5) and PPM (P6) bytes, 8 or 16 bits.
  Both produce raw J2K or JP2, lossless or rate-controlled, with optional
  tiling.
- Byte-oriented API with no `dart:io` in the import graph; works on the Dart
  VM, dart2js and dart2wasm. `decodeJpeg2000Source` and
  `encodeJpeg2000Source` accept files and paths on the VM and `Blob`/`File`
  in browsers.
- Command-line tools `jp2dec` and `jp2enc`.

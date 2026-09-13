## 1.0.0

First stable release. The public surface — `decodeJpeg2000`,
`decodeJpeg2000Source`, `probeJpeg2000`, `encodeJpeg2000Pixels`,
`encodeJpeg2000`, `encodeJpeg2000Source`, the option classes and the sealed
`Jpeg2000Exception` hierarchy — is unchanged from 0.9.0 and is now covered by
semantic versioning. Everything below is additive or a fix.

### Upgrade from 0.9.0 is not optional on the web

0.9.0 **fails on every 8-bit non-RGB decode compiled with `dart2js`**: gray,
gray+alpha, RGBA and multi-component images all throw. `pixels16![index]`
inside the sample loop let dart2js hoist the receiver null check out of the
loop, so the null 16-bit buffer was dereferenced on paths that never touch it.
The Dart VM and dart2wasm were unaffected, which is why it survived release.
If you ship 0.9.0 to a browser, upgrade.

### Added

- `decodeJpeg2000Parallel` and `Jpeg2000ParallelOptions`: decode spread over
  worker isolates, behind `if (dart.library.io)`, with the sequential path as
  the default and as the web fallback. Splits by tile, or by code block when
  there are fewer tiles than workers — the single-tile image typical of PDF.
  The code-block path drives the real `StdEntropyDecoder`, so its output is
  bit-identical to the sequential decode by construction. Measured on eight
  cores: 2.6x to 3.8x above 0.2 megapixel; below `minParallelPixels`
  (36864 samples, measured not guessed) it stays sequential.
  `decodeJpeg2000` remains synchronous and untouched.
- Subsampled components in raw codestreams (4:2:0, 4:2:2) now decode instead
  of throwing. Resampling moved out of `Resampler`, which needed a
  `ColorSpace` a raw codestream does not have, into a colour-free
  `ComponentUpsampler`; `Resampler` became a thin adapter, so the package has
  one resampling implementation rather than two. Subsampling factors now span
  1 to 255, the full range of XRsiz/YRsiz in ISO/IEC 15444-1 A.5.1, instead of
  being capped at 2:1.
- ATK marker (ISO/IEC 15444-2): wavelet kernels signalled by ATK index are
  resolved and synthesised by the generic lifting procedure of Annex G.
  Installation of the filter is deferred to the end of each header because an
  ATK may follow the COD that uses it. Validation: the 5-3 and 9-7 kernels
  described through ATK reproduce the specialised filters bit for bit; the
  specialised filters were not replaced. Still rejected, with the clause in
  the message: the arbitrary category of Annex H and 128-bit coefficient
  types. The encoder remains Part 1.
- Encoder: per-component bit depth and signed samples; the multiple component
  transform is switched off automatically when the first three components
  differ in depth or subsampling, as G.2 requires.
- Float32x4 (SIMD) synthesis for the irreversible path: 9/7 inverse wavelet,
  inverse ICT and RGB pixel collection, bit-exact against the JJ2000 fixtures.
  A 2717x3701 RGB image went from 1236 to 417 ms on the VM JIT and 1436 to
  493 ms in AOT.

### Fixed

- **dart2js**: every 8-bit non-RGB decode threw. See above.
- `Jpeg2000DecodeOptions.resolution` threw `RangeError` for any level below
  full resolution. The inverse wavelet adapter answered tile, component and
  corner geometry at the subband-tree level (always the total number of
  decomposition levels) while image width and height answered at the target
  level; the two coincide only at full resolution. Sizes now follow the B.5
  formula at the target level, and synthesis allocates the reduced buffer
  instead of allocating the full one and using a corner. Full-resolution
  decodes are byte-identical to before. This is a deliberate divergence from
  the JJ2000 reference, which carries the same defect; it is documented in
  `doc/DIVERGENCIAS_JJ2000.md` so nobody "fixes" it back.
- `resolution` was documented backwards, as the number of levels to discard.
  It is the level to reconstruct: 0 is the coarsest (the LL band alone) and
  `NL` is the full image. A level above the maximum is clamped with a warning.
- `getCompImgWidth` returned `compW * subs`, which overruns the image edge
  when the width is not a multiple of the subsampling factor — a 4:2:0 JP2
  nine pixels wide decoded wrong. Inherited from JJ2000.
- The progression order in a POC marker was not validated, unlike COD and
  COC; an out-of-range Ppoc reached the `default` branch. It is now rejected
  with the value that was read, instead of being reported as an unsupported
  feature.

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

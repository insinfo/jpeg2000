/// Pure Dart JPEG 2000 codec.
///
/// This library is byte-oriented on purpose: it never exposes file paths or
/// `dart:io` types, so the same import works on the Dart VM, in dart2js and in
/// dart2wasm builds. Decode with [decodeJpeg2000], inspect a header without
/// decoding with [probeJpeg2000], and encode PGM/PPM bytes with
/// [encodeJpeg2000]. Every input problem surfaces as a [Jpeg2000Exception]
/// subtype.
library;

export 'src/api/jpeg2000_codec.dart';
export 'src/jpeg2000_exceptions.dart';

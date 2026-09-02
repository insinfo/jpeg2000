import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import '../image/input/img_reader.dart';
import '../image/input/img_reader_pgm.dart';

bool get isBrowserPlatform => false;

String? get browserUserAgent => null;

StringSink get stdoutSink => io.stdout;

StringSink get stderrSink => io.stderr;

void flushSink(StringSink sink) {
  if (sink case final io.IOSink ioSink) {
    ioSink.flush();
  }
}

Future<Uint8List> readBinarySource(Object source) async {
  if (source is Uint8List) {
    return source;
  }
  if (source is List<int>) {
    return Uint8List.fromList(source);
  }
  if (source is io.File) {
    return source.readAsBytes();
  }
  if (source is String) {
    return io.File(source).readAsBytes();
  }
  throw ArgumentError.value(
    source,
    'source',
    'Expected bytes, dart:io File, or filesystem path.',
  );
}

Future<String> readTextSource(Object source) async {
  if (source is String) {
    return io.File(source).readAsString();
  }
  if (source is io.File) {
    return source.readAsString();
  }
  if (source is List<int>) {
    return utf8.decode(source);
  }
  throw ArgumentError.value(
    source,
    'source',
    'Expected bytes, dart:io File, or filesystem path.',
  );
}

/// Opens the PGM file at [path] as the single-component mask of an
/// arbitrary-shape ROI (`-Rroi A <path>` on the encoder command line).
ImgReader openRoiMaskReader(String path) => ImgReaderPGM(path);

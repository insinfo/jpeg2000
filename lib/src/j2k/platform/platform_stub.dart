import 'dart:convert';
import 'dart:typed_data';

import '../image/input/img_reader.dart';

bool get isBrowserPlatform => false;

String? get browserUserAgent => null;

StringSink get stdoutSink => _UnsupportedSink('stdout');

StringSink get stderrSink => _UnsupportedSink('stderr');

void flushSink(StringSink sink) {}

Future<Uint8List> readBinarySource(Object source) async {
  if (source is Uint8List) {
    return source;
  }
  if (source is List<int>) {
    return Uint8List.fromList(source);
  }
  throw UnsupportedError('No binary source reader is available.');
}

Future<String> readTextSource(Object source) async {
  if (source is String) {
    return source;
  }
  if (source is List<int>) {
    return utf8.decode(source);
  }
  throw UnsupportedError('No text source reader is available.');
}

class _UnsupportedSink implements StringSink {
  _UnsupportedSink(this.name);

  final String name;

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}
}

/// Arbitrary-shape ROI masks come from PGM files, which need a filesystem.
ImgReader openRoiMaskReader(String path) {
  throw UnsupportedError(
    'Arbitrary-shape ROI masks are only supported on the Dart VM: '
    'cannot open "$path" here.',
  );
}

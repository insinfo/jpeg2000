import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get isBrowserPlatform => true;

String? get browserUserAgent => web.window.navigator.userAgent;

StringSink get stdoutSink => const _BrowserConsoleSink(false);

StringSink get stderrSink => const _BrowserConsoleSink(true);

void flushSink(StringSink sink) {}

Future<Uint8List> readBinarySource(Object source) async {
  if (source is Uint8List) {
    return source;
  }
  if (source is List<int>) {
    return Uint8List.fromList(source);
  }
  if (source is web.Blob) {
    return readBrowserBlob(source);
  }
  throw ArgumentError.value(
    source,
    'source',
    'Expected bytes or package:web Blob/File.',
  );
}

Future<String> readTextSource(Object source) async {
  if (source is String) {
    return source;
  }
  if (source is List<int>) {
    return utf8.decode(source);
  }
  if (source is web.Blob) {
    final text = await source.text().toDart;
    return text.toDart;
  }
  throw ArgumentError.value(
    source,
    'source',
    'Expected text, bytes, or package:web Blob/File.',
  );
}

Future<Uint8List> readBrowserBlob(web.Blob blob) async {
  final buffer = await blob.arrayBuffer().toDart;
  return Uint8List.view(buffer.toDart);
}

class _BrowserConsoleSink implements StringSink {
  const _BrowserConsoleSink(this.isError);

  final bool isError;

  @override
  void write(Object? object) {
    if (object != null && object.toString().isNotEmpty) {
      _emit(object.toString());
    }
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    write(objects.map((e) => e.toString()).join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    write(String.fromCharCode(charCode));
  }

  @override
  void writeln([Object? object = '']) {
    _emit(object?.toString() ?? '');
  }

  void _emit(String message) {
    if (isError) {
      web.console.error(message.toJS);
    } else {
      web.console.log(message.toJS);
    }
  }
}

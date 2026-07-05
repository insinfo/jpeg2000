import 'dart:convert';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/platform/platform.dart' as platform;
import 'package:test/test.dart';

void main() {
  group('platform abstraction', () {
    test('reads in-memory bytes on every platform', () async {
      final bytes = Uint8List.fromList(utf8.encode('alpha=beta'));

      expect(await platform.readBinarySource(bytes), bytes);
      expect(await platform.readTextSource(bytes), 'alpha=beta');
    });

    test('exposes browser metadata through package:web implementation', () {
      if (platform.isBrowserPlatform) {
        expect(platform.browserUserAgent, isNotNull);
        expect(platform.browserUserAgent, isNotEmpty);
      } else {
        expect(platform.browserUserAgent, isNull);
      }
    });
  });
}

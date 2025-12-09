import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/util/ArrayUtil.dart';
import 'package:test/test.dart';

void main() {
  group('ArrayUtil', () {
    test('intArraySet handles small lists', () {
      final values = <int>[1, 2, 3, 4, 5];
      ArrayUtil.intArraySet(values, 7);
      expect(values, everyElement(7));
    });

    test('intArraySet handles large lists', () {
      final values = Int32List.fromList(List<int>.generate(64, (index) => index));
      ArrayUtil.intArraySet(values, -3);
      expect(values, everyElement(-3));
    });

    test('byteArraySet handles small lists', () {
      final values = <int>[1, 2, 3, 4];
      ArrayUtil.byteArraySet(values, 0x7F);
      expect(values, equals(<int>[0x7F, 0x7F, 0x7F, 0x7F]));
    });

    test('byteArraySet handles large lists', () {
      final values = Uint8List(32);
      ArrayUtil.byteArraySet(values, 0xA5);
      expect(values, everyElement(0xA5));
    });

    test('array setters tolerate empty lists', () {
      final intValues = <int>[];
      final byteValues = Uint8List(0);
      ArrayUtil.intArraySet(intValues, 1);
      ArrayUtil.byteArraySet(byteValues, 2);
      expect(intValues, isEmpty);
      expect(byteValues, isEmpty);
    });
  });
}


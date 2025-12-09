import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/entropy/decoder/ByteInputBuffer.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/ByteToBitInput.dart';
import 'package:test/test.dart';

void main() {
  group('ByteToBitInput parity', () {
    test('readBit handles bit stuffing after FF', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([0xFF, 0xAA]));
      final input = ByteToBitInput(buffer);

      final prefix = List<int>.generate(8, (_) => input.readBit());
      expect(prefix, everyElement(equals(1)));

      final stuffed = List<int>.generate(7, (_) => input.readBit());
      expect(stuffed, [0, 1, 0, 1, 0, 1, 0]);
    });

    test('checkBytePadding flags non alternating tail', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([0xAA]));
      final input = ByteToBitInput(buffer);
      for (var i = 0; i < 4; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isTrue);
    });

    test('checkBytePadding accepts alternating tail', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([0x55]));
      final input = ByteToBitInput(buffer);
      for (var i = 0; i < 4; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isFalse);
    });

    test('checkBytePadding detects trailing bytes', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([0x55, 0x00]));
      final input = ByteToBitInput(buffer);
      for (var i = 0; i < 8; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isTrue);
    });
  });
}


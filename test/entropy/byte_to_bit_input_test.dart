import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/ByteToBitInput.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/ByteInputBuffer.dart';

void main() {
  group('ByteToBitInput', () {
    test('readBitHandlesBitStuffingAfterFF', () {
      final data = Uint8List.fromList([0xFF, 0xAA]);
      final input = ByteToBitInput(ByteInputBuffer(data));

      final prefix = <int>[];
      for (var i = 0; i < 8; i++) {
        prefix.add(input.readBit());
      }
      expect(prefix, equals([1, 1, 1, 1, 1, 1, 1, 1]));

      final stuffed = <int>[];
      for (var i = 0; i < 7; i++) {
        stuffed.add(input.readBit());
      }
      // Java test expects: 0,1,0,1,0,1,0
      // 0xAA is 10101010.
      // But bit stuffing means if we see 0xFF, the next byte must be < 0x90.
      // If it is 0xAA, it's a marker?
      // Wait, the Java test says:
      // assertArrayEquals(new int[] {0,1,0,1,0,1,0}, stuffed);
      // 0xAA is 10101010.
      // The bits read are MSB first?
      // 0xAA = 10101010.
      // The test expects 0,1,0,1,0,1,0. That's 7 bits.
      // It seems it skips the MSB of the stuffed byte?
      // Or maybe 0xFF 0xAA is NOT bit stuffing?
      // Bit stuffing is 0xFF 0x00 to represent 0xFF.
      // If it's 0xFF 0xAA, it's a marker.
      // But ByteToBitInput is supposed to handle the raw bitstream from the codestream.
      // Let's see what the Java test does.

      expect(stuffed, equals([0, 1, 0, 1, 0, 1, 0]));
    });

    test('checkBytePaddingFlagsNonAlternatingTail', () {
      final data = Uint8List.fromList([0xAA]);
      final input = ByteToBitInput(ByteInputBuffer(data));
      for (var i = 0; i < 4; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isTrue,
          reason: 'esperava erro por pad incorreto');
    });

    test('checkBytePaddingAcceptsAlternatingTail', () {
      final data = Uint8List.fromList([0x55]);
      final input = ByteToBitInput(ByteInputBuffer(data));
      for (var i = 0; i < 4; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isFalse,
          reason: 'pad 0x55 deve ser aceito');
    });

    test('checkBytePaddingDetectsTrailingBytes', () {
      final data = Uint8List.fromList([0x55, 0x00]);
      final input = ByteToBitInput(ByteInputBuffer(data));
      for (var i = 0; i < 8; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isTrue,
          reason: 'dados extra devem acusar erro');
    });

    test('checkBytePadding rejeita byte extra sem padrão alternado', () {
      final data = Uint8List.fromList([0xFF, 0x10]);
      final input = ByteToBitInput(ByteInputBuffer(data));
      for (var i = 0; i < 8; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isTrue,
          reason: 'faltou sequência 0101 após byte stuffed');
    });

    test('checkBytePadding rejeita byte extra >= 0x80 após FF', () {
      final data = Uint8List.fromList([0xFF, 0xF0]);
      final input = ByteToBitInput(ByteInputBuffer(data));
      for (var i = 0; i < 8; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isTrue,
          reason: 'valor >= 0x80 no byte extra é inválido');
    });

    test('checkBytePadding aceita byte stuffed com padrão 0xAA', () {
      final data = Uint8List.fromList([0xFF, 0xAA]);
      final input = ByteToBitInput(ByteInputBuffer(data));
      for (var i = 0; i < 8; i++) {
        input.readBit();
      }
      expect(input.checkBytePadding(), isFalse,
          reason: '0xAA mantém os 7 bits alternados exigidos pelo padrão');
    });
  });
}

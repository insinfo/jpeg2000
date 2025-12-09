import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/entropy/decoder/ByteInputBuffer.dart';
import 'package:jpeg2000/src/j2k/io/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('ByteInputBuffer parity', () {
    test('readSequenceAndEof reproduces Java behavior', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([0x01, 0x7F, 0xFF]));
      expect(buffer.read(), 0x01);
      expect(buffer.read(), 0x7F);
      expect(buffer.read(), 0xFF);
      expect(buffer.read(), -1);
      expect(buffer.readChecked, throwsA(isA<EOFException>()));
    });

    test('setByteArray switches to new window', () {
      final first = Uint8List.fromList([10, 11, 12, 13]);
      final second = Uint8List.fromList([20, 21, 22, 23, 24]);
      final buffer = ByteInputBuffer(first);

      expect(buffer.read(), 10);
      expect(buffer.read(), 11);

      buffer.setByteArray(second, 1, 3);
      expect(buffer.read(), 21);
      expect(buffer.read(), 22);
      expect(buffer.read(), 23);
      expect(buffer.read(), -1);

      buffer.setByteArray(second, 0, second.length);
      expect(buffer.read(), 20);
    });

    test('addByteArray appends data after shifting unread bytes', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([40, 41, 42, 43]));
      expect(buffer.read(), 40);
      expect(buffer.read(), 41);

      final extra = Uint8List.fromList([100, 101, 102]);
      buffer.addByteArray(extra, 0, extra.length);

      final remaining = <int>[];
      for (var i = 0; i < 5; i++) {
        remaining.add(buffer.read());
      }
      expect(remaining, [42, 43, 100, 101, 102]);
    });

    test('setByteArray com buffer atual e offset negativo estende janela', () {
      final storage = Uint8List.fromList([5, 6, 7, 8, 9, 10]);
      final buffer = ByteInputBuffer.view(storage, 0, 3);

      expect(buffer.read(), 5);
      expect(buffer.read(), 6);
      expect(buffer.read(), 7);
      expect(buffer.read(), -1);

      buffer.setByteArray(null, -1, 2);
      expect(buffer.read(), 8);
      expect(buffer.read(), 9);
      expect(buffer.read(), -1);
    });

    test('setByteArray reposiciona janela ao receber buffer explícito', () {
      final storage = Uint8List.fromList([50, 51, 52, 53, 54]);
      final buffer = ByteInputBuffer(storage);

      buffer.setByteArray(storage, 2, 2);
      expect(buffer.read(), 52);
      expect(buffer.read(), 53);
      expect(buffer.read(), -1);
    });

    test('setByteArray rejeita fatias inválidas', () {
      final storage = Uint8List(4);
      final buffer = ByteInputBuffer(storage);

      expect(() => buffer.setByteArray(null, -1, 5), throwsArgumentError);
      expect(() => buffer.setByteArray(storage, 2, 5), throwsArgumentError);
      expect(() => buffer.setByteArray(storage, -1, 1), throwsArgumentError);
    });

    test('addByteArray realoca preservando bytes não lidos', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([1, 2, 3, 4]));
      expect(buffer.read(), 1);

      final extra = Uint8List.fromList([5, 6, 7, 8, 9, 10, 11]);
      buffer.addByteArray(extra, 0, extra.length);

      final values = <int>[];
      int value;
      while ((value = buffer.read()) != -1) {
        values.add(value);
      }
      expect(values, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    });

    test('addByteArray rejeita slice fora do intervalo', () {
      final buffer = ByteInputBuffer(Uint8List.fromList([0, 0, 0, 0]));
      final extra = Uint8List.fromList([1, 2, 3]);

      expect(() => buffer.addByteArray(extra, 2, 5), throwsArgumentError);
      expect(() => buffer.addByteArray(extra, -1, 1), throwsArgumentError);
    });
  });
}

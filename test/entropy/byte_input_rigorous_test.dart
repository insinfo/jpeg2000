import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/ByteInputBuffer.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/ByteToBitInput.dart';

/// Testes RIGOROSOS para ByteToBitInput - operações fundamentais
/// Foco em byte stuffing e overflow que podem causar bugs no MQDecoder
void main() {
  ByteToBitInput _buildInput(Uint8List data, {int offset = 0, int? length}) {
    final sliceLength = length ?? (data.length - offset);
    final buffer = (offset == 0 && sliceLength == data.length)
        ? ByteInputBuffer(data)
        : ByteInputBuffer.view(data, offset, sliceLength);
    return ByteToBitInput(buffer);
  }

  List<int> _bitsOf(int value, {int width = 8}) {
    return List<int>.generate(width, (index) {
      final shift = width - 1 - index;
      return (value >> shift) & 0x01;
    });
  }

  List<int> _readBits(ByteToBitInput input, int count) {
    return List<int>.generate(count, (_) => input.readBit());
  }

  int _readAlignedByte(ByteToBitInput input) {
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 1) | input.readBit();
    }
    return value;
  }

  List<int> _readAlignedBytes(ByteToBitInput input, int count) {
    return List<int>.generate(count, (_) => _readAlignedByte(input));
  }

  group('ByteToBitInput - Operações Básicas RIGOROSAS', () {
    test('readBit - cada bit de 0xAC (10101100)', () {
      final data = Uint8List.fromList([0xAC]);
      final input = _buildInput(data);
      
      // 0xAC = 0b10101100 (MSB primeiro)
      expect(input.readBit(), 1, reason: 'bit 7 (MSB)');
      expect(input.readBit(), 0, reason: 'bit 6');
      expect(input.readBit(), 1, reason: 'bit 5');
      expect(input.readBit(), 0, reason: 'bit 4');
      expect(input.readBit(), 1, reason: 'bit 3');
      expect(input.readBit(), 1, reason: 'bit 2');
      expect(input.readBit(), 0, reason: 'bit 1');
      expect(input.readBit(), 0, reason: 'bit 0 (LSB)');
    });

    test('readBit - transição entre bytes', () {
      final data = Uint8List.fromList([0xFF, 0x00]);
      final input = _buildInput(data);
      
      // Primeiro byte: 8 bits = 1
      for (int i = 0; i < 8; i++) {
        expect(input.readBit(), 1, reason: 'Bit $i de 0xFF');
      }
      
      // Depois de um 0xFF apenas 7 bits do próximo byte carregam informação útil
      for (int i = 0; i < 7; i++) {
        expect(input.readBit(), 0, reason: 'Bit $i de 0x00 após stuffing');
      }
    });

    test('readBit reconstrói bytes sem stuffing', () {
      final data = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]);
      final input = _buildInput(data);
      
      expect(_readAlignedBytes(input, data.length), data);
    });
  });

  group('ByteToBitInput - Byte Stuffing CRÍTICO', () {
    test('0xFF 0x00 consome apenas 7 bits do byte seguinte', () {
      final data = Uint8List.fromList([0xFF, 0x00, 0xAB]);
      final input = _buildInput(data);

      expect(_readBits(input, 8), everyElement(equals(1)));
      expect(_readBits(input, 7), everyElement(equals(0)));

      final proximo = <int>[input.readBit(), ..._readBits(input, 7)];
      expect(proximo, equals(_bitsOf(0xAB)));
    });

    test('0xFF 0x00 antes de 0x12 mantém a sequência correta', () {
      final data = Uint8List.fromList([0xFF, 0x00, 0x12]);
      final input = _buildInput(data);

      expect(_readBits(input, 8), everyElement(equals(1)));
      expect(_readBits(input, 7), everyElement(equals(0)));
      expect(_readBits(input, 8), equals(_bitsOf(0x12)));
    });

    test('Múltiplos 0xFF 0x00 consecutivos mantêm apenas 7 bits úteis', () {
      final data = Uint8List.fromList([0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x99]);
      final input = _buildInput(data);

      for (var i = 0; i < 3; i++) {
        expect(_readBits(input, 8), everyElement(equals(1)), reason: '0xFF número $i');
        expect(_readBits(input, 7), everyElement(equals(0)), reason: 'stuffing $i');
      }

      final restante = <int>[input.readBit(), ..._readBits(input, 7)];
      expect(restante, equals(_bitsOf(0x99)));
    });

    test('0xFF final sem byte extra mantém os 8 bits originais', () {
      final data = Uint8List.fromList([0x12, 0xFF]);
      final input = _buildInput(data);

      expect(_readBits(input, 8), equals(_bitsOf(0x12)));
      expect(_readBits(input, 8), everyElement(equals(1)));
    });

    test('0xFF 0x01 ainda descarta o bit forçado a zero', () {
      final data = Uint8List.fromList([0xFF, 0x01]);
      final input = _buildInput(data);

      expect(_readBits(input, 8), everyElement(equals(1)));
      expect(_readBits(input, 7), equals([0, 0, 0, 0, 0, 0, 1]));
    });
  });

  group('ByteToBitInput - Offset e Length RIGOROSOS', () {
    test('Offset correto', () {
      final data = Uint8List.fromList([0x00, 0x11, 0x22, 0x33, 0x44]);
      final input = _buildInput(data, offset: 2, length: 2); // Offset 2, length 2
      
      expect(_readAlignedBytes(input, 2), equals([0x22, 0x33]));
    });

    test('Length exato', () {
      final data = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final input = _buildInput(data, length: 2); // Apenas 2 bytes
      
      expect(_readAlignedBytes(input, 2), equals([0xAA, 0xBB]));
      // Não deve conseguir ler o terceiro byte
    });
  });

  group('ByteToBitInput - Casos que Podem Causar Bug no MQDecoder', () {
    test('Padrão real de bitstream JPEG2000', () {
      // Dados típicos de um code-block
      final data = Uint8List.fromList([
        0x84, 0x00, 0xFF, 0x00, 0x20, 0xFF, 0x00, 0x10
      ]);
      final input = _buildInput(data);

      expect(_readBits(input, 8), equals(_bitsOf(0x84)));
      expect(_readBits(input, 8), equals(_bitsOf(0x00)));
      expect(_readBits(input, 8), everyElement(equals(1)));
      expect(_readBits(input, 7), everyElement(equals(0)));
      expect(_readBits(input, 8), equals(_bitsOf(0x20)));
      expect(_readBits(input, 8), everyElement(equals(1)));
      expect(_readBits(input, 7), everyElement(equals(0)));
      expect(_readBits(input, 8), equals(_bitsOf(0x10)));
    });

    test('Leitura de bits com byte stuffing no meio', () {
      final data = Uint8List.fromList([0xF0, 0xFF, 0x00, 0x0F]);
      final input = _buildInput(data);
      
      // Ler 0xF0 = 0b11110000
      for (int i = 0; i < 4; i++) expect(input.readBit(), 1);
      for (int i = 0; i < 4; i++) expect(input.readBit(), 0);
      
      // Ler 0xFF = 0b11111111
      for (int i = 0; i < 8; i++) expect(input.readBit(), 1);
      
      // Bit stuffing injeta 7 zeros do 0x00 reservado antes dos bits de 0x0F
      expect(_readBits(input, 7), everyElement(equals(0)));
      expect(_readBits(input, 8), equals(_bitsOf(0x0F)));
    });

    test('Overflow de buffer - não deve crashar', () {
      final data = Uint8List.fromList([0x12]);
      final input = _buildInput(data, length: 1);
      
      expect(_readAlignedBytes(input, 1), equals([0x12]));
      // Ler além do fim - deve ter comportamento definido
      expect(() => input.readBit(), returnsNormally);
    });

    test('Todo 0xFF com byte stuffing', () {
      // 10 bytes: 5x (0xFF 0x00)
      final data = Uint8List(10);
      for (int i = 0; i < 5; i++) {
        data[i * 2] = 0xFF;
        data[i * 2 + 1] = 0x00;
      }
      
      final input = _buildInput(data);
      
      for (int i = 0; i < 5; i++) {
        expect(_readBits(input, 8), everyElement(equals(1)), reason: '0xFF número $i');
        expect(_readBits(input, 7), everyElement(equals(0)), reason: 'stuffing $i');
      }
    });
  });

  group('ByteToBitInput - Comparação com Comportamento Java', () {
    test('Sequência idêntica ao TestDecoder.java', () {
      // Dados reais do solid_blue_jj2000.j2k
      final data = Uint8List.fromList([
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
      ]);
      final input = _buildInput(data);

      expect(_readAlignedBytes(input, data.length), equals(data));
    });

    test('Padrão alternado - detectar erro de ordem de bits', () {
      // Se bits estiverem na ordem errada, este teste falhará
      final data = Uint8List.fromList([0x55]); // 0b01010101
      final input = _buildInput(data);
      
      // MSB primeiro (padrão JPEG2000)
      expect(input.readBit(), 0);
      expect(input.readBit(), 1);
      expect(input.readBit(), 0);
      expect(input.readBit(), 1);
      expect(input.readBit(), 0);
      expect(input.readBit(), 1);
      expect(input.readBit(), 0);
      expect(input.readBit(), 1);
    });

    test('Bit 0x80 primeiro (MSB)', () {
      final data = Uint8List.fromList([0x80]); // 0b10000000
      final input = _buildInput(data);
      
      expect(input.readBit(), 1); // Bit 7 (MSB)
      for (int i = 0; i < 7; i++) {
        expect(input.readBit(), 0);
      }
    });

    test('Bit 0x01 último (LSB)', () {
      final data = Uint8List.fromList([0x01]); // 0b00000001
      final input = _buildInput(data);
      
      for (int i = 0; i < 7; i++) {
        expect(input.readBit(), 0);
      }
      expect(input.readBit(), 1); // Bit 0 (LSB)
    });
  });
}


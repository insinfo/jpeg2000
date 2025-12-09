import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/util/Int32Utils.dart';

/// Testes rigorosos para Int32Utils - operações bitwise fundamentais
/// Compara comportamento Dart vs Java int32
void main() {
  group('Int32Utils - Operações Básicas', () {
    test('asInt32 - converte para signed 32-bit', () {
      // Valores positivos
      expect(Int32Utils.asInt32(0), 0);
      expect(Int32Utils.asInt32(1), 1);
      expect(Int32Utils.asInt32(0x7FFFFFFF), 0x7FFFFFFF); // Max positive
      
      // Valores negativos (bit 31 setado)
      expect(Int32Utils.asInt32(0x80000000), -2147483648); // Min negative
      expect(Int32Utils.asInt32(0xFFFFFFFF), -1);
      expect(Int32Utils.asInt32(0xFFFFFFFE), -2);
    });

    test('asInt32 - overflow behavior', () {
      // Valores maiores que 32 bits devem fazer wrap
      expect(Int32Utils.asInt32(0x100000000), 0); // 33 bits -> wrap to 0
      expect(Int32Utils.asInt32(0x100000001), 1); // 33 bits -> wrap to 1
      expect(Int32Utils.asInt32(0x1FFFFFFFF), -1); // wrap to -1
    });

    test('encodeSignSample - sign bit encoding', () {
      // Sign=0 (positive), setmask=0
      expect(Int32Utils.encodeSignSample(0, 0), 0);
      
      // Sign=1 (negative), setmask=0
      expect(Int32Utils.encodeSignSample(1, 0), -2147483648); // 0x80000000
      
      // Sign=0, setmask with bits
      expect(Int32Utils.encodeSignSample(0, 0x0C000000), 0x0C000000);
      
      // Sign=1, setmask with bits
      expect(Int32Utils.encodeSignSample(1, 0x0C000000), -1946157056); // 0x8C000000
    });

    test('refineMagnitude - magnitude refinement', () {
      // Caso simples: current=0, sem símbolos
      final result1 = Int32Utils.refineMagnitude(0, 0xFFFFFFFF, 0, 0, 0);
      expect(result1, 0);
      
      // Setar bit no bitplane 5
      final result2 = Int32Utils.refineMagnitude(0, 0xFFFFFFFF, 1, 5, 0);
      expect(result2, 0x20); // bit 5 setado
      
      // Com setmask
      final result3 = Int32Utils.refineMagnitude(0, 0xFFFFFFFF, 1, 5, 0x10);
      expect(result3, 0x30); // bits 5 e 4 setados
      
      // Com resetmask para limpar bits
      final result4 = Int32Utils.refineMagnitude(0xFF, 0xF0, 0, 0, 0);
      expect(result4, 0xF0); // bits baixos limpos
    });

    test('refineMagnitude - case real do cleanup pass', () {
      // Simulando cleanup pass bp=27, sign=1
      int data = Int32Utils.encodeSignSample(1, 0x0C000000); // setmask=(3<<27)>>1
      expect(data, -1946157056); // 0x8C000000
      
      // Bits devem estar em: 31 (sign), 27, 26
      expect(data & (1 << 31), isNot(0)); // bit 31
      expect(data & (1 << 27), isNot(0)); // bit 27  
      expect(data & (1 << 26), isNot(0)); // bit 26
    });

    test('refineMagnitude - case real magnitude refinement bp=26', () {
      int data = -1946157056; // Estado após cleanup
      
      final resetmask = (-1) << 27; // 0xF8000000
      final setmask = (1 << 26) >> 1; // 0x02000000
      final sym = 1;
      final bp = 26;
      
      data = Int32Utils.refineMagnitude(data, resetmask, sym, bp, setmask);
      
      // Deve ter bits: 31, 27, 26, 25
      expect(data & (1 << 31), isNot(0)); // bit 31 (sign)
      expect(data & (1 << 27), isNot(0)); // bit 27
      expect(data & (1 << 26), isNot(0)); // bit 26 (symbol)
      expect(data & (1 << 25), isNot(0)); // bit 25 (setmask)
    });
  });

  group('Int32Utils - Sequence Completa', () {
    test('Reconstrução completa até bp=19', () {
      int data = 0;
      
      // Cleanup pass bp=27, sign=1
      int bp = 27;
      int sign = 1;
      int setmask = (3 << bp) >> 1;
      data = Int32Utils.encodeSignSample(sign, setmask);
      
      // Mag ref passes
      final passes = [
        {'bp': 26, 'sym': 1},
        {'bp': 25, 'sym': 0},
        {'bp': 24, 'sym': 1},
        {'bp': 23, 'sym': 0},
        {'bp': 22, 'sym': 0},
        {'bp': 21, 'sym': 0},
        {'bp': 20, 'sym': 1},
        {'bp': 19, 'sym': 1},
      ];
      
      for (final pass in passes) {
        bp = pass['bp'] as int;
        final sym = pass['sym'] as int;
        setmask = (1 << bp) >> 1;
        final resetmask = (-1) << (bp + 1);
        
        data = Int32Utils.refineMagnitude(data, resetmask, sym, bp, setmask);
      }
      
      // Valor esperado: -1927544832 (0x8D1C0000)
      expect(data, -1927544832);
    });
  });

  group('Int32Utils - Casos Extremos', () {
    test('Shift operations - não devem causar overflow inesperado', () {
      // Left shift até 31 bits
      expect(Int32Utils.asInt32(1 << 31), -2147483648);
      expect(Int32Utils.asInt32(1 << 30), 1073741824);
      
      // Right shift de valores negativos (arithmetic)
      expect(Int32Utils.asInt32(-1 >> 1), -1); // Arithmetic shift mantém sinal
      
      // Unsigned right shift em Dart não funciona como Java
      // Em Dart, usar >>> mas comportamento é diferente
      // Não é crítico para JPEG2000
    });

    test('Bitwise AND com resetmask', () {
      final value = 0xFFFFFFFF;
      final resetmask1 = (-1) << 27; // 0xF8000000
      expect(Int32Utils.asInt32(value & resetmask1), -134217728);
      
      final resetmask2 = (-1) << 16; // 0xFFFF0000
      expect(Int32Utils.asInt32(value & resetmask2), -65536);
    });

    test('Bitwise OR com setmask', () {
      final value = 0;
      final setmask1 = 0x0C000000;
      expect(Int32Utils.asInt32(value | setmask1), 0x0C000000);
      
      final setmask2 = 0x80000000;
      expect(Int32Utils.asInt32(value | setmask2), -2147483648);
    });

    test('Combinação AND + OR + shift', () {
      int value = 0xABCDEF12;
      
      // Limpar bits 7-0
      value = value & 0xFFFFFF00;
      expect(value & 0xFF, 0);
      
      // Setar bit 5
      value = value | (1 << 5);
      expect(value & (1 << 5), isNot(0));
      
      // Converter para int32
      final result = Int32Utils.asInt32(value);
      expect(result, Int32Utils.asInt32(0xABCDEF20));
    });
  });

  group('Int32Utils - Comparação com Valores Esperados Java', () {
    test('Valores do TestDecoder.java', () {
      // Valores conhecidos do trace Java
      expect(Int32Utils.asInt32(0x8D1C0000), -1927544832);
      expect(Int32Utils.asInt32(0x8C000000), -1946157056);
      expect(Int32Utils.asInt32(0x8E000000), -1912602624);
    });

    test('Máscaras típicas de JPEG2000', () {
      // Cleanup setmask para bp=27
      final cleanupMask27 = (3 << 27) >> 1;
      expect(cleanupMask27, 0x0C000000);
      
      // Mag ref setmask para bp=26
      final magRefMask26 = (1 << 26) >> 1;
      expect(magRefMask26, 0x02000000);
      
      // Resetmask para bp=27
      final resetMask27 = (-1) << 28;
      expect(Int32Utils.asInt32(resetMask27), -268435456); // 0xF0000000
    });
  });
}


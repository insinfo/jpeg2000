import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/util/ArrayUtil.dart';

/// Testes RIGOROSOS para ArrayUtil
/// Operações de array que podem causar bugs se não funcionarem identicamente ao Java
void main() {
  group('ArrayUtil - intArraySet (limpar arrays)', () {
    test('Limpar array pequeno para 0', () {
      final arr = Int32List.fromList([1, 2, 3, 4, 5]);
      ArrayUtil.intArraySet(arr, 0);
      
      expect(arr[0], 0);
      expect(arr[1], 0);
      expect(arr[2], 0);
      expect(arr[3], 0);
      expect(arr[4], 0);
    });

    test('Limpar array grande', () {
      final arr = Int32List(1000);
      for (int i = 0; i < arr.length; i++) {
        arr[i] = i;
      }
      
      ArrayUtil.intArraySet(arr, 0);
      
      for (int i = 0; i < arr.length; i++) {
        expect(arr[i], 0, reason: 'Index $i deve ser 0');
      }
    });

    test('Setar array para valor não-zero', () {
      final arr = Int32List(10);
      ArrayUtil.intArraySet(arr, 42);
      
      for (int i = 0; i < arr.length; i++) {
        expect(arr[i], 42);
      }
    });

    test('Setar array para valor negativo', () {
      final arr = Int32List(5);
      ArrayUtil.intArraySet(arr, -1);
      
      for (int i = 0; i < arr.length; i++) {
        expect(arr[i], -1);
      }
    });

    test('Array vazio não deve crashar', () {
      final arr = Int32List(0);
      expect(() => ArrayUtil.intArraySet(arr, 0), returnsNormally);
    });

    test('Limpar state array típico de JPEG2000', () {
      // State array usado no StdEntropyDecoder
      final maxWidth = 64;
      final maxHeight = 64;
      final stateSize = (maxWidth + 2) * (((maxHeight + 1) >> 1) + 2);
      
      final state = Int32List(stateSize);
      
      // Preencher com lixo
      for (int i = 0; i < state.length; i++) {
        state[i] = i | 0x80000000; // Valores com bit de sinal
      }
      
      // Limpar
      ArrayUtil.intArraySet(state, 0);
      
      // Verificar tudo zerado
      for (int i = 0; i < state.length; i++) {
        expect(state[i], 0, reason: 'State[$i] deve ser 0 após reset');
      }
    });

    test('Múltiplas limpezas consecutivas', () {
      final arr = Int32List.fromList([1, 2, 3, 4, 5]);
      
      ArrayUtil.intArraySet(arr, 0);
      expect(arr, [0, 0, 0, 0, 0]);
      
      for (int i = 0; i < arr.length; i++) arr[i] = i + 10;
      ArrayUtil.intArraySet(arr, 0);
      expect(arr, [0, 0, 0, 0, 0]);
      
      for (int i = 0; i < arr.length; i++) arr[i] = -i;
      ArrayUtil.intArraySet(arr, 0);
      expect(arr, [0, 0, 0, 0, 0]);
    });
  });

  group('ArrayUtil - Performance e Consistency', () {
    test('Limpar array muito grande', () {
      // 1MB de int32
      final arr = Int32List(256 * 1024);
      
      for (int i = 0; i < arr.length; i++) {
        arr[i] = i & 0xFFFF;
      }
      
      final start = DateTime.now();
      ArrayUtil.intArraySet(arr, 0);
      final elapsed = DateTime.now().difference(start);
      
      // Verificar alguns valores aleatórios
      expect(arr[0], 0);
      expect(arr[arr.length ~/ 2], 0);
      expect(arr[arr.length - 1], 0);
      
      // Não deve demorar mais que 100ms
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('Consistência após múltiplas operações', () {
      final arr = Int32List(100);
      
      // 10 ciclos de: setar valores → limpar
      for (int cycle = 0; cycle < 10; cycle++) {
        for (int i = 0; i < arr.length; i++) {
          arr[i] = cycle * 100 + i;
        }
        
        ArrayUtil.intArraySet(arr, 0);
        
        for (int i = 0; i < arr.length; i++) {
          expect(arr[i], 0, reason: 'Cycle $cycle, index $i');
        }
      }
    });
  });

  group('ArrayUtil - Casos Críticos para JPEG2000', () {
    test('Limpar data array de code-block', () {
      // Típico code-block 64x64
      final data = Int32List(64 * 64);
      
      // Simular coeficientes decodificados
      for (int i = 0; i < data.length; i++) {
        data[i] = (i % 2 == 0) ? -1927544832 : 1234567;
      }
      
      ArrayUtil.intArraySet(data, 0);
      
      // Tudo deve estar zerado
      int nonZero = 0;
      for (int i = 0; i < data.length; i++) {
        if (data[i] != 0) nonZero++;
      }
      expect(nonZero, 0, reason: 'Todos elementos devem ser 0');
    });

    test('Reset de state entre code-blocks', () {
      // Simular processamento de múltiplos code-blocks
      final state = Int32List(100);
      
      for (int codeBlock = 0; codeBlock < 5; codeBlock++) {
        // Preencher state com "lixo" do code-block anterior
        for (int i = 0; i < state.length; i++) {
          state[i] = codeBlock * 1000 + i;
        }
        
        // Reset para próximo code-block
        ArrayUtil.intArraySet(state, 0);
        
        // Verificar reset completo
        bool allZero = true;
        for (int i = 0; i < state.length; i++) {
          if (state[i] != 0) {
            allZero = false;
            break;
          }
        }
        expect(allZero, true, reason: 'Code-block $codeBlock: state não resetado');
      }
    });

    test('Verificar que não há referência compartilhada', () {
      final arr1 = Int32List.fromList([1, 2, 3]);
      final arr2 = Int32List.fromList([4, 5, 6]);
      
      ArrayUtil.intArraySet(arr1, 0);
      
      // arr2 NÃO deve ser afetado
      expect(arr2[0], 4);
      expect(arr2[1], 5);
      expect(arr2[2], 6);
    });
  });

  group('ArrayUtil - Comparação com Comportamento Java', () {
    test('Arrays.fill() equivalente', () {
      // Java: Arrays.fill(array, value)
      // Dart: ArrayUtil.intArraySet(array, value)
      
      final arr = Int32List(50);
      ArrayUtil.intArraySet(arr, 123);
      
      for (int i = 0; i < arr.length; i++) {
        expect(arr[i], 123);
      }
    });

    test('Valores típicos de state array', () {
      final state = Int32List(10);
      
      // Valores típicos de state bits
      state[0] = 0x8000; // STATE_SIG_R1
      state[1] = 0x4000; // STATE_VISITED_R1
      state[2] = 0x2000; // STATE_NZ_CTXT_R1
      
      ArrayUtil.intArraySet(state, 0);
      
      expect(state[0], 0);
      expect(state[1], 0);
      expect(state[2], 0);
    });
  });
}


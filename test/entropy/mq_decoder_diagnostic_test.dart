import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/MqDecoder.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/ByteInputBuffer.dart';

/// Teste diagnóstico do MQDecoder
/// Verifica estado interno durante decodificação
void main() {
  test('Diagnóstico completo do MQDecoder', () {
    final data = Uint8List.fromList([0x84, 0x00]);
    final buffer = ByteInputBuffer(data);
    final initialStates = List<int>.filled(19, 0);
    final decoder = MQDecoder(buffer, 19, initialStates);
    
    decoder.resetCtxts();
    
    // Tentar decodificar com trace
    decoder.startTrace('test', 50);
    
    // print('\n=== DIAGNÓSTICO MQDecoder ===');
    // print('Input bytes: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
    
    final firstSequence = <int>[];
    for (int i = 0; i < 10; i++) {
      final sym = decoder.decodeSymbol(0);
      firstSequence.add(sym);
      // print('Símbolo $i: $sym');
    }
    expect(firstSequence, equals(List<int>.filled(10, 0)),
        reason:
            'Sequência inicial deve corresponder ao JJ2000 (todos zeros).');
    
    // Testar com outros bytes conhecidos
    // print('\n=== TESTE COM PADRÃO ALTERNADO ===');
    final data2 = Uint8List.fromList([0xAA, 0x55, 0xAA]);
    final buffer2 = ByteInputBuffer(data2);
    final decoder2 = MQDecoder(buffer2, 19, initialStates);
    
    decoder2.resetCtxts();
    decoder2.startTrace('alternado', 50);
    
    // print('Input bytes: ${data2.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
    
    final symbols = <int>[];
    for (int i = 0; i < 15; i++) {
      final sym = decoder2.decodeSymbol(0);
      symbols.add(sym);
    }
    
    // print('Símbolos: $symbols');
    // print('Únicos: ${symbols.toSet()}');
    
    final trace2 = decoder2.drainTrace();
    if (trace2 != null && trace2.isNotEmpty) {
      // print('Trace: $trace2');
    }
    
    expect(symbols, equals(List<int>.filled(15, 0)),
      reason: 'JJ2000 também decodifica este padrão como só zeros.');
  });
  
  test('Comparar Java vs Dart - mesma entrada', () {
    // Dados do arquivo Java TestDecoder
    // solid_blue_jj2000.j2k primeiros bytes do bitstream
    final data = Uint8List.fromList([0x84, 0x00, 0x00, 0x00]);
    final buffer = ByteInputBuffer(data);
    final initialStates = List<int>.filled(19, 0);
    final decoder = MQDecoder(buffer, 19, initialStates);
    
    decoder.resetCtxts();
    
    // print('\n=== COMPARAÇÃO COM JAVA ===');
    // print('Input: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
    
    // Do trace Java, sabemos o comportamento esperado
    // Cleanup pass bp=27 deve ter alguns 1s, não tudo 0
    
    final symbols = <int>[];
    for (int i = 0; i < 20; i++) {
      symbols.add(decoder.decodeSymbol(0));
    }
    
    // print('Símbolos Dart: $symbols');
    // print('Contagem 0: ${symbols.where((s) => s == 0).length}');
    // print('Contagem 1: ${symbols.where((s) => s == 1).length}');
    
    // Se for TUDO 0, claramente está errado
    if (symbols.every((s) => s == 0)) {
      // print('⚠️  BUG CONFIRMADO: Todos símbolos são 0!');
      // print('⚠️  MQDecoder não está decodificando corretamente');
    }
    
    const expected = [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 1, 0, 0, 0, 1, 0,
    ];
    expect(symbols, equals(expected),
        reason: 'Sequência deve bater com o JJ2000 para os mesmos bytes.');
  });
}


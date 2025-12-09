import 'dart:typed_data';
import 'package:jpeg2000/src/j2k/entropy/decoder/MqDecoder.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/ByteInputBuffer.dart';

void main() {
  print('=== MQDecoder Debug Test ===\n');
  
  // Test 1: Single 0x00 byte (should give varied output)
  print('Test 1: Single 0x00 byte');
  final data1 = Uint8List.fromList([0x00]);
  testDecode(data1, 10);
  
  // Test 2: 0x84, 0x00 (Java shows all zeros)
  print('\nTest 2: Bytes 0x84, 0x00');
  final data2 = Uint8List.fromList([0x84, 0x00]);
  testDecode(data2, 10);
  
  // Test 3: 0xFF, 0x00 (byte stuffing, Java shows all ones)
  print('\nTest 3: Bytes 0xFF, 0x00 (byte stuffing)');
  final data3 = Uint8List.fromList([0xFF, 0x00]);
  testDecode(data3, 10);
}

void testDecode(Uint8List data, int numSymbols) {
  print('  Input bytes: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
  
  final buffer = ByteInputBuffer(data);
  final initialStates = List<int>.filled(1, 0);
  final decoder = MQDecoder(buffer, 1, initialStates);
  
  decoder.resetCtxts();
  
  print('  Decoded symbols:');
  final symbols = <int>[];
  for (int i = 0; i < numSymbols; i++) {
    final sym = decoder.decodeSymbol(0);
    symbols.add(sym);
  }
  
  print('  ${symbols.join(', ')}');
  
  final zeros = symbols.where((s) => s == 0).length;
  final ones = symbols.where((s) => s == 1).length;
  print('  Summary: $zeros zeros, $ones ones');
  
  if (zeros == numSymbols || ones == numSymbols) {
    print('  ⚠️  WARNING: All same value');
  } else {
    print('  ✓ Varied output');
  }
}


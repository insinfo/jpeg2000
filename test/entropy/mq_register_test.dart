// import 'package:jpeg2000/src/j2k/util/Int32Utils.dart';

void main() {
  // print('=== MQ Register Behavior Test ===\n');
  
  // Teste 1: inicialização
  int c = (0x00 ^ 0xFF) << 16;
  // print('Initial c (0x00): 0x${c.toRadixString(16)} = $c');
  
  // Teste 2: shift left 7
  c = c << 7;
  // print('After c<<7: 0x${c.toRadixString(16)} = $c');
  
  // Teste 3: adição em byteIn
  int b = 0x84;
  c += 0xFF00 - (b << 8);
  // print('After byteIn(0x84): 0x${c.toRadixString(16)} = $c');
  
  // Teste 4: shift (SEM mask32)
  // int cNoMask = c << 1;
  // print('After c<<1 (no mask): 0x${cNoMask.toRadixString(16)} = $cNoMask');
  
  // Teste 5: shift (COM mask32)
  // int cWithMask = Int32Utils.mask32(c << 1);
  // print('After c<<1 (with mask32): 0x${cWithMask.toRadixString(16)} = $cWithMask');
  
  // Teste 6: comparação com >>> 16 (SEM mask)
  // int topBitsNoMask = cNoMask >>> 16;
  // print('Top 16 bits (no mask, c>>>16): 0x${topBitsNoMask.toRadixString(16)} = $topBitsNoMask');
  
  // Teste 7: comparação com >>> 16 (COM mask)
  // int topBitsWithMask = cWithMask >>> 16;
  // print('Top 16 bits (with mask, c>>>16): 0x${topBitsWithMask.toRadixString(16)} = $topBitsWithMask');
  
  // Teste 8: subtração
  // int interval = 0x7FFF;
  // int cSubNoMask = cNoMask - (interval << 16);
  // int cSubWithMask = Int32Utils.mask32(cWithMask - (interval << 16));
  
  // print('\nAfter c-=(interval<<16) NO MASK: 0x${cSubNoMask.toRadixString(16)} = $cSubNoMask');
  // print('Top 16 bits: 0x${(cSubNoMask >>> 16).toRadixString(16)} = ${cSubNoMask >>> 16}');
  
  // print('\nAfter c-=(interval<<16) WITH MASK: 0x${cSubWithMask.toRadixString(16)} = $cSubWithMask');
  // print('Top 16 bits: 0x${(cSubWithMask >>> 16).toRadixString(16)} = ${cSubWithMask >>> 16}');
  
  // print('\n=== Java Expected Values ===');
  // print('After c<<1: 0xff00f600 = -16714240');
  // print('Top 16 bits (c>>>16): 0xff00 = 65280');
  // print('After c-=(interval<<16): 0x7f01f600 = 2130834944');
  // print('Top 16 bits: 0x7f01 = 32513');
}


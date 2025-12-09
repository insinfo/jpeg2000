List<int> getBitsSet(int value) {
  List<int> bits = [];
  for (int i = 0; i < 32; i++) {
    if ((value & (1 << i)) != 0) {
      bits.add(i);
    }
  }
  return bits;
}

void main() {
  print('=== Manual Reconstruction Test ===\n');
  
  int data = 0;
  
  // Cleanup pass bp=27, sign=1
  int bp = 27;
  int sym = 1;  // sign
  int setmask = (3 << bp) >> 1;
  data = (sym << 31) | setmask;
  print('After cleanup bp=$bp, sign=$sym:');
  print('  setmask = ${setmask.toRadixString(2).padLeft(32, '0')} = 0x${setmask.toRadixString(16)}');
  print('  data    = ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)} = 0x${data.toSigned(32).toRadixString(16)}');
  print('  Bits set: ${getBitsSet(data.toSigned(32))}\n');
  
  // Mag ref bp=26, sym=1
  bp = 26;
  sym = 1;
  setmask = (1 << bp) >> 1;
  int resetmask = (-1) << (bp + 1);
  print('Mag ref bp=$bp, sym=$sym:');
  print('  resetmask = ${resetmask.toRadixString(2).padLeft(32, '0')} = 0x${resetmask.toRadixString(16)}');
  print('  setmask   = ${setmask.toRadixString(2).padLeft(32, '0')} = 0x${setmask.toRadixString(16)}');
  
  // Java way: two operations
  data = (data & resetmask);
  print('  After &=: ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)}');
  data = data | (sym << bp) | setmask;
  print('  After |=: ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)} = 0x${data.toSigned(32).toRadixString(16)}');
  print('  Bits set: ${getBitsSet(data.toSigned(32))}\n');
  
  // Mag ref bp=25, sym=0
  bp = 25;
  sym = 0;
  setmask = (1 << bp) >> 1;
  resetmask = (-1) << (bp + 1);
  print('Mag ref bp=$bp, sym=$sym:');
  print('  resetmask = ${resetmask.toRadixString(2).padLeft(32, '0')} = 0x${resetmask.toRadixString(16)}');
  print('  setmask   = ${setmask.toRadixString(2).padLeft(32, '0')} = 0x${setmask.toRadixString(16)}');
  data = (data & resetmask);
  print('  After &=: ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)}');
  data = data | (sym << bp) | setmask;
  print('  After |=: ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)} = 0x${data.toSigned(32).toRadixString(16)}');
  print('  Bits set: ${getBitsSet(data.toSigned(32))}\n');
  
  // Mag ref bp=24, sym=1
  bp = 24;
  sym = 1;
  setmask = (1 << bp) >> 1;
  resetmask = (-1) << (bp + 1);
  print('Mag ref bp=$bp, sym=$sym:');
  print('  resetmask = ${resetmask.toRadixString(2).padLeft(32, '0')} = 0x${resetmask.toRadixString(16)}');
  print('  setmask   = ${setmask.toRadixString(2).padLeft(32, '0')} = 0x${setmask.toRadixString(16)}');
  data = (data & resetmask);
  print('  After &=: ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)}');
  data = data | (sym << bp) | setmask;
  print('  After |=: ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)} = 0x${data.toSigned(32).toRadixString(16)}');
  print('  Bits set: ${getBitsSet(data.toSigned(32))}\n');
  
  // Continue for more bit planes...
  for (bp = 23; bp >= 19; bp--) {
    // From Java trace: bp 23,22,21 have sym=0, bp 20,19 have sym=1
    sym = (bp >= 21) ? 0 : 1;
    setmask = (1 << bp) >> 1;
    resetmask = (-1) << (bp + 1);
    print('Mag ref bp=$bp, sym=$sym:');
    data = (data & resetmask);
    data = data | (sym << bp) | setmask;
    print('  Result: ${data.toSigned(32).toRadixString(2).padLeft(32, '0')} = ${data.toSigned(32)} = 0x${data.toSigned(32).toRadixString(16)}');
    print('  Bits set: ${getBitsSet(data.toSigned(32))}\n');
  }
  
  print('\n=== FINAL VALUE ===');
  print('Expected: -1927544832 = 0x8D000000');
  print('Got:      $data = 0x${data.toSigned(32).toRadixString(16)}');
  print('Match: ${data.toSigned(32) == -1927544832}');
}

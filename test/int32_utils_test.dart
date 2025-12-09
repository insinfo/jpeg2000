import 'package:jpeg2000/src/j2k/util/Int32Utils.dart';
import 'package:test/test.dart';


void main() {
  group('Int32Utils', () {
    test('mask32', () {
      expect(Int32Utils.mask32(0), 0);
      expect(Int32Utils.mask32(1), 1);
      expect(Int32Utils.mask32(-1), 0xFFFFFFFF);
      expect(Int32Utils.mask32(-2), 0xFFFFFFFE);
      expect(Int32Utils.mask32(0x7FFFFFFF), 0x7FFFFFFF);
      expect(Int32Utils.mask32(0x80000000), 0x80000000);
    });

    test('logicalShiftRight (>>>)', () {
      // Java: -1 >>> 1 = 2147483647 (0x7FFFFFFF)
      expect(Int32Utils.logicalShiftRight(-1, 1), 0x7FFFFFFF);
      
      // Java: -1 >>> 31 = 1
      expect(Int32Utils.logicalShiftRight(-1, 31), 1);
      
      // Java: -1 >>> 0 = -1 (Wait, in Java >>> returns int, so it's signed? No, >>> returns int but bitwise it's 0xFFFFFFFF)
      // In Java: Integer.toHexString(-1 >>> 0) is "ffffffff".
      // But as an int, it is -1.
      // Wait, Int32Utils.logicalShiftRight returns an int.
      // If I expect 0xFFFFFFFF, that is 4294967295 in Dart (positive).
      // In Java, -1 >>> 0 is -1.
      // Let's check what Int32Utils.logicalShiftRight returns.
      // mask32(mask32(-1) >>> 0) -> mask32(0xFFFFFFFF >>> 0) -> mask32(0xFFFFFFFF) -> 0xFFFFFFFF.
      // So it returns unsigned 32-bit integer value.
      expect(Int32Utils.logicalShiftRight(-1, 0), 0xFFFFFFFF);

      // Java: 0x80000000 >>> 1 = 0x40000000 (1073741824)
      expect(Int32Utils.logicalShiftRight(0x80000000, 1), 0x40000000);
    });

    test('asInt32', () {
      expect(Int32Utils.asInt32(0xFFFFFFFF), -1);
      expect(Int32Utils.asInt32(0x80000000), -2147483648);
      expect(Int32Utils.asInt32(0x7FFFFFFF), 2147483647);
    });

    test('encodeSignSample', () {
      // sign=0, setmask=0
      expect(Int32Utils.encodeSignSample(0, 0), 0);
      
      // sign=1, setmask=0. Java: (1<<31) | 0 = 0x80000000 (-2147483648)
      expect(Int32Utils.encodeSignSample(1, 0), -2147483648);
      
      // sign=0, setmask=1
      expect(Int32Utils.encodeSignSample(0, 1), 1);
    });

    test('refineMagnitude', () {
      // current=0, resetmask=0xFFFFFFFF, symbol=1, bitPlane=0, setmask=0
      // step1 = 0 & -1 = 0
      // step2 = 1 << 0 = 1
      // res = 0 | 1 | 0 = 1
      expect(Int32Utils.refineMagnitude(0, 0xFFFFFFFF, 1, 0, 0), 1);

      // current with sign bit set (negative in 32-bit)
      // current = 0x80000000 (-2147483648)
      // resetmask = 0x7FFFFFFF (clears sign bit? No, resetmask usually clears bits below bitPlane)
      // In StdEntropyDecoder: resetmask = (-1) << (bitPlane + 1)
      // If bitPlane=30, resetmask = (-1) << 31 = 0x80000000 (in 32-bit)
      // In Dart: (-1) << 31 = 0xFFFFFFFF80000000
      
      // Let's test with bitPlane=30
      int bitPlane = 30;
      int resetmask = (-1) << (bitPlane + 1); // Dart 64-bit shift
      // resetmask should be 0xFFFFFFFF80000000
      
      int current = -2147483648; // 0x80000000 (sign bit set)
      // step1 = current & resetmask
      // -2147483648 is 0xFFFFFFFF80000000 in 64-bit (sign extended)
      // step1 = 0xFFFFFFFF80000000 & 0xFFFFFFFF80000000 = 0xFFFFFFFF80000000
      
      int symbol = 1;
      int setmask = (1 << bitPlane) >> 1; // 1<<30 = 0x40000000. >>1 = 0x20000000
      
      // step2 = symbol << bitPlane = 1 << 30 = 0x40000000
      
      // res = step1 | step2 | setmask
      // res = 0xFFFFFFFF80000000 | 0x40000000 | 0x20000000
      // res = 0xFFFFFFFFE0000000
      
      // asInt32(res) -> toSigned(32)
      // 0xE0000000 is 1110...
      // toSigned(32) should take lower 32 bits: E0000000
      // E0000000 is negative in 32-bit.
      // 0xE0000000 = -536870912
      
      int result = Int32Utils.refineMagnitude(current, resetmask, symbol, bitPlane, setmask);
      
      // Expected: 0x80000000 | 0x40000000 | 0x20000000 = 0xE0000000
      expect(result, -536870912);
    });
  });
}


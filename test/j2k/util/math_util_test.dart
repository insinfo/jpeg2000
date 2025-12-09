import 'package:jpeg2000/src/j2k/util/MathUtil.dart';
import 'package:test/test.dart';

void main() {
  group('MathUtil', () {
    test('log2 computes floor for powers of two', () {
      expect(MathUtil.log2(1), 0);
      expect(MathUtil.log2(2), 1);
      expect(MathUtil.log2(32), 5);
      expect(MathUtil.log2(1024), 10);
    });

    test('log2 computes floor for non powers of two', () {
      expect(MathUtil.log2(15), 3);
      expect(MathUtil.log2(8), 3);
      expect(MathUtil.log2(120), 6);
    });

    test('log2 rejects zero', () {
      expect(() => MathUtil.log2(0), throwsArgumentError);
    });

    test('lcm computes expected values', () {
      expect(MathUtil.lcm(3, 4), 12);
      expect(MathUtil.lcm(5, 6), 30);
    });

    test('lcm rejects non positive values', () {
      expect(() => MathUtil.lcm(-1, 5), throwsArgumentError);
      expect(() => MathUtil.lcm(0, 5), throwsArgumentError);
    });

    test('lcm many aggregates values', () {
      expect(MathUtil.lcmMany([3, 4, 5]), 60);
    });

    test('gcd computes expected values', () {
      expect(MathUtil.gcd(30, 18), 6);
      expect(MathUtil.gcd(4, 0), 0);
      expect(MathUtil.gcd(0, 0), 0);
    });

    test('gcd rejects negative values', () {
      expect(() => MathUtil.gcd(-1, 2), throwsArgumentError);
      expect(() => MathUtil.gcd(1, -2), throwsArgumentError);
    });

    test('gcd many aggregates values', () {
      expect(MathUtil.gcdMany([9, 6, 3]), 3);
    });
  });
}


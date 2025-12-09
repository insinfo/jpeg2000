/// Mathematical helpers mirrored from JJ2000's utility set.
class MathUtil {
  /// Returns `floor(log2(value))` for positive integers.
  static int log2(int value) {
    if (value <= 0) {
      throw ArgumentError('$value <= 0');
    }
    var temp = value;
    var result = -1;
    while (temp > 0) {
      temp >>= 1;
      result++;
    }
    return result;
  }

  /// Least common multiple of two positive integers.
  static int lcm(int a, int b) {
    if (a <= 0 || b <= 0) {
      throw ArgumentError(
        'Cannot compute the least common multiple if any value is non-positive.',
      );
    }
    final max = a > b ? a : b;
    final min = a > b ? b : a;
    for (var i = 1; i <= min; i++) {
      if ((max * i) % min == 0) {
        return max * i;
      }
    }
    throw StateError('Cannot find the least common multiple of $a and $b');
  }

  /// Least common multiple of an array of positive integers.
  static int lcmMany(List<int> values) {
    if (values.length < 2) {
      throw StateError('lcmMany requires at least two numbers.');
    }
    var result = lcm(values[values.length - 1], values[values.length - 2]);
    for (var i = values.length - 3; i >= 0; i--) {
      final value = values[i];
      if (value <= 0) {
        throw ArgumentError(
          'Cannot compute the least common multiple when a value is non-positive.',
        );
      }
      result = lcm(result, value);
    }
    return result;
  }

  /// Greatest common divisor of two non-negative integers.
  static int gcd(int a, int b) {
    if (a < 0 || b < 0) {
      throw ArgumentError('Cannot compute the GCD if any value is negative.');
    }
    var x = a > b ? a : b;
    var y = a > b ? b : a;
    if (y == 0) {
      return 0;
    }
    var g = y;
    while (g != 0) {
      final remainder = x % g;
      x = g;
      g = remainder;
    }
    return x;
  }

  /// Greatest common divisor of an array of non-negative integers.
  static int gcdMany(List<int> values) {
    if (values.length < 2) {
      throw StateError('gcdMany requires at least two numbers.');
    }
    var result = gcd(values[values.length - 1], values[values.length - 2]);
    for (var i = values.length - 3; i >= 0; i--) {
      final value = values[i];
      if (value < 0) {
        throw ArgumentError('Cannot compute the GCD if any value is negative.');
      }
      result = gcd(result, value);
    }
    return result;
  }
}

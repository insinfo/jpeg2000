import 'dart:io';

import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/util/MathUtil.dart';

void main() {
  group('MathUtil Comparison', () {
    late List<String> javaOutputLines;

    setUpAll(() async {
      final fixtureFile = File('test/fixtures/math_util.csv');
      if (!fixtureFile.existsSync()) {
        throw Exception('Fixture file not found: ${fixtureFile.path}. Run the Java test generator first.');
      }
      javaOutputLines = await fixtureFile.readAsLines();
    });

    test('matches Java implementation', () {
      for (final line in javaOutputLines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(',');
        final method = parts[0];

        if (method == 'lcmArray' || method == 'gcdArray') {
          final args = parts[1].split(' ').map(int.parse).toList();
          final expectedResult = int.parse(parts[2]);
          int actualResult;
          if (method == 'lcmArray') {
            actualResult = MathUtil.lcmMany(args);
          } else {
            actualResult = MathUtil.gcdMany(args);
          }
          expect(
            actualResult,
            equals(expectedResult),
            reason: 'Failed for $method($args)',
          );
          continue;
        }

        final arg1 = int.parse(parts[1]);
        final arg2 = parts[2].isNotEmpty ? int.parse(parts[2]) : null;
        final expectedResult = int.parse(parts[3]);

        int actualResult;
        if (method == 'log2') {
          actualResult = MathUtil.log2(arg1);
        } else if (method == 'lcm') {
          actualResult = MathUtil.lcm(arg1, arg2!);
        } else if (method == 'gcd') {
          actualResult = MathUtil.gcd(arg1, arg2!);
        } else {
          fail('Unknown method from Java output: $method');
        }

        expect(
          actualResult,
          equals(expectedResult),
          reason: 'Failed for $method($arg1${arg2 != null ? ", $arg2" : ""})',
        );
      }
    });
  });
}


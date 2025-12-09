import 'dart:io';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';

void main() {
  group('ParameterList Comparison', () {
    test('Compare with Java fixtures', () async {
      final file = File('test/fixtures/parameter_list.csv');
      if (!await file.exists()) {
        fail('Fixture file not found: ${file.path}');
      }
      final lines = await file.readAsLines();

      final testCases = <int, Map<String, dynamic>>{};

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(',');
        final id = int.parse(parts[0]);
        final type = parts[1];
        
        testCases.putIfAbsent(id, () => {'args': <int, String>{}, 'props': <String, String>{}, 'error': null});
        
        if (type == 'ARG') {
          final index = int.parse(parts[2]);
          final val = parts[3];
          (testCases[id]!['args'] as Map<int, String>)[index] = val;
        } else if (type == 'PROP') {
          final key = parts[2];
          final val = parts[3];
          (testCases[id]!['props'] as Map<String, String>)[key] = val;
        } else if (type == 'ERROR') {
          testCases[id]!['error'] = parts[3];
        }
      }

      testCases.forEach((id, data) {
        final argsMap = data['args'] as Map<int, String>;
        final args = List<String>.generate(argsMap.length, (i) => argsMap[i]!);
        final expectedProps = data['props'] as Map<String, String>;
        final expectedError = data['error'] as String?;

        final pl = ParameterList();
        
        if (expectedError != null) {
          // Expect error
          try {
             pl.parseArgs(args);
             fail('Test $id: Expected error $expectedError but succeeded');
          } catch (e) {
             // Success
          }
        } else {
          try {
            pl.parseArgs(args);
            
            // Check all expected props are present and correct
            expectedProps.forEach((key, val) {
              expect(pl.getParameter(key), equals(val), reason: 'Test $id: Property $key mismatch');
            });
            
            // Check that we don't have extra properties
            // Note: propertyNames() includes defaults, but here we have no defaults.
            // We should check that the number of properties matches.
            int count = 0;
            for (var _ in pl.propertyNames()) {
              count++;
            }
            expect(count, equals(expectedProps.length), reason: 'Test $id: Property count mismatch');
            
          } catch (e) {
            fail('Test $id: Unexpected error: $e');
          }
        }
      });
    });
  });
}


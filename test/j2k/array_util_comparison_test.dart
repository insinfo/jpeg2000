import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/util/ArrayUtil.dart';

void main() {
  group('ArrayUtil Comparison', () {
    test('Compare with Java fixtures', () async {
      final file = File('test/fixtures/array_util.csv');
      if (!await file.exists()) {
        fail('Fixture file not found: ${file.path}');
      }
      final lines = await file.readAsLines();

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(',');
        final type = parts[0];
        final size = int.parse(parts[1]);
        final val = int.parse(parts[2]);
        final expectedStr = parts.length > 3 ? parts[3] : '';
        
        if (type == 'int') {
          final expected = expectedStr.isEmpty 
              ? <int>[] 
              : expectedStr.split(' ').map(int.parse).toList();
          
          // Use Int32List to match Java int[]
          final actual = Int32List(size);
          ArrayUtil.intArraySet(actual, val);
          
          expect(actual, equals(expected), reason: 'Failed for int array size $size');
        } else if (type == 'byte') {
           final expected = expectedStr.isEmpty 
              ? <int>[] 
              : expectedStr.split(' ').map(int.parse).toList();
          
          // Use Int8List to match Java byte[] (signed)
          final actual = Int8List(size);
          ArrayUtil.byteArraySet(actual, val);
          
          expect(actual, equals(expected), reason: 'Failed for byte array size $size');
        }
      }
    });
  });
}


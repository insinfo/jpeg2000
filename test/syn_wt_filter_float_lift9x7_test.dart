import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilterFloatLift9x7.dart';

void main() {
  group('SynWTFilterFloatLift9x7 Tests', () {
    test('synthetizeLpfFloat', () {
      final filter = SynWTFilterFloatLift9x7();
      
      final lowSig = Float32List.fromList([10.0, 12.0, 14.0]);
      final highSig = Float32List.fromList([2.0, 4.0, 6.0]);
      final outSig = Float32List(6);
      
      filter.synthetizeLpfFloat(
        lowSig, 0, 3, 1,
        highSig, 0, 3, 1,
        outSig, 0, 1,
      );
      
      // Java Output: 8.837282 11.638958 10.533728 15.129042 11.54763 17.46399
      final expected = [8.837282, 11.638958, 10.533728, 15.129042, 11.54763, 17.46399];
      
      for (var i = 0; i < 6; i++) {
        expect(outSig[i], closeTo(expected[i], 0.00001), reason: 'Mismatch at index $i');
      }
    });
  });
}


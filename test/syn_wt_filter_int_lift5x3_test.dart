import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilterIntLift5x3.dart';

void main() {
  group('SynWTFilterIntLift5x3 Tests', () {
    test('synthetizeLpfInt', () {
      final filter = SynWTFilterIntLift5x3();
      
      final lowSig = [10, 12, 14];
      final highSig = [2, 4, 6];
      final outSig = List<int>.filled(6, 0);
      
      filter.synthetizeLpfInt(
        lowSig, 0, 3, 1,
        highSig, 0, 3, 1,
        outSig, 0, 1,
      );
      
      expect(outSig, equals([9, 11, 10, 14, 11, 17]));
    });
  });
}


import 'package:jpeg2000/src/j2k/wavelet/analysis/AnWtFilterIntLift5x3.dart';
import 'package:jpeg2000/src/j2k/wavelet/FilterTypes.dart';
import 'package:jpeg2000/src/j2k/wavelet/WaveletFilter.dart';
import 'package:test/test.dart';

void main() {
  group('AnWTFilterIntLift5x3', () {
    test('analyzeLpfInt produces expected bands for even length input', () {
      final filter = AnWTFilterIntLift5x3();
      final inSig = <int>[0, 2, 4, 6, 8, 10];
      final low = List<int>.filled(3, 0);
      final high = List<int>.filled(3, 0);

      filter.analyzeLpfInt(inSig, 0, inSig.length, 1, low, 0, 1, high, 0, 1);

      expect(low, equals(<int>[0, 4, 9]));
      expect(high, equals(<int>[0, 0, 2]));
    });

    test('analyzeHpfInt produces expected bands for even length input', () {
      final filter = AnWTFilterIntLift5x3();
      final inSig = <int>[0, 2, 4, 6, 8, 10];
      final low = List<int>.filled(3, 0);
      final high = List<int>.filled(3, 0);

      filter.analyzeHpfInt(inSig, 0, inSig.length, 1, low, 0, 1, high, 0, 1);

      expect(low, equals(<int>[2, 6, 10]));
      expect(high, equals(<int>[-2, 0, 0]));
    });

    test('odd length signals apply symmetric extensions', () {
      final filter = AnWTFilterIntLift5x3();
      final inSig = <int>[3, 5, 7, 9, 11];
      final lowLpf = List<int>.filled(3, 0);
      final highLpf = List<int>.filled(2, 0);
      filter.analyzeLpfInt(inSig, 0, inSig.length, 1, lowLpf, 0, 1, highLpf, 0, 1);
      expect(lowLpf, equals(<int>[3, 7, 11]));
      expect(highLpf, equals(<int>[0, 0]));

      final lowHpf = List<int>.filled(2, 0);
      final highHpf = List<int>.filled(3, 0);
      filter.analyzeHpfInt(inSig, 0, inSig.length, 1, lowHpf, 0, 1, highHpf, 0, 1);
      expect(lowHpf, equals(<int>[5, 10]));
      expect(highHpf, equals(<int>[-2, 0, 2]));
    });

    test('metadata aligns with JJ2000 reference', () {
      final filter = AnWTFilterIntLift5x3();
      expect(filter.getAnLowNegSupport(), 2);
      expect(filter.getAnLowPosSupport(), 2);
      expect(filter.getAnHighNegSupport(), 1);
      expect(filter.getAnHighPosSupport(), 1);
      expect(filter.getSynLowNegSupport(), 1);
      expect(filter.getSynLowPosSupport(), 1);
      expect(filter.getSynHighNegSupport(), 2);
      expect(filter.getSynHighPosSupport(), 2);
      expect(filter.isReversible(), isTrue);
      expect(filter.getImplType(), WaveletFilter.wtFilterIntLift);
      expect(filter.getFilterType(), FilterTypes.w5x3);
      expect(filter.isSameAsFullWT(2, 1, 6), isTrue);
      expect(filter.isSameAsFullWT(1, 1, 6), isFalse);
      expect(filter.isSameAsFullWT(2, 2, 5), isTrue);
      expect(filter.isSameAsFullWT(2, 1, 5), isFalse);
      expect(filter.getLPSynthesisFilter().length, 3);
      expect(filter.getHPSynthesisFilter().length, 5);
      expect(filter.toString(), contains('w5x3'));
    });
  });
}


@TestOn('vm')
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:j2k/src/j2k/wavelet/atk_kernel.dart';
import 'package:j2k/src/j2k/wavelet/synthesis/syn_wt_filter_float_lift9x7.dart';
import 'package:j2k/src/j2k/wavelet/synthesis/syn_wt_filter_generic_lift.dart';
import 'package:j2k/src/j2k/wavelet/synthesis/syn_wt_filter_int_lift5x3.dart';
import 'package:test/test.dart';

/// The generic lifting synthesis of ISO/IEC 15444-2 (ITU-T T.801) Annex G.
///
/// Annex G.4 gives the parameters that make the generic procedure reproduce
/// the two kernels of ISO/IEC 15444-1, so the hand-written 5-3 and 9-7 filters
/// of this package are the reference the generic one is checked against: the
/// reversible case has to agree exactly, the irreversible one to the precision
/// of the constants each side uses.
void main() {
  /// T.801 Table G.2, the 5-3 reversible kernel.
  AtkKernel reversible53({int index = 2}) => AtkKernel(
        index: index,
        coefficientType: 0,
        wholeSampleSymmetric: true,
        reversible: true,
        initialParity: 0,
        constantExtension: false,
        scale: 1,
        steps: const <AtkLiftingStep>[
          AtkLiftingStep(
            coefficients: <double>[-1],
            exponent: 1,
            residue: 1,
          ),
          AtkLiftingStep(
            coefficients: <double>[1],
            exponent: 2,
            residue: 2,
          ),
        ],
      );

  /// T.801 Table G.6, the 9-7 irreversible kernel.
  AtkKernel irreversible97({int index = 3}) => AtkKernel(
        index: index,
        coefficientType: 2,
        wholeSampleSymmetric: true,
        reversible: false,
        initialParity: 0,
        constantExtension: false,
        scale: 1.230174104914001,
        steps: const <AtkLiftingStep>[
          AtkLiftingStep(coefficients: <double>[-1.586134342059924]),
          AtkLiftingStep(coefficients: <double>[-0.052980118572961]),
          AtkLiftingStep(coefficients: <double>[0.882911075530934]),
          AtkLiftingStep(coefficients: <double>[0.443506852043971]),
        ],
      );

  group('generic reversible lifting', () {
    test('reproduces the 5-3 kernel of T.801 G.4.1.1 exactly', () {
      final reference = SynWTFilterIntLift5x3();
      final generic = SynWTFilterGenericIntLift(reversible53());
      final random = Random(20260913);

      for (var length = 1; length <= 33; length++) {
        for (final lowFirst in <bool>[true, false]) {
          final lowLen = lowFirst ? (length + 1) >> 1 : length >> 1;
          final highLen = length - lowLen;
          final low = Int32List(lowLen);
          final high = Int32List(highLen);
          for (var i = 0; i < lowLen; i++) {
            low[i] = random.nextInt(4096) - 2048;
          }
          for (var i = 0; i < highLen; i++) {
            high[i] = random.nextInt(4096) - 2048;
          }

          final expected = Int32List(length);
          final actual = Int32List(length);
          if (lowFirst) {
            reference.synthetizeLpfInt(
                low, 0, lowLen, 1, high, 0, highLen, 1, expected, 0, 1);
            generic.synthetizeLpfInt(
                low, 0, lowLen, 1, high, 0, highLen, 1, actual, 0, 1);
          } else {
            reference.synthetizeHpfInt(
                low, 0, lowLen, 1, high, 0, highLen, 1, expected, 0, 1);
            generic.synthetizeHpfInt(
                low, 0, lowLen, 1, high, 0, highLen, 1, actual, 0, 1);
          }

          expect(actual, expected,
              reason: 'length $length, '
                  '${lowFirst ? 'low-pass' : 'high-pass'} first');
        }
      }
    });

    test('honours the output stride and offset', () {
      final reference = SynWTFilterIntLift5x3();
      final generic = SynWTFilterGenericIntLift(reversible53());
      final low = Int32List.fromList(<int>[10, -20, 30, -40]);
      final high = Int32List.fromList(<int>[1, 2, -3, 4]);

      final expected = Int32List(40);
      final actual = Int32List(40);
      reference.synthetizeLpfInt(low, 0, 4, 1, high, 0, 4, 1, expected, 3, 4);
      generic.synthetizeLpfInt(low, 0, 4, 1, high, 0, 4, 1, actual, 3, 4);
      expect(actual, expected);
    });

    test('reports itself as reversible and integer-typed', () {
      final generic = SynWTFilterGenericIntLift(reversible53());
      expect(generic.isReversible(), isTrue);
      expect(generic.kernel.index, 2);
      expect(generic.getSynLowNegSupport(), greaterThan(0));
    });
  });

  group('generic irreversible lifting', () {
    test('reproduces the 9-7 kernel of T.801 G.4.2.3', () {
      final reference = SynWTFilterFloatLift9x7();
      final generic = SynWTFilterGenericFloatLift(irreversible97());
      final random = Random(20260914);

      for (var length = 2; length <= 33; length++) {
        for (final lowFirst in <bool>[true, false]) {
          final lowLen = lowFirst ? (length + 1) >> 1 : length >> 1;
          final highLen = length - lowLen;
          if (lowLen == 0 || highLen == 0) {
            continue;
          }
          final low = Float32List(lowLen);
          final high = Float32List(highLen);
          for (var i = 0; i < lowLen; i++) {
            low[i] = random.nextDouble() * 200 - 100;
          }
          for (var i = 0; i < highLen; i++) {
            high[i] = random.nextDouble() * 200 - 100;
          }

          final expected = Float32List(length);
          final actual = Float32List(length);
          // `synthetizeHpfFloat` of the 9-7 filter scales its two input bands
          // in place, so each side gets its own copy of the coefficients.
          final referenceLow = Float32List.fromList(low);
          final referenceHigh = Float32List.fromList(high);
          if (lowFirst) {
            reference.synthetizeLpfFloat(referenceLow, 0, lowLen, 1,
                referenceHigh, 0, highLen, 1, expected, 0, 1);
            generic.synthetizeLpfFloat(
                low, 0, lowLen, 1, high, 0, highLen, 1, actual, 0, 1);
          } else {
            reference.synthetizeHpfFloat(referenceLow, 0, lowLen, 1,
                referenceHigh, 0, highLen, 1, expected, 0, 1);
            generic.synthetizeHpfFloat(
                low, 0, lowLen, 1, high, 0, highLen, 1, actual, 0, 1);
          }

          for (var i = 0; i < length; i++) {
            expect(actual[i], closeTo(expected[i], 1e-3),
                reason: 'length $length, '
                    '${lowFirst ? 'low-pass' : 'high-pass'} first, sample $i');
          }
        }
      }
    });

    test('reports itself as irreversible', () {
      final generic = SynWTFilterGenericFloatLift(irreversible97());
      expect(generic.isReversible(), isFalse);
      expect(generic.kernel.stepCount, 4);
    });
  });

  group('kernels the synthesis refuses', () {
    test('rejects an arbitrary (ARB) kernel, which needs T.801 Annex H', () {
      expect(
        () => SynWTFilterGenericLift.create(AtkKernel(
          index: 4,
          coefficientType: 0,
          wholeSampleSymmetric: false,
          reversible: true,
          initialParity: 0,
          constantExtension: true,
          scale: 1,
          steps: const <AtkLiftingStep>[
            AtkLiftingStep(coefficients: <double>[1], exponent: 1),
          ],
        )),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('rejects a kernel without lifting steps', () {
      expect(
        () => SynWTFilterGenericLift.create(const AtkKernel(
          index: 5,
          coefficientType: 0,
          wholeSampleSymmetric: true,
          reversible: true,
          initialParity: 0,
          constantExtension: false,
          scale: 1,
          steps: <AtkLiftingStep>[],
        )),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('rejects an irreversible kernel whose scaling factor is zero', () {
      expect(
        () => SynWTFilterGenericLift.create(const AtkKernel(
          index: 6,
          coefficientType: 2,
          wholeSampleSymmetric: true,
          reversible: false,
          initialParity: 0,
          constantExtension: false,
          scale: 0,
          steps: <AtkLiftingStep>[
            AtkLiftingStep(coefficients: <double>[0.5]),
          ],
        )),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('whole-sample symmetric extension', () {
    test('folds indices the way PSEO does', () {
      // PSEO mirrors about the first and the last sample without repeating
      // them: for a signal of five samples the extension reads
      // ... 2 1 | 0 1 2 3 4 | 3 2 ...
      const length = 5;
      const expected = <int, int>{
        -3: 3,
        -2: 2,
        -1: 1,
        0: 0,
        4: 4,
        5: 3,
        6: 2,
        7: 1,
        8: 0,
        9: 1,
      };
      expected.forEach((position, folded) {
        expect(SynWTFilterGenericLift.foldPosition(position, length), folded,
            reason: 'position $position');
      });
    });
  });
}

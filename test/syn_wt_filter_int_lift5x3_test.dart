import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:j2k/src/j2k/wavelet/synthesis/syn_wt_filter_int_lift5x3.dart';

void main() {
  group('SynWTFilterIntLift5x3 Tests', () {
    test('synthetizeLpfInt', () {
      final filter = SynWTFilterIntLift5x3();

      final lowSig = Int32List.fromList([10, 12, 14]);
      final highSig = Int32List.fromList([2, 4, 6]);
      final outSig = Int32List(6);

      filter.synthetizeLpfInt(
        lowSig,
        0,
        3,
        1,
        highSig,
        0,
        3,
        1,
        outSig,
        0,
        1,
      );

      expect(outSig, equals([9, 11, 10, 14, 11, 17]));
    });
  });
}

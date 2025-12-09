import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/NotImplementedError.dart';
import 'package:jpeg2000/src/j2k/wavelet/WtDecompSpec.dart';

void main() {
  group('WTDecompSpec', () {
    test('returns main defaults for all components', () {
      final spec = WTDecompSpec(3, WTDecompSpec.wtDecompDyadic, 5);
      expect(spec.getMainDefDecompType(), WTDecompSpec.wtDecompDyadic);
      expect(spec.getMainDefLevels(), 5);
      for (var comp = 0; comp < 3; comp++) {
        expect(spec.getDecSpecType(comp), WTDecompSpec.decSpecMainDef);
        expect(spec.getDecompType(comp), WTDecompSpec.wtDecompDyadic);
        expect(spec.getLevels(comp), 5);
      }
    });

    test('component override raises but stores override state', () {
      final spec = WTDecompSpec(2, WTDecompSpec.wtDecompDyadic, 4);
      expect(
        () => spec.setMainCompDefDecompType(1, WTDecompSpec.wtDecompPacket, 2),
        throwsA(isA<NotImplementedError>()),
      );
      expect(spec.getDecSpecType(1), WTDecompSpec.decSpecCompDef);
      expect(spec.getDecompType(1), WTDecompSpec.wtDecompPacket);
      expect(spec.getLevels(1), 2);
    });
  });
}


import 'package:jpeg2000/src/j2k/image/input/ImgReaderPgm.dart';
import 'package:jpeg2000/src/j2k/roi/encoder/RoiOptionParser.dart';
import 'package:test/test.dart';

void main() {
  group('parseRoiOptions', () {
    test('returns empty list for blank input', () {
      expect(parseRoiOptions('   ', 3), isEmpty);
    });

    test('creates rectangular ROIs for all components when no c token', () {
      final result = parseRoiOptions('R 0 1 2 3', 2);
      expect(result, hasLength(2));
      expect(result[0].isRectangular, isTrue);
      expect(result[0].component, 0);
      expect(result[0].upperLeftX, 0);
      expect(result[0].upperLeftY, 1);
      expect(result[0].width, 2);
      expect(result[0].height, 3);
      expect(result[1].component, 1);
    });

    test('filters components using c token', () {
      final result = parseRoiOptions('c0,2 R 1 2 3 4', 3);
      expect(result, hasLength(2));
      expect(result[0].component, 0);
      expect(result[1].component, 2);
    });

    test('supports circular ROI syntax', () {
      final result = parseRoiOptions('C 5 -3 9', 1);
      expect(result, hasLength(1));
      expect(result.first.isCircular, isTrue);
      expect(result.first.centerX, 5);
      expect(result.first.centerY, -3);
      expect(result.first.radius, 9);
    });

    test('supports arbitrary ROI masks', () {
      final result = parseRoiOptions('A mask.pgm', 1);
      expect(result, hasLength(1));
      expect(result.first.isArbitrary, isTrue);
      expect(result.first.mask, isA<ImgReaderPGM>());
      expect(result.first.mask!.path, 'mask.pgm');
    });

    test('reuses latest component selection until overridden', () {
      final result = parseRoiOptions('c0 R 0 0 1 1 R 1 1 2 2', 3);
      expect(result, hasLength(2));
      expect(result[0].component, 0);
      expect(result[1].component, 0);
    });
  });
}


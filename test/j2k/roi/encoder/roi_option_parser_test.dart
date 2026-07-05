@TestOn('vm')
import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/image/input/img_reader_pgm.dart';
import 'package:jpeg2000/src/j2k/roi/encoder/roi_option_parser.dart';
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
      // The reader opens the mask eagerly (like JJ2000), so create a real
      // 2x2 raw PGM file.
      final dir = Directory.systemTemp.createTempSync('roi_mask_');
      final maskPath = '${dir.path}${Platform.pathSeparator}mask.pgm';
      File(maskPath).writeAsBytesSync(
          Uint8List.fromList('P5\n2 2\n255\n'.codeUnits + [0, 255, 255, 0]));
      try {
        final result = parseRoiOptions('A $maskPath', 1);
        expect(result, hasLength(1));
        expect(result.first.isArbitrary, isTrue);
        expect(result.first.mask, isA<ImgReaderPGM>());
        expect(result.first.mask!.w, 2);
        expect(result.first.mask!.h, 2);
        result.first.mask!.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('reuses latest component selection until overridden', () {
      final result = parseRoiOptions('c0 R 0 0 1 1 R 1 1 2 2', 3);
      expect(result, hasLength(2));
      expect(result[0].component, 0);
      expect(result[1].component, 0);
    });
  });
}

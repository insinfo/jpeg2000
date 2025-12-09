import 'package:jpeg2000/src/j2k/codestream/HeaderInfo.dart';
import 'package:jpeg2000/src/j2k/codestream/markers.dart';
import 'package:jpeg2000/src/j2k/roi/MaxShiftSpec.dart';
import 'package:jpeg2000/src/j2k/roi/RectRoiSpec.dart';
import 'package:jpeg2000/src/j2k/roi/RectangularRoi.dart';
import 'package:test/test.dart';

void main() {
  group('HeaderInfoSIZ', () {
    test('computes cached geometry metrics', () {
      final siz = HeaderInfoSIZ()
        ..xsiz = 130
        ..ysiz = 66
        ..x0siz = 1
        ..y0siz = 2
        ..xtsiz = 64
        ..ytsiz = 32
        ..xt0siz = 0
        ..yt0siz = 0
        ..csiz = 2
        ..ssiz = <int>[0x07, 0x87]
        ..xrsiz = <int>[1, 2]
        ..yrsiz = <int>[1, 2];

      expect(siz.getCompImgWidth(0), equals(129));
      expect(siz.getCompImgWidth(1), equals(64));
      expect(siz.getMaxCompWidth(), equals(129));

      expect(siz.getCompImgHeight(0), equals(64));
      expect(siz.getCompImgHeight(1), equals(32));
      expect(siz.getMaxCompHeight(), equals(64));

      expect(siz.getNumTiles(), equals(9));

      expect(siz.isOrigSigned(0), isFalse);
      expect(siz.isOrigSigned(1), isTrue);
      expect(siz.getOrigBitDepth(0), equals(8));
      expect(siz.getOrigBitDepth(1), equals(8));
    });
  });

  group('HeaderInfo.populateRoiSpecs', () {
    test('propagates implicit ROI shifts and clears rectangles', () {
      final headerInfo = HeaderInfo();
      final defaultRgn = headerInfo.getNewRGN()
        ..lrgn = 5
        ..crgn = 0
        ..srgn = Markers.SRGN_IMPLICIT
        ..sprgn = 5;
      headerInfo.rgn['main_c0'] = defaultRgn;

      final tileRgn = headerInfo.getNewRGN()
        ..lrgn = 5
        ..crgn = 1
        ..srgn = Markers.SRGN_IMPLICIT
        ..sprgn = 2;
      headerInfo.rgn['t1_c1'] = tileRgn;

      final roiSpec = MaxShiftSpec(2, 2);
      final rectSpec = RectROISpec(2, 2);

      final componentRoi = RectangularROI(x0: 0, y0: 0, width: 8, height: 8);
      final untouchedRoi = RectangularROI(x0: 4, y0: 4, width: 8, height: 8);
      final tileCompRoi = RectangularROI(x0: 2, y0: 2, width: 4, height: 4);

      rectSpec
        ..setCompDef(0, componentRoi)
        ..setTileCompVal(0, 1, untouchedRoi)
        ..setTileCompVal(1, 1, tileCompRoi);

      headerInfo.populateRoiSpecs(
          roiMaxShift: roiSpec, rectangularRois: rectSpec);

      expect(roiSpec.getCompDef(0), equals(5));
      expect(rectSpec.getCompDef(0), isNull);

      expect(roiSpec.getTileCompVal(1, 1), equals(2));
      expect(rectSpec.getTileCompVal(1, 1), isNull);

      expect(rectSpec.getTileCompVal(0, 1), same(untouchedRoi));
    });
  });
}

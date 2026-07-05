@TestOn('vm')
import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/image/data_blk.dart';
import 'package:jpeg2000/src/j2k/image/coord.dart';
import 'package:jpeg2000/src/j2k/quantization/quantizer/quantizer.dart';
import 'package:jpeg2000/src/j2k/roi/encoder/arb_roi_mask_generator.dart';
import 'package:jpeg2000/src/j2k/roi/encoder/roi.dart';
import 'package:jpeg2000/src/j2k/wavelet/analysis/c_blk_wt_data.dart';
import 'package:jpeg2000/src/j2k/wavelet/analysis/c_blk_wt_data_src.dart';
import 'package:jpeg2000/src/j2k/wavelet/analysis/subband_an.dart';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/image/data_blk_int.dart';
import 'package:jpeg2000/src/j2k/image/input/img_reader_pgm.dart';

void main() {
  group('ArbROIMaskGenerator', () {
    test('rasterizes circular ROIs like JJ2000 generic generator', () {
      final generator = ArbROIMaskGenerator(
        <ROI>[ROI.circular(component: 0, x: 2, y: 2, radius: 2)],
        1,
        _FakeQuantizer(width: 5, height: 5),
      );
      final subband = _leafSubband(width: 5, height: 5);
      final block = DataBlkInt.withGeometry(0, 0, 5, 5);

      final hasRoi = generator.getRoiMask(block, subband, 7, 0);

      expect(hasRoi, isTrue);
      expect(block.getDataInt(), <int>[
        0,
        0,
        0,
        0,
        0,
        0,
        7,
        7,
        7,
        0,
        0,
        7,
        7,
        7,
        0,
        0,
        7,
        7,
        7,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
    });

    test('rasterizes arbitrary PGM ROI masks', () {
      final dir = Directory.systemTemp.createTempSync('arb_roi_mask_');
      final maskPath = '${dir.path}${Platform.pathSeparator}mask.pgm';
      final maskBytes = <int>[
        0,
        255,
        0,
        0,
        255,
        255,
        0,
        0,
        0,
        0,
        255,
        0,
      ];
      File(maskPath).writeAsBytesSync(
        Uint8List.fromList('P5\n4 3\n255\n'.codeUnits + maskBytes),
      );

      ImgReaderPGM? maskReader;
      try {
        maskReader = ImgReaderPGM(maskPath);
        final generator = ArbROIMaskGenerator(
          <ROI>[ROI.arbitrary(component: 0, mask: maskReader)],
          1,
          _FakeQuantizer(width: 4, height: 3),
        );
        final subband = _leafSubband(width: 4, height: 3);
        final block = DataBlkInt.withGeometry(0, 0, 4, 3);

        final hasRoi = generator.getRoiMask(block, subband, 5, 0);

        expect(hasRoi, isTrue);
        expect(block.getDataInt(), <int>[
          0,
          5,
          0,
          0,
          5,
          5,
          0,
          0,
          0,
          0,
          5,
          0,
        ]);
      } finally {
        maskReader?.close();
        dir.deleteSync(recursive: true);
      }
    });
  });
}

SubbandAn _leafSubband({required int width, required int height}) {
  return SubbandAn()
    ..ulx = 0
    ..uly = 0
    ..ulcx = 0
    ..ulcy = 0
    ..w = width
    ..h = height
    ..resLvl = 0;
}

class _FakeQuantizer extends Quantizer {
  _FakeQuantizer({required int width, required int height})
      : super(_FakeWtDataSrc(width: width, height: height));

  @override
  void calcSbParams(SubbandAn sb, int n) {}

  @override
  CBlkWTData? getNextCodeBlock(int c, CBlkWTData? cblk) => null;

  @override
  CBlkWTData? getNextInternCodeBlock(int c, CBlkWTData? cblk) => null;

  @override
  int getMaxMagBits(int c) => 0;

  @override
  int getNumGuardBits(int t, int c) => 2;

  @override
  bool isDerived(int t, int c) => false;

  @override
  bool isReversible(int t, int c) => true;
}

class _FakeWtDataSrc implements CBlkWTDataSrc {
  _FakeWtDataSrc({required this.width, required this.height});

  final int width;
  final int height;

  @override
  int getCbULX() => 0;

  @override
  int getCbULY() => 0;

  @override
  int getCompImgHeight(int component) => height;

  @override
  int getCompImgWidth(int component) => width;

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getCompULX(int component) => 0;

  @override
  int getCompULY(int component) => 0;

  @override
  int getDataType(int t, int c) => DataBlk.typeInt;

  @override
  int getFixedPoint(int c) => 0;

  @override
  int getImgHeight() => height;

  @override
  int getImgULX() => 0;

  @override
  int getImgULY() => 0;

  @override
  int getImgWidth() => width;

  @override
  int getNomRangeBits(int component) => 8;

  @override
  int getNomTileHeight() => height;

  @override
  int getNomTileWidth() => width;

  @override
  int getNumComps() => 1;

  @override
  int getNumTiles() => 1;

  @override
  Coord getNumTilesCoord(Coord? reuse) {
    final coord = reuse ?? Coord(0, 0);
    coord
      ..x = 1
      ..y = 1;
    return coord;
  }

  @override
  SubbandAn getAnSubbandTree(int t, int c) {
    return _leafSubband(width: width, height: height);
  }

  @override
  CBlkWTData? getNextCodeBlock(int c, CBlkWTData? cblk) => null;

  @override
  CBlkWTData? getNextInternCodeBlock(int c, CBlkWTData? cblk) => null;

  @override
  Coord getTile(Coord? reuse) {
    final coord = reuse ?? Coord(0, 0);
    coord
      ..x = 0
      ..y = 0;
    return coord;
  }

  @override
  int getTileCompHeight(int tile, int component) => height;

  @override
  int getTileCompWidth(int tile, int component) => width;

  @override
  int getTileHeight() => height;

  @override
  int getTileIdx() => 0;

  @override
  int getTilePartULX() => 0;

  @override
  int getTilePartULY() => 0;

  @override
  int getTileWidth() => width;

  @override
  bool isReversible(int t, int c) => true;

  @override
  void nextTile() {}

  @override
  void setTile(int x, int y) {}
}

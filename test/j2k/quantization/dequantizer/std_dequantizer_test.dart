import 'dart:typed_data';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/decoder/DecoderSpecs.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlk.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/CBlkQuantDataSrcDec.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/StdDequantizer.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/StdDequantizerParams.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SubbandSyn.dart';

void main() {
  group('StdDequantizer', () {
    test('initialises subband magnitude bits from guard bits and gain', () {
      final src = _StubQuantDataSrcDec();
      final specs = DecoderSpecs.basic(1, 1);
      specs.qsss.setTileCompVal(
        0,
        0,
        StdDequantizerParams(
          exp: <List<int>>[<int>[7]],
          nStep: <List<double>>[<double>[1.0]],
        ),
      );
      specs.gbs.setTileCompVal(0, 0, 1);

      final dequantizer = StdDequantizer(src, <int>[8], specs);

      dequantizer.setTile(0, 0);
      expect(src.root.magBits, equals(0));

      final result = dequantizer.getCodeBlock(
        0,
        0,
        0,
        src.root,
        DataBlkInt(),
      ) as DataBlkInt;

      expect(result.getDataInt(), isNotNull);
      expect(src.root.magBits, equals(9));
    });

    test('prefers exponent table when available', () {
      final src = _StubQuantDataSrcDec();
      final specs = DecoderSpecs.basic(1, 1);
      specs.qts.setTileCompVal(0, 0, 'expounded');
      specs.qsss.setTileCompVal(
        0,
        0,
        StdDequantizerParams(
          exp: <List<int>>[
            <int>[0, 0, 0],
            <int>[0, 12, 0],
          ],
          nStep: <List<double>>[
            <double>[1.0],
            <double>[1.0, 1.0, 1.0],
          ],
        ),
      );
      specs.gbs.setTileCompVal(0, 0, 1);

      final dequantizer = StdDequantizer(src, <int>[8], specs)
        ..setTile(0, 0);

      final subband = _makeSubband(resLvl: 1, sbandIdx: 1);
      expect(subband.magBits, equals(0));

      dequantizer.getCodeBlock(0, 0, 0, subband, DataBlkInt());

      expect(subband.magBits, equals(13));
    });

    test('derives exponent fallback from LL subband', () {
      final src = _StubQuantDataSrcDec();
      final specs = DecoderSpecs.basic(1, 1);
      specs.qts.setTileCompVal(0, 0, 'derived');
      specs.qsss.setTileCompVal(
        0,
        0,
        StdDequantizerParams(
          exp: <List<int>>[
            <int>[10],
          ],
          nStep: <List<double>>[
            <double>[1.0],
          ],
        ),
      );
      specs.gbs.setTileCompVal(0, 0, 2);

      final dequantizer = StdDequantizer(src, <int>[7], specs)
        ..setTile(0, 0);

      final subband = _makeSubband(resLvl: 2, sbandIdx: 3, anGainExp: 1);
      expect(subband.magBits, equals(0));

      dequantizer.getCodeBlock(0, 0, 0, subband, DataBlkInt());

      expect(subband.magBits, equals(12));
    });
  });
}

SubbandSyn _makeSubband({
  required int resLvl,
  required int sbandIdx,
  int anGainExp = 0,
}) {
  final subband = SubbandSyn()
    ..isNode = false
    ..orientation = 0
    ..level = resLvl
    ..resLvl = resLvl
    ..sbandIdx = sbandIdx
    ..anGainExp = anGainExp
    ..ulx = 0
    ..uly = 0
    ..w = 1
    ..h = 1
    ..nomCBlkW = 1
    ..nomCBlkH = 1
    ..numCb = Coord(1, 1)
    ..magBits = 0;
  return subband;
}

class _StubQuantDataSrcDec extends CBlkQuantDataSrcDec {
  _StubQuantDataSrcDec()
      : block = DataBlkInt.withGeometry(0, 0, 1, 1),
        root = SubbandSyn() {
    block.setDataInt(Int32List.fromList(<int>[0]));
    block.progressive = false;
    root
      ..isNode = false
      ..orientation = 0
      ..level = 0
      ..resLvl = 0
      ..anGainExp = 0
      ..sbandIdx = 0
      ..ulx = 0
      ..uly = 0
      ..w = 1
      ..h = 1
      ..nomCBlkW = 1
      ..nomCBlkH = 1
      ..numCb = Coord(1, 1)
      ..magBits = 0;
  }

  final DataBlkInt block;
  final SubbandSyn root;
  int _tileIdx = 0;

  @override
  int getNumComps() => 1;

  @override
  int getNomRangeBits(int component) => 8;

  @override
  int getCbULX() => 0;

  @override
  int getCbULY() => 0;

  @override
  DataBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? reusable,
  ) {
    final DataBlkInt target = reusable is DataBlkInt ? reusable : DataBlkInt();
    target
      ..ulx = 0
      ..uly = 0
      ..w = block.w
      ..h = block.h
      ..offset = 0
      ..scanw = block.w
      ..progressive = false
      ..setDataInt(Int32List.fromList(block.getDataInt() ?? const <int>[]));
    return target;
  }

  @override
  DataBlk getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? reusable,
  ) {
    return getCodeBlock(
      component,
      verticalCodeBlockIndex,
      horizontalCodeBlockIndex,
      subband,
      reusable,
    );
  }

  @override
  void setTile(int x, int y) {
    _tileIdx = 0;
  }

  @override
  void nextTile() {}

  @override
  Coord getTile(Coord? reuse) {
    final coord = reuse ?? Coord();
    coord
      ..x = 0
      ..y = 0;
    return coord;
  }

  @override
  int getTileIdx() => _tileIdx;

  @override
  int getTileWidth(int resLevel) => block.w;

  @override
  int getTileHeight(int resLevel) => block.h;

  @override
  int getNomTileWidth() => block.w;

  @override
  int getNomTileHeight() => block.h;

  @override
  int getImgWidth(int resLevel) => block.w;

  @override
  int getImgHeight(int resLevel) => block.h;

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getTileCompWidth(int tile, int component, int resLevel) => block.w;

  @override
  int getTileCompHeight(int tile, int component, int resLevel) => block.h;

  @override
  int getCompImgWidth(int component, int resLevel) => block.w;

  @override
  int getCompImgHeight(int component, int resLevel) => block.h;

  @override
  int getResULX(int component, int resLevel) => 0;

  @override
  int getResULY(int component, int resLevel) => 0;

  @override
  int getImgULX(int resLevel) => 0;

  @override
  int getImgULY(int resLevel) => 0;

  @override
  int getTilePartULX() => 0;

  @override
  int getTilePartULY() => 0;

  @override
  Coord getNumTiles(Coord? reuse) {
    final coord = reuse ?? Coord();
    coord
      ..x = 1
      ..y = 1;
    return coord;
  }

  @override
  int getNumTilesTotal() => 1;

  @override
  SubbandSyn getSynSubbandTree(int tile, int component) => root;
}



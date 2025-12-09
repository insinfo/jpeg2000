import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/decoder/DecoderSpecs.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlk.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkFloat.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/InvCompTransf.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/CBlkQuantDataSrcDec.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/StdDequantizer.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/StdDequantizerParams.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SubbandSyn.dart';
import 'package:test/test.dart';

class MockCBlkQuantDataSrcDec implements CBlkQuantDataSrcDec {
  final List<int> data;
  final int w;
  final int h;

  MockCBlkQuantDataSrcDec(this.data, this.w, this.h);

  @override
  DataBlk getCodeBlock(int c, int m, int n, SubbandSyn sb, DataBlk? cblk) {
    return getInternCodeBlock(c, m, n, sb, cblk);
  }

  @override
  DataBlk getInternCodeBlock(
      int c, int m, int n, SubbandSyn sb, DataBlk? cblk) {
    if (cblk == null) cblk = DataBlkInt();
    cblk.w = w;
    cblk.h = h;
    cblk.ulx = 0;
    cblk.uly = 0;
    cblk.offset = 0;
    cblk.scanw = w;
    cblk.progressive = false;
    cblk.setData(Int32List.fromList(data));
    return cblk;
  }

  @override
  int getNomRangeBits(int c) => 8;
  @override
  SubbandSyn getSynSubbandTree(int t, int c) => SubbandSyn();
  @override
  int getNumComps() => 1;

  int getFixedPoint(int c) => 0;

  @override
  int getTileWidth(int rl) => w;
  @override
  int getTileHeight(int rl) => h;
  @override
  int getNomTileWidth() => w;
  @override
  int getNomTileHeight() => h;
  @override
  int getImgWidth(int rl) => w;
  @override
  int getImgHeight(int rl) => h;
  @override
  int getCompSubsX(int c) => 1;
  @override
  int getCompSubsY(int c) => 1;
  @override
  int getTileCompWidth(int t, int c, int rl) => w;
  @override
  int getTileCompHeight(int t, int c, int rl) => h;
  @override
  int getCompImgWidth(int c, int rl) => w;
  @override
  int getCompImgHeight(int c, int rl) => h;
  @override
  void setTile(int x, int y) {}
  @override
  void nextTile() {}
  @override
  Coord getTile(Coord? c) => c ?? Coord(0, 0);
  @override
  int getTileIdx() => 0;
  @override
  int getTilePartULX() => 0;
  @override
  int getTilePartULY() => 0;
  int getCompULX(int c) => 0;
  int getCompULY(int c) => 0;
  @override
  int getImgULX(int rl) => 0;
  @override
  int getImgULY(int rl) => 0;
  @override
  Coord getNumTiles(Coord? c) => c ?? Coord(1, 1);
  @override
  int getNumTilesTotal() => 1;

  @override
  int getCbULX() => 0;

  @override
  int getCbULY() => 0;

  @override
  int getResULX(int c, int rl) => 0;
  @override
  int getResULY(int c, int rl) => 0;
}

void main() {
  test('StdDequantizer Irreversible Test', () {
    int w = 2;
    int h = 2;
    // Input data in Sign-Magnitude representation
    // 10 -> 10
    // -10 -> 10 | 0x80000000
    // 20 -> 20
    // -20 -> 20 | 0x80000000
    List<int> inputData = [10, 10 | 0x80000000, 20, 20 | 0x80000000];
    var src = MockCBlkQuantDataSrcDec(inputData, w, h);

    // Setup DecoderSpecs
    int nTiles = 1;
    int nComps = 1;
    var decSpec = DecoderSpecs.basic(nTiles, nComps);

    // 1. QuantTypeSpec: Irreversible (Scalar Expounded)
    decSpec.qts.setDefault("expounded");

    // Set default Component Transformation to NONE
    decSpec.cts.setDefault(InvCompTransf.none);

    // 2. QuantStepSizeSpec
    var params = StdDequantizerParams(
      exp: [
        [0]
      ], // 1 resolution level, 1 subband (LL)
      nStep: [
        [0.001]
      ],
    );

    decSpec.qsss.setDefault(params);

    // 3. GuardBitsSpec
    decSpec.gbs.setDefault(2);

    List<int> utrb = [8]; // 8 bits range

    var deq = StdDequantizer(src, utrb, decSpec);
    deq.setTile(0, 0); // Initialize rb

    // Setup SubbandSyn
    var sb = SubbandSyn();
    sb.resLvl = 0;
    sb.sbandIdx = 0;
    sb.anGainExp = 0;
    sb.magBits = 31; // Magnitude bits
    sb.level = 0;

    var outBlk = DataBlkFloat();
    deq.getInternCodeBlock(0, 0, 0, sb, outBlk);

    var outData = outBlk.getDataFloat()!;

    // print("Dequantizer Output:");
    // for (var v in outData) {
    //   print("$v ");
    // }

    expect(outData[0], closeTo(2.56, 0.0001));
    expect(outData[1], closeTo(-2.56, 0.0001));
    expect(outData[2], closeTo(5.12, 0.0001));
    expect(outData[3], closeTo(-5.12, 0.0001));
  });
}



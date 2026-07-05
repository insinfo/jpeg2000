import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/image/blk_img_data_src.dart';
import 'package:jpeg2000/src/j2k/image/comp_transf_spec.dart';
import 'package:jpeg2000/src/j2k/image/coord.dart';
import 'package:jpeg2000/src/j2k/image/data_blk.dart';
import 'package:jpeg2000/src/j2k/image/data_blk_float.dart';
import 'package:jpeg2000/src/j2k/image/data_blk_int.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/inv_comp_transf.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/inv_component_transformer.dart';
import 'package:test/test.dart';

class MockBlkImgDataSrc implements BlkImgDataSrc {
  final int w;
  final int h;
  final int numComps;
  final List<List<int>> dataInt;
  final List<List<double>> dataFloat;

  MockBlkImgDataSrc({
    required this.w,
    required this.h,
    required this.numComps,
    this.dataInt = const [],
    this.dataFloat = const [],
  });

  @override
  int getFixedPoint(int c) => 0;

  @override
  DataBlk getInternCompData(DataBlk blk, int c) {
    return getCompData(blk, c);
  }

  @override
  DataBlk getCompData(DataBlk blk, int c) {
    if (blk is DataBlkInt) {
      blk.w = w;
      blk.h = h;
      blk.ulx = 0;
      blk.uly = 0;
      blk.offset = 0;
      blk.scanw = w;
      blk.progressive = false;

      final required = w * h;
      var arr = blk.getDataInt();
      if (arr == null || arr.length < required) {
        arr = Int32List(required);
        blk.setDataInt(arr);
      }

      if (dataInt.isNotEmpty) {
        for (var i = 0; i < required; i++) {
          arr[i] = dataInt[c][i];
        }
      }
      return blk;
    } else if (blk is DataBlkFloat) {
      blk.w = w;
      blk.h = h;
      blk.ulx = 0;
      blk.uly = 0;
      blk.offset = 0;
      blk.scanw = w;
      blk.progressive = false;

      final required = w * h;
      var arr = blk.getDataFloat();
      if (arr == null || arr.length < required) {
        arr = Float32List(required);
        blk.setDataFloat(arr);
      }

      if (dataFloat.isNotEmpty) {
        for (var i = 0; i < required; i++) {
          arr[i] = dataFloat[c][i];
        }
      }
      return blk;
    }
    throw ArgumentError('Unsupported DataBlk type: ${blk.runtimeType}');
  }

  @override
  int getNumComps() => numComps;

  @override
  int getTileIdx() => 0;

  @override
  int getTileWidth() => w;

  @override
  int getTileHeight() => h;

  @override
  int getNomTileWidth() => w;

  @override
  int getNomTileHeight() => h;

  @override
  int getImgWidth() => w;

  @override
  int getImgHeight() => h;

  @override
  int getImgULX() => 0;

  @override
  int getImgULY() => 0;

  @override
  int getCompSubsX(int c) => 1;

  @override
  int getCompSubsY(int c) => 1;

  @override
  int getTileCompWidth(int t, int c) => w;

  @override
  int getTileCompHeight(int t, int c) => h;

  @override
  int getCompImgWidth(int c) => w;

  @override
  int getCompImgHeight(int c) => h;

  @override
  int getCompULX(int c) => 0;

  @override
  int getCompULY(int c) => 0;

  @override
  void setTile(int x, int y) {}

  @override
  void nextTile() {}

  @override
  Coord getTile(Coord? c) => Coord(0, 0);

  @override
  int getNomRangeBits(int c) => 8;

  @override
  int getTilePartULX() => 0;

  @override
  int getTilePartULY() => 0;

  @override
  Coord getNumTilesCoord(Coord? c) {
    if (c != null) {
      c.x = 1;
      c.y = 1;
      return c;
    } else {
      return Coord(1, 1);
    }
  }

  @override
  int getNumTiles() => 1;
}

// Mock CompTransfSpec
class MockCompTransfSpec extends CompTransfSpec {
  MockCompTransfSpec(int nComp, int nTiles, int type)
      : super(nTiles, nComp, 1) {
    _type = type;
  }

  int _type = InvCompTransf.none;

  @override
  int? getSpec(int t, int c) {
    return _type;
  }
}

void main() {
  group('InvCompTransf Tests', () {
    test('RCT Transformation', () {
      final w = 2;
      final h = 1;
      final numComps = 3;

      final yData = [100, 76];
      final cbData = [0, -25];
      final crData = [0, 100];

      final src = MockBlkImgDataSrc(
        w: w,
        h: h,
        numComps: numComps,
        dataInt: [yData, cbData, crData],
      );

      final cts = MockCompTransfSpec(numComps, 1, InvCompTransf.invRct);

      final trans = InvCompTransfImgDataSrc(src, cts);

      // Check Component 0 (R)
      var blk = DataBlkInt();
      blk.w = w;
      blk.h = h;
      blk = trans.getCompData(blk, 0) as DataBlkInt;
      var data = blk.getDataInt()!;
      expect(data[0], equals(100));
      expect(data[1], equals(158));

      // Check Component 1 (G)
      blk = trans.getCompData(blk, 1) as DataBlkInt;
      data = blk.getDataInt()!;
      expect(data[0], equals(100));
      expect(data[1], equals(58));

      // Check Component 2 (B)
      blk = trans.getCompData(blk, 2) as DataBlkInt;
      data = blk.getDataInt()!;
      expect(data[0], equals(100));
      expect(data[1], equals(33));
    });

    test('ICT Transformation', () {
      final w = 1;
      final h = 1;
      final numComps = 3;

      // Y = 100, Cb = 10, Cr = 20
      final yData = [100.0];
      final cbData = [10.0];
      final crData = [20.0];

      final src = MockBlkImgDataSrc(
        w: w,
        h: h,
        numComps: numComps,
        dataFloat: [yData, cbData, crData],
      );

      final cts = MockCompTransfSpec(numComps, 1, InvCompTransf.invIct);

      final trans = InvCompTransfImgDataSrc(src, cts);

      // Check Component 0 (R)
      // Java: 128
      var blk = DataBlkInt();
      blk.w = w;
      blk.h = h;

      // Mirrors JJ2000: invICT produces integer samples via (int)(x + 0.5f).
      var result = trans.getCompData(blk, 0);

      if (result is DataBlkInt) {
        var data = result.getDataInt()!;
        // 100 + 1.402*20 = 128.04 -> 128
        expect(data[0], equals(128));
      } else {
        fail("ICT should return DataBlkInt");
      }

      // Check Component 1 (G)
      // Java: 82
      result = trans.getCompData(blk, 1);
      if (result is DataBlkInt) {
        var data = result.getDataInt()!;
        // 100 - 0.34413*10 - 0.71414*20 = 82.27 -> 82
        expect(data[0], equals(82));
      } else {
        fail("ICT should return DataBlkInt");
      }

      // Check Component 2 (B)
      // Java: 118
      result = trans.getCompData(blk, 2);
      if (result is DataBlkInt) {
        var data = result.getDataInt()!;
        // 100 + 1.772*10 = 117.72 -> 118
        expect(data[0], equals(118));
      } else {
        fail("ICT should return DataBlkInt");
      }
    });
  });
}

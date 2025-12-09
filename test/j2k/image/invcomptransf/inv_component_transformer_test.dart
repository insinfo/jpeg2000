import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/image/BlkImgDataSrc.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlk.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkFloat.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';
import 'package:jpeg2000/src/j2k/image/CompTransfSpec.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/InvComponentTransformer.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/InvCompTransf.dart';
import 'package:jpeg2000/src/j2k/ModuleSpec.dart';

void main() {
  group('InvCompTransfImgDataSrc', () {
    test('applies reversible component transform', () {
      final spec = CompTransfSpec(1, 3, ModuleSpec.SPEC_TYPE_TILE)
        ..setDefault(InvCompTransf.invRct);
      final source = _RctStub();
      final transformer = InvCompTransfImgDataSrc(source, spec);

      final r = transformer.getInternCompData(
        DataBlkInt()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 2,
        0,
      ) as DataBlkInt;
      final g = transformer.getInternCompData(
        DataBlkInt()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 2,
        1,
      ) as DataBlkInt;
      final b = transformer.getInternCompData(
        DataBlkInt()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 2,
        2,
      ) as DataBlkInt;

      expect(r.getDataInt(), equals(<int>[45, 70, 35, 15]));
      expect(g.getDataInt(), equals(<int>[30, 55, 25, 10]));
      expect(b.getDataInt(), equals(<int>[20, 45, 30, 5]));
    });

    test('applies irreversible component transform', () {
      final spec = CompTransfSpec(1, 3, ModuleSpec.SPEC_TYPE_TILE)
        ..setDefault(InvCompTransf.invIct);
      final source = _IctStub();
      final transformer = InvCompTransfImgDataSrc(source, spec);

      final r = transformer.getInternCompData(
        DataBlkFloat()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 1,
        0,
      ) as DataBlkFloat;
      final g = transformer.getInternCompData(
        DataBlkFloat()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 1,
        1,
      ) as DataBlkFloat;
      final b = transformer.getInternCompData(
        DataBlkFloat()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 1,
        2,
      ) as DataBlkFloat;

      expect(r.getDataFloat(), closeToList(<double>[255.0, 64.0]));
      expect(g.getDataFloat(), closeToList(<double>[128.0, 128.0]));
      expect(b.getDataFloat(), closeToList(<double>[64.0, 32.0]));
    });
  });
}

Matcher closeToList(List<double> expected, {double epsilon = 1e-3}) {
  return predicate<List<double>>((actual) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var i = 0; i < expected.length; i++) {
      if ((actual[i] - expected[i]).abs() > epsilon) {
        return false;
      }
    }
    return true;
  }, 'matches $expected within ±$epsilon');
}

class _RctStub implements BlkImgDataSrc {
  _RctStub()
      : y = <int>[
          31,
          56,
          28,
          10,
        ],
        cb = <int>[
          -10,
          -10,
          5,
          -5,
        ],
        cr = <int>[
          15,
          15,
          10,
          5,
        ];

  final List<int> y;
  final List<int> cb;
  final List<int> cr;

  @override
  int getFixedPoint(int component) => 0;

  @override
  DataBlk getCompData(DataBlk block, int component) =>
      getInternCompData(block, component);

  @override
  DataBlk getInternCompData(DataBlk block, int component) {
    final data = _select(component);
    final DataBlkInt out = block is DataBlkInt ? block : DataBlkInt();
    out
      ..ulx = 0
      ..uly = 0
      ..w = 2
      ..h = 2
      ..offset = 0
      ..scanw = 2
      ..progressive = false
      ..setDataInt(Int32List.fromList(data));
    return out;
  }

  List<int> _select(int component) {
    switch (component) {
      case 0:
        return y;
      case 1:
        return cb;
      case 2:
        return cr;
      default:
        return <int>[0, 0, 0, 0];
    }
  }

  @override
  int getTileWidth() => 2;

  @override
  int getTileHeight() => 2;

  @override
  int getNomTileWidth() => 2;

  @override
  int getNomTileHeight() => 2;

  @override
  int getImgWidth() => 2;

  @override
  int getImgHeight() => 2;

  @override
  int getNumComps() => 3;

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getTileCompWidth(int tile, int component) => 2;

  @override
  int getTileCompHeight(int tile, int component) => 2;

  @override
  int getCompImgWidth(int component) => 2;

  @override
  int getCompImgHeight(int component) => 2;

  @override
  void setTile(int x, int y) {}

  @override
  void nextTile() {}

  @override
  Coord getTile(Coord? reuse) => (reuse ?? Coord())
    ..x = 0
    ..y = 0;

  @override
  int getTileIdx() => 0;

  @override
  int getNomRangeBits(int component) => 8;

  @override
  int getCompULX(int component) => 0;

  @override
  int getCompULY(int component) => 0;

  @override
  int getTilePartULX() => 0;

  @override
  int getTilePartULY() => 0;

  @override
  int getImgULX() => 0;

  @override
  int getImgULY() => 0;

  @override
  Coord getNumTilesCoord(Coord? reuse) => (reuse ?? Coord())
    ..x = 1
    ..y = 1;

  @override
  int getNumTiles() => 1;
}

class _IctStub implements BlkImgDataSrc {
  _IctStub()
      : y = Float32List.fromList(<double>[158.677, 97.92]),
        cb = Float32List.fromList(<double>[-53.42933, -37.19808]),
        cr = Float32List.fromList(<double>[68.70384, -24.19424]);

  final Float32List y;
  final Float32List cb;
  final Float32List cr;

  @override
  int getFixedPoint(int component) => 0;

  @override
  DataBlk getCompData(DataBlk block, int component) =>
      getInternCompData(block, component);

  @override
  DataBlk getInternCompData(DataBlk block, int component) {
    final data = _select(component);
    final DataBlkFloat out = block is DataBlkFloat ? block : DataBlkFloat();
    out
      ..ulx = 0
      ..uly = 0
      ..w = data.length
      ..h = 1
      ..offset = 0
      ..scanw = data.length
      ..progressive = false
      ..setDataFloat(Float32List.fromList(List<double>.from(data)));
    return out;
  }

  Float32List _select(int component) {
    switch (component) {
      case 0:
        return y;
      case 1:
        return cb;
      case 2:
        return cr;
      default:
        return Float32List(0);
    }
  }

  @override
  int getTileWidth() => y.length;

  @override
  int getTileHeight() => 1;

  @override
  int getNomTileWidth() => y.length;

  @override
  int getNomTileHeight() => 1;

  @override
  int getImgWidth() => y.length;

  @override
  int getImgHeight() => 1;

  @override
  int getNumComps() => 3;

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getTileCompWidth(int tile, int component) => y.length;

  @override
  int getTileCompHeight(int tile, int component) => 1;

  @override
  int getCompImgWidth(int component) => y.length;

  @override
  int getCompImgHeight(int component) => 1;

  @override
  void setTile(int x, int y) {}

  @override
  void nextTile() {}

  @override
  Coord getTile(Coord? reuse) => (reuse ?? Coord())
    ..x = 0
    ..y = 0;

  @override
  int getTileIdx() => 0;

  @override
  int getNomRangeBits(int component) => 8;

  @override
  int getCompULX(int component) => 0;

  @override
  int getCompULY(int component) => 0;

  @override
  int getTilePartULX() => 0;

  @override
  int getTilePartULY() => 0;

  @override
  int getImgULX() => 0;

  @override
  int getImgULY() => 0;

  @override
  Coord getNumTilesCoord(Coord? reuse) => (reuse ?? Coord())
    ..x = 1
    ..y = 1;

  @override
  int getNumTiles() => 1;
}


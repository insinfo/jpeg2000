import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/image/blk_img_data_src.dart';
import 'package:jpeg2000/src/j2k/image/coord.dart';
import 'package:jpeg2000/src/j2k/image/data_blk.dart';
import 'package:jpeg2000/src/j2k/image/data_blk_float.dart';
import 'package:jpeg2000/src/j2k/image/data_blk_int.dart';
import 'package:jpeg2000/src/j2k/image/comp_transf_spec.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/inv_component_transformer.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/inv_comp_transf.dart';
import 'package:jpeg2000/src/j2k/module_spec.dart';

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

    test('reports original component bit depths after inverse RCT', () {
      final spec = CompTransfSpec(1, 3, ModuleSpec.SPEC_TYPE_TILE)
        ..setDefault(InvCompTransf.invRct);
      final source = _RctStub(bitDepths: const <int>[8, 9, 9]);
      final transformer = InvCompTransfImgDataSrc(
        source,
        spec,
        originalBitDepths: const <int>[8, 8, 8],
      );

      expect(source.getNomRangeBits(1), 9);
      expect(transformer.getNomRangeBits(0), 8);
      expect(transformer.getNomRangeBits(1), 8);
      expect(transformer.getNomRangeBits(2), 8);
    });

    test('applies irreversible component transform', () {
      final spec = CompTransfSpec(1, 3, ModuleSpec.SPEC_TYPE_TILE)
        ..setDefault(InvCompTransf.invIct);
      final source = _IctStub();
      final transformer = InvCompTransfImgDataSrc(source, spec);

      // Mirrors JJ2000: invICT always produces integer samples, rounded
      // with (int)(x + 0.5f).
      final r = transformer.getInternCompData(
        DataBlkInt()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 1,
        0,
      ) as DataBlkInt;
      final g = transformer.getInternCompData(
        DataBlkInt()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 1,
        1,
      ) as DataBlkInt;
      final b = transformer.getInternCompData(
        DataBlkInt()
          ..ulx = 0
          ..uly = 0
          ..w = 2
          ..h = 1,
        2,
      ) as DataBlkInt;

      expect(r.getDataInt(), equals(<int>[255, 64]));
      expect(g.getDataInt(), equals(<int>[128, 128]));
      expect(b.getDataInt(), equals(<int>[64, 32]));
    });

    test('ICT blue channel ignores Cr term like JJ2000', () {
      final spec = CompTransfSpec(1, 3, ModuleSpec.SPEC_TYPE_TILE)
        ..setDefault(InvCompTransf.invIct);
      final source = _IctStub(
        yValues: const <double>[100],
        cbValues: const <double>[0],
        crValues: const <double>[10000],
      );
      final transformer = InvCompTransfImgDataSrc(source, spec);

      final b = transformer.getInternCompData(
        DataBlkInt()
          ..ulx = 0
          ..uly = 0
          ..w = 1
          ..h = 1,
        2,
      ) as DataBlkInt;

      expect(b.getDataInt(), equals(<int>[100]));
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
  _RctStub({List<int>? bitDepths})
      : bitDepths = bitDepths ?? const <int>[8, 8, 8],
        y = <int>[
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
  final List<int> bitDepths;

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
  int getNomRangeBits(int component) => bitDepths[component];

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
  _IctStub({
    List<double>? yValues,
    List<double>? cbValues,
    List<double>? crValues,
  })  : y = Float32List.fromList(yValues ?? <double>[158.677, 97.92]),
        cb = Float32List.fromList(cbValues ?? <double>[-53.42933, -37.19808]),
        cr = Float32List.fromList(crValues ?? <double>[68.70384, -24.19424]);

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

import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/decoder/DecoderSpecs.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlk.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/CBlkWTDataSrcDec.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/InverseWT.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SubbandSyn.dart';

void main() {
  group('InvWTFull', () {
    test('reconstructs single-leaf subband from code-block data', () {
      final width = 4;
      final height = 4;
      final samples = List<int>.generate(width * height, (index) => index + 1);

      final decoderSpecs = DecoderSpecs.basic(1, 1);
      final src = _StubCBlkWTDataSrcDec(width, height, samples);

      final inverse = InverseWT.createInstance(src, decoderSpecs);
      inverse.setTile(0, 0);

      final request = DataBlkInt()
        ..ulx = 0
        ..uly = 0
        ..w = width
        ..h = height;
      final result = inverse.getCompData(request, 0) as DataBlkInt;

      expect(result.progressive, isFalse);
      expect(result.scanw, width);
      expect(result.offset, 0);
      expect(result.getData(), orderedEquals(samples));
    });
  });
}

class _StubCBlkWTDataSrcDec extends CBlkWTDataSrcDec {
  _StubCBlkWTDataSrcDec(this.width, this.height, List<int> values)
      : data = List<int>.from(values) {
    _root = SubbandSyn()
      ..isNode = false
      ..orientation = 0
      ..level = 0
      ..resLvl = 0
      ..ulx = 0
      ..uly = 0
      ..ulcx = 0
      ..ulcy = 0
      ..w = width
      ..h = height
      ..nomCBlkW = width
      ..nomCBlkH = height
      ..numCb = Coord(1, 1)
      ..magBits = 8;
  }

  final int width;
  final int height;
  final List<int> data;
  late final SubbandSyn _root;
  int _tileIdx = 0;
  int _tileX = 0;
  int _tileY = 0;

  @override
  int getNomRangeBits(int component) => 8;

  @override
  int getFixedPoint(int component) => 0;

  @override
  int getCbULX() => 0;

  @override
  int getCbULY() => 0;

  @override
  int getTileWidth(int resLevel) => width;

  @override
  int getTileHeight(int resLevel) => height;

  @override
  int getNomTileWidth() => width;

  @override
  int getNomTileHeight() => height;

  @override
  int getImgWidth(int resLevel) => width;

  @override
  int getImgHeight(int resLevel) => height;

  @override
  int getNumComps() => 1;

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getTileCompWidth(int tile, int component, int resLevel) => width;

  @override
  int getTileCompHeight(int tile, int component, int resLevel) => height;

  @override
  int getCompImgWidth(int component, int resLevel) => width;

  @override
  int getCompImgHeight(int component, int resLevel) => height;

  @override
  void setTile(int x, int y) {
    _tileX = x;
    _tileY = y;
    _tileIdx = y * 1 + x;
  }

  @override
  void nextTile() {
    _tileIdx = (_tileIdx + 1) % getNumTilesTotal();
    _tileX = _tileIdx % 1;
    _tileY = _tileIdx ~/ 1;
  }

  @override
  Coord getTile(Coord? reuse) {
    final coord = reuse ?? Coord();
    coord
      ..x = _tileX
      ..y = _tileY;
    return coord;
  }

  @override
  int getTileIdx() => _tileIdx;

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
  SubbandSyn getSynSubbandTree(int tile, int component) => _root;

  @override
  DataBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) {
    final DataBlkInt result;
    if (block is DataBlkInt) {
      result = block;
      var buffer = result.getData() as List<int>?;
      if (buffer == null || buffer.length < data.length) {
        buffer = Int32List.fromList(data);
        result.setData(buffer);
      } else {
        for (var i = 0; i < data.length; i++) {
          buffer[i] = data[i];
        }
      }
    } else {
      result = DataBlkInt.withGeometry(0, 0, width, height)
        ..setData(Int32List.fromList(data));
    }

    result
      ..ulx = 0
      ..uly = 0
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = false;
    return result;
  }

  @override
  DataBlk getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) {
    final DataBlkInt result;
    if (block is DataBlkInt) {
      result = block;
      var buffer = result.getData() as List<int>?;
      if (buffer == null || buffer.length < data.length) {
        buffer = Int32List.fromList(data);
        result.setData(buffer);
      } else {
        for (var i = 0; i < data.length; i++) {
          buffer[i] = data[i];
        }
      }
    } else {
      result = DataBlkInt.withGeometry(0, 0, width, height)
        ..setData(Int32List.fromList(data));
    }

    result
      ..ulx = 0
      ..uly = 0
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = false;
    return result;
  }
}



import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/image/BlkImgDataSrc.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlk.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';
import 'package:jpeg2000/src/j2k/image/output/ImgWriterPgx.dart';

typedef _ComponentSamples = List<int>;

void main() {
  group('ImgWriterPgx', () {
    test('packs 16-bit unsigned samples', () {
      final source = _SingleTileSource(
        width: 2,
        height: 1,
        components: const <_ComponentSamples>[
          <int>[0, 32767],
        ],
        bitDepths: const <int>[16],
      );

      final tempDir = Directory.systemTemp.createTempSync('img_writer_pgx_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/component.pgx';

      final writer = ImgWriterPgx.fromPath(outputPath, source, 0, false);
      addTearDown(writer.close);

      writer.writeAll();
      writer.flush();
      writer.close();

      final bytes = File(outputPath).readAsBytesSync();
      final headerEnd = bytes.indexOf(0x0a) + 1;
      final header = ascii.decode(bytes.sublist(0, headerEnd));
      expect(header, equals('PG ML + 16 2 1\n'));

      final data = bytes.sublist(headerEnd);
      expect(data, equals(<int>[0x80, 0x00, 0xff, 0xff]));
    });
  });
}

class _SingleTileSource implements BlkImgDataSrc {
  _SingleTileSource({
    required this.width,
    required this.height,
    required List<_ComponentSamples> components,
    required List<int> bitDepths,
  })  : _components = components,
        _bitDepths = bitDepths {
    if (_components.isEmpty) {
      throw ArgumentError('At least one component is required.');
    }
    if (_components.length != _bitDepths.length) {
      throw ArgumentError('Bit depth metadata must align with components.');
    }
    for (final component in _components) {
      if (component.length != width * height) {
        throw ArgumentError('Component sample count must match image size.');
      }
    }
  }

  final int width;
  final int height;
  final List<_ComponentSamples> _components;
  final List<int> _bitDepths;

  @override
  int getTileWidth() => width;

  @override
  int getTileHeight() => height;

  @override
  int getNomTileWidth() => width;

  @override
  int getNomTileHeight() => height;

  @override
  int getImgWidth() => width;

  @override
  int getImgHeight() => height;

  @override
  int getNumComps() => _components.length;

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getTileCompWidth(int tile, int component) => width;

  @override
  int getTileCompHeight(int tile, int component) => height;

  @override
  int getCompImgWidth(int component) => width;

  @override
  int getCompImgHeight(int component) => height;

  @override
  int getNomRangeBits(int component) => _bitDepths[component];

  @override
  int getFixedPoint(int component) => 0;

  @override
  DataBlk getInternCompData(DataBlk block, int component) {
    final result = block is DataBlkInt ? block : DataBlkInt();
    final reqWidth = block.w;
    final reqHeight = block.h;
    final ulx = block.ulx;
    final uly = block.uly;

    final length = reqWidth * reqHeight;
    var payload = result.data;
    if (payload == null || payload.length < length) {
      payload = Int32List(length);
      result.data = payload;
    }

    for (var row = 0; row < reqHeight; row++) {
      for (var col = 0; col < reqWidth; col++) {
        final sampleIndex = (uly + row) * width + (ulx + col);
        payload[row * reqWidth + col] = _components[component][sampleIndex];
      }
    }

    result
      ..ulx = ulx
      ..uly = uly
      ..w = reqWidth
      ..h = reqHeight
      ..offset = 0
      ..scanw = reqWidth
      ..progressive = false;
    return result;
  }

  @override
  DataBlk getCompData(DataBlk block, int component) =>
      getInternCompData(block, component);

  @override
  void setTile(int x, int y) {
    if (x != 0 || y != 0) {
      throw ArgumentError('Only tile (0,0) is available.');
    }
  }

  @override
  void nextTile() {
    throw UnsupportedError('Tile iteration not supported in fake source.');
  }

  @override
  Coord getTile(Coord? reuse) {
    final coord = reuse ?? Coord();
    coord
      ..x = 0
      ..y = 0;
    return coord;
  }

  @override
  int getTileIdx() => 0;

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
  Coord getNumTilesCoord(Coord? reuse) {
    final coord = reuse ?? Coord();
    coord
      ..x = 1
      ..y = 1;
    return coord;
  }

  @override
  int getNumTiles() => 1;
}


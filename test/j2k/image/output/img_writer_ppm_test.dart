import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/image/BlkImgDataSrc.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlk.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';
import 'package:jpeg2000/src/j2k/image/output/ImgWriterPpm.dart';

void main() {
  group('ImgWriterPpm', () {
    test('emits P6 header and saturates channel data', () {
      final source = _FakeRgbSource(
        width: 2,
        height: 1,
        samples: const <List<int>>[
          <int>[-128, 30],
          <int>[-64, 127],
          <int>[0, 140],
        ],
      );

      final tempDir = Directory.systemTemp.createTempSync('img_writer_ppm_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/output.ppm';

      final writer = ImgWriterPpm.fromPath(outputPath, source, 0, 1, 2);
      addTearDown(writer.close);

      writer.writeAll();
      writer.flush();
      writer.close();

      final bytes = File(outputPath).readAsBytesSync();
      final newline = '\n'.codeUnitAt(0);
      var headerEnd = 0;
      var newlineCount = 0;
      while (headerEnd < bytes.length && newlineCount < 3) {
        if (bytes[headerEnd] == newline) {
          newlineCount++;
        }
        headerEnd++;
      }

      final header = ascii.decode(bytes.sublist(0, headerEnd));
      expect(header, equals('P6\n2 1\n255\n'));

      final pixelBytes = bytes.sublist(headerEnd);
      expect(pixelBytes, equals(<int>[0, 64, 128, 158, 255, 255]));
    });
  });
}

class _FakeRgbSource implements BlkImgDataSrc {
  _FakeRgbSource({
    required this.width,
    required this.height,
    required List<List<int>> samples,
  }) : _samples = samples.map((component) => List<int>.from(component)).toList() {
    if (_samples.length != 3) {
      throw ArgumentError('Fake RGB source expects exactly 3 components.');
    }
    for (final component in _samples) {
      if (component.length != width * height) {
        throw ArgumentError('Component sample count does not match image size.');
      }
    }
  }

  final int width;
  final int height;
  final List<List<int>> _samples;

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
  int getNumComps() => 3;

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
  int getNomRangeBits(int component) => 8;

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
        payload[row * reqWidth + col] = _samples[component][sampleIndex];
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
      throw ArgumentError('Fake data source supports a single tile at (0,0).');
    }
  }

  @override
  void nextTile() {
    throw UnsupportedError('Tile iteration is not supported by the fake source.');
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


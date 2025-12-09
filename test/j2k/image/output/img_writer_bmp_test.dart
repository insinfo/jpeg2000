import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/image/BlkImgDataSrc.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlk.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';
import 'package:jpeg2000/src/j2k/image/output/ImgWriterBmp.dart';

void main() {
  group('ImgWriterBmp', () {
    test('writes 24-bit colour bitmap', () {
      final source = _StaticImageSource(
        width: 2,
        height: 1,
        components: const <List<int>>[
          <int>[127, -112], // R channel -> [255, 16]
          <int>[-128, -96], // G channel -> [0, 32]
          <int>[0, -64], // B channel -> [128, 64]
        ],
        bitDepths: const <int>[8, 8, 8],
        fixedPoints: const <int>[0, 0, 0],
      );

      final tempDir = Directory.systemTemp.createTempSync('img_writer_bmp_rgb_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/output.bmp';

      final writer = ImgWriterBmp.fromPath(outputPath, source);
      addTearDown(writer.close);

      writer.writeAll();
      writer.flush();
      writer.close();

      final bytes = File(outputPath).readAsBytesSync();
      final header = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 54)));

      expect(header.getUint16(0, Endian.little), equals(0x4d42));
      expect(header.getUint32(2, Endian.little), equals(54 + 8));
      expect(header.getUint32(10, Endian.little), equals(54));

      expect(header.getUint32(14, Endian.little), equals(40));
      expect(header.getInt32(18, Endian.little), equals(2));
      expect(header.getInt32(22, Endian.little), equals(-1));
      expect(header.getUint16(26, Endian.little), equals(1));
      expect(header.getUint16(28, Endian.little), equals(24));
      expect(header.getUint32(34, Endian.little), equals(8));

      final pixelData = bytes.sublist(54, 54 + 8);
      expect(
        pixelData,
        equals(<int>[128, 0, 255, 64, 32, 16, 0, 0]),
      );
    });

    test('writes 8-bit grayscale bitmap with palette', () {
      final source = _StaticImageSource(
        width: 4,
        height: 1,
        components: const <List<int>>[
          <int>[-128, -1, 0, 127], // -> [0, 127, 128, 255]
        ],
        bitDepths: const <int>[8],
        fixedPoints: const <int>[0],
      );

      final tempDir = Directory.systemTemp.createTempSync('img_writer_bmp_gray_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/output.bmp';

      final writer = ImgWriterBmp.fromPath(outputPath, source);
      addTearDown(writer.close);

      writer.writeAll();
      writer.flush();
      writer.close();

      final bytes = File(outputPath).readAsBytesSync();
      final header = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 54)));

      expect(header.getUint16(0, Endian.little), equals(0x4d42));
      expect(header.getUint32(2, Endian.little), equals(1078 + 4));
      expect(header.getUint32(10, Endian.little), equals(1078));
      expect(header.getUint16(28, Endian.little), equals(8));
      expect(header.getUint32(46, Endian.little), equals(256));

      final paletteStart = 54;
      final paletteEnd = 1078;
      expect(bytes.sublist(paletteStart, paletteStart + 4), equals(<int>[0, 0, 0, 0]));
      expect(bytes.sublist(paletteEnd - 4, paletteEnd), equals(<int>[255, 255, 255, 0]));

      final pixelData = bytes.sublist(1078, 1078 + 4);
      expect(pixelData, equals(<int>[0, 127, 128, 255]));
    });
  });
}

class _StaticImageSource implements BlkImgDataSrc {
  _StaticImageSource({
    required this.width,
    required this.height,
    required List<List<int>> components,
    required List<int> bitDepths,
    required List<int> fixedPoints,
  })  : _components = components,
        _bitDepths = bitDepths,
        _fixedPoints = fixedPoints {
    if (_components.isEmpty) {
      throw ArgumentError('At least one component is required.');
    }
    if (_components.length != _bitDepths.length ||
        _components.length != _fixedPoints.length) {
      throw ArgumentError('Metadata arrays must align with component count.');
    }
    for (final component in _components) {
      if (component.length != width * height) {
        throw ArgumentError('Component sample count must match image size.');
      }
    }
  }

  final int width;
  final int height;
  final List<List<int>> _components;
  final List<int> _bitDepths;
  final List<int> _fixedPoints;

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
  int getFixedPoint(int component) => _fixedPoints[component];

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


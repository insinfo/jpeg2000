import 'BlkImgDataSrc.dart';
import 'Coord.dart';
import 'DataBlk.dart';
import '../NoNextElementException.dart';

/// Aggregates multiple [BlkImgDataSrc] instances as separate components.
class ImgDataJoiner implements BlkImgDataSrc {
  ImgDataJoiner(List<BlkImgDataSrc> sources, List<int> componentIndices)
      : imageData = List<BlkImgDataSrc>.from(sources, growable: false),
        compIdx = List<int>.from(componentIndices, growable: false) {
    if (imageData.length != compIdx.length) {
      throw ArgumentError('sources and component indices must match in size');
    }
    nc = imageData.length;
    subsX = List<int>.filled(nc, 1, growable: false);
    subsY = List<int>.filled(nc, 1, growable: false);

    var maxWidth = 0;
    var maxHeight = 0;

    for (var i = 0; i < nc; i++) {
      final data = imageData[i];
      final component = compIdx[i];
      if (data.getNumTiles() != 1 ||
          data.getCompULX(component) != 0 ||
          data.getCompULY(component) != 0) {
        throw ArgumentError(
          'All inputs must be single-tile and originate at the canvas origin',
        );
      }
      maxWidth = maxWidth > data.getCompImgWidth(component)
          ? maxWidth
          : data.getCompImgWidth(component);
      maxHeight = maxHeight > data.getCompImgHeight(component)
          ? maxHeight
          : data.getCompImgHeight(component);
    }

    w = maxWidth;
    h = maxHeight;

    for (var i = 0; i < nc; i++) {
      final data = imageData[i];
      final component = compIdx[i];
      final compWidth = data.getCompImgWidth(component);
      final compHeight = data.getCompImgHeight(component);

      subsX[i] = (maxWidth + compWidth - 1) ~/ compWidth;
      subsY[i] = (maxHeight + compHeight - 1) ~/ compHeight;

      if ((maxWidth + subsX[i] - 1) ~/ subsX[i] != compWidth ||
          (maxHeight + subsY[i] - 1) ~/ subsY[i] != compHeight) {
        throw StateError('Unable to infer subsampling factors for component');
      }
    }
  }

  late final int w;
  late final int h;
  late final int nc;
  final List<BlkImgDataSrc> imageData;
  final List<int> compIdx;
  late final List<int> subsX;
  late final List<int> subsY;

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
  int getNumComps() => nc;

  @override
  int getCompSubsX(int component) => subsX[component];

  @override
  int getCompSubsY(int component) => subsY[component];

  @override
  int getTileCompWidth(int tile, int component) =>
      imageData[component].getTileCompWidth(tile, compIdx[component]);

  @override
  int getTileCompHeight(int tile, int component) =>
      imageData[component].getTileCompHeight(tile, compIdx[component]);

  @override
  int getCompImgWidth(int component) =>
      imageData[component].getCompImgWidth(compIdx[component]);

  @override
  int getCompImgHeight(int component) =>
      imageData[component].getCompImgHeight(compIdx[component]);

  @override
  int getNomRangeBits(int component) =>
      imageData[component].getNomRangeBits(compIdx[component]);

  @override
  int getFixedPoint(int component) =>
      imageData[component].getFixedPoint(compIdx[component]);

  @override
  DataBlk getInternCompData(DataBlk block, int component) =>
      imageData[component].getInternCompData(block, compIdx[component]);

  @override
  DataBlk getCompData(DataBlk block, int component) =>
      imageData[component].getCompData(block, compIdx[component]);

  @override
  void setTile(int x, int y) {
    if (x != 0 || y != 0) {
      throw ArgumentError('ImgDataJoiner does not support tiling');
    }
  }

  @override
  void nextTile() {
    throw NoNextElementException();
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

  @override
  String toString() {
    final buffer = StringBuffer('ImgDataJoiner: WxH = $w x $h');
    for (var i = 0; i < nc; i++) {
      buffer.writeln();
      buffer.write('- Component $i ${imageData[i]}');
    }
    return buffer.toString();
  }
}


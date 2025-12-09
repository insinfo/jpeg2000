import 'Coord.dart';
import 'ImgData.dart';

/// Default [ImgData] implementation that forwards calls to an underlying source.
class ImgDataAdapter implements ImgData {
  ImgDataAdapter(this.source);

  final ImgData source;

  int tileIndex = 0;

  @override
  int getTileWidth() => source.getTileWidth();

  @override
  int getTileHeight() => source.getTileHeight();

  @override
  int getNomTileWidth() => source.getNomTileWidth();

  @override
  int getNomTileHeight() => source.getNomTileHeight();

  @override
  int getImgWidth() => source.getImgWidth();

  @override
  int getImgHeight() => source.getImgHeight();

  @override
  int getNumComps() => source.getNumComps();

  @override
  int getCompSubsX(int component) => source.getCompSubsX(component);

  @override
  int getCompSubsY(int component) => source.getCompSubsY(component);

  @override
  int getTileCompWidth(int tile, int component) =>
      source.getTileCompWidth(tile, component);

  @override
  int getTileCompHeight(int tile, int component) =>
      source.getTileCompHeight(tile, component);

  @override
  int getCompImgWidth(int component) => source.getCompImgWidth(component);

  @override
  int getCompImgHeight(int component) => source.getCompImgHeight(component);

  @override
  int getNomRangeBits(int component) => source.getNomRangeBits(component);

  @override
  void setTile(int x, int y) {
    source.setTile(x, y);
    tileIndex = source.getTileIdx();
  }

  @override
  void nextTile() {
    source.nextTile();
    tileIndex = source.getTileIdx();
  }

  @override
  Coord getTile(Coord? reuse) => source.getTile(reuse);

  @override
  int getTileIdx() => source.getTileIdx();

  @override
  int getTilePartULX() => source.getTilePartULX();

  @override
  int getTilePartULY() => source.getTilePartULY();

  @override
  int getCompULX(int component) => source.getCompULX(component);

  @override
  int getCompULY(int component) => source.getCompULY(component);

  @override
  int getImgULX() => source.getImgULX();

  @override
  int getImgULY() => source.getImgULY();

  @override
  Coord getNumTilesCoord(Coord? reuse) => source.getNumTilesCoord(reuse);

  @override
  int getNumTiles() => source.getNumTiles();
}


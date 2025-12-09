import 'Coord.dart';

/// Interface for sources that expose tiling and component metadata.
abstract class ImgData {
  int getTileWidth();

  int getTileHeight();

  int getNomTileWidth();

  int getNomTileHeight();

  int getImgWidth();

  int getImgHeight();

  int getNumComps();

  int getCompSubsX(int component);

  int getCompSubsY(int component);

  int getTileCompWidth(int tile, int component);

  int getTileCompHeight(int tile, int component);

  int getCompImgWidth(int component);

  int getCompImgHeight(int component);

  int getNomRangeBits(int component);

  void setTile(int x, int y);

  void nextTile();

  Coord getTile(Coord? reuse);

  int getTileIdx();

  int getTilePartULX();

  int getTilePartULY();

  int getCompULX(int component);

  int getCompULY(int component);

  int getImgULX();

  int getImgULY();

  Coord getNumTilesCoord(Coord? reuse);

  int getNumTiles();
}

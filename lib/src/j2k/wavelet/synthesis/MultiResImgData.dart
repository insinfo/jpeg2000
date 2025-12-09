import '../../image/Coord.dart';
import 'SubbandSyn.dart';

/// Contract for data sources that expose multi-resolution imagery to the inverse wavelet stage.
abstract class MultiResImgData {
  int getTileWidth(int resLevel);
  int getTileHeight(int resLevel);
  int getNomTileWidth();
  int getNomTileHeight();
  int getImgWidth(int resLevel);
  int getImgHeight(int resLevel);
  int getNumComps();
  int getCompSubsX(int component);
  int getCompSubsY(int component);
  int getTileCompWidth(int tile, int component, int resLevel);
  int getTileCompHeight(int tile, int component, int resLevel);
  int getCompImgWidth(int component, int resLevel);
  int getCompImgHeight(int component, int resLevel);
  int getNomRangeBits(int component);
  void setTile(int x, int y);
  void nextTile();
  Coord getTile(Coord? reuse);
  int getTileIdx();
  int getResULX(int component, int resLevel);
  int getResULY(int component, int resLevel);
  int getImgULX(int resLevel);
  int getImgULY(int resLevel);
  int getTilePartULX();
  int getTilePartULY();
  Coord getNumTiles(Coord? reuse);
  int getNumTilesTotal();
  SubbandSyn getSynSubbandTree(int tile, int component);
}


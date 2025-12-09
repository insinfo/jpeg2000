import '../../image/Coord.dart';
import 'MultiResImgData.dart';
import 'SubbandSyn.dart';

/// Convenience base class that forwards [MultiResImgData] calls to a wrapped source.
abstract class MultiResImgDataAdapter implements MultiResImgData {
  MultiResImgDataAdapter(this.source);

  final MultiResImgData source;

  @override
  int getTileWidth(int resLevel) => source.getTileWidth(resLevel);

  @override
  int getTileHeight(int resLevel) => source.getTileHeight(resLevel);

  @override
  int getNomTileWidth() => source.getNomTileWidth();

  @override
  int getNomTileHeight() => source.getNomTileHeight();

  @override
  int getImgWidth(int resLevel) => source.getImgWidth(resLevel);

  @override
  int getImgHeight(int resLevel) => source.getImgHeight(resLevel);

  @override
  int getNumComps() => source.getNumComps();

  @override
  int getCompSubsX(int component) => source.getCompSubsX(component);

  @override
  int getCompSubsY(int component) => source.getCompSubsY(component);

  @override
  int getTileCompWidth(int tile, int component, int resLevel) =>
      source.getTileCompWidth(tile, component, resLevel);

  @override
  int getTileCompHeight(int tile, int component, int resLevel) =>
      source.getTileCompHeight(tile, component, resLevel);

  @override
  int getCompImgWidth(int component, int resLevel) =>
      source.getCompImgWidth(component, resLevel);

  @override
  int getCompImgHeight(int component, int resLevel) =>
      source.getCompImgHeight(component, resLevel);

    @override
    int getNomRangeBits(int component) => source.getNomRangeBits(component);

  @override
  void setTile(int x, int y) => source.setTile(x, y);

  @override
  void nextTile() => source.nextTile();

  @override
  Coord getTile(Coord? reuse) => source.getTile(reuse);

  @override
  int getTileIdx() => source.getTileIdx();

  @override
  int getResULX(int component, int resLevel) =>
      source.getResULX(component, resLevel);

  @override
  int getResULY(int component, int resLevel) =>
      source.getResULY(component, resLevel);

  @override
  int getImgULX(int resLevel) => source.getImgULX(resLevel);

  @override
  int getImgULY(int resLevel) => source.getImgULY(resLevel);

  @override
  int getTilePartULX() => source.getTilePartULX();

  @override
  int getTilePartULY() => source.getTilePartULY();

  @override
  Coord getNumTiles(Coord? reuse) => source.getNumTiles(reuse);

  @override
  int getNumTilesTotal() => source.getNumTilesTotal();

  @override
  SubbandSyn getSynSubbandTree(int tile, int component) =>
      source.getSynSubbandTree(tile, component);
}


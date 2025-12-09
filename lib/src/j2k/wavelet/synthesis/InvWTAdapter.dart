import '../../decoder/DecoderSpecs.dart';
import '../../image/Coord.dart';
import 'InvWT.dart';
import 'MultiResImgData.dart';
import 'SubbandSyn.dart';

/// Default adapter that forwards most [InvWT] queries to the wrapped
/// [MultiResImgData] while tracking the requested reconstruction level.
abstract class InvWTAdapter implements InvWT {
  InvWTAdapter(this.mresSrc, this.decSpec)
      : maxImgRes = decSpec.dls.getMin(),
        resLevel = 0;

  /// Decoder specifications (number of decomposition levels, etc.).
  final DecoderSpecs decSpec;

  /// Underlying source of multi-resolution data.
  final MultiResImgData mresSrc;

  /// Requested reconstruction resolution level.
  int resLevel;

  /// Maximum available image resolution level across components.
  final int maxImgRes;

  @override
  void setImgResLevel(int resLevel) {
    if (resLevel < 0) {
      throw ArgumentError('Resolution level index cannot be negative.');
    }
    this.resLevel = resLevel;
  }

  @override
  int getTileWidth() {
    final tileIdx = getTileIdx();
    var minRl = 0x7fffffff;
    final numComps = mresSrc.getNumComps();
    for (var c = 0; c < numComps; c++) {
      final rl = mresSrc.getSynSubbandTree(tileIdx, c).resLvl;
      if (rl < minRl) {
        minRl = rl;
      }
    }
    return mresSrc.getTileWidth(minRl);
  }

  @override
  int getTileHeight() {
    final tileIdx = getTileIdx();
    var minRl = 0x7fffffff;
    final numComps = mresSrc.getNumComps();
    for (var c = 0; c < numComps; c++) {
      final rl = mresSrc.getSynSubbandTree(tileIdx, c).resLvl;
      if (rl < minRl) {
        minRl = rl;
      }
    }
    return mresSrc.getTileHeight(minRl);
  }

  @override
  int getNomTileWidth() => mresSrc.getNomTileWidth();

  @override
  int getNomTileHeight() => mresSrc.getNomTileHeight();

  @override
  int getImgWidth() => mresSrc.getImgWidth(resLevel);

  @override
  int getImgHeight() => mresSrc.getImgHeight(resLevel);

  @override
  int getNumComps() => mresSrc.getNumComps();

  @override
  int getCompSubsX(int component) => mresSrc.getCompSubsX(component);

  @override
  int getCompSubsY(int component) => mresSrc.getCompSubsY(component);

  @override
  int getTileCompWidth(int tile, int component) {
    final rl = mresSrc.getSynSubbandTree(tile, component).resLvl;
    return mresSrc.getTileCompWidth(tile, component, rl);
  }

  @override
  int getTileCompHeight(int tile, int component) {
    final rl = mresSrc.getSynSubbandTree(tile, component).resLvl;
    return mresSrc.getTileCompHeight(tile, component, rl);
  }

  @override
  int getCompImgWidth(int component) {
    final rl = decSpec.dls.getMinInComp(component);
    return mresSrc.getCompImgWidth(component, rl);
  }

  @override
  int getCompImgHeight(int component) {
    final rl = decSpec.dls.getMinInComp(component);
    return mresSrc.getCompImgHeight(component, rl);
  }

  @override
  int getNomRangeBits(int component) => mresSrc.getNomRangeBits(component);

  @override
  void setTile(int x, int y) => mresSrc.setTile(x, y);

  @override
  void nextTile() => mresSrc.nextTile();

  @override
  Coord getTile(Coord? reuse) => mresSrc.getTile(reuse);

  @override
  int getTileIdx() => mresSrc.getTileIdx();

  @override
  int getCompULX(int component) {
    final tileIdx = getTileIdx();
    final rl = mresSrc.getSynSubbandTree(tileIdx, component).resLvl;
    return mresSrc.getResULX(component, rl);
  }

  @override
  int getCompULY(int component) {
    final tileIdx = getTileIdx();
    final rl = mresSrc.getSynSubbandTree(tileIdx, component).resLvl;
    return mresSrc.getResULY(component, rl);
  }

  @override
  int getImgULX() => mresSrc.getImgULX(resLevel);

  @override
  int getImgULY() => mresSrc.getImgULY(resLevel);

  @override
  int getTilePartULX() => mresSrc.getTilePartULX();

  @override
  int getTilePartULY() => mresSrc.getTilePartULY();

  @override
  Coord getNumTilesCoord(Coord? reuse) => mresSrc.getNumTiles(reuse);

  @override
  int getNumTiles() => mresSrc.getNumTilesTotal();

  /// Returns the synthesis subband tree for the given tile/component.
  SubbandSyn getSynSubbandTree(int tile, int component) =>
      mresSrc.getSynSubbandTree(tile, component);
}


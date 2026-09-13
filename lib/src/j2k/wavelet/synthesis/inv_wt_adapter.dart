import '../../decoder/decoder_specs.dart';
import '../../image/coord.dart';
import 'inv_wt.dart';
import 'multi_res_img_data.dart';
import 'subband_syn.dart';

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

  /// Resolution level actually reconstructed for [component] of [tile].
  ///
  /// The synthesis subband tree is always built to the full decomposition
  /// depth of the tile-component, so its `resLvl` is *not* the level the
  /// inverse transform stops at when fewer levels are asked for. Discarding
  /// `maxImgRes - resLevel` levels leaves level
  /// `resLevel - maxImgRes + resLvl` of this component, which is exactly the
  /// threshold `InvWTFull` uses to decide which subbands to synthesise, so
  /// every geometry query below has to be answered at that level too.
  /// ISO/IEC 15444-1 (ITU-T T.800) B.5 fixes the coordinates of a resolution
  /// level as `ceil(tcx0 / 2^(NL - r))`, which is what the multi-resolution
  /// source computes when given the level.
  int reconstructedResLevel(int tile, int component) =>
      _clampResLevel(mresSrc.getSynSubbandTree(tile, component).resLvl);

  int _clampResLevel(int treeResLevel) {
    final level = resLevel - maxImgRes + treeResLevel;
    if (level < 0) {
      return 0;
    }
    return level > treeResLevel ? treeResLevel : level;
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
    return mresSrc.getTileWidth(_clampResLevel(minRl));
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
    return mresSrc.getTileHeight(_clampResLevel(minRl));
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
  int getTileCompWidth(int tile, int component) => mresSrc.getTileCompWidth(
      tile, component, reconstructedResLevel(tile, component));

  @override
  int getTileCompHeight(int tile, int component) => mresSrc.getTileCompHeight(
      tile, component, reconstructedResLevel(tile, component));

  @override
  int getCompImgWidth(int component) {
    final rl = _clampResLevel(decSpec.dls.getMinInComp(component));
    return mresSrc.getCompImgWidth(component, rl);
  }

  @override
  int getCompImgHeight(int component) {
    final rl = _clampResLevel(decSpec.dls.getMinInComp(component));
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
    return mresSrc.getResULX(
        component, reconstructedResLevel(tileIdx, component));
  }

  @override
  int getCompULY(int component) {
    final tileIdx = getTileIdx();
    return mresSrc.getResULY(
        component, reconstructedResLevel(tileIdx, component));
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

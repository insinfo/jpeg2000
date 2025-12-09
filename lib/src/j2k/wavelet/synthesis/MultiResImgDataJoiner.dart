import '../../image/Coord.dart';
import 'MultiResImgData.dart';
import 'SubbandSyn.dart';

/// Aggregates multiple [MultiResImgData] providers into a single component space.
class MultiResImgDataJoiner implements MultiResImgData {
  MultiResImgDataJoiner(List<MultiResImgData> sources, List<int> componentIndices)
      : _sources = List<MultiResImgData>.from(sources, growable: false),
        _componentIndices =
            List<int>.from(componentIndices, growable: false) {
    if (_sources.isEmpty) {
      throw ArgumentError('At least one source must be provided');
    }
    if (_sources.length != _componentIndices.length) {
      throw ArgumentError('Source/component index arrays must have equal length');
    }
    final reference = _sources.first;
    final referenceTileCount = reference.getNumTilesTotal();
    for (var i = 1; i < _sources.length; i++) {
      final candidate = _sources[i];
      if (candidate.getNumTilesTotal() != referenceTileCount) {
        throw StateError('All sources must expose the same tile layout');
      }
    }
  }

  final List<MultiResImgData> _sources;
  final List<int> _componentIndices;

  MultiResImgData get _primary => _sources.first;

  MultiResImgData _sourceForComponent(int component) => _sources[component];

  int _indexForComponent(int component) => _componentIndices[component];

  @override
  int getTileWidth(int resLevel) => _primary.getTileWidth(resLevel);

  @override
  int getTileHeight(int resLevel) => _primary.getTileHeight(resLevel);

  @override
  int getNomTileWidth() => _primary.getNomTileWidth();

  @override
  int getNomTileHeight() => _primary.getNomTileHeight();

  @override
  int getImgWidth(int resLevel) => _primary.getImgWidth(resLevel);

  @override
  int getImgHeight(int resLevel) => _primary.getImgHeight(resLevel);

  @override
  int getNumComps() => _sources.length;

  @override
  int getCompSubsX(int component) =>
      _sourceForComponent(component).getCompSubsX(_indexForComponent(component));

  @override
  int getCompSubsY(int component) =>
      _sourceForComponent(component).getCompSubsY(_indexForComponent(component));

  @override
  int getTileCompWidth(int tile, int component, int resLevel) =>
      _sourceForComponent(component).getTileCompWidth(
        tile,
        _indexForComponent(component),
        resLevel,
      );

  @override
  int getTileCompHeight(int tile, int component, int resLevel) =>
      _sourceForComponent(component).getTileCompHeight(
        tile,
        _indexForComponent(component),
        resLevel,
      );

  @override
  int getCompImgWidth(int component, int resLevel) =>
      _sourceForComponent(component).getCompImgWidth(
        _indexForComponent(component),
        resLevel,
      );

  @override
  int getCompImgHeight(int component, int resLevel) =>
      _sourceForComponent(component).getCompImgHeight(
        _indexForComponent(component),
        resLevel,
      );

  @override
  int getNomRangeBits(int component) =>
      _sourceForComponent(component).getNomRangeBits(_indexForComponent(component));

  @override
  void setTile(int x, int y) {
    for (final src in _sources) {
      src.setTile(x, y);
    }
    _enforceAlignedTileIndex();
  }

  @override
  void nextTile() {
    for (final src in _sources) {
      src.nextTile();
    }
    _enforceAlignedTileIndex();
  }

  void _enforceAlignedTileIndex() {
    final expected = _primary.getTileIdx();
    for (var i = 1; i < _sources.length; i++) {
      final candidate = _sources[i].getTileIdx();
      if (candidate != expected) {
        throw StateError('Merged sources do not expose the same tile index');
      }
    }
  }

  @override
  Coord getTile(Coord? reuse) => _primary.getTile(reuse);

  @override
  int getTileIdx() => _primary.getTileIdx();

  @override
  int getResULX(int component, int resLevel) =>
      _sourceForComponent(component).getResULX(
        _indexForComponent(component),
        resLevel,
      );

  @override
  int getResULY(int component, int resLevel) =>
      _sourceForComponent(component).getResULY(
        _indexForComponent(component),
        resLevel,
      );

  @override
  int getImgULX(int resLevel) => _primary.getImgULX(resLevel);

  @override
  int getImgULY(int resLevel) => _primary.getImgULY(resLevel);

  @override
  int getTilePartULX() => _primary.getTilePartULX();

  @override
  int getTilePartULY() => _primary.getTilePartULY();

  @override
  Coord getNumTiles(Coord? reuse) => _primary.getNumTiles(reuse);

  @override
  int getNumTilesTotal() => _primary.getNumTilesTotal();

  @override
  SubbandSyn getSynSubbandTree(int tile, int component) =>
      _sourceForComponent(component).getSynSubbandTree(
        tile,
        _indexForComponent(component),
      );
}


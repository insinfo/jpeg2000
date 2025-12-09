import '../ModuleSpec.dart';
import 'RectangularRoi.dart';

/// Module specification storing rectangular ROIs per tile/component.
class RectROISpec extends ModuleSpec<RectangularROI?> {
  RectROISpec(int numTiles, int numComps)
      : super(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP);

  /// Retrieves the ROI configured for the given [tile] and [component], if any.
  RectangularROI? roiFor(int tile, int component) => getSpec(tile, component);

  /// Default ROI applied when no tile/component specific entry exists.
  RectangularROI? get defaultROI => getDefault();

  set defaultROI(RectangularROI? value) => setDefault(value);

  /// Converts the specification into a nested map structure indexed by tile/component.
  Map<int, Map<int, RectangularROI>> toTileComponentMap() {
    final result = <int, Map<int, RectangularROI>>{};
    for (var tile = 0; tile < nTiles; tile++) {
      for (var comp = 0; comp < nComp; comp++) {
        final roi = getSpec(tile, comp);
        if (roi == null) {
          continue;
        }
        final tileEntry = result.putIfAbsent(tile, () => <int, RectangularROI>{});
        tileEntry[comp] = roi;
      }
    }
    return result;
  }
}


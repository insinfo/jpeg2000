import '../ModuleSpec.dart';
import 'invcomptransf/InvCompTransf.dart';

/// Holds per-tile component transformation selections.
class CompTransfSpec extends ModuleSpec<int> {
  CompTransfSpec(int numTiles, int numComps, int specType)
      : super(numTiles, numComps, specType);

  /// Returns `true` if any tile enables a component transform.
  bool isCompTransfUsed() {
    final defaultValue = getDefault();
    if (defaultValue != null && defaultValue != InvCompTransf.none) {
      return true;
    }
    final tiles = tileDef;
    if (tiles != null) {
      for (var t = tiles.length - 1; t >= 0; t--) {
        final value = tiles[t];
        if (value != null && value != InvCompTransf.none) {
          return true;
        }
      }
    }
    return false;
  }
}


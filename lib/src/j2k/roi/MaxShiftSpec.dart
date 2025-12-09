import '../IntegerSpec.dart';
import '../ModuleSpec.dart';
import '../util/ParameterList.dart';

/// ROI max-shift specification mirroring JJ2000's command line handling.
class MaxShiftSpec extends IntegerSpec {
  MaxShiftSpec(int numTiles, int numComps)
      : super(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP);

  MaxShiftSpec.fromParameters(
    int numTiles,
    int numComps,
    ParameterList parameters,
    String optionName,
  ) : super.fromParameters(
          numTiles,
          numComps,
          ModuleSpec.SPEC_TYPE_TILE_COMP,
          parameters,
          optionName,
        ) {
    _validateAll();
  }

  @override
  void setDefault(int value) {
    _ensureNonNegative(value, 'default ROI max-shift');
    super.setDefault(value);
  }

  @override
  void setCompDef(int component, int value) {
    _ensureNonNegative(value, 'component ROI max-shift');
    super.setCompDef(component, value);
  }

  @override
  void setTileDef(int tile, int value) {
    _ensureNonNegative(value, 'tile ROI max-shift');
    super.setTileDef(tile, value);
  }

  @override
  void setTileCompVal(int tile, int component, int value) {
    _ensureNonNegative(value, 'tile/component ROI max-shift');
    super.setTileCompVal(tile, component, value);
  }

  void _validateAll() {
    final defValue = getDefault();
    if (defValue != null) {
      _ensureNonNegative(defValue, 'default ROI max-shift');
    }
    for (var t = 0; t < nTiles; t++) {
      for (var c = 0; c < nComp; c++) {
        final value = getSpec(t, c);
        if (value != null) {
          _ensureNonNegative(value, 'ROI max-shift');
        }
      }
    }
  }

  /// Returns the max-shift for the specified tile/component pair or `0` if none was set.
  int shiftFor(int tile, int component) {
    final value = getSpec(tile, component);
    if (value != null) {
      return value;
    }
    final defaultValue = getDefault();
    return defaultValue ?? 0;
  }

  static void _ensureNonNegative(int value, String context) {
    if (value < 0) {
      throw ArgumentError('$context cannot be negative: $value');
    }
  }
}


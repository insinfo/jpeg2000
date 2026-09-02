import '../module_spec.dart';
import '../util/parameter_list.dart';

/// Captures the quantization type selection for each tile-component.
class QuantTypeSpec extends ModuleSpec<String> {
  static const int specDef = ModuleSpec.specDef;
  static const int specCompDef = ModuleSpec.specCompDef;
  static const int specTileDef = ModuleSpec.specTileDef;
  static const int specTileComp = ModuleSpec.specTileComp;
  static List<bool> parseIdx(String token, int max) =>
      ModuleSpec.parseIdx(token, max);

  QuantTypeSpec(super.numTiles, super.numComps, super.specType);

  QuantTypeSpec.fromParameters(
    super.numTiles,
    super.numComps,
    super.specType,
    ParameterList parameters,
  ) {
    final param = parameters.getParameter('Qtype');
    if (param == null) {
      setDefault(parameters.getBooleanParameter('lossless')
          ? 'reversible'
          : 'expounded');
      return;
    }

    _parseSpecification(param, parameters);

    if (getDefault() == null) {
      _finalizeDefault(parameters);
    }
  }

  void _parseSpecification(String param, ParameterList parameters) {
    var curSpecType = specDef;
    List<bool>? tileSpec;
    List<bool>? compSpec;

    for (final rawWord in param.split(RegExp(r'\s+'))) {
      if (rawWord.isEmpty) {
        continue;
      }
      final word = rawWord.toLowerCase();
      switch (word[0]) {
        case 't':
          tileSpec = parseIdx(word, nTiles);
          curSpecType = curSpecType == specCompDef ? specTileComp : specTileDef;
          break;
        case 'c':
          compSpec = parseIdx(word, nComp);
          curSpecType = curSpecType == specTileDef ? specTileComp : specCompDef;
          break;
        case 'r':
        case 'd':
        case 'e':
          if (!_isRecognized(word)) {
            throw ArgumentError("Unknown parameter for '-Qtype' option: $word");
          }
          if (parameters.getBooleanParameter('lossless') &&
              (word == 'derived' || word == 'expounded')) {
            throw ArgumentError(
              'Cannot use non reversible quantization with -lossless option',
            );
          }

          switch (curSpecType) {
            case specDef:
              setDefault(word);
              break;
            case specTileDef:
              final tiles = tileSpec;
              if (tiles == null) {
                throw ArgumentError(
                  'Tile specification missing before value "$word"',
                );
              }
              for (var i = tiles.length - 1; i >= 0; i--) {
                if (tiles[i]) {
                  setTileDef(i, word);
                }
              }
              break;
            case specCompDef:
              final comps = compSpec;
              if (comps == null) {
                throw ArgumentError(
                  'Component specification missing before value "$word"',
                );
              }
              for (var i = comps.length - 1; i >= 0; i--) {
                if (comps[i]) {
                  setCompDef(i, word);
                }
              }
              break;
            case specTileComp:
              final tiles = tileSpec;
              final comps = compSpec;
              if (tiles == null || comps == null) {
                throw ArgumentError(
                  'Tile/component specification missing before value "$word"',
                );
              }
              for (var ti = tiles.length - 1; ti >= 0; ti--) {
                if (!tiles[ti]) {
                  continue;
                }
                for (var ci = comps.length - 1; ci >= 0; ci--) {
                  if (comps[ci]) {
                    setTileCompVal(ti, ci, word);
                  }
                }
              }
              break;
          }

          curSpecType = specDef;
          tileSpec = null;
          compSpec = null;
          break;
        default:
          throw ArgumentError("Unknown parameter for '-Qtype' option: $word");
      }
    }
  }

  void _finalizeDefault(ParameterList parameters) {
    var unspecified = 0;
    for (var t = nTiles - 1; t >= 0; t--) {
      for (var c = nComp - 1; c >= 0; c--) {
        if (specValType[t][c] == specDef) {
          unspecified++;
        }
      }
    }

    if (unspecified != 0) {
      setDefault(parameters.getBooleanParameter('lossless')
          ? 'reversible'
          : 'expounded');
    } else {
      final firstValue = getTileCompVal(0, 0);
      if (firstValue == null) {
        throw StateError('Tile-component specification missing for 0,0');
      }
      setDefault(firstValue);
      switch (specValType[0][0]) {
        case specTileDef:
          for (var c = nComp - 1; c >= 0; c--) {
            if (specValType[0][c] == specTileDef) {
              specValType[0][c] = specDef;
            }
          }
          tileDef?[0] = null;
          break;
        case specCompDef:
          for (var t = nTiles - 1; t >= 0; t--) {
            if (specValType[t][0] == specCompDef) {
              specValType[t][0] = specDef;
            }
          }
          compDef?[0] = null;
          break;
        case specTileComp:
          specValType[0][0] = specDef;
          tileCompVal?.remove('t0c0');
          break;
      }
    }
  }

  static bool _isRecognized(String value) {
    switch (value) {
      case 'reversible':
      case 'derived':
      case 'expounded':
        return true;
      default:
        return false;
    }
  }

  bool isDerived(int tile, int component) {
    final value = getTileCompVal(tile, component);
    return value != null && value.toLowerCase() == 'derived';
  }

  bool isReversible(int tile, int component) {
    final value = getTileCompVal(tile, component);
    return value != null && value.toLowerCase() == 'reversible';
  }

  bool isFullyReversible() {
    final defaultValue = getDefault();
    if (defaultValue == null || defaultValue.toLowerCase() != 'reversible') {
      return false;
    }
    for (var t = nTiles - 1; t >= 0; t--) {
      for (var c = nComp - 1; c >= 0; c--) {
        if (specValType[t][c] != specDef) {
          return false;
        }
      }
    }
    return true;
  }

  bool isFullyNonReversible() {
    for (var t = nTiles - 1; t >= 0; t--) {
      for (var c = nComp - 1; c >= 0; c--) {
        final value = getSpec(t, c);
        if (value != null && value.toLowerCase() == 'reversible') {
          return false;
        }
      }
    }
    return true;
  }
}

import 'ModuleSpec.dart';
import 'util/ParameterList.dart';

/// Holds string specifications for JJ2000 options on a tile/component grid.
class StringSpec extends ModuleSpec<String> {
  static const int SPEC_DEF = ModuleSpec.SPEC_DEF;
  static const int SPEC_COMP_DEF = ModuleSpec.SPEC_COMP_DEF;
  static const int SPEC_TILE_DEF = ModuleSpec.SPEC_TILE_DEF;
  static const int SPEC_TILE_COMP = ModuleSpec.SPEC_TILE_COMP;
    static List<bool> parseIdx(String token, int max) =>
      ModuleSpec.parseIdx(token, max);

  StringSpec(int numTiles, int numComps, int specType)
      : super(numTiles, numComps, specType);

  StringSpec.fromParameters(
    int numTiles,
    int numComps,
    int specType,
    String optionName,
    List<String> recognizedValues,
    ParameterList parameters,
  ) : super(numTiles, numComps, specType) {
    var param = parameters.getParameter(optionName);
    if (param == null) {
      final defaults = parameters.getDefaultParameterList();
      if (defaults == null) {
        throw ArgumentError('Missing defaults for option -$optionName');
      }
      param = defaults.getParameter(optionName);
      if (param == null || !_isRecognized(param, recognizedValues)) {
        throw ArgumentError(
          "Default parameter of option -$optionName not recognized: $param",
        );
      }
      setDefault(param);
      return;
    }

    _parseSpecification(param, optionName, recognizedValues);

    if (getDefault() == null) {
      _finalizeDefault(optionName, recognizedValues, parameters);
    }
  }

  static bool _isRecognized(String candidate, List<String> recognized) {
    for (final value in recognized) {
      if (value.toLowerCase() == candidate.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  void _parseSpecification(
    String param,
    String optionName,
    List<String> recognizedValues,
  ) {
    var curSpecType = SPEC_DEF;
    List<bool>? tileSpec;
    List<bool>? compSpec;

    for (final rawWord in param.split(RegExp(r'\s+'))) {
      if (rawWord.isEmpty) {
        continue;
      }
      final word = rawWord;
      switch (word[0]) {
        case 't':
          tileSpec = parseIdx(word, nTiles);
          curSpecType =
              curSpecType == SPEC_COMP_DEF ? SPEC_TILE_COMP : SPEC_TILE_DEF;
          break;
        case 'c':
          compSpec = parseIdx(word, nComp);
          curSpecType =
              curSpecType == SPEC_TILE_DEF ? SPEC_TILE_COMP : SPEC_COMP_DEF;
          break;
        default:
          if (!_isRecognized(word, recognizedValues)) {
            throw ArgumentError(
              "Parameter of option -$optionName not recognized: $word",
            );
          }
          switch (curSpecType) {
            case SPEC_DEF:
              setDefault(word);
              break;
            case SPEC_TILE_DEF:
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
            case SPEC_COMP_DEF:
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
            case SPEC_TILE_COMP:
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

          curSpecType = SPEC_DEF;
          tileSpec = null;
          compSpec = null;
          break;
      }
    }
  }

  void _finalizeDefault(
    String optionName,
    List<String> recognizedValues,
    ParameterList parameters,
  ) {
    var unspecified = 0;
    for (var t = nTiles - 1; t >= 0; t--) {
      for (var c = nComp - 1; c >= 0; c--) {
        if (specValType[t][c] == SPEC_DEF) {
          unspecified++;
        }
      }
    }

    if (unspecified != 0) {
      final defaults = parameters.getDefaultParameterList();
      if (defaults == null) {
        throw ArgumentError('Missing defaults for option -$optionName');
      }
      final param = defaults.getParameter(optionName);
      if (param == null || !_isRecognized(param, recognizedValues)) {
        throw ArgumentError(
          "Default parameter of option -$optionName not recognized: $param",
        );
      }
      setDefault(param);
    } else {
      final firstValue = getTileCompVal(0, 0);
      if (firstValue == null) {
        throw StateError('Tile-component specification missing for 0,0');
      }
      setDefault(firstValue);
      switch (specValType[0][0]) {
        case SPEC_TILE_DEF:
          for (var c = nComp - 1; c >= 0; c--) {
            if (specValType[0][c] == SPEC_TILE_DEF) {
              specValType[0][c] = SPEC_DEF;
            }
          }
          tileDef?[0] = null;
          break;
        case SPEC_COMP_DEF:
          for (var t = nTiles - 1; t >= 0; t--) {
            if (specValType[t][0] == SPEC_COMP_DEF) {
              specValType[t][0] = SPEC_DEF;
            }
          }
          compDef?[0] = null;
          break;
        case SPEC_TILE_COMP:
          specValType[0][0] = SPEC_DEF;
          tileCompVal?.remove('t0c0');
          break;
      }
    }
  }
}


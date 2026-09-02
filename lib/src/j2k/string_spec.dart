import 'module_spec.dart';
import 'util/parameter_list.dart';

/// Holds string specifications for JJ2000 options on a tile/component grid.
class StringSpec extends ModuleSpec<String> {
  static const int specDef = ModuleSpec.specDef;
  static const int specCompDef = ModuleSpec.specCompDef;
  static const int specTileDef = ModuleSpec.specTileDef;
  static const int specTileComp = ModuleSpec.specTileComp;
  static List<bool> parseIdx(String token, int max) =>
      ModuleSpec.parseIdx(token, max);

  StringSpec(super.numTiles, super.numComps, super.specType);

  StringSpec.fromParameters(
    super.numTiles,
    super.numComps,
    super.specType,
    String optionName,
    List<String> recognizedValues,
    ParameterList parameters,
  ) {
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
    var curSpecType = specDef;
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
          curSpecType = curSpecType == specCompDef ? specTileComp : specTileDef;
          break;
        case 'c':
          compSpec = parseIdx(word, nComp);
          curSpecType = curSpecType == specTileDef ? specTileComp : specCompDef;
          break;
        default:
          if (!_isRecognized(word, recognizedValues)) {
            throw ArgumentError(
              "Parameter of option -$optionName not recognized: $word",
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
        if (specValType[t][c] == specDef) {
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
}

import '../module_spec.dart';
import '../util/parameter_list.dart';

/// Stores the base quantization step sizes per tile-component.
class QuantStepSizeSpec extends ModuleSpec<dynamic> {
  // NOTE: the value type is dynamic because this spec is shared by the two
  // sides of the codec (as the raw ModuleSpec is in JJ2000): the encoder
  // stores the normalized base step as a double (from -Qstep), while the
  // decoder stores StdDequantizerParams parsed from the QCD/QCC markers.
  static const int specDef = ModuleSpec.specDef;
  static const int specCompDef = ModuleSpec.specCompDef;
  static const int specTileDef = ModuleSpec.specTileDef;
  static const int specTileComp = ModuleSpec.specTileComp;

  static List<bool> parseIdx(String token, int max) =>
      ModuleSpec.parseIdx(token, max);

  QuantStepSizeSpec(super.numTiles, super.numComps, super.specType);

  QuantStepSizeSpec.fromParameters(
    super.numTiles,
    super.numComps,
    super.specType,
    ParameterList parameters,
  ) {
    final param = parameters.getParameter('Qstep');
    if (param == null) {
      throw ArgumentError('Qstep option not specified');
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
        default:
          final value = double.tryParse(word);
          if (value == null) {
            throw ArgumentError(
              'Bad parameter for -Qstep option: $word',
            );
          }
          if (value <= 0.0) {
            throw ArgumentError(
              'Normalized base step must be positive: $value',
            );
          }

          switch (curSpecType) {
            case specDef:
              setDefault(_wrapValue(value));
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
                  setTileDef(i, _wrapValue(value));
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
                  setCompDef(i, _wrapValue(value));
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
                    setTileCompVal(ti, ci, _wrapValue(value));
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
      final defaults = parameters.getDefaultParameterList();
      if (defaults == null) {
        throw ArgumentError('Missing defaults for Qstep');
      }
      final value = defaults.getFloatParameter('Qstep');
      if (value <= 0.0) {
        throw ArgumentError('Default Qstep must be positive: $value');
      }
      setDefault(_wrapValue(value));
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

// The encoder-side value stored for each tile-component is the normalized
// base step itself, as a double (mirrors JJ2000, which stores a Float). The
// decoder side stores StdDequantizerParams objects parsed from QCD/QCC.
double _wrapValue(double value) => value;

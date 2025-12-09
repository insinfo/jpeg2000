import '../ModuleSpec.dart';
import '../util/ParameterList.dart';

/// Stores the number of guard bits to use per tile-component.
class GuardBitsSpec extends ModuleSpec<int> {
  static const int SPEC_DEF = ModuleSpec.SPEC_DEF;
  static const int SPEC_COMP_DEF = ModuleSpec.SPEC_COMP_DEF;
  static const int SPEC_TILE_DEF = ModuleSpec.SPEC_TILE_DEF;
  static const int SPEC_TILE_COMP = ModuleSpec.SPEC_TILE_COMP;
    static List<bool> parseIdx(String token, int max) =>
      ModuleSpec.parseIdx(token, max);

  GuardBitsSpec(int numTiles, int numComps, int specType)
      : super(numTiles, numComps, specType);

  GuardBitsSpec.fromParameters(
    int numTiles,
    int numComps,
    int specType,
    ParameterList parameters,
  ) : super(numTiles, numComps, specType) {
    final param = parameters.getParameter('Qguard_bits');
    if (param == null) {
      throw ArgumentError('Qguard_bits option not specified');
    }

    _parseSpecification(param);

    if (getDefault() == null) {
      _finalizeDefault(parameters);
    }
  }

  void _parseSpecification(String param) {
    var curSpecType = SPEC_DEF;
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
          curSpecType =
              curSpecType == SPEC_COMP_DEF ? SPEC_TILE_COMP : SPEC_TILE_DEF;
          break;
        case 'c':
          compSpec = parseIdx(word, nComp);
          curSpecType =
              curSpecType == SPEC_TILE_DEF ? SPEC_TILE_COMP : SPEC_COMP_DEF;
          break;
        default:
          final value = int.tryParse(word);
          if (value == null) {
            throw ArgumentError(
              'Bad parameter for -Qguard_bits option: $word',
            );
          }
          if (value <= 0) {
            throw ArgumentError(
              'Guard bits value must be positive: $value',
            );
          }

          switch (curSpecType) {
            case SPEC_DEF:
              setDefault(value);
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
                  setTileDef(i, value);
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
                  setCompDef(i, value);
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
                    setTileCompVal(ti, ci, value);
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

  void _finalizeDefault(ParameterList parameters) {
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
        throw ArgumentError('Missing defaults for Qguard_bits');
      }
      final value = defaults.getIntParameter('Qguard_bits');
      setDefault(value);
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


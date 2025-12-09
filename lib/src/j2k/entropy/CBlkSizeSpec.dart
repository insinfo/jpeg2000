import '../ModuleSpec.dart';
import '../util/MathUtil.dart';
import '../util/ParameterList.dart';
import 'StdEntropyCoderOptions.dart';

/// Specification of code-block sizes per tile/component.
class CBlkSizeSpec extends ModuleSpec<List<int>> {
  static const int SPEC_DEF = ModuleSpec.SPEC_DEF;
  static const int SPEC_COMP_DEF = ModuleSpec.SPEC_COMP_DEF;
  static const int SPEC_TILE_DEF = ModuleSpec.SPEC_TILE_DEF;
  static const int SPEC_TILE_COMP = ModuleSpec.SPEC_TILE_COMP;
  static List<bool> parseIdx(String token, int max) =>
      ModuleSpec.parseIdx(token, max);

  static const String optionName = 'Cblksiz';

  int maxCBlkWidth = 0;
  int maxCBlkHeight = 0;

  CBlkSizeSpec(int numTiles, int numComps, int specType)
      : super(numTiles, numComps, specType);

  CBlkSizeSpec.fromParameters(
    int numTiles,
    int numComps,
    int specType,
    ParameterList parameters,
  ) : super(numTiles, numComps, specType) {
    final param = parameters.getParameter(optionName);
    if (param == null) {
      throw ArgumentError('$optionName option not specified');
    }

    final tokens = param.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();
    var index = 0;
    var firstValue = true;
    var currentType = SPEC_DEF;
    List<bool>? tileSpec;
    List<bool>? compSpec;

    List<int> takeDims(String firstWord) {
      if (!_startsWithDigit(firstWord)) {
        throw ArgumentError('Bad construction for parameter: $firstWord');
      }
      final width = int.tryParse(firstWord);
      if (width == null) {
        throw ArgumentError(
          "'$optionName' option: the code-block width could not be parsed.",
        );
      }
      _validateDimension(width, isWidth: true);

      if (index >= tokens.length) {
        throw ArgumentError(
          "'$optionName' option: could not parse the code-block height",
        );
      }
      final heightWord = tokens[index++];
      final height = int.tryParse(heightWord);
      if (height == null) {
        throw ArgumentError(
          "'$optionName' option: the code-block height could not be parsed.",
        );
      }
      _validateDimension(height, isWidth: false);

      if (width * height > StdEntropyCoderOptions.MAX_CB_AREA) {
        throw ArgumentError(
          "'$optionName' option: the code-block area (width * height) cannot be greater than ${StdEntropyCoderOptions.MAX_CB_AREA}",
        );
      }
      return List<int>.unmodifiable(<int>[width, height]);
    }

    while (index < tokens.length) {
      final word = tokens[index++];
      switch (word[0]) {
        case 't':
          tileSpec = parseIdx(word, nTiles);
          currentType = currentType == SPEC_COMP_DEF ? SPEC_TILE_COMP : SPEC_TILE_DEF;
          break;
        case 'c':
          compSpec = parseIdx(word, nComp);
          currentType = currentType == SPEC_TILE_DEF ? SPEC_TILE_COMP : SPEC_COMP_DEF;
          break;
        default:
          final dims = takeDims(word);

          if (firstValue) {
            setDefault(dims);
            firstValue = false;
          }

          switch (currentType) {
            case SPEC_DEF:
              setDefault(dims);
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
                  setTileDef(i, dims);
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
                  setCompDef(i, dims);
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
                    setTileCompVal(ti, ci, dims);
                  }
                }
              }
              break;
          }

          currentType = SPEC_DEF;
          tileSpec = null;
          compSpec = null;
          break;
      }
    }
  }

  int getMaxCBlkWidth() => maxCBlkWidth;

  int getMaxCBlkHeight() => maxCBlkHeight;

  int getCBlkWidth(int type, int tile, int component) {
    final dims = _selectDims(type, tile, component);
    return dims[0];
  }

  int getCBlkHeight(int type, int tile, int component) {
    final dims = _selectDims(type, tile, component);
    return dims[1];
  }

  @override
  void setDefault(List<int> value) {
    super.setDefault(value);
    _storeHighestDims(value);
  }

  @override
  void setTileDef(int tile, List<int> value) {
    super.setTileDef(tile, value);
    _storeHighestDims(value);
  }

  @override
  void setCompDef(int component, List<int> value) {
    super.setCompDef(component, value);
    _storeHighestDims(value);
  }

  @override
  void setTileCompVal(int tile, int component, List<int> value) {
    super.setTileCompVal(tile, component, value);
    _storeHighestDims(value);
  }

  List<int> _selectDims(int type, int tile, int component) {
    switch (type) {
      case SPEC_DEF:
        return _requireDims(getDefault());
      case SPEC_COMP_DEF:
        return _requireDims(getCompDef(component));
      case SPEC_TILE_DEF:
        return _requireDims(getTileDef(tile));
      case SPEC_TILE_COMP:
        return _requireDims(getTileCompVal(tile, component));
      default:
        throw ArgumentError('Unknown specification type: $type');
    }
  }

  List<int> _requireDims(List<int>? value) {
    if (value == null) {
      throw StateError('Code-block dimensions not specified');
    }
    return value;
  }

  void _storeHighestDims(List<int> dims) {
    if (dims[0] > maxCBlkWidth) {
      maxCBlkWidth = dims[0];
    }
    if (dims[1] > maxCBlkHeight) {
      maxCBlkHeight = dims[1];
    }
  }

  static bool _startsWithDigit(String word) {
    if (word.isEmpty) {
      return false;
    }
    final codeUnit = word.codeUnitAt(0);
    return codeUnit >= 0x30 && codeUnit <= 0x39;
  }

  static void _validateDimension(int value, {required bool isWidth}) {
    if (value > StdEntropyCoderOptions.MAX_CB_DIM) {
      final label = isWidth ? 'width' : 'height';
      throw ArgumentError(
        "'$optionName' option: the code-block $label cannot be greater than ${StdEntropyCoderOptions.MAX_CB_DIM}",
      );
    }
    if (value < StdEntropyCoderOptions.MIN_CB_DIM) {
      final label = isWidth ? 'width' : 'height';
      throw ArgumentError(
        "'$optionName' option: the code-block $label cannot be less than ${StdEntropyCoderOptions.MIN_CB_DIM}",
      );
    }
    if (value != (1 << MathUtil.log2(value))) {
      final label = isWidth ? 'width' : 'height';
      throw ArgumentError(
        "'$optionName' option: the code-block $label must be a power of 2",
      );
    }
  }
}


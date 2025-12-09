import '../codestream/markers.dart';
import '../ModuleSpec.dart';
import '../util/MathUtil.dart';
import '../util/ParameterList.dart';
import '../IntegerSpec.dart';

/// Stores precinct partition sizes per tile/component.
class PrecinctSizeSpec extends ModuleSpec<List<List<int>>> {
  static const int SPEC_DEF = ModuleSpec.SPEC_DEF;
  static const int SPEC_COMP_DEF = ModuleSpec.SPEC_COMP_DEF;
  static const int SPEC_TILE_DEF = ModuleSpec.SPEC_TILE_DEF;
  static const int SPEC_TILE_COMP = ModuleSpec.SPEC_TILE_COMP;
  static List<bool> parseIdx(String token, int max) =>
      ModuleSpec.parseIdx(token, max);

  static const String optionName = 'Cpp';

  final IntegerSpec dls;

  PrecinctSizeSpec(
    int numTiles,
    int numComps,
    int specType,
    this.dls,
  ) : super(numTiles, numComps, specType) {
    _setDefaultPrecinct();
  }

  PrecinctSizeSpec.fromParameters(
    int numTiles,
    int numComps,
    int specType,
    Object? _imgSrc,
    this.dls,
    ParameterList parameters,
  ) : super(numTiles, numComps, specType) {
    _setDefaultPrecinct();

    final param = parameters.getParameter(optionName);
    if (param == null) {
      return;
    }

    final tokens = param.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();
    var index = 0;
    String? pending;
    var currentType = SPEC_DEF;
    List<bool>? tileSpec;
    List<bool>? compSpec;

    bool hasNext() => pending != null || index < tokens.length;

    String nextToken() {
      if (pending != null) {
        final value = pending!;
        pending = null;
        return value;
      }
      if (index >= tokens.length) {
        throw StateError('No tokens available');
      }
      return tokens[index++];
    }

    while (hasNext()) {
      final word = nextToken();
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
          if (!_startsWithDigit(word)) {
            throw ArgumentError('Bad construction for parameter: $word');
          }
          final widths = <int>[];
          final heights = <int>[];
          var currentWord = word;

          while (true) {
            final width = _parsePrecinctDimension(currentWord);
            if (!hasNext()) {
              throw ArgumentError("'$optionName' option: could not parse the precinct height");
            }
            final heightWord = nextToken();
            final height = _parsePrecinctDimension(heightWord);
            widths.add(width);
            heights.add(height);

            if (!hasNext()) {
              _applyPrecinct(widths, heights, currentType, tileSpec, compSpec);
              currentType = SPEC_DEF;
              tileSpec = null;
              compSpec = null;
              break;
            }

            final peek = nextToken();
            if (!_startsWithDigit(peek)) {
              pending = peek;
              _applyPrecinct(widths, heights, currentType, tileSpec, compSpec);
              currentType = SPEC_DEF;
              tileSpec = null;
              compSpec = null;
              break;
            }

            currentWord = peek;
          }
          break;
      }
    }
  }

  int getPPX(int tile, int component, int resolutionLevel) {
    final entry = _selectEntry(tile, component);
    final widths = entry.value[0];
    final idx = entry.mrl - resolutionLevel;
    if (idx < widths.length) {
      return widths[idx];
    }
    return widths.last;
  }

  int getPPY(int tile, int component, int resolutionLevel) {
    final entry = _selectEntry(tile, component);
    final heights = entry.value[1];
    final idx = entry.mrl - resolutionLevel;
    if (idx < heights.length) {
      return heights[idx];
    }
    return heights.last;
  }

  void _applyPrecinct(
    List<int> widths,
    List<int> heights,
    int specType,
    List<bool>? tileSpec,
    List<bool>? compSpec,
  ) {
    final value = List<List<int>>.unmodifiable(
      <List<int>>[
        List<int>.unmodifiable(widths),
        List<int>.unmodifiable(heights),
      ],
    );

    switch (specType) {
      case SPEC_DEF:
        setDefault(value);
        return;
      case SPEC_TILE_DEF:
        final tiles = tileSpec;
        if (tiles == null) {
          throw ArgumentError('Tile specification missing before precinct dimensions');
        }
        for (var i = tiles.length - 1; i >= 0; i--) {
          if (tiles[i]) {
            setTileDef(i, value);
          }
        }
        return;
      case SPEC_COMP_DEF:
        final comps = compSpec;
        if (comps == null) {
          throw ArgumentError('Component specification missing before precinct dimensions');
        }
        for (var i = comps.length - 1; i >= 0; i--) {
          if (comps[i]) {
            setCompDef(i, value);
          }
        }
        return;
      case SPEC_TILE_COMP:
        final tiles = tileSpec;
        final comps = compSpec;
        if (tiles == null || comps == null) {
          throw ArgumentError('Tile/component specification missing before precinct dimensions');
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
        return;
      default:
        throw ArgumentError('Unknown specification type: $specType');
    }
  }

  _PrecinctEntry _selectEntry(int tile, int component) {
    final tileSpecified = tile != -1;
    final compSpecified = component != -1;
    if (tileSpecified && compSpecified) {
      final value = getTileCompVal(tile, component);
      final mrl = dls.getTileCompVal(tile, component);
      return _PrecinctEntry(_requirePrecincts(value), _requireLevel(mrl));
    }
    if (tileSpecified) {
      final value = getTileDef(tile);
      final mrl = dls.getTileDef(tile);
      return _PrecinctEntry(_requirePrecincts(value), _requireLevel(mrl));
    }
    if (compSpecified) {
      final value = getCompDef(component);
      final mrl = dls.getCompDef(component);
      return _PrecinctEntry(_requirePrecincts(value), _requireLevel(mrl));
    }
    final value = getDefault();
    final mrl = dls.getDefault();
    return _PrecinctEntry(_requirePrecincts(value), _requireLevel(mrl));
  }

  List<List<int>> _requirePrecincts(List<List<int>>? value) {
    if (value == null) {
      throw StateError('Precinct sizes not specified');
    }
    if (value.length != 2) {
      throw StateError('Invalid precinct specification structure');
    }
    return value;
  }

  int _requireLevel(int? level) {
    if (level == null) {
      throw StateError('Number of decomposition levels not specified');
    }
    return level;
  }

  static bool _startsWithDigit(String word) {
    if (word.isEmpty) {
      return false;
    }
    final codeUnit = word.codeUnitAt(0);
    return codeUnit >= 0x30 && codeUnit <= 0x39;
  }

  static int _parsePrecinctDimension(String token) {
    final value = int.tryParse(token);
    if (value == null) {
      throw ArgumentError("'$optionName' option: the argument '$token' could not be parsed.");
    }
    if (value <= 0 || value != (1 << MathUtil.log2(value))) {
      throw ArgumentError('Precinct dimensions must be powers of 2');
    }
    return value;
  }

  void _setDefaultPrecinct() {
    final defaultSize = Markers.PRECINCT_PARTITION_DEF_SIZE;
    setDefault(
      List<List<int>>.unmodifiable(
        <List<int>>[
          List<int>.unmodifiable(<int>[defaultSize]),
          List<int>.unmodifiable(<int>[defaultSize]),
        ],
      ),
    );
  }
}

class _PrecinctEntry {
  _PrecinctEntry(this.value, this.mrl);

  final List<List<int>> value;
  final int mrl;
}


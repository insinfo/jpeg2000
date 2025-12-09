import '../codestream/ProgressionType.dart';
import '../IntegerSpec.dart';
import '../ModuleSpec.dart';
import '../util/ParameterList.dart';
import 'progression.dart';

/// Parses and stores progression order specifications for each tile.
class ProgressionSpec extends ModuleSpec<List<Progression>> {
  ProgressionSpec(
    int numTiles,
    int numComps, {
    required this.numLayers,
    required IntegerSpec decompositionLevels,
  })  : dls = decompositionLevels,
        super(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE);

  ProgressionSpec.fromParameters(
    int numTiles,
    int numComps,
    int numLayers,
    IntegerSpec decompositionLevels,
    ParameterList parameters,
  )   : numLayers = numLayers,
        dls = decompositionLevels,
        super(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE) {
    final value = parameters.getParameter('Aptype') ??
        parameters.getDefaultParameterList()?.getParameter('Aptype');
    if (value == null) {
      _applyDefaultProgression();
      return;
    }
    _parseProgressions(value);
    if (getDefault() == null) {
      _applyDefaultProgression();
    }
  }

  final int numLayers;
  final IntegerSpec dls;

  void _parseProgressions(String param) {
    var curSpecType = ModuleSpec.SPEC_DEF;
    List<bool>? currentTiles;
    final tokens = param.split(RegExp(r'\s+'));

    var progression = <Progression>[];
    Progression? curProg;
    var needInteger = false;
    var intType = 0;

    void flushProgressions() {
      if (progression.isEmpty) {
        return;
      }
      switch (curSpecType) {
        case ModuleSpec.SPEC_DEF:
          setDefault(_cloneProgressions(progression));
          break;
        case ModuleSpec.SPEC_TILE_DEF:
          final tiles = currentTiles;
          if (tiles == null) {
            throw ArgumentError('Missing tile specification for progression.');
          }
          for (var i = 0; i < tiles.length; i++) {
            if (tiles[i]) {
              setTileDef(i, _cloneProgressions(progression));
            }
          }
          break;
        default:
          throw ArgumentError('Unsupported specification type for progression.');
      }
      progression = <Progression>[];
      curProg = null;
      needInteger = false;
      intType = 0;
    }

    for (final rawWord in tokens) {
      final word = rawWord.trim();
      if (word.isEmpty) {
        continue;
      }
      final first = word[0];
      if (first == 't') {
        if (needInteger) {
          throw ArgumentError('Incomplete progression definition before tile spec.');
        }
        flushProgressions();
        currentTiles = ModuleSpec.parseIdx(word, nTiles);
        curSpecType = ModuleSpec.SPEC_TILE_DEF;
        continue;
      }

      final numeric = int.tryParse(word);
      if (numeric != null) {
        final activeProg = curProg;
        if (!needInteger || activeProg == null) {
          throw ArgumentError('Unexpected numeric token in -Aptype: $word');
        }
        _applyInteger(activeProg, intType, numeric);
        intType++;
        if (intType == 5) {
          needInteger = false;
          intType = 0;
        }
        continue;
      }

      final mode = _progressionTypeFor(word);
      if (mode == -1) {
        throw ArgumentError('Unknown progression type: $word');
      }
      if (needInteger) {
        throw ArgumentError('Missing progression bounds before declaring next progression.');
      }
      final newProg = Progression(
        mode,
        0,
        nComp,
        0,
        dls.getMax() + 1,
        numLayers,
      );
      progression.add(newProg);
      curProg = newProg;
      needInteger = true;
      intType = 0;
    }

    if (needInteger) {
      throw ArgumentError('Incomplete progression definition at end of -Aptype.');
    }

    flushProgressions();
  }

  void _applyInteger(Progression prog, int intType, int value) {
    final maxDecomp = dls.getMax();
    switch (intType) {
      case 0:
        if (value < 0 || value > maxDecomp) {
          throw ArgumentError('Invalid resolution start: $value');
        }
        prog.rs = value;
        break;
      case 1:
        if (value < 0 || value >= nComp) {
          throw ArgumentError('Invalid component start: $value');
        }
        prog.cs = value;
        break;
      case 2:
        if (value <= 0 || value > numLayers) {
          throw ArgumentError('Invalid layer limit: $value');
        }
        prog.lye = value;
        break;
      case 3:
        if (value <= prog.rs || value > maxDecomp + 1) {
          throw ArgumentError('Invalid resolution end: $value');
        }
        prog.re = value;
        break;
      case 4:
        if (value <= prog.cs || value > nComp) {
          throw ArgumentError('Invalid component end: $value');
        }
        prog.ce = value;
        break;
      default:
        throw ArgumentError('Too many integers for progression specification.');
    }
  }

  void _applyDefaultProgression() {
    final defaultProg = <Progression>[
      Progression(
        ProgressionType.LY_RES_COMP_POS_PROG,
        0,
        nComp,
        0,
        dls.getMax() + 1,
        numLayers,
      ),
    ];
    setDefault(_cloneProgressions(defaultProg));
  }

  int _progressionTypeFor(String token) {
    switch (token.toLowerCase()) {
      case 'layer':
      case 'lyrescomp':
      case 'layer-resolution-component-position':
      case 'ly-res-comp-pos':
        return ProgressionType.LY_RES_COMP_POS_PROG;
      case 'res':
      case 'reslayercomp':
      case 'resolution-layer-component-position':
      case 'res-ly-comp-pos':
        return ProgressionType.RES_LY_COMP_POS_PROG;
      case 'res-pos':
      case 'resposcomp':
      case 'resolution-position-component-layer':
        return ProgressionType.RES_POS_COMP_LY_PROG;
      case 'pos-comp':
      case 'poscompres':
      case 'position-component-resolution-layer':
        return ProgressionType.POS_COMP_RES_LY_PROG;
      case 'comp-pos':
      case 'compposres':
      case 'component-position-resolution-layer':
        return ProgressionType.COMP_POS_RES_LY_PROG;
      default:
        return -1;
    }
  }

  List<Progression> _cloneProgressions(List<Progression> source) {
    return List<Progression>.generate(
      source.length,
      (index) => source[index].copy(),
      growable: false,
    );
  }
}


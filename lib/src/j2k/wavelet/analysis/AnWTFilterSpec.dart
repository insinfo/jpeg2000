import '../../ModuleSpec.dart';
import '../../quantization/QuantTypeSpec.dart';
import '../../util/ParameterList.dart';
import 'AnWtFilter.dart';
import 'AnWtFilterIntLift5x3.dart';
import 'AnWtFilterFloatLift9x7.dart';

/// This class extends ModuleSpec class for analysis filters specification
/// holding purpose.
///
/// @see ModuleSpec
class AnWTFilterSpec extends ModuleSpec {
  /// The reversible default filter
  static const String REV_FILTER_STR = "w5x3";

  /// The non-reversible default filter
  static const String NON_REV_FILTER_STR = "w9x7";

  /// Constructs a new 'AnWTFilterSpec' for the specified number of
  /// components and tiles.
  ///
  /// [nt] The number of tiles
  ///
  /// [nc] The number of components
  ///
  /// [type] the type of the specification module i.e. tile specific,
  /// component specific or both.
  ///
  /// [qts] Quantization specifications
  ///
  /// [pl] The ParameterList
  AnWTFilterSpec(
      int nt, int nc, int type, QuantTypeSpec qts, ParameterList pl)
      : super(nt, nc, type) {
    // Check parameters
    pl.checkListSingle(AnWTFilter.optionPrefix.codeUnitAt(0),
        ParameterList.toNameArray(AnWTFilter.getParameterInfo()));

    String? param = pl.getParameter("Ffilters");

    // No parameter specified
    if (param == null) {

      // If lossless compression, uses the reversible filters in each
      // tile-components
      if (pl.getBooleanParameter("lossless")) {
        setDefault(parseFilters(REV_FILTER_STR));
        return;
      }

      // If no filter is specified through the command-line, use
      // REV_FILTER_STR or NON_REV_FILTER_STR according to the
      // quantization type
      for (int t = nt - 1; t >= 0; t--) {
        for (int c = nc - 1; c >= 0; c--) {
          switch (qts.getSpecValType(t, c)) {
            case ModuleSpec.SPEC_DEF:
              if (getDefault() == null) {
                if (pl.getBooleanParameter("lossless")) {
                  setDefault(parseFilters(REV_FILTER_STR));
                }
                if ((qts.getDefault() as String) == "reversible") {
                  setDefault(parseFilters(REV_FILTER_STR));
                } else {
                  setDefault(parseFilters(NON_REV_FILTER_STR));
                }
              }
              specValType[t][c] = ModuleSpec.SPEC_DEF;
              break;
            case ModuleSpec.SPEC_COMP_DEF:
              if (!isCompSpecified(c)) {
                if ((qts.getCompDef(c) as String) == "reversible") {
                  setCompDef(c, parseFilters(REV_FILTER_STR));
                } else {
                  setCompDef(c, parseFilters(NON_REV_FILTER_STR));
                }
              }
              specValType[t][c] = ModuleSpec.SPEC_COMP_DEF;
              break;
            case ModuleSpec.SPEC_TILE_DEF:
              if (!isTileSpecified(t)) {
                if ((qts.getTileDef(t) as String) == "reversible") {
                  setTileDef(t, parseFilters(REV_FILTER_STR));
                } else {
                  setTileDef(t, parseFilters(NON_REV_FILTER_STR));
                }
              }
              specValType[t][c] = ModuleSpec.SPEC_TILE_DEF;
              break;
            case ModuleSpec.SPEC_TILE_COMP:
              if (!isTileCompSpecified(t, c)) {
                if ((qts.getTileCompVal(t, c) as String) == "reversible") {
                  setTileCompVal(t, c, parseFilters(REV_FILTER_STR));
                } else {
                  setTileCompVal(t, c, parseFilters(NON_REV_FILTER_STR));
                }
              }
              specValType[t][c] = ModuleSpec.SPEC_TILE_COMP;
              break;
            default:
              throw ArgumentError("Unsupported specification type");
          }
        }
      }
      return;
    }

    // Parse argument
    // StringTokenizer stk = new StringTokenizer(param);
    List<String> tokens = param.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    
    String word; // current word
    int curSpecType = ModuleSpec.SPEC_DEF; // Specification type of the
    // current parameter
    List<bool>? tileSpec; // Tiles concerned by the specification
    List<bool>? compSpec; // Components concerned by the specification
    List<List<AnWTFilter>> filter;

    int tokenIdx = 0;
    while (tokenIdx < tokens.length) {
      word = tokens[tokenIdx++];

      switch (word[0]) {
        case 't': // Tiles specification
        case 'T': // Tiles specification
          tileSpec = ModuleSpec.parseIdx(word, nTiles);
          if (curSpecType == ModuleSpec.SPEC_COMP_DEF) {
            curSpecType = ModuleSpec.SPEC_TILE_COMP;
          } else {
            curSpecType = ModuleSpec.SPEC_TILE_DEF;
          }
          break;
        case 'c': // Components specification
        case 'C': // Components specification
          compSpec = ModuleSpec.parseIdx(word, nComp);
          if (curSpecType == ModuleSpec.SPEC_TILE_DEF) {
            curSpecType = ModuleSpec.SPEC_TILE_COMP;
          } else {
            curSpecType = ModuleSpec.SPEC_COMP_DEF;
          }
          break;
        case 'w': // WT filters specification
        case 'W': // WT filters specification
          if (pl.getBooleanParameter("lossless") &&
              word.toLowerCase() == "w9x7") {
            throw ArgumentError("Cannot use non reversible wavelet transform with '-lossless' option");
          }

          filter = parseFilters(word);
          if (curSpecType == ModuleSpec.SPEC_DEF) {
            setDefault(filter);
          } else if (curSpecType == ModuleSpec.SPEC_TILE_DEF) {
            var ts = tileSpec!;
            for (int i = ts.length - 1; i >= 0; i--) {
              if (ts[i]) {
                setTileDef(i, filter);
              }
            }
          } else if (curSpecType == ModuleSpec.SPEC_COMP_DEF) {
            var cs = compSpec!;
            for (int i = cs.length - 1; i >= 0; i--) {
              if (cs[i]) {
                setCompDef(i, filter);
              }
            }
          } else {
            var ts = tileSpec!;
            var cs = compSpec!;
            for (int i = ts.length - 1; i >= 0; i--) {
              for (int j = cs.length - 1; j >= 0; j--) {
                if (ts[i] && cs[j]) {
                  setTileCompVal(i, j, filter);
                }
              }
            }
          }

          // Re-initialize
          curSpecType = ModuleSpec.SPEC_DEF;
          tileSpec = null;
          compSpec = null;
          break;

        default:
          throw ArgumentError("Bad construction for parameter: $word");
      }
    }

    // Check that default value has been specified
    if (getDefault() == null) {
      int ndefspec = 0;
      for (int t = nt - 1; t >= 0; t--) {
        for (int c = nc - 1; c >= 0; c--) {
          if (specValType[t][c] == ModuleSpec.SPEC_DEF) {
            ndefspec++;
          }
        }
      }

      // If some tile-component have received no specification, it takes
      // the default value defined in ParameterList
      if (ndefspec != 0) {
        if ((qts.getDefault() as String) == "reversible") {
          setDefault(parseFilters(REV_FILTER_STR));
        } else {
          setDefault(parseFilters(NON_REV_FILTER_STR));
        }
      } else {
        // All tile-component have been specified, takes the first
        // tile-component value as default.
        setDefault(getTileCompVal(0, 0));
        switch (specValType[0][0]) {
          case ModuleSpec.SPEC_TILE_DEF:
            for (int c = nc - 1; c >= 0; c--) {
              if (specValType[0][c] == ModuleSpec.SPEC_TILE_DEF) {
                specValType[0][c] = ModuleSpec.SPEC_DEF;
              }
            }
            tileDef![0] = null;
            break;
          case ModuleSpec.SPEC_COMP_DEF:
            for (int t = nt - 1; t >= 0; t--) {
              if (specValType[t][0] == ModuleSpec.SPEC_COMP_DEF) {
                specValType[t][0] = ModuleSpec.SPEC_DEF;
              }
            }
            compDef![0] = null;
            break;
          case ModuleSpec.SPEC_TILE_COMP:
            specValType[0][0] = ModuleSpec.SPEC_DEF;
            tileCompVal!["t0c0"] = null;
            break;
        }
      }
    }

    // Check consistency between filter and quantization type
    // specification
    for (int t = nt - 1; t >= 0; t--) {
      for (int c = nc - 1; c >= 0; c--) {
        // Reversible quantization
        if ((qts.getTileCompVal(t, c) as String) == "reversible") {
          // If filter is reversible, it is OK
          if (isReversible(t, c)) continue;

          // Non reversible filter specified -> Error
          throw ArgumentError(
              "Filter of tile-component ($t,$c) does not allow reversible quantization. Specify '-Qtype expounded' or '-Qtype derived' in the command line.");
        } else {
          // No reversible quantization
          // No reversible filter -> OK
          if (!isReversible(t, c)) continue;

          // Reversible filter specified -> Error
          throw ArgumentError(
              "Filter of tile-component ($t,$c) does not allow non-reversible quantization. Specify '-Qtype reversible' in the command line");
        }
      }
    }
  }

  /// Parse filters from the given word
  ///
  /// [word] String to parse
  ///
  /// Returns Analysis wavelet filter (first dimension: by direction,
  /// second dimension: by decomposition levels)
  List<List<AnWTFilter>> parseFilters(String word) {
    List<List<AnWTFilter>> filt = List.generate(2, (_) => List.filled(1, AnWTFilterIntLift5x3())); // Dummy init
    if (word.toLowerCase() == "w5x3") {
      filt[0][0] = AnWTFilterIntLift5x3();
      filt[1][0] = AnWTFilterIntLift5x3();
      return filt;
    } else if (word.toLowerCase() == "w9x7") {
      filt[0][0] = AnWTFilterFloatLift9x7();
      filt[1][0] = AnWTFilterFloatLift9x7();
      return filt;
    } else {
      throw ArgumentError("Non JPEG 2000 part I filter: $word");
    }
  }

  /// Returns the data type used by the filters in this object, as defined in
  /// the 'DataBlk' interface for specified tile-component.
  ///
  /// [t] Tile index
  ///
  /// [c] Component index
  ///
  /// Returns The data type of the filters in this object
  ///
  /// @see ucar.jpeg.jj2000.j2k.image.DataBlk
  int getWTDataType(int t, int c) {
    List<List<AnWTFilter>> an = getSpec(t, c) as List<List<AnWTFilter>>;
    return an[0][0].getDataType();
  }

  /// Returns the horizontal analysis filters to be used in component 'n' and
  /// tile 't'.
  ///
  /// The horizontal analysis filters are returned in an array of
  /// AnWTFilter. Each element contains the horizontal filter for each
  /// resolution level starting with resolution level 1 (i.e. the analysis
  /// filter to go from resolution level 1 to resolution level 0). If there
  /// are less elements than the maximum resolution level, then the last
  /// element is assumed to be repeated.
  ///
  /// [t] The tile index, in raster scan order
  ///
  /// [c] The component index.
  ///
  /// Returns The array of horizontal analysis filters for component 'n' and
  /// tile 't'.
  List<AnWTFilter> getHFilters(int t, int c) {
    List<List<AnWTFilter>> an = getSpec(t, c) as List<List<AnWTFilter>>;
    return an[0];
  }

  /// Returns the vertical analysis filters to be used in component 'n' and
  /// tile 't'.
  ///
  /// The vertical analysis filters are returned in an array of
  /// AnWTFilter. Each element contains the vertical filter for each
  /// resolution level starting with resolution level 1 (i.e. the analysis
  /// filter to go from resolution level 1 to resolution level 0). If there
  /// are less elements than the maximum resolution level, then the last
  /// element is assumed to be repeated.
  ///
  /// [t] The tile index, in raster scan order
  ///
  /// [c] The component index.
  ///
  /// Returns The array of horizontal analysis filters for component 'n' and
  /// tile 't'.
  List<AnWTFilter> getVFilters(int t, int c) {
    List<List<AnWTFilter>> an = getSpec(t, c) as List<List<AnWTFilter>>;
    return an[1];
  }

  /// Debugging method
  @override
  String toString() {
    String str = "";
    List<List<AnWTFilter>> an;

    str += "nTiles=$nTiles\nnComp=$nComp\n\n";

    for (int t = 0; t < nTiles; t++) {
      for (int c = 0; c < nComp; c++) {
        an = getSpec(t, c) as List<List<AnWTFilter>>;

        str += "(t:$t,c:$c)\n";

        // Horizontal filters
        str += "\tH:";
        for (int i = 0; i < an[0].length; i++) {
          str += " " + an[0][i].toString();
        }
        // Horizontal filters
        str += "\n\tV:";
        for (int i = 0; i < an[1].length; i++) {
          str += " " + an[1][i].toString();
        }
        str += "\n";
      }
    }

    return str;
  }

  /// Check the reversibility of filters contained is the given
  /// tile-component.
  ///
  /// [t] The index of the tile
  ///
  /// [c] The index of the component
  bool isReversible(int t, int c) {
    // Note: no need to buffer the result since this method is
    // normally called once per tile-component.
    List<AnWTFilter> hfilter = getHFilters(t, c);
    List<AnWTFilter> vfilter = getVFilters(t, c);

    // As soon as a filter is not reversible, false can be returned
    for (int i = hfilter.length - 1; i >= 0; i--) {
      if (!hfilter[i].isReversible() || !vfilter[i].isReversible()) {
        return false;
      }
    }
    return true;
  }
}


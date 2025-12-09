import '../../ModuleSpec.dart';
import '../../util/ParameterList.dart';
import '../../wavelet/analysis/AnWtFilter.dart';
import '../../wavelet/analysis/AnWtFilterSpec.dart';
import '../../wavelet/FilterTypes.dart';
import '../CompTransfSpec.dart';
import '../invcomptransf/InvCompTransf.dart';

/// This class extends CompTransfSpec class in order to hold encoder specific
/// aspects of CompTransfSpec.
///
/// @see CompTransfSpec
class ForwCompTransfSpec extends CompTransfSpec {
  /// Constructs a new 'ForwCompTransfSpec' for the specified number of
  /// components and tiles, the wavelet filters type and the parameter of the
  /// option 'Mct'. This constructor is called by the encoder. It also checks
  /// that the arguments belong to the recognized arguments list.
  ///
  /// This constructor chose the component transformation type depending
  /// on the wavelet filters : RCT with w5x3 filter and ICT with w9x7
  /// filter. Note: All filters must use the same data type.
  ///
  /// [nt] The number of tiles
  ///
  /// [nc] The number of components
  ///
  /// [type] the type of the specification module i.e. tile specific,
  /// component specific or both.
  ///
  /// [wfs] The wavelet filter specifications
  ///
  /// [pl] The ParameterList
  ForwCompTransfSpec(
      int nt, int nc, int type, AnWTFilterSpec wfs, ParameterList pl)
      : super(nt, nc, type) {
    String? param = pl.getParameter("Mct");

    if (param == null) {
      // The option has not been specified

      // If less than three component, do not use any component
      // transformation
      if (nc < 3) {
        setDefault(InvCompTransf.none);
        return;
      }
      // If the compression is lossless, uses RCT
      else if (pl.getBooleanParameter("lossless")) {
        setDefault(InvCompTransf.invRct);
        return;
      } else {
        List<List<AnWTFilter>> anfilt;
        List<int> filtType = List.filled(nComp, 0);
        for (int c = 0; c < 3; c++) {
          anfilt = wfs.getCompDef(c) as List<List<AnWTFilter>>;
          filtType[c] = anfilt[0][0].getFilterType();
        }

        // Check that the three first components use the same filters
        bool reject = false;
        for (int c = 1; c < 3; c++) {
          if (filtType[c] != filtType[0]) reject = true;
        }

        if (reject) {
          setDefault(InvCompTransf.none);
        } else {
          anfilt = wfs.getCompDef(0) as List<List<AnWTFilter>>;
          if (anfilt[0][0].getFilterType() == FilterTypes.W9X7) {
            setDefault(InvCompTransf.invIct);
          } else {
            setDefault(InvCompTransf.invRct);
          }
        }
      }

      // Each tile receives a component transform specification
      // according the type of wavelet filters that are used by the
      // three first components
      for (int t = 0; t < nt; t++) {
        List<List<AnWTFilter>> anfilt;
        List<int> filtType = List.filled(nComp, 0);
        for (int c = 0; c < 3; c++) {
          anfilt = wfs.getTileCompVal(t, c) as List<List<AnWTFilter>>;
          filtType[c] = anfilt[0][0].getFilterType();
        }

        // Check that the three components use the same filters
        bool reject = false;
        for (int c = 1; c < nComp; c++) {
          if (filtType[c] != filtType[0]) reject = true;
        }

        if (reject) {
          setTileDef(t, InvCompTransf.none);
        } else {
          anfilt = wfs.getTileCompVal(t, 0) as List<List<AnWTFilter>>;
          if (anfilt[0][0].getFilterType() == FilterTypes.W9X7) {
            setTileDef(t, InvCompTransf.invIct);
          } else {
            setTileDef(t, InvCompTransf.invRct);
          }
        }
      }
      return;
    }

    // Parse argument
    List<String> tokens =
        param.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    String word; // current word
    int curSpecType = ModuleSpec.SPEC_DEF; // Specification type of the
    // current parameter
    List<bool>? tileSpec; // Tiles concerned by the
    // specification

    int tokenIdx = 0;
    while (tokenIdx < tokens.length) {
      word = tokens[tokenIdx++];

      switch (word[0]) {
        case 't': // Tiles specification
          tileSpec = ModuleSpec.parseIdx(word, nTiles);
          if (curSpecType == ModuleSpec.SPEC_COMP_DEF) {
            curSpecType = ModuleSpec.SPEC_TILE_COMP;
          } else {
            curSpecType = ModuleSpec.SPEC_TILE_DEF;
          }
          break;
        case 'c': // Components specification
          throw ArgumentError(
              "Component specific parameters not allowed with '-Mct' option");
        default:
          if (word == "off") {
            if (curSpecType == ModuleSpec.SPEC_DEF) {
              setDefault(InvCompTransf.none);
            } else if (curSpecType == ModuleSpec.SPEC_TILE_DEF) {
              for (int i = tileSpec!.length - 1; i >= 0; i--) {
                if (tileSpec[i]) {
                  setTileDef(i, InvCompTransf.none);
                }
              }
            }
          } else if (word == "on") {
            if (nc < 3) {
              throw ArgumentError(
                  "Cannot use component transformation on a image with less than three components");
            }

            if (curSpecType == ModuleSpec.SPEC_DEF) {
              // Set arbitrarily the default
              // value to RCT (later will be found the suitable
              // component transform for each tile)
              setDefault(InvCompTransf.invRct);
            } else if (curSpecType == ModuleSpec.SPEC_TILE_DEF) {
              for (int i = tileSpec!.length - 1; i >= 0; i--) {
                if (tileSpec[i]) {
                  if (getFilterType(i, wfs) == FilterTypes.W5X3) {
                    setTileDef(i, InvCompTransf.invRct);
                  } else {
                    setTileDef(i, InvCompTransf.invIct);
                  }
                }
              }
            }
          } else {
            throw ArgumentError(
                "Default parameter of option Mct not recognized: $param");
          }

          // Re-initialize
          curSpecType = ModuleSpec.SPEC_DEF;
          tileSpec = null;
          break;
      }
    }

    // Check that default value has been specified
    if (getDefault() == null) {
      // If not, set arbitrarily the default value to 'none' but
      // specifies explicitely a default value for each tile depending
      // on the wavelet transform that is used
      setDefault(InvCompTransf.none);

      for (int t = 0; t < nt; t++) {
        if (isTileSpecified(t)) {
          continue;
        }

        List<List<AnWTFilter>> anfilt;
        List<int> filtType = List.filled(nComp, 0);
        for (int c = 0; c < 3; c++) {
          anfilt = wfs.getTileCompVal(t, c) as List<List<AnWTFilter>>;
          filtType[c] = anfilt[0][0].getFilterType();
        }

        // Check that the three components use the same filters
        bool reject = false;
        for (int c = 1; c < nComp; c++) {
          if (filtType[c] != filtType[0]) reject = true;
        }

        if (reject) {
          setTileDef(t, InvCompTransf.none);
        } else {
          anfilt = wfs.getTileCompVal(t, 0) as List<List<AnWTFilter>>;
          if (anfilt[0][0].getFilterType() == FilterTypes.W9X7) {
            setTileDef(t, InvCompTransf.invIct);
          } else {
            setTileDef(t, InvCompTransf.invRct);
          }
        }
      }
    }

    // Check validity of component transformation of each tile compared to
    // the filter used.
    for (int t = nt - 1; t >= 0; t--) {
      if (getTileDef(t) == InvCompTransf.none) {
        // No comp. transf is used. No check is needed
        continue;
      } else if (getTileDef(t) == InvCompTransf.invRct) {
        // Tile is using Reversible component transform
        int filterType = getFilterType(t, wfs);
        switch (filterType) {
          case FilterTypes.W5X3: // OK
            break;
          case FilterTypes.W9X7: // Must use ICT
            if (isTileSpecified(t)) {
              // User has requested RCT -> Error
              throw ArgumentError(
                  "Cannot use RCT with 9x7 filter in tile $t");
            } else {
              // Specify ICT for this tile
              setTileDef(t, InvCompTransf.invIct);
            }
            break;
          default:
            throw ArgumentError(
                "Default filter is not JPEG 2000 part I compliant");
        }
      } else {
        // ICT
        int filterType = getFilterType(t, wfs);
        switch (filterType) {
          case FilterTypes.W5X3: // Must use RCT
            if (isTileSpecified(t)) {
              // User has requested ICT -> Error
              throw ArgumentError(
                  "Cannot use ICT with filter 5x3 in tile $t");
            } else {
              setTileDef(t, InvCompTransf.invRct);
            }
            break;
          case FilterTypes.W9X7: // OK
            break;
          default:
            throw ArgumentError(
                "Default filter is not JPEG 2000 part I compliant");
        }
      }
    }
  }

  /// Get the filter type common to all component of a given tile. If the
  /// tile index is -1, it searches common filter type of default
  /// specifications.
  ///
  /// [t] The tile index
  ///
  /// [wfs] The analysis filters specifications
  ///
  /// Returns The filter type common to all the components
  int getFilterType(int t, AnWTFilterSpec wfs) {
    List<List<AnWTFilter>> anfilt;
    List<int> filtType = List.filled(nComp, 0);
    for (int c = 0; c < nComp; c++) {
      if (t == -1) {
        anfilt = wfs.getCompDef(c) as List<List<AnWTFilter>>;
      } else {
        anfilt = wfs.getTileCompVal(t, c) as List<List<AnWTFilter>>;
      }
      filtType[c] = anfilt[0][0].getFilterType();
    }

    // Check that all filters are the same one
    bool reject = false;
    for (int c = 1; c < nComp; c++) {
      if (filtType[c] != filtType[0]) reject = true;
    }
    if (reject) {
      throw ArgumentError(
          "Can not use component transformation when components do not use the same filters");
    }
    return filtType[0];
  }
}


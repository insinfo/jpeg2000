import '../entropy/CBlkSizeSpec.dart';
import '../entropy/PrecinctSizeSpec.dart';
import '../entropy/ProgressionSpec.dart';
import '../image/BlkImgDataSrc.dart';
import '../image/forwcomptransf/ForwCompTransfSpec.dart';
import '../IntegerSpec.dart';
import '../ModuleSpec.dart';
import '../quantization/GuardBitsSpec.dart';
import '../quantization/QuantStepSizeSpec.dart';
import '../quantization/QuantTypeSpec.dart';
import '../quantization/quantizer/Quantizer.dart';
import '../roi/MaxShiftSpec.dart';
import '../StringSpec.dart';
import '../util/ParameterList.dart';
import '../wavelet/analysis/AnWtFilterSpec.dart';

/// This class holds references to each module specifications used in the
/// encoding chain. This avoid big amount of arguments in method calls. A
/// specification contains values of each tile-component for one module. All
/// members must be instance of ModuleSpec class (or its children).
///
/// @see ModuleSpec
class EncoderSpecs {
  /// ROI maxshift value specifications
  late MaxShiftSpec rois;

  /// Quantization type specifications
  late QuantTypeSpec qts;

  /// Quantization normalized base step size specifications
  late QuantStepSizeSpec qsss;

  /// Number of guard bits specifications
  late GuardBitsSpec gbs;

  /// Analysis wavelet filters specifications
  late AnWTFilterSpec wfs;

  /// Component transformation specifications
  late ForwCompTransfSpec cts;

  /// Number of decomposition levels specifications
  late IntegerSpec dls;

  /// The length calculation specifications
  late StringSpec lcs;

  /// The termination type specifications
  late StringSpec tts;

  /// Error resilience segment symbol use specifications
  late StringSpec sss;

  /// Causal stripes specifications
  late StringSpec css;

  /// Regular termination specifications
  late StringSpec rts;

  /// MQ reset specifications
  late StringSpec mqrs;

  /// By-pass mode specifications
  late StringSpec bms;

  /// Precinct partition specifications
  late PrecinctSizeSpec pss;

  /// Start of packet (SOP) marker use specification
  late StringSpec sops;

  /// End of packet header (EPH) marker use specification
  late StringSpec ephs;

  /// Code-blocks sizes specification
  late CBlkSizeSpec cblks;

  /// Progression/progression changes specification
  late ProgressionSpec pocs;

  /// The number of tiles within the image
  int nTiles;

  /// The number of components within the image
  int nComp;

  /// Initialize all members with the given number of tiles and components
  /// and the command-line arguments stored in a ParameterList instance
  ///
  /// [nt] Number of tiles
  ///
  /// [nc] Number of components
  ///
  /// [imgsrc] The image source (used to get the image size)
  ///
  /// [pl] The ParameterList instance
  EncoderSpecs(this.nTiles, this.nComp, BlkImgDataSrc imgsrc, ParameterList pl) {
    // ROI
    rois = MaxShiftSpec.fromParameters(nTiles, nComp, pl, "Rroi");

    // Quantization
    pl.checkListSingle(Quantizer.OPT_PREFIX.codeUnitAt(0),
        ParameterList.toNameArray(Quantizer.getParameterInfo()));
    qts = QuantTypeSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, pl);
    qsss = QuantStepSizeSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, pl);
    gbs = GuardBitsSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, pl);

    // Wavelet transform
    wfs = AnWTFilterSpec(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, qts, pl);
    dls = IntegerSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, pl, "Wlev");

    // Component transformation
    cts = ForwCompTransfSpec(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE, wfs, pl);

    // Entropy coder
    List<String> strLcs = ["near_opt", "lazy_good", "lazy"];
    lcs = StringSpec.fromParameters(
        nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, "Clen_calc", strLcs, pl);
    List<String> strTerm = ["near_opt", "easy", "predict", "full"];
    tts = StringSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP,
        "Cterm_type", strTerm, pl);
    List<String> strBoolean = ["on", "off"];
    sss = StringSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP,
        "Cseg_symbol", strBoolean, pl);
    css = StringSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, "Ccausal",
        strBoolean, pl);
    rts = StringSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP,
        "Cterminate", strBoolean, pl);
    mqrs = StringSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, "CresetMQ",
        strBoolean, pl);
    bms = StringSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, "Cbypass",
        strBoolean, pl);
    cblks = CBlkSizeSpec.fromParameters(nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, pl);

    // Precinct partition
    pss = PrecinctSizeSpec.fromParameters(
        nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE_COMP, imgsrc, dls, pl);

    // Codestream
    sops = StringSpec.fromParameters(
        nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE, "Psop", strBoolean, pl);
    ephs = StringSpec.fromParameters(
        nTiles, nComp, ModuleSpec.SPEC_TYPE_TILE, "Peph", strBoolean, pl);
    
    // Progression order
    String? rate = pl.getParameter("rate");
    int numLayers = 1;
    if (rate != null) {
        numLayers = rate.split(RegExp(r'\s+')).length;
    }
    pocs = ProgressionSpec.fromParameters(nTiles, nComp, numLayers, dls, pl);
  }
}



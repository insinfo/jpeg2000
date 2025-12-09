import '../entropy/CBlkSizeSpec.dart';
import '../entropy/PrecinctSizeSpec.dart';
import '../image/CompTransfSpec.dart';
import '../image/invcomptransf/InvCompTransf.dart';
import '../IntegerSpec.dart';
import '../ModuleSpec.dart';
import '../quantization/dequantizer/StdDequantizerParams.dart';
import '../quantization/GuardBitsSpec.dart';
import '../quantization/QuantStepSizeSpec.dart';
import '../quantization/QuantTypeSpec.dart';
import '../roi/MaxShiftSpec.dart';
import '../roi/RectRoiSpec.dart';
import '../wavelet/synthesis/SynWTFilterSpec.dart';
import '../wavelet/WtDecompSpec.dart';

/// Aggregated decoder specifications required by the inverse wavelet stage.
///
/// The original JJ2000 implementation exposes a wide collection of module
/// specifications (quantization, entropy options, precincts, etc.). For the
/// synthesis pipeline we surface the subset currently required by the decoder
/// (decomposition levels, wavelet filters, quantization metadata and component
/// transform choices).
class DecoderSpecs {
  DecoderSpecs({
    required this.dls,
    required this.wfs,
    required this.qts,
    required this.qsss,
    required this.gbs,
    required this.rois,
    required this.cts,
    required this.ecopts,
    required this.pss,
    required this.cblks,
    required this.ers,
    required this.nls,
    required this.pos,
    required this.pcs,
    required this.sops,
    required this.ephs,
    required this.pphs,
    required this.iccs,
    required this.wts,
    this.rectRois,
  });

  factory DecoderSpecs.basic(int numTiles, int numComps) {
    final dls = IntegerSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP)
      ..setDefault(0);
    final wfs = SynWTFilterSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP);
    final qts = QuantTypeSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP)
      ..setDefault('reversible');
    final qsss = QuantStepSizeSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP)
      ..setDefault(
        StdDequantizerParams(
          nStep: <List<double>>[<double>[1.0]],
        ),
      );
    final gbs = GuardBitsSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP)
      ..setDefault(1);
    final rois = MaxShiftSpec(numTiles, numComps)
      ..setDefault(0);
    final rectRois = RectROISpec(numTiles, numComps);
    final cts = CompTransfSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE)
      ..setDefault(InvCompTransf.none);
    final ecopts = ModuleSpec<int>(
      numTiles,
      numComps,
      ModuleSpec.SPEC_TYPE_TILE_COMP,
    )..setDefault(0);
    final pss = PrecinctSizeSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP, dls);
    final cblks = CBlkSizeSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE_COMP)
      ..setDefault(<int>[64, 64]);
    final ers = ModuleSpec<bool>(
      numTiles,
      numComps,
      ModuleSpec.SPEC_TYPE_TILE_COMP,
    )..setDefault(false);
    final nls = IntegerSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE)
      ..setDefault(1);
    final pos = IntegerSpec(numTiles, numComps, ModuleSpec.SPEC_TYPE_TILE)
      ..setDefault(0);
    final pcs = ModuleSpec<List<List<int>>?>(
      numTiles,
      numComps,
      ModuleSpec.SPEC_TYPE_TILE,
    )..setDefault(null);
    final sops = ModuleSpec<bool>(
      numTiles,
      numComps,
      ModuleSpec.SPEC_TYPE_TILE,
    )..setDefault(false);
    final ephs = ModuleSpec<bool>(
      numTiles,
      numComps,
      ModuleSpec.SPEC_TYPE_TILE,
    )..setDefault(false);
    final pphs = ModuleSpec<bool>(
      numTiles,
      numComps,
      ModuleSpec.SPEC_TYPE_TILE,
    )..setDefault(false);
    final iccs = ModuleSpec<Object?>(
      numTiles,
      numComps,
      ModuleSpec.SPEC_TYPE_TILE,
    )..setDefault(null);
    return DecoderSpecs(
      dls: dls,
      wfs: wfs,
      qts: qts,
      qsss: qsss,
      gbs: gbs,
      rois: rois,
      cts: cts,
      ecopts: ecopts,
      pss: pss,
      cblks: cblks,
      ers: ers,
      nls: nls,
      pos: pos,
      pcs: pcs,
      sops: sops,
      ephs: ephs,
      pphs: pphs,
      iccs: iccs,
      wts: WTDecompSpec(numComps, WTDecompSpec.wtDecompDyadic, 0),
      rectRois: rectRois,
    );
  }

  /// Number of decomposition levels specifications (`dls` in JJ2000).
  final IntegerSpec dls;

  /// Synthesis wavelet filters per tile/component (`wfs`).
  final SynWTFilterSpec wfs;

  /// Quantization type selections (`qts`).
  final QuantTypeSpec qts;

  /// Quantization step sizes (`qsss`).
  final QuantStepSizeSpec qsss;

  /// Guard bits (`gbs`).
  final GuardBitsSpec gbs;

  /// ROI max-shift specifications (`rois`).
  final MaxShiftSpec rois;

  /// Optional rectangular ROI definitions (`rectRois`).
  final RectROISpec? rectRois;

  /// Component transform usage (`cts`).
  final CompTransfSpec cts;

  /// Entropy coding options per tile/component (`ecopts`).
  final ModuleSpec<int> ecopts;

  /// Precinct partition sizes (`pss`).
  final PrecinctSizeSpec pss;

  /// Code-block size specifications (`cblks`).
  final CBlkSizeSpec cblks;

  /// Error resilience flags (`ers`).
  final ModuleSpec<bool> ers;

  /// Number of layers (`nls`).
  final IntegerSpec nls;

  /// Progression order (`pos`).
  final IntegerSpec pos;

  /// Progression order changes (`pcs`).
  final ModuleSpec<List<List<int>>?> pcs;

  /// SOP marker usage (`sops`).
  final ModuleSpec<bool> sops;

  /// EPH marker usage (`ephs`).
  final ModuleSpec<bool> ephs;

  /// Packed packet header usage (`pphs`).
  final ModuleSpec<bool> pphs;

  /// ICC profile specifications (`iccs`).
  final ModuleSpec<Object?> iccs;

  /// Wavelet tree decomposition specification (`wts`).
  final WTDecompSpec wts;
}



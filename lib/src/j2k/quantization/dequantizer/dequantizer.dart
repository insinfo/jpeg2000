import 'dart:math' as math;

import '../../decoder/decoder_specs.dart';
import '../../image/comp_transf_spec.dart';
import '../../image/data_blk.dart';
import '../../image/invcomptransf/inv_comp_transf.dart';
import '../../wavelet/synthesis/syn_wt_filter_spec.dart';
import '../../wavelet/synthesis/c_blk_wt_data_src_dec.dart';
import '../../wavelet/synthesis/multi_res_img_data_adapter.dart';
import '../../wavelet/synthesis/subband_syn.dart';
import 'c_blk_quant_data_src_dec.dart';

/// Base class for dequantizers operating on quantized wavelet code-blocks.
abstract class Dequantizer extends MultiResImgDataAdapter
    implements CBlkWTDataSrcDec {
  /// JJ2000 option prefix used to scope dequantizer-specific CLI parameters.
  static const String optionPrefix = 'Q';
  Dequantizer(
    this.src,
    List<int> utrb,
    DecoderSpecs decSpec,
  )   : utrb = List<int>.from(utrb, growable: false),
        cts = decSpec.cts,
        wfs = decSpec.wfs,
        super(src) {
    if (utrb.length != src.getNumComps()) {
      throw ArgumentError('Invalid utrb length: ${utrb.length}');
    }
    rb = List<int>.from(utrb, growable: false);
  }

  final CBlkQuantDataSrcDec src;
  final List<int> utrb;
  late List<int> rb;
  final CompTransfSpec cts;
  final SynWTFilterSpec wfs;

  static List<List<String>>? getParameterInfo() => null;

  @override
  int getNomRangeBits(int component) => rb[component];

  @override
  int getCbULX() => src.getCbULX();

  @override
  int getCbULY() => src.getCbULY();

  @override
  void setTile(int x, int y) {
    src.setTile(x, y);
    _initialiseForTile(src.getTileIdx());
  }

  @override
  void nextTile() {
    src.nextTile();
    _initialiseForTile(src.getTileIdx());
  }

  void _initialiseForTile(int tileIdx) {
    var transform =
        cts.getTileDef(tileIdx) ?? cts.getDefault() ?? InvCompTransf.none;
    if (transform == InvCompTransf.none) {
      rb = List<int>.from(utrb, growable: false);
      return;
    }

    final components = math.min(src.getNumComps(), 3);
    var reversibleCount = 0;
    for (var c = 0; c < components; c++) {
      if (wfs.isReversible(tileIdx, c)) {
        reversibleCount++;
      }
    }

    if (reversibleCount == 3) {
      rb = InvCompTransf.calcMixedBitDepths(
        utrb,
        InvCompTransf.invRct,
        rb.length == utrb.length ? rb : null,
      );
    } else if (reversibleCount == 0) {
      rb = InvCompTransf.calcMixedBitDepths(
        utrb,
        InvCompTransf.invIct,
        rb.length == utrb.length ? rb : null,
      );
    } else {
      throw ArgumentError(
        'Wavelet and component transforms mismatch for tile $tileIdx',
      );
    }
  }

  @override
  int getFixedPoint(int component);

  @override
  DataBlk? getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  );

  @override
  DataBlk? getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  );
}

import '../../decoder/decoder_specs.dart';
import '../../image/blk_img_data_src.dart';
import 'c_blk_wt_data_src_dec.dart';
import 'inv_wt_adapter.dart';
import 'inv_wt_full.dart';

/// Abstract base for inverse wavelet transforms operating on full tiles/components.
abstract class InverseWT extends InvWTAdapter implements BlkImgDataSrc {
  InverseWT(CBlkWTDataSrcDec src, DecoderSpecs decSpec) : super(src, decSpec);

  /// Factory matching JJ2000's default full-frame inverse transform path.
  static InverseWT createInstance(
    CBlkWTDataSrcDec src,
    DecoderSpecs decSpec,
  ) {
    return InvWTFull(src, decSpec);
  }
}

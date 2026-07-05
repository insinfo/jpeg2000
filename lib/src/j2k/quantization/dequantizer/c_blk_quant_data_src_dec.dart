import '../../image/data_blk.dart';
import '../../wavelet/synthesis/inv_wt_data.dart';
import '../../wavelet/synthesis/subband_syn.dart';

/// Source of quantized wavelet code-blocks for the decoder.
abstract class CBlkQuantDataSrcDec extends InvWTData {
  DataBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  );

  DataBlk getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  );
}

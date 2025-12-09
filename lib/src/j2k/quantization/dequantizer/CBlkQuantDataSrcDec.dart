import '../../image/DataBlk.dart';
import '../../wavelet/synthesis/InvWTData.dart';
import '../../wavelet/synthesis/SubbandSyn.dart';

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


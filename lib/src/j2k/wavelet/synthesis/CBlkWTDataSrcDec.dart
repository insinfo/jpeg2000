import '../../image/DataBlk.dart';
import 'InvWTData.dart';
import 'SubbandSyn.dart';

/// Decoder-side access to wavelet coefficient code-blocks.
abstract class CBlkWTDataSrcDec extends InvWTData {
  /// Nominal range bits of the reconstructed image data for the component.
  @override
  int getNomRangeBits(int component);

  /// Fixed-point fractional bits for the component.
  int getFixedPoint(int component);

  /// Returns a copy of the requested code-block.
  DataBlk? getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  );

  /// Returns a reference (or copy) of the requested code-block.
  DataBlk? getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  );
}


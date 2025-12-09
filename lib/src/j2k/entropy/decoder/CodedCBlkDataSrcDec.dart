import '../../wavelet/synthesis/InvWtData.dart';
import '../../wavelet/synthesis/SubbandSyn.dart';
import 'DecLyrdCBlk.dart';

/// Source of entropy-coded code-block data for the decoder side.
abstract class CodedCBlkDataSrcDec extends InvWTData {
  /// Returns the requested coded code-block for the given tile/component.
  ///
  /// [firstLayer] selects the first quality layer to include. [numLayers]
  /// determines how many layers should be returned; a negative value means
  /// "all available" starting at [firstLayer]. When [block] is supplied its
  /// buffers may be reused.
  DecLyrdCBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    int firstLayer,
    int numLayers,
    DecLyrdCBlk? block,
  );
}


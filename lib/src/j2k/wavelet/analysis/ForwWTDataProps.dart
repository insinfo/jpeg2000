import '../../image/ImgData.dart';
import 'SubbandAn.dart';

/// This interface extends the ImgData interface with methods that are
/// necessary for forward wavelet data (i.e. data that is produced by a forward
/// wavelet transform).
abstract class ForwWTDataProps implements ImgData {
  /// Returns the reversibility of the given tile-component. Data is
  /// reversible when it is suitable for lossless and lossy-to-lossless
  /// compression.
  ///
  /// [t] Tile index
  ///
  /// [c] Component index
  ///
  /// Returns true is the data is reversible, false if not.
  bool isReversible(int t, int c);

  /// Returns a reference to the root of subband tree structure representing
  /// the subband decomposition for the specified tile-component.
  ///
  /// [t] The index of the tile.
  ///
  /// [c] The index of the component.
  ///
  /// Returns The root of the subband tree structure, see Subband.
  ///
  /// @see SubbandAn
  ///
  /// @see Subband
  SubbandAn getAnSubbandTree(int t, int c);

  /// Returns the horizontal offset of the code-block partition. Allowable
  /// values are 0 and 1, nothing else.
  int getCbULX();

  /// Returns the vertical offset of the code-block partition. Allowable
  /// values are 0 and 1, nothing else.
  int getCbULY();
}


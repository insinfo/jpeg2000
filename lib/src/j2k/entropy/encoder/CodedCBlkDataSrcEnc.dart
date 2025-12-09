import '../../wavelet/analysis/ForwWTDataProps.dart';
import 'CBlkRateDistStats.dart';

/// This interface defines a source of entropy coded data and methods to
/// transfer it in a code-block by code-block basis. In each call to
/// 'getNextCodeBlock()' a new coded code-block is returned. The code-block are
/// retruned in no specific-order.
///
/// This interface is the source of data for the rate allocator. See the
/// 'PostCompRateAllocator' class.
///
/// For each coded-code-block the entropy-coded data is returned along with
/// the rate-distortion statistics in a 'CBlkRateDistStats' object.
///
/// @see PostCompRateAllocator
/// @see CBlkRateDistStats
/// @see EntropyCoder
abstract class CodedCBlkDataSrcEnc extends ForwWTDataProps {
  /// Returns the next coded code-block in the current tile for the specified
  /// component, as a copy (see below). The order in which code-blocks are
  /// returned is not specified. However each code-block is returned only
  /// once and all code-blocks will be returned if the method is called 'N'
  /// times, where 'N' is the number of code-blocks in the tile. After all
  /// the code-blocks have been returned for the current tile calls to this
  /// method will return 'null'.
  ///
  /// When changing the current tile (through 'setTile()' or 'nextTile()')
  /// this method will always return the first code-block, as if this method
  /// was never called before for the new current tile.
  ///
  /// The data returned by this method is always a copy of the internal
  /// data of this object, if any, and it can be modified "in place" without
  /// any problems after being returned.
  ///
  /// [c] The component for which to return the next code-block.
  ///
  /// [ccb] If non-null this object might be used in returning the coded
  /// code-block in this or any subsequent call to this method. If null a new
  /// one is created and returned. If the 'data' array of 'cbb' is not null
  /// it may be reused to return the compressed data.
  ///
  /// @return The next coded code-block in the current tile for component
  /// 'c', or null if all code-blocks for the current tile have been
  /// returned.
  ///
  /// @see CBlkRateDistStats
  CBlkRateDistStats? getNextCodeBlock(int c, CBlkRateDistStats? ccb);

  /// Returns the width of a packet for the specified tile-component and
  /// resolution level.
  ///
  /// [t] The tile
  ///
  /// [c] The component
  ///
  /// [r] The resolution level
  ///
  /// @return The width of a packet for the specified tile- component and
  /// resolution level.
  int getPPX(int t, int c, int r);

  /// Returns the height of a packet for the specified tile-component and
  /// resolution level.
  ///
  /// [t] The tile
  ///
  /// [c] The component
  ///
  /// [r] The resolution level
  ///
  /// @return The height of a packet for the specified tile- component and
  /// resolution level.
  int getPPY(int t, int c, int r);

  /// Returns true if the precinct partition is used for the specified
  /// component and tile, returns false otherwise
  ///
  /// [c] The component
  ///
  /// [t] The tile
  bool precinctPartitionUsed(int c, int t);
}



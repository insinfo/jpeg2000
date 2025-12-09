import '../../wavelet/analysis/CBlkWTData.dart';
import '../../wavelet/analysis/ForwWTDataProps.dart';

/// This interface defines a source of quantized wavelet coefficients and
/// methods to transfer them in a code-block by code-block basis. In each call
/// to 'getNextCodeBlock()' or 'getNextInternCodeBlock()' a new code-block is
/// returned. The code-blocks are returned in no specific order.
///
/// This class is the source of data for the entropy coder. See the
/// 'EntropyCoder' class.
///
/// Code-block data is returned in sign-magnitude representation, instead of
/// the normal two's complement one. Only integral types are used. The sign
/// magnitude representation is more adequate for entropy coding. In sign
/// magnitude representation, the most significant bit is used for the sign (0
/// if positive, 1 if negative) and the magnitude of the coefficient is stored
/// in the next M most significant bits. The rest of the bits (least
/// significant bits) can contain a fractional value of the quantized
/// coefficient. The number 'M' of magnitude bits is communicated in the
/// 'magbits' member variable of the 'CBlkWTData'.
///
/// Note that no more of one object may request data, otherwise one object
/// would get some of the data and another one another part, in no defined
/// manner.
///
/// @see ForwWTDataProps
/// @see CBlkWTDataSrc
/// @see Quantizer
/// @see EntropyCoder
abstract class CBlkQuantDataSrcEnc implements ForwWTDataProps {
  /// Returns the next code-block in the current tile for the specified
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
  /// any problems after being returned. The 'offset' of the returned data is
  /// 0, and the 'scanw' is the same as the code-block width. See the
  /// 'CBlkWTData' class.
  ///
  /// The 'ulx' and 'uly' members of the returned 'CBlkWTData' object
  /// contain the coordinates of the top-left corner of the block, with
  /// respect to the tile, not the subband.
  ///
  /// [c] The component for which to return the next code-block.
  ///
  /// [cblk] If non-null this object will be used to return the new
  /// code-block. If null a new one will be allocated and returned. If the
  /// "data" array of the object is non-null it will be reused, if possible,
  /// to return the data.
  ///
  /// Returns The next code-block in the current tile for component 'c', or
  /// null if all code-blocks for the current tile have been returned.
  ///
  /// @see CBlkWTData
  CBlkWTData? getNextCodeBlock(int c, CBlkWTData? cblk);

  /// Returns the next code-block in the current tile for the specified
  /// component. The order in which code-blocks are returned is not
  /// specified. However each code-block is returned only once and all
  /// code-blocks will be returned if the method is called 'N' times, where
  /// 'N' is the number of code-blocks in the tile. After all the code-blocks
  /// have been returned for the current tile calls to this method will
  /// return 'null'.
  ///
  /// When changing the current tile (through 'setTile()' or 'nextTile()')
  /// this method will always return the first code-block, as if this method
  /// was never called before for the new current tile.
  ///
  /// The data returned by this method can be the data in the internal
  /// buffer of this object, if any, and thus can not be modified by the
  /// caller. The 'offset' and 'scanw' of the returned data can be
  /// arbitrary. See the 'CBlkWTData' class.
  ///
  /// The 'ulx' and 'uly' members of the returned 'CBlkWTData' object
  /// contain the coordinates of the top-left corner of the block, with
  /// respect to the tile, not the subband.
  ///
  /// [c] The component for which to return the next code-block.
  ///
  /// [cblk] If non-null this object will be used to return the new
  /// code-block. If null a new one will be allocated and returned. If the
  /// "data" array of the object is non-null it will be reused, if possible,
  /// to return the data.
  ///
  /// Returns The next code-block in the current tile for component 'n', or
  /// null if all code-blocks for the current tile have been returned.
  ///
  /// @see CBlkWTData
  CBlkWTData? getNextInternCodeBlock(int c, CBlkWTData? cblk);
}



import 'CBlkWTData.dart';
import 'ForwWTDataProps.dart';

/// This abstract class defines methods to transfer wavelet data in a
/// code-block by code-block basis. In each call to 'getNextCodeBlock()' or
/// 'getNextInternCodeBlock()' a new code-block is returned. The code-blocks
/// are returned in no specific order.
///
/// This class is the source of data for the quantizer. See the 'Quantizer'
/// class.
///
/// Note that no more of one object may request data, otherwise one object
/// would get some of the data and another one another part, in no defined
/// manner.
///
/// @see ForwWTDataProps
/// @see WaveletTransform
/// @see ucar.jpeg.jj2000.j2k.quantization.quantizer.CBlkQuantDataSrcEnc
/// @see ucar.jpeg.jj2000.j2k.quantization.quantizer.Quantizer
abstract class CBlkWTDataSrc implements ForwWTDataProps {
  /// Returns the position of the fixed point in the specified component, or
  /// equivalently the number of fractional bits. This is the position of the
  /// least significant integral (i.e. non-fractional) bit, which is
  /// equivalent to the number of fractional bits. For instance, for
  /// fixed-point values with 2 fractional bits, 2 is returned. For
  /// floating-point data this value does not apply and 0 should be
  /// returned. Position 0 is the position of the least significant bit in
  /// the data.
  ///
  /// [c] The index of the component.
  ///
  /// Returns The position of the fixed-point, which is the same as the
  /// number of fractional bits. For floating-point data 0 is returned.
  int getFixedPoint(int c);

  /// Return the data type of this CBlkWTDataSrc for the given component in
  /// the current tile. Its value should be either DataBlk.TYPE_INT or
  /// DataBlk.TYPE_FLOAT but can change according to the current
  /// tile-component.
  ///
  /// [t] Tile index
  ///
  /// [c] Component index
  ///
  /// Returns Current data type
  int getDataType(int t, int c);

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
  /// 0, and the 'scanw' is the same as the code-block width.  The 'magbits'
  /// of the returned data is not set by this method and should be
  /// ignored. See the 'CBlkWTData' class.
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
  /// arbitrary. The 'magbits' of the returned data is not set by this method
  /// and should be ignored. See the 'CBlkWTData' class.
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



import '../../image/DataBlk.dart';
import 'SubbandAn.dart';

/// This is a generic abstract class to store a code-block of wavelet data,
/// quantized or not. This class does not have the notion of
/// components. Therefore, it should be used for data from a single
/// component. Subclasses should implement the different types of storage
/// (int, float, etc.).
///
/// The data is always stored in one array, of the type matching the data
/// type (i.e. for 'int' it's an 'int[]'). The data should be stored in the
/// array in standard scan-line order. That is the samples go from the top-left
/// corner of the code-block to the lower-right corner by line and then
/// column.
///
/// The member variable 'offset' gives the index in the array of the first
/// data element (i.e. the top-left coefficient). The member variable 'scanw'
/// gives the width of the scan that is used to store the data, that can be
/// different from the width of the block. Element '(x,y)' of the code-block
/// (i.e. '(0,0)' is the top-left coefficient), will appear at position
/// 'offset+y*scanw+x' in the array of data.
///
/// The classes CBlkWTDataInt and CBlkWTDataFloat provide
/// implementations for int and float types respectively.
///
/// The types of data are the same as those defined by the 'DataBlk'
/// class.
///
/// @see CBlkWTDataSrc
/// @see ucar.jpeg.jj2000.j2k.quantization.quantizer.CBlkQuantDataSrcEnc
/// @see DataBlk
/// @see CBlkWTDataInt
/// @see CBlkWTDataFloat
abstract class CBlkWTData {
  /// The horizontal coordinate of the upper-left corner of the code-block
  int ulx = 0;

  /// The vertical coordinate of the upper left corner of the code-block
  int uly = 0;

  /// The horizontal index of the code-block, within the subband
  int n = 0;

  /// The vertical index of the code-block, within the subband
  int m = 0;

  /// The subband in which this code-block is found
  SubbandAn? sb;

  /// The width of the code-block
  int w = 0;

  /// The height of the code-block
  int h = 0;

  /// The offset in the array of the top-left coefficient
  int offset = 0;

  /// The width of the scanlines used to store the data in the array
  int scanw = 0;

  /// The number of magnitude bits in the integer representation. This is
  /// only used for quantized wavelet data.
  int magbits = 0;

  /// The WMSE scaling factor (multiplicative) to apply to the distortion
  /// measures of the data of this code-block. By default it is 1.
  double wmseScaling = 1.0;

  /// The value by which the absolute value of the data has to be divided in
  /// order to get the real absolute value. This value is useful to obtain
  /// the complement of 2 representation of a coefficient that is currently
  /// using the sign-magnitude representation.
  double convertFactor = 1.0;

  /// The quantization step size of the code-block. The value is updated by
  /// the quantizer module
  double stepSize = 1.0;

  /// Number of ROI coefficients in the code-block
  int nROIcoeff = 0;

  /// Number of ROI magnitude bit-planes
  int nROIbp = 0;

  /// Returns the data type of the CBlkWTData object, as defined in
  /// the DataBlk class.
  ///
  /// Returns The data type of the object, as defined in the DataBlk class.
  ///
  /// @see DataBlk
  int getDataType();

  /// Returns the array containing the data, or null if there is no data. The
  /// returned array is of the type returned by getDataType() (e.g.,
  /// for TYPE_INT, it is a int[]).
  ///
  /// Each implementing class should provide a type specific equivalent
  /// method (e.g., getDataInt() in DataBlkInt) which
  /// returns an array of the correct type explicitely and not through an
  /// Object.
  ///
  /// Returns The array containing the data, or null if there is no
  /// data.
  ///
  /// @see #getDataType
  Object? getData();

  /// Sets the data array to the specified one. The type of the specified
  /// data array must match the one returned by getDataType() (e.g.,
  /// for TYPE_INT, it should be a int[]). If the wrong
  /// type of array is given a ClassCastException will be thrown.
  ///
  /// The size of the array is not necessarily checked for consistency
  /// with w and h or any other fields.
  ///
  /// Each implementing class should provide a type specific equivalent
  /// method (e.g., setDataInt() in DataBlkInt) which takes
  /// an array of the correct type explicetely and not through an
  /// Object.
  ///
  /// [arr] The new data array to use
  ///
  /// @see #getDataType
  void setData(Object arr);

  /// Returns a string of informations about the DataBlk
  ///
  /// Returns Block dimensions and progressiveness in a string
  @override
  String toString() {
    String typeString = "";
    switch (getDataType()) {
      case DataBlk.typeByte:
        typeString = "Unsigned Byte";
        break;
      case DataBlk.typeShort:
        typeString = "Short";
        break;
      case DataBlk.typeInt:
        typeString = "Integer";
        break;
      case DataBlk.typeFloat:
        typeString = "Float";
        break;
    }

    return "ulx=$ulx, uly=$uly, idx=($m,$n), w=$w, h=$h, off=$offset, scanw=$scanw, wmseScaling=$wmseScaling, convertFactor=$convertFactor, stepSize=$stepSize, type=$typeString, magbits=$magbits, nROIcoeff=$nROIcoeff, nROIbp=$nROIbp";
  }
}


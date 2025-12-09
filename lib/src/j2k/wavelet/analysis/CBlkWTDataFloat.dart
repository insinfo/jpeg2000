import 'dart:typed_data';
import '../../image/DataBlk.dart';
import 'CBlkWTData.dart';

/// This is an implementation of the 'CBlkWTData' abstract class for 32 bit
/// floating point data (float).
///
/// The methods in this class are declared final, so that they can be
/// inlined by inlining compilers.
///
/// @see CBlkWTData
class CBlkWTDataFloat extends CBlkWTData {
  /// The array where the data is stored
  Float32List? data;

  /// Returns the identifier of this data type, TYPE_FLOAT, as
  /// defined in DataBlk.
  ///
  /// Returns The type of data stored. Always DataBlk.TYPE_FLOAT
  ///
  /// @see DataBlk#TYPE_FLOAT
  @override
  int getDataType() {
    return DataBlk.typeFloat;
  }

  /// Returns the array containing the data, or null if there is no data
  /// array. The returned array is a float array.
  ///
  /// Returns The array of data (a float[]) or null if there is no data.
  @override
  Object? getData() {
    return data;
  }

  /// Returns the array containing the data, or null if there is no data
  /// array.
  ///
  /// Returns The array of data or null if there is no data.
  Float32List? getDataFloat() {
    return data;
  }

  /// Sets the data array to the specified one. The provided array must be a
  /// float array, otherwise a ClassCastException is thrown. The size of the
  /// array is not checked for consistency with the code-block dimensions.
  ///
  /// [arr] The data array to use. Must be a float array.
  @override
  void setData(Object arr) {
    data = arr as Float32List?;
  }

  /// Sets the data array to the specified one. The size of the array is not
  /// checked for consistency with the code-block dimensions. This method is
  /// more efficient than 'setData()'.
  ///
  /// [arr] The data array to use.
  void setDataFloat(Float32List? arr) {
    data = arr;
  }
}



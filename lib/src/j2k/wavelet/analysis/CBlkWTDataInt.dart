import 'dart:typed_data';
import '../../image/DataBlk.dart';
import 'CBlkWTData.dart';

/// This is an implementation of the 'CBlkWTData' abstract class for signed 32
/// bit integer data.
///
/// The methods in this class are declared final, so that they can be
/// inlined by inlining compilers.
///
/// @see CBlkWTData
class CBlkWTDataInt extends CBlkWTData {
  /// The array where the data is stored
  Int32List? data;

  /// Returns the data type of this object, always DataBlk.TYPE_INT.
  ///
  /// Returns The data type of the object, always DataBlk.TYPE_INT
  @override
  int getDataType() {
    return DataBlk.typeInt;
  }

  /// Returns the array containing the data, or null if there is no data
  /// array. The returned array is an int array.
  ///
  /// Returns The array of data (a int[]) or null if there is no data.
  @override
  Object? getData() {
    return data;
  }

  /// Returns the array containing the data, or null if there is no data
  /// array.
  ///
  /// Returns The array of data or null if there is no data.
  Int32List? getDataInt() {
    return data;
  }

  /// Sets the data array to the specified one. The provided array must be a
  /// int array, otherwise a ClassCastException is thrown. The size of the
  /// array is not checked for consistency with the code-block dimensions.
  ///
  /// [arr] The data array to use. Must be an int array.
  @override
  void setData(Object arr) {
    data = arr as Int32List?;
  }

  /// Sets the data array to the specified one. The size of the array is not
  /// checked for consistency with the code-block dimensions. This method is
  /// more efficient than 'setData()'.
  ///
  /// [arr] The data array to use.
  void setDataInt(Int32List? arr) {
    data = arr;
  }
}



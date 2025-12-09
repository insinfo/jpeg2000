import 'dart:typed_data';
import '../tags/ICCCurveType.dart';
import 'LookUpTable.dart';
import 'LookUpTable32Gamma.dart';
import 'LookUpTable32Interp.dart';

/// Toplevel class for a int [] lut.
abstract class LookUpTable32 extends LookUpTable {
  /// Maximum output value of the LUT
  final int dwMaxOutput;

  /// the lut values.
  late final Int32List lut;

  /// Create an abbreviated string representation of a 16 bit lut.
  /// @return the lut as a String
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[LookUpTable32 ");
    rep.write("max= $dwMaxOutput");
    rep.write(", nentries= $dwNumInput");
    return (rep..write("]")).toString();
  }

  /// Create the string representation of a 32 bit lut.
  /// @return the lut as a String
  String toStringWholeLut() {
    StringBuffer rep = StringBuffer("[LookUpTable32${LookUpTable.eol}");
    int row, col;
    rep.write("max output = $dwMaxOutput${LookUpTable.eol}");
    for (row = 0; row < dwNumInput ~/ 10; ++row) {
      rep.write("lut[${10 * row}] : ");
      for (col = 0; col < 10; ++col) {
        rep.write("${lut[10 * row + col]} ");
      }
      rep.write(LookUpTable.eol);
    }
    // Partial row.
    rep.write("lut[${10 * row}] : ");
    for (col = 0; col < dwNumInput % 10; ++col) {
      rep.write("${lut[10 * row + col]} ");
    }
    rep.write("${LookUpTable.eol}${LookUpTable.eol}");
    return rep.toString();
  }

  /// Factory method for getting a 32 bit lut from a given curve.
  ///   @param curve  the data
  ///   @param dwNumInput the size of the lut
  ///   @param dwMaxOutput max output value of the lut
  /// @return the lookup table
  static LookUpTable32 createInstance(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput, // Number of input values in created LUT
      int dwMaxOutput // Maximum output value of the LUT
      ) {
    if (curve.count == 1)
      return LookUpTable32Gamma(curve, dwNumInput, dwMaxOutput);
    else
      return LookUpTable32Interp(curve, dwNumInput, dwMaxOutput);
  }

  /// Construct an empty 32 bit
  ///   @param dwNumInput the size of the lut t lut.
  ///   @param dwMaxOutput max output value of the lut
  LookUpTable32(
      int dwNumInput, // Number of i   nput values in created LUT
      this.dwMaxOutput // Maximum output value of the LUT
      )
      : super(null, dwNumInput) {
    lut = Int32List(dwNumInput);
  }

  /// Construct a 16 bit lut from a given curve.
  ///   @param curve the data
  ///   @param dwNumInput the size of the lut t lut.
  ///   @param dwMaxOutput max output value of the lut
  LookUpTable32.fromCurve(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput, // Number of input values in created LUT
      this.dwMaxOutput // Maximum output value of the LUT
      )
      : super(curve, dwNumInput) {
    lut = Int32List(dwNumInput);
  }

  /// lut accessor
  ///   @param index of the element
  /// @return the lut [index]
  int elementAt(int index) {
    return lut[index];
  }
}


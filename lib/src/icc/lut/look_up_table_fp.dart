import 'dart:typed_data';
import '../tags/icc_curve_type.dart';
import 'look_up_table.dart';
import 'look_up_table_fp_gamma.dart';
import 'look_up_table_fp_interp.dart';

/// Toplevel class for a float [] lut.
abstract class LookUpTableFP extends LookUpTable {
  /// The lut values.
  late final Float32List lut;

  /// Factory method for getting a lut from a given curve.
  ///   @param curve  the data
  ///   @param dwNumInput the size of the lut
  /// @return the lookup table
  static LookUpTableFP createInstance(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput // Number of input values in created LUT
      ) {
    if (curve.nEntries == 1) {
      return LookUpTableFPGamma(curve, dwNumInput);
    } else {
      return LookUpTableFPInterp(curve, dwNumInput);
    }
  }

  /// Construct an empty lut
  ///   @param dwNumInput the size of the lut t lut.
  ///   @param dwMaxOutput max output value of the lut
  LookUpTableFP(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput // Number of input values in created LUT
      )
      : super(curve, dwNumInput) {
    lut = Float32List(dwNumInput);
  }

  /// lut accessor
  ///   @param index of the element
  /// @return the lut [index]
  double elementAt(int index) {
    return lut[index];
  }
}

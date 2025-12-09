import 'dart:math';
import '../tags/ICCCurveType.dart';
import 'LookUpTableFP.dart';

/// Class Description
class LookUpTableFPGamma extends LookUpTableFP {
  double dfE = -1;
  static const String eol = '\n'; // System.getProperty("line.separator");

  LookUpTableFPGamma(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput // Number of input values in created LUT
      ) : super(curve, dwNumInput) {
    // Gamma exponent for inverse transformation
    dfE = ICCCurveType.curveGammaToDouble(curve.entryAt(0));
    for (int i = 0; i < dwNumInput; i++) {
      lut[i] = pow(i / (dwNumInput - 1), dfE).toDouble();
    }
  }

  /// Create an abbreviated string representation of a 16 bit lut.
  /// @return the lut as a String
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[LookUpTableGamma ");
    rep.write("dfe= $dfE");
    rep.write(", nentries= ${lut.length}");
    return (rep..write("]")).toString();
  }
}


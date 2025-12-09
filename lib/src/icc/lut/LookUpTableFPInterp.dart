import '../tags/ICCCurveType.dart';
import 'LookUpTableFP.dart';

/// An interpolated floating point lut
class LookUpTableFPInterp extends LookUpTableFP {
  /// Create an abbreviated string representation of a 16 bit lut.
  /// @return the lut as a String
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[LookUpTable32 ")
      ..write(" nentries= ${lut.length}");
    return (rep..write("]")).toString();
  }

  /// Construct the lut from the curve data
  ///   @oaram  curve the data
  ///   @oaram  dwNumInput the lut size
  LookUpTableFPInterp(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput // Number of input values in created LUT
      ) : super(curve, dwNumInput) {
    int dwLowIndex, dwHighIndex; // Indices of interpolation points
    double dfLowIndex; // FP indices of interpolation points
    double dfTargetIndex; // Target index into interpolation table
    double dfRatio; // Ratio of LUT input points to curve values
    double dfLow, dfHigh; // Interpolation values

    dfRatio = (curve.nEntries - 1) / (dwNumInput - 1);

    for (int i = 0; i < dwNumInput; i++) {
      dfTargetIndex = i * dfRatio;
      dfLowIndex = dfTargetIndex.floorToDouble();
      dwLowIndex = dfLowIndex.toInt();
      // dfHighIndex = dfTargetIndex.ceilToDouble(); // Not used directly
      dwHighIndex = dfTargetIndex.ceil().toInt();

      if (dwLowIndex == dwHighIndex) {
        lut[i] = ICCCurveType.curveToDouble(curve.entryAt(dwLowIndex));
      } else {
        dfLow = ICCCurveType.curveToDouble(curve.entryAt(dwLowIndex));
        dfHigh = ICCCurveType.curveToDouble(curve.entryAt(dwHighIndex));
        lut[i] = (dfLow + (dfHigh - dfLow) * (dfTargetIndex - dfLowIndex));
      }
    }
  }
}


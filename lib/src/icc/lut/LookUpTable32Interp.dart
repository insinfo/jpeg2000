import '../tags/ICCCurveType.dart';
import 'LookUpTable32.dart';

/// An interpolated 32 bit lut
class LookUpTable32Interp extends LookUpTable32 {
  /// Construct the lut from the curve data
  ///   @oaram  curve the data
  ///   @oaram  dwNumInput the lut size
  ///   @oaram  dwMaxOutput the lut max value
  LookUpTable32Interp(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput, // Number of input values in created LUT
      int dwMaxOutput // Maximum output value of the LUT
      )
      : super.fromCurve(curve, dwNumInput, dwMaxOutput) {
    int dwLowIndex, dwHighIndex; // Indices of interpolation points
    double dfLowIndex; // FP indices of interpolation points
    double dfTargetIndex; // Target index into interpolation table
    double dfRatio; // Ratio of LUT input points to curve values
    double dfLow, dfHigh; // Interpolation values
    double dfOut; // Output LUT value

    dfRatio = (curve.count - 1) / (dwNumInput - 1);

    for (int i = 0; i < dwNumInput; i++) {
      dfTargetIndex = i * dfRatio;
      dfLowIndex = dfTargetIndex.floorToDouble();
      dwLowIndex = dfLowIndex.toInt();
      // dfHighIndex = dfTargetIndex.ceilToDouble(); // Not used
      dwHighIndex = dfTargetIndex.ceil().toInt();

      if (dwLowIndex == dwHighIndex) {
        dfOut = ICCCurveType.curveToDouble(curve.entry[dwLowIndex]);
      } else {
        dfLow = ICCCurveType.curveToDouble(curve.entry[dwLowIndex]);
        dfHigh = ICCCurveType.curveToDouble(curve.entry[dwHighIndex]);
        dfOut = dfLow + (dfHigh - dfLow) * (dfTargetIndex - dfLowIndex);
      }

      lut[i] = (dfOut * dwMaxOutput + 0.5).floor();
    }
  }
}


import 'dart:math' as math;
import '../tags/ICCCurveType.dart';
import 'LookUpTable32.dart';

/// A Gamma based 32 bit lut.
class LookUpTable32Gamma extends LookUpTable32 {
  /* Construct the lut    
     *   @param curve data 
     *   @param dwNumInput size of lut  
     *   @param dwMaxOutput max value of lut   
     */
  LookUpTable32Gamma(
      ICCCurveType curve, // Pointer to the curve data
      int dwNumInput, // Number of input values in created LUT
      int dwMaxOutput // Maximum output value of the LUT
      )
      : super.fromCurve(curve, dwNumInput, dwMaxOutput) {
    double dfE = ICCCurveType.curveGammaToDouble(
        curve.entry[0]); // Gamma exponent for inverse transformation
    for (int i = 0; i < dwNumInput; i++) {
      lut[i] =
          (math.pow(i / (dwNumInput - 1), dfE) * dwMaxOutput + 0.5).floor();
    }
  }
}


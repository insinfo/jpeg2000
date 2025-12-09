import 'dart:math' as math;
import '../tags/ICCCurveType.dart';
import 'LookUpTable8.dart';

/// Gamma based LUT with 8-bit output.
class LookUpTable8Gamma extends LookUpTable8 {
  LookUpTable8Gamma(
      ICCCurveType curve, int dwNumInput, int dwMaxOutput)
      : super.fromCurve(curve, dwNumInput, dwMaxOutput) {
    double exponent = ICCCurveType.curveGammaToDouble(curve.entry[0]);
    for (int i = 0; i < dwNumInput; i++) {
      double normalized = (dwNumInput == 1) ? 0.0 : i / (dwNumInput - 1);
      int value =
          (math.pow(normalized, exponent) * dwMaxOutput + 0.5).floor();
      if (value < 0) {
        value = 0;
      } else if (value > dwMaxOutput) {
        value = dwMaxOutput;
      }
      if (value > 255) value = 255;
      lut[i] = value;
    }
  }
}

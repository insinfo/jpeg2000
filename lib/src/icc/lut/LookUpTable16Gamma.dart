import 'dart:math' as math;
import '../tags/ICCCurveType.dart';
import 'LookUpTable16.dart';

/// Gamma based LUT with 16-bit output.
class LookUpTable16Gamma extends LookUpTable16 {
  LookUpTable16Gamma(
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
      if (value > 0xFFFF) value = 0xFFFF;
      lut[i] = value;
    }
  }
}

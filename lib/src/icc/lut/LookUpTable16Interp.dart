import '../tags/ICCCurveType.dart';
import 'LookUpTable16.dart';

/// Interpolated 16-bit LUT built from ICC curve data.
class LookUpTable16Interp extends LookUpTable16 {
  LookUpTable16Interp(
      ICCCurveType curve, int dwNumInput, int dwMaxOutput)
      : super.fromCurve(curve, dwNumInput, dwMaxOutput) {
    double ratio =
        (dwNumInput == 1) ? 0.0 : (curve.count - 1) / (dwNumInput - 1);

    for (int i = 0; i < dwNumInput; i++) {
      double targetIndex = i * ratio;
      int lowIndex = targetIndex.floor();
      int highIndex = targetIndex.ceil();

      double output;
      if (lowIndex == highIndex) {
        output = ICCCurveType.curveToDouble(curve.entry[lowIndex]);
      } else {
        double low = ICCCurveType.curveToDouble(curve.entry[lowIndex]);
        double high = ICCCurveType.curveToDouble(curve.entry[highIndex]);
        output = low + (high - low) * (targetIndex - lowIndex);
      }

      int value = (output * dwMaxOutput + 0.5).floor();
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

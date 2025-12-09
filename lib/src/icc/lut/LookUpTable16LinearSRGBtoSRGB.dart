import 'dart:math' as math;
import 'LookUpTable16.dart';

/// Linear sRGB to encoded sRGB LUT with 16-bit precision.
class LookUpTable16LinearSRGBtoSRGB extends LookUpTable16 {
  static LookUpTable16LinearSRGBtoSRGB createInstance(
      int shadowCutoff,
      double shadowSlope,
      int linearMaxValue,
      double scaleAfterExp,
      double exponent,
      double reduceAfterExp) {
    return LookUpTable16LinearSRGBtoSRGB(shadowCutoff, shadowSlope,
        linearMaxValue, scaleAfterExp, exponent, reduceAfterExp);
  }

  LookUpTable16LinearSRGBtoSRGB(
      int shadowCutoff,
      double shadowSlope,
      int linearMaxValue,
      double scaleAfterExp,
      double exponent,
      double reduceAfterExp)
      : super(linearMaxValue + 1, 0) {
    int i = 0;
    shadowCutoff = shadowCutoff.clamp(0, linearMaxValue).toInt();
    double normalize = (linearMaxValue == 0) ? 0.0 : 1.0 / linearMaxValue;

    for (; i <= shadowCutoff && i < lut.length; i++) {
      int value = (shadowSlope * i + 0.5).floor();
      if (value < 0) value = 0;
      if (value > 0xFFFF) value = 0xFFFF;
      lut[i] = value;
    }

    for (; i < lut.length; i++) {
      double encoded = math.pow(i * normalize, exponent).toDouble();
      int value = (scaleAfterExp * encoded - reduceAfterExp + 0.5).floor();
      if (value < 0) value = 0;
      if (value > 0xFFFF) value = 0xFFFF;
      lut[i] = value;
    }
  }
}

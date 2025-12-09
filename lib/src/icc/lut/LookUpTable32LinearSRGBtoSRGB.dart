import 'dart:math';
import 'LookUpTable32.dart';

/// A Linear 32 bit SRGB to SRGB lut
class LookUpTable32LinearSRGBtoSRGB extends LookUpTable32 {
  /// Factory method for creating the lut.
  ///   @param wShadowCutoff size of shadow region
  ///   @param dfShadowSlope shadow region parameter
  ///   @param ksRGBLinearMaxValue size of lut
  ///   @param ksRGB8ScaleAfterExp post shadow region parameter
  ///   @param ksRGBExponent post shadow region parameter
  ///   @param ksRGB8ReduceAfterEx post shadow region parameter
  /// @return the lut
  static LookUpTable32LinearSRGBtoSRGB createInstance(
      int inMax,
      int outMax,
      double shadowCutoff,
      double shadowSlope,
      double scaleAfterExp,
      double exponent,
      double reduceAfterExp) {
    return LookUpTable32LinearSRGBtoSRGB(inMax, outMax, shadowCutoff,
        shadowSlope, scaleAfterExp, exponent, reduceAfterExp);
  }

  /// Construct the lut
  ///   @param wShadowCutoff size of shadow region
  ///   @param dfShadowSlope shadow region parameter
  ///   @param ksRGBLinearMaxValue size of lut
  ///   @param ksRGB8ScaleAfterExp post shadow region parameter
  ///   @param ksRGBExponent post shadow region parameter
  ///   @param ksRGB8ReduceAfterExp post shadow region parameter
  LookUpTable32LinearSRGBtoSRGB(
      int inMax,
      int outMax,
      double shadowCutoff,
      double shadowSlope,
      double scaleAfterExp,
      double exponent,
      double reduceAfterExp)
      : super(inMax + 1, outMax) {
    int i = -1;
    // Normalization factor for i.
    double normalize = 1.0 / inMax;

    // Generate the final linear-sRGB to non-linear sRGB LUT

    // calculate where shadow portion of lut ends.
    int cutOff = (shadowCutoff * inMax).floor();

    // Scale to account for output
    shadowSlope *= outMax;

    // Our output needs to be centered on zero so we shift it down.
    int shift = (outMax + 1) ~/ 2;

    for (i = 0; i <= cutOff; i++) {
      lut[i] = (shadowSlope * (i * normalize) + 0.5).floor() - shift;
    }

    // Scale values for output.
    scaleAfterExp *= outMax;
    reduceAfterExp *= outMax;

    // Now calculate the rest
    for (; i <= inMax; i++) {
      lut[i] = (scaleAfterExp * pow(i * normalize, exponent) -
                  reduceAfterExp +
                  0.5)
              .floor() -
          shift;
    }
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer("[LookUpTable32LinearSRGBtoSRGB:");
    return (rep..write("]")).toString();
  }
}


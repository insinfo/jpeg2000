import 'dart:math';
import 'dart:typed_data';
import '../RestrictedICCProfile.dart';
import '../ICCProfile.dart';
import '../../j2k/image/DataBlkInt.dart';
import '../../j2k/image/DataBlkFloat.dart';
import 'LookUpTableFP.dart';
import '../../colorspace/ColorSpace.dart';

/// This class constructs a LookUpTableFP from a RestrictedICCProfile.
/// The values in this table are used to calculate a second lookup table (simply a short []).
/// table.  When this transform is applied to an input DataBlk, an output data block is
/// constructed by using the input samples as indices into the lookup table, whose values
/// are used to populate the output DataBlk.
class MonochromeTransformTosRGB {
  static const String eol = '\n'; // System.getProperty ("line.separator");

  /// Transform parameter.
  static const double ksRGBShadowCutoff = 0.0031308;

  /// Transform parameter.
  static const double ksRGBShadowSlope = 12.92;

  /// Transform parameter.
  static const double ksRGB8ShadowSlope = (255 * ksRGBShadowSlope);

  /// Transform parameter.
  static const double ksRGBExponent = (1.0 / 2.4);

  /// Transform parameter.
  static const double ksRGB8ScaleAfterExp = 269.025;

  /// Transform parameter.
  static const double ksRGB8ReduceAfterExp = 14.025;

  late final Int16List lut;
  int dwInputMaxValue = 0;
  late final LookUpTableFP fLut;

  /// String representation of class
  /// @return suitable representation for class
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[MonochromeTransformTosRGB ");
    StringBuffer body = StringBuffer("  ");

    // Print the parameters:
    body.write("$eol ksRGBShadowSlope= $ksRGBShadowSlope");
    body.write("$eol ksRGBShadowCutoff= $ksRGBShadowCutoff");
    body.write("$eol ksRGBShadowSlope= $ksRGBShadowSlope");
    body.write("$eol ksRGB8ShadowSlope= $ksRGB8ShadowSlope");
    body.write("$eol ksRGBExponent= $ksRGBExponent");
    body.write("$eol ksRGB8ScaleAfterExp= $ksRGB8ScaleAfterExp");
    body.write("$eol ksRGB8ReduceAfterExp= $ksRGB8ReduceAfterExp");
    body.write("$eol dwInputMaxValue= $dwInputMaxValue");

    // Print the LinearSRGBtoSRGB lut.
    body.write("$eol [lut = [short[${lut.length}]]]");

    // Print the FP luts.
    body.write("$eol fLut=  $fLut");

    rep.write(ColorSpace.indent("  ", body.toString()));
    return (rep..write("]")).toString();
  }

  /// Construct the lut from the RestrictedICCProfile.
  ///
  ///   @param rICC input RestrictedICCProfile
  ///   @param dwInputMaxValue size of the output lut.
  ///   @param dwInputShiftValue value used to shift samples to positive
  MonochromeTransformTosRGB(RestrictedICCProfile rICC, int dwInputMaxValue,
      int dwInputShiftValue) {
    if (rICC.getType() != RestrictedICCProfile.kMonochromeInput)
      throw ArgumentError(
          "MonochromeTransformTosRGB: wrong type ICCProfile supplied");

    this.dwInputMaxValue = dwInputMaxValue;
    lut = Int16List(dwInputMaxValue + 1);
    fLut = LookUpTableFP.createInstance(
        rICC.trc[ICCProfile.GRAY], dwInputMaxValue + 1);

    // First calculate the value for the shadow region
    int i;
    for (i = 0;
        ((i <= dwInputMaxValue) && (fLut.lut[i] <= ksRGBShadowCutoff));
        i++) {
      lut[i] = (ksRGB8ShadowSlope * fLut.lut[i] + 0.5).floor() -
          dwInputShiftValue;
    }

    // Now calculate the rest
    for (; i <= dwInputMaxValue; i++) {
      lut[i] = (ksRGB8ScaleAfterExp * pow(fLut.lut[i], ksRGBExponent) -
                  ksRGB8ReduceAfterExp +
                  0.5)
              .floor() -
          dwInputShiftValue;
    }
  }

  /// Populate the output block by looking up the values in the lut, using the input
  /// as lut indices.
  ///   @param inb input samples
  ///   @param outb output samples.
  /// @exception MonochromeTransformException
  void applyInt(DataBlkInt inb, DataBlkInt outb) {
    int i, j;

    Int32List input = inb.getDataInt() as Int32List;
    Int32List output = outb.getDataInt() as Int32List;

    if (output.length < input.length) {
      output = Int32List(input.length);
      outb.setDataInt(output);
    }

    outb.uly = inb.uly;
    outb.ulx = inb.ulx;
    outb.h = inb.h;
    outb.w = inb.w;
    outb.offset = inb.offset;
    outb.scanw = inb.scanw;

    // o = inb.offset; // Not used
    for (i = 0; i < inb.h * inb.w; ++i) {
      j = input[i];
      if (j < 0)
        j = 0;
      else if (j > dwInputMaxValue) j = dwInputMaxValue;
      output[i] = lut[j];
    }
  }

  /// Populate the output block by looking up the values in the lut, using the input
  /// as lut indices.
  ///   @param inb input samples
  ///   @param outb output samples.
  /// @exception MonochromeTransformException
  void applyFloat(DataBlkFloat inb, DataBlkFloat outb) {
    int i, j;

    Float32List input = inb.getDataFloat() as Float32List;
    Float32List output = outb.getDataFloat() as Float32List;

    if (output.length < input.length) {
      output = Float32List(input.length);
      outb.setDataFloat(output);
    }
    
    outb.uly = inb.uly;
    outb.ulx = inb.ulx;
    outb.h = inb.h;
    outb.w = inb.w;
    outb.offset = inb.offset;
    outb.scanw = inb.scanw;

    // o = inb.offset; // Not used
    for (i = 0; i < inb.h * inb.w; ++i) {
      j = input[i].toInt();
      if (j < 0)
        j = 0;
      else if (j > dwInputMaxValue) j = dwInputMaxValue;
      output[i] = lut[j].toDouble();
    }
  }
}


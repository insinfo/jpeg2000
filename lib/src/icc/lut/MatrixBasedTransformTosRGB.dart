import 'dart:typed_data';
import '../RestrictedICCProfile.dart';
import '../ICCProfile.dart';
import '../tags/ICCXYZType.dart';
import '../../j2k/image/DataBlkInt.dart';
import '../../j2k/image/DataBlkFloat.dart';
import 'LookUpTableFP.dart';
import 'LookUpTable32LinearSRGBtoSRGB.dart';
import '../../colorspace/ColorSpace.dart';

/// Transform for applying ICCProfiling to an input DataBlk
class MatrixBasedTransformTosRGB {
  static const String eol = '\n'; // System.getProperty ("line.separator");

  // Start of contant definitions:

  // Convenience
  static const int RED = ICCProfile.RED;
  static const int GREEN = ICCProfile.GREEN;
  static const int BLUE = ICCProfile.BLUE;

  // Define the PCS to linear sRGB matrix coefficients
  static const double SRGB00 = 3.1337;
  static const double SRGB01 = -1.6173;
  static const double SRGB02 = -0.4907;
  static const double SRGB10 = -0.9785;
  static const double SRGB11 = 1.9162;
  static const double SRGB12 = 0.0334;
  static const double SRGB20 = 0.0720;
  static const double SRGB21 = -0.2290;
  static const double SRGB22 = 1.4056;

  // Define constants representing the indices into the matrix array
  static const int M00 = 0;
  static const int M01 = 1;
  static const int M02 = 2;
  static const int M10 = 3;
  static const int M11 = 4;
  static const int M12 = 5;
  static const int M20 = 6;
  static const int M21 = 7;
  static const int M22 = 8;

  static const double ksRGBExponent = (1.0 / 2.4);
  static const double ksRGBScaleAfterExp = 1.055;
  static const double ksRGBReduceAfterExp = 0.055;
  static const double ksRGBShadowCutoff = 0.0031308;
  static const double ksRGBShadowSlope = 12.92;

  // End of contant definitions:

  late final Float64List matrix; // Matrix coefficients

  final List<LookUpTableFP?> fLut = List.filled(3, null);
  late final LookUpTable32LinearSRGBtoSRGB lut; // Linear sRGB to sRGB LUT

  late final Int32List dwMaxValue;
  late final Int32List dwShiftValue;

  // int dwMaxCols = 0; // Maximum number of columns that can be processed
  // int dwMaxRows = 0; // Maximum number of rows that can be processed

  List<Float32List>? fBuf; // Intermediate output of the first LUT operation.

  /// String representation of class
  /// @return suitable representation for class
  @override
  String toString() {
    int i, j;

    StringBuffer rep = StringBuffer("[MatrixBasedTransformTosRGB: ");

    StringBuffer body = StringBuffer("  ");
    body.write("$eol ksRGBExponent= $ksRGBExponent");
    body.write("$eol ksRGBScaleAfterExp= $ksRGBScaleAfterExp");
    body.write("$eol ksRGBReduceAfterExp= $ksRGBReduceAfterExp");

    body.write("$eol dwMaxValues= ${dwMaxValue[0]}, ${dwMaxValue[1]}, ${dwMaxValue[2]}");

    body.write("$eol dwShiftValues= ${dwShiftValue[0]}, ${dwShiftValue[1]}, ${dwShiftValue[2]}");

    body.write("$eol$eol fLut= ");
    body.write("$eol${ColorSpace.indent("  ", "fLut[RED]=  ${fLut[0]}")}");
    body.write("$eol${ColorSpace.indent("  ", "fLut[GRN]=  ${fLut[1]}")}");
    body.write("$eol${ColorSpace.indent("  ", "fLut[BLU]=  ${fLut[2]}")}");

    // Print the matrix
    body.write("$eol$eol [matrix ");
    for (i = 0; i < 3; ++i) {
      body.write("$eol  ");
      for (j = 0; j < 3; ++j) {
        body.write("${matrix[3 * i + j]}   ");
      }
    }
    body.write("]");

    // Print the LinearSRGBtoSRGB lut.
    body.write("$eol$eol $lut");

    rep.write(ColorSpace.indent("  ", body.toString()));
    return (rep..write("]")).toString();
  }

  /// Construct a 3 component transform based on an input RestricedICCProfile
  /// This transform will pass the input throught a floating point lut (LookUpTableFP),
  /// apply a matrix to the output and finally pass the intermediate buffer through
  /// a 32-bit lut (LookUpTable32LinearSRGBtoSRGB).  This operation will be designated (LFP*M*L32) * Data
  /// The operators (LFP*M*L8) are constructed here.  Although the data for
  /// only one component is returned, the transformation must be done for all
  /// components, because the matrix application involves a linear combination of
  /// component input to produce the output.
  ///   @param rICC input profile
  ///   @param dwMaxValue clipping value for output.
  ///   @param dwMaxCols number of columns to transform
  ///   @param dwMaxRows number of rows to transform
  MatrixBasedTransformTosRGB(
      RestrictedICCProfile rICC, List<int> dwMaxValue, List<int> dwShiftValue) {
    // Assure the proper type profile for this xform.
    if (rICC.getType() != RestrictedICCProfile.kThreeCompInput)
      throw ArgumentError(
          "MatrixBasedTransformTosRGB: wrong type ICCProfile supplied");

    int c; // component index.
    this.dwMaxValue = Int32List.fromList(dwMaxValue);
    this.dwShiftValue = Int32List.fromList(dwShiftValue);

    // Create the LUTFP from the input profile.
    for (c = 0; c < 3; ++c) {
      fLut[c] =
          LookUpTableFP.createInstance(rICC.trc[c], dwMaxValue[c] + 1);
    }

    // Create the Input linear to PCS matrix
    matrix = createMatrix(rICC, this.dwMaxValue); // Create and matrix from the ICC profile.

    // Create the final LUT32
    lut = LookUpTable32LinearSRGBtoSRGB.createInstance(
        dwMaxValue[0],
        dwMaxValue[0],
        ksRGBShadowCutoff,
        ksRGBShadowSlope,
        ksRGBScaleAfterExp,
        ksRGBExponent,
        ksRGBReduceAfterExp);
  }

  Float64List createMatrix(RestrictedICCProfile rICC, Int32List maxValues) {
    // Coefficients from the input linear to PCS matrix
    double dfPCS00 = ICCXYZType.xyzToDouble(rICC.colorant![RED]!.x);
    double dfPCS01 = ICCXYZType.xyzToDouble(rICC.colorant![GREEN]!.x);
    double dfPCS02 = ICCXYZType.xyzToDouble(rICC.colorant![BLUE]!.x);
    double dfPCS10 = ICCXYZType.xyzToDouble(rICC.colorant![RED]!.y);
    double dfPCS11 = ICCXYZType.xyzToDouble(rICC.colorant![GREEN]!.y);
    double dfPCS12 = ICCXYZType.xyzToDouble(rICC.colorant![BLUE]!.y);
    double dfPCS20 = ICCXYZType.xyzToDouble(rICC.colorant![RED]!.z);
    double dfPCS21 = ICCXYZType.xyzToDouble(rICC.colorant![GREEN]!.z);
    double dfPCS22 = ICCXYZType.xyzToDouble(rICC.colorant![BLUE]!.z);

    Float64List matrix = Float64List(9);
    matrix[M00] = maxValues[0] *
        (SRGB00 * dfPCS00 + SRGB01 * dfPCS10 + SRGB02 * dfPCS20);
    matrix[M01] = maxValues[0] *
        (SRGB00 * dfPCS01 + SRGB01 * dfPCS11 + SRGB02 * dfPCS21);
    matrix[M02] = maxValues[0] *
        (SRGB00 * dfPCS02 + SRGB01 * dfPCS12 + SRGB02 * dfPCS22);
    matrix[M10] = maxValues[1] *
        (SRGB10 * dfPCS00 + SRGB11 * dfPCS10 + SRGB12 * dfPCS20);
    matrix[M11] = maxValues[1] *
        (SRGB10 * dfPCS01 + SRGB11 * dfPCS11 + SRGB12 * dfPCS21);
    matrix[M12] = maxValues[1] *
        (SRGB10 * dfPCS02 + SRGB11 * dfPCS11 + SRGB12 * dfPCS22);
    matrix[M20] = maxValues[2] *
        (SRGB20 * dfPCS00 + SRGB21 * dfPCS10 + SRGB22 * dfPCS20);
    matrix[M21] = maxValues[2] *
        (SRGB20 * dfPCS01 + SRGB21 * dfPCS11 + SRGB22 * dfPCS21);
    matrix[M22] = maxValues[2] *
        (SRGB20 * dfPCS02 + SRGB21 * dfPCS12 + SRGB22 * dfPCS22);

    return matrix;
  }

  /// Performs the transform.  Pass the input throught the LookUpTableFP, apply the
  /// matrix to the output and finally pass the intermediate buffer through the
  /// LookUpTable32LinearSRGBtoSRGB.  This operation is designated (LFP*M*L32) * Data are already
  /// constructed.  Although the data for only one component is returned, the
  /// transformation must be done for all components, because the matrix application
  /// involves a linear combination of component input to produce the output.
  ///   @param ncols number of columns in the input
  ///   @param nrows number of rows in the input
  ///   @param inb input data block
  ///   @param outb output data block
  /// @exception MatrixBasedTransformException
  void applyInt(List<DataBlkInt> inb, List<DataBlkInt> outb) {
    List<Int32List?> input = List.filled(3, null);
    List<Int32List?> output = List.filled(3, null);

    int nrows = inb[0].h;
    int ncols = inb[0].w;

    if ((fBuf == null) || (fBuf![0].length < ncols * nrows)) {
      fBuf = List.generate(3, (_) => Float32List(ncols * nrows));
    }

    // for each component (rgb)
    for (int c = 0; c < 3; ++c) {
      // Reference the input and output samples.
      input[c] = inb[c].getDataInt();
      output[c] = outb[c].getDataInt();

      // Assure a properly sized output buffer.
      if (output[c] == null || output[c]!.length < input[c]!.length) {
        output[c] = Int32List(input[c]!.length);
        outb[c].setDataInt(output[c]!);
      }

      // The first thing to do is to process the input into a standard form
      // and through the first input LUT, producing floating point output values
      standardizeMatrixLineThroughLutInt(
          inb[c], fBuf![c], dwMaxValue[c], fLut[c]!);
    }

    // For each row and column
    Float32List ra = fBuf![RED];
    Float32List ga = fBuf![GREEN];
    Float32List ba = fBuf![BLUE];

    Int32List ro = output[RED]!;
    Int32List go = output[GREEN]!;
    Int32List bo = output[BLUE]!;
    Int32List lut32 = lut.lut;

    double r, g, b;
    int val, index = 0;
    for (int y = 0; y < inb[0].h; ++y) {
      int end = index + inb[0].w;
      while (index < end) {
        // Calculate the rgb pixel indices for this row / column
        r = ra[index];
        g = ga[index];
        b = ba[index];

        // Apply the matrix to the intermediate floating point data in order to index the
        // final LUT.
        val = (matrix[M00] * r + matrix[M01] * g + matrix[M02] * b + 0.5)
            .toInt();
        // Clip the calculated value if necessary..
        if (val < 0)
          ro[index] = lut32[0];
        else if (val >= lut32.length)
          ro[index] = lut32[lut32.length - 1];
        else
          ro[index] = lut32[val];

        val = (matrix[M10] * r + matrix[M11] * g + matrix[M12] * b + 0.5)
            .toInt();
        // Clip the calculated value if necessary..
        if (val < 0)
          go[index] = lut32[0];
        else if (val >= lut32.length)
          go[index] = lut32[lut32.length - 1];
        else
          go[index] = lut32[val];

        val = (matrix[M20] * r + matrix[M21] * g + matrix[M22] * b + 0.5)
            .toInt();
        // Clip the calculated value if necessary..
        if (val < 0)
          bo[index] = lut32[0];
        else if (val >= lut32.length)
          bo[index] = lut32[lut32.length - 1];
        else
          bo[index] = lut32[val];

        index++;
      }
    }
  }

  /// Performs the transform.  Pass the input throught the LookUpTableFP, apply the
  /// matrix to the output and finally pass the intermediate buffer through the
  /// LookUpTable32LinearSRGBtoSRGB.  This operation is designated (LFP*M*L32) * Data are already
  /// constructed.  Although the data for only one component is returned, the
  /// transformation must be done for all components, because the matrix application
  /// involves a linear combination of component input to produce the output.
  ///   @param ncols number of columns in the input
  ///   @param nrows number of rows in the input
  ///   @param inb input data block
  ///   @param outb output data block
  /// @exception MatrixBasedTransformException
  void applyFloat(List<DataBlkFloat> inb, List<DataBlkFloat> outb) {
    List<Float32List?> input = List.filled(3, null);
    List<Float32List?> output = List.filled(3, null);

    int nrows = inb[0].h;
    int ncols = inb[0].w;

    if ((fBuf == null) || (fBuf![0].length < ncols * nrows)) {
      fBuf = List.generate(3, (_) => Float32List(ncols * nrows));
    }

    // for each component (rgb)
    for (int c = 0; c < 3; ++c) {
      // Reference the input and output pixels.
      input[c] = inb[c].getDataFloat();
      output[c] = outb[c].getDataFloat();

      // Assure a properly sized output buffer.
      if (output[c] == null || output[c]!.length < input[c]!.length) {
        output[c] = Float32List(input[c]!.length);
        outb[c].setDataFloat(output[c]!);
      }

      // The first thing to do is to process the input into a standard form
      // and through the first input LUT, producing floating point output values
      standardizeMatrixLineThroughLutFloat(
          inb[c], fBuf![c], dwMaxValue[c].toDouble(), fLut[c]!);
    }

    Int32List lut32 = lut.lut;

    // For each row and column
    int index = 0, val;
    for (int y = 0; y < inb[0].h; ++y) {
      int end = index + inb[0].w;
      while (index < end) {
        // Calculate the rgb pixel indices for this row / column

        // Apply the matrix to the intermediate floating point data inorder to index the
        // final LUT.
        val = (matrix[M00] * fBuf![RED][index] +
                matrix[M01] * fBuf![GREEN][index] +
                matrix[M02] * fBuf![BLUE][index] +
                0.5)
            .toInt();
        // Clip the calculated value if necessary..
        if (val < 0)
          output[0]![index] = lut32[0].toDouble();
        else if (val >= lut32.length)
          output[0]![index] = lut32[lut32.length - 1].toDouble();
        else
          output[0]![index] = lut32[val].toDouble();

        val = (matrix[M10] * fBuf![RED][index] +
                matrix[M11] * fBuf![GREEN][index] +
                matrix[M12] * fBuf![BLUE][index] +
                0.5)
            .toInt();
        // Clip the calculated value if necessary..
        if (val < 0)
          output[1]![index] = lut32[0].toDouble();
        else if (val >= lut32.length)
          output[1]![index] = lut32[lut32.length - 1].toDouble();
        else
          output[1]![index] = lut32[val].toDouble();

        val = (matrix[M20] * fBuf![RED][index] +
                matrix[M21] * fBuf![GREEN][index] +
                matrix[M22] * fBuf![BLUE][index] +
                0.5)
            .toInt();
        // Clip the calculated value if necessary..
        if (val < 0)
          output[2]![index] = lut32[0].toDouble();
        else if (val >= lut32.length)
          output[2]![index] = lut32[lut32.length - 1].toDouble();
        else
          output[2]![index] = lut32[val].toDouble();

        index++;
      }
    }
  }

  static void standardizeMatrixLineThroughLutInt(
      DataBlkInt inb, // input datablock
      Float32List out, // output data reference
      int dwInputMaxValue, // Maximum value of the input for clipping
      LookUpTableFP lut // Inital input LUT
      ) {
    int wTemp, j = 0;
    Int32List input = inb.getDataInt()!; // input pixel reference
    Float32List lutFP = lut.lut;
    for (int y = inb.uly; y < inb.uly + inb.h; ++y) {
      for (int x = inb.ulx; x < inb.ulx + inb.w; ++x) {
        int i = inb.offset + (y - inb.uly) * inb.scanw + (x - inb.ulx); // pixel index.
        if (input[i] > dwInputMaxValue)
          wTemp = dwInputMaxValue;
        else if (input[i] < 0)
          wTemp = 0;
        else
          wTemp = input[i];
        out[j++] = lutFP[wTemp];
      }
    }
  }

  static void standardizeMatrixLineThroughLutFloat(
      DataBlkFloat inb, // input datablock
      Float32List out, // output data reference
      double dwInputMaxValue, // Maximum value of the input for clipping
      LookUpTableFP lut // Inital input LUT
      ) {
    int j = 0;
    double wTemp;
    Float32List input = inb.getDataFloat()!; // input pixel reference
    Float32List lutFP = lut.lut;

    for (int y = inb.uly; y < inb.uly + inb.h; ++y) {
      for (int x = inb.ulx; x < inb.ulx + inb.w; ++x) {
        int i = inb.offset + (y - inb.uly) * inb.scanw + (x - inb.ulx); // pixel index.
        if (input[i] > dwInputMaxValue)
          wTemp = dwInputMaxValue;
        else if (input[i] < 0)
          wTemp = 0;
        else
          wTemp = input[i];
        out[j++] = lutFP[wTemp.toInt()];
      }
    }
  }
}


import 'dart:math' as math;
import 'dart:typed_data';

import '../../encoder/EncoderSpecs.dart';
import '../../image/DataBlk.dart';
import '../../wavelet/analysis/CBlkWTData.dart';
import '../../wavelet/analysis/CBlkWTDataFloat.dart';
import '../../wavelet/analysis/CBlkWTDataInt.dart';
import '../../wavelet/analysis/CBlkWTDataSrc.dart';
import '../../wavelet/analysis/SubbandAn.dart';
import '../../wavelet/subband.dart';
import '../GuardBitsSpec.dart';
import '../QuantStepSizeSpec.dart';
import '../QuantTypeSpec.dart';
import 'Quantizer.dart';

/// This class implements scalar quantization of integer or floating-point
/// valued source data. The source data is the wavelet transformed image data
/// and the output is the quantized wavelet coefficients represented in
/// sign-magnitude (see below).
///
/// Sign magnitude representation is used (instead of two's complement) for
/// the output data. The most significant bit is used for the sign (0 if
/// positive, 1 if negative). Then the magnitude of the quantized coefficient
/// is stored in the next M most significat bits. The rest of the bits (least
/// significant bits) can contain a fractional value of the quantized
/// coefficient. This fractional value is not to be coded by the entropy
/// coder. However, it can be used to compute rate-distortion measures with
/// greater precision.
///
/// The value of M is determined for each subband as the sum of the number
/// of guard bits G and the nominal range of quantized wavelet coefficients in
/// the corresponding subband (Rq), minus 1:
///
/// M = G + Rq -1
///
/// The value of G should be the same for all subbands. The value of Rq
/// depends on the quantization step size, the nominal range of the component
/// before the wavelet transform and the analysis gain of the subband (see
/// Subband).
///
/// The blocks of data that are requested should not cross subband
/// boundaries.
///
/// @see Subband
///
/// @see Quantizer
class StdQuantizer extends Quantizer {
  /// The number of mantissa bits for the quantization steps
  static const int QSTEP_MANTISSA_BITS = 11;

  /// The number of exponent bits for the quantization steps
  // NOTE: formulas in 'convertFromExpMantissa()' and
  // 'convertToExpMantissa()' methods do not support more than 5 bits.
  static const int QSTEP_EXPONENT_BITS = 5;

  /// The maximum value of the mantissa for the quantization steps
  static const int QSTEP_MAX_MANTISSA = (1 << QSTEP_MANTISSA_BITS) - 1;

  /// The maximum value of the exponent for the quantization steps
  static const int QSTEP_MAX_EXPONENT = (1 << QSTEP_EXPONENT_BITS) - 1;

  /// The ID for no quantization (i.e. reversible)
  static const int SQCX_NO_QUANTIZATION = 0;

  /// The ID for scalar derived quantization
  static const int SQCX_SCALAR_DERIVED = 1;

  /// The ID for scalar expounded quantization
  static const int SQCX_SCALAR_EXPOUNDED = 2;

  /// The shift for the guard bits in the Sqcd/Sqcc field
  static const int SQCX_GB_SHIFT = 5;

  /// The shift for the exponent in the SPqcd/SPqcc field
  static const int SQCX_EXP_SHIFT = 11;

  /// Natural log of 2, used as a convenience variable
  static final double log2 = math.log(2);

  /// The quantization type specifications
  late QuantTypeSpec qts;

  /// The quantization step size specifications
  late QuantStepSizeSpec qsss;

  /// The guard bits specifications
  late GuardBitsSpec gbs;

  /// The 'CBlkWTDataFloat' object used to request data, used when
  /// quantizing floating-point data.
  // This variable makes the class thread unsafe, but it avoids allocating
  // new objects for code-block that is quantized.
  CBlkWTDataFloat? infblk;

  /// Initializes the source of wavelet transform coefficients. The
  /// constructor takes information on whether the quantizer is in
  /// reversible, derived or expounded mode. If the quantizer is reversible
  /// the value of 'derived' is ignored. If the source data is not integer
  /// (int) then the quantizer can not be reversible.
  ///
  /// After initializing member attributes, getAnSubbandTree is called for
  /// all components setting the 'stepWMSE' for all subbands in the current
  /// tile.
  ///
  /// [src] The source of wavelet transform coefficients.
  ///
  /// [encSpec] The encoder specifications
  StdQuantizer(CBlkWTDataSrc src, EncoderSpecs encSpec) : super(src) {
    qts = encSpec.qts;
    qsss = encSpec.qsss;
    gbs = encSpec.gbs;
  }

  /// Returns the quantization type spec object associated to the quantizer.
  ///
  /// Returns The quantization type spec
  QuantTypeSpec getQuantTypeSpec() {
    return qts;
  }

  /// Returns the number of guard bits used by this quantizer in the given
  /// tile-component.
  ///
  /// [t] Tile index
  ///
  /// [c] Component index
  ///
  /// Returns The number of guard bits
  @override
  int getNumGuardBits(int t, int c) {
    return (gbs.getTileCompVal(t, c) as int);
  }

  /// Returns true if the quantized data is reversible, for the specified
  /// tile-component. For the quantized data to be reversible it is necessary
  /// and sufficient that the quantization is reversible.
  ///
  /// [t] The tile to test for reversibility
  ///
  /// [c] The component to test for reversibility
  ///
  /// Returns True if the quantized data is reversible, false if not.
  @override
  bool isReversible(int t, int c) {
    return qts.isReversible(t, c);
  }

  /// Returns true if given tile-component uses derived quantization step
  /// sizes.
  ///
  /// [t] Tile index
  ///
  /// [c] Component index
  ///
  /// Returns True if derived
  @override
  bool isDerived(int t, int c) {
    return qts.isDerived(t, c);
  }

  /// Returns the next code-block in the current tile for the specified
  /// component, as a copy (see below). The order in which code-blocks are
  /// returned is not specified. However each code-block is returned only
  /// once and all code-blocks will be returned if the method is called 'N'
  /// times, where 'N' is the number of code-blocks in the tile. After all
  /// the code-blocks have been returned for the current tile calls to this
  /// method will return 'null'.
  ///
  /// When changing the current tile (through 'setTile()' or 'nextTile()')
  /// this method will always return the first code-block, as if this method
  /// was never called before for the new current tile.
  ///
  /// The data returned by this method is always a copy of the
  /// data. Therfore it can be modified "in place" without any problems after
  /// being returned. The 'offset' of the returned data is 0, and the 'scanw'
  /// is the same as the code-block width. See the 'CBlkWTData' class.
  ///
  /// The 'ulx' and 'uly' members of the returned 'CBlkWTData' object
  /// contain the coordinates of the top-left corner of the block, with
  /// respect to the tile, not the subband.
  ///
  /// [c] The component for which to return the next code-block.
  ///
  /// [cblk] If non-null this object will be used to return the new
  /// code-block. If null a new one will be allocated and returned. If the
  /// "data" array of the object is non-null it will be reused, if possible,
  /// to return the data.
  ///
  /// Returns The next code-block in the current tile for component 'n', or
  /// null if all code-blocks for the current tile have been returned.
  ///
  /// @see CBlkWTData
  @override
  CBlkWTData? getNextCodeBlock(int c, CBlkWTData? cblk) {
    return getNextInternCodeBlock(c, cblk);
  }

  /// Returns the next code-block in the current tile for the specified
  /// component. The order in which code-blocks are returned is not
  /// specified. However each code-block is returned only once and all
  /// code-blocks will be returned if the method is called 'N' times, where
  /// 'N' is the number of code-blocks in the tile. After all the code-blocks
  /// have been returned for the current tile calls to this method will
  /// return 'null'.
  ///
  /// When changing the current tile (through 'setTile()' or 'nextTile()')
  /// this method will always return the first code-block, as if this method
  /// was never called before for the new current tile.
  ///
  /// The data returned by this method can be the data in the internal
  /// buffer of this object, if any, and thus can not be modified by the
  /// caller. The 'offset' and 'scanw' of the returned data can be
  /// arbitrary. See the 'CBlkWTData' class.
  ///
  /// The 'ulx' and 'uly' members of the returned 'CBlkWTData' object
  /// contain the coordinates of the top-left corner of the block, with
  /// respect to the tile, not the subband.
  ///
  /// [c] The component for which to return the next code-block.
  ///
  /// [cblk] If non-null this object will be used to return the new
  /// code-block. If null a new one will be allocated and returned. If the
  /// "data" array of the object is non-null it will be reused, if possible,
  /// to return the data.
  ///
  /// Returns The next code-block in the current tile for component 'n', or
  /// null if all code-blocks for the current tile have been returned.
  ///
  /// @see CBlkWTData
  @override
  CBlkWTData? getNextInternCodeBlock(int c, CBlkWTData? cblk) {
    // NOTE: this method is declared final since getNextCodeBlock() relies
    // on this particular implementation
    int k, j;
    int tmp, shiftBits, jmin;
    int w, h;
    Int32List outarr;
    Float32List? infarr;
    CBlkWTDataFloat? infblk;
    double invstep; // The inverse of the quantization step size
    bool intq; // flag for quantizig ints
    SubbandAn sb;
    double stepUDR; // The quantization step size (for a dynamic
    // range of 1, or unit)
    final tIdx = getTileIdx();
    int g = (gbs.getTileCompVal(tIdx, c) as int);

    // Are we quantizing ints or floats?
    intq = (src.getDataType(tIdx, c) == DataBlk.typeInt);

    // Check that we have an output object
    if (cblk == null) {
      cblk = CBlkWTDataInt();
    }

    // Cache input float code-block
    infblk = this.infblk;

    // Get data to quantize. When quantizing int data 'cblk' is used to
    // get the data to quantize and to return the quantized data as well,
    // that's why 'getNextCodeBlock()' is used. This can not be done when
    // quantizing float data because of the different data types, that's
    // why 'getNextInternCodeBlock()' is used in that case.
    if (intq) {
      // Source data is int
      cblk = src.getNextCodeBlock(c, cblk);
      if (cblk == null) {
        return null; // No more code-blocks in current tile for comp.
      }
      // Input and output arrays are the same (for "in place" quant.)
      outarr = cblk.getData() as Int32List;
    } else {
      // Source data is float
      // Can not use 'cblk' to get float data, use 'infblk'
      infblk = src.getNextInternCodeBlock(c, infblk) as CBlkWTDataFloat?;
      if (infblk == null) {
        // Release buffer from infblk: this enables to garbage collect
        // the big buffer when we are done with last code-block of
        // component.
        this.infblk?.setDataFloat(null);
        return null; // No more code-blocks in current tile for comp.
      }
      this.infblk = infblk; // Save local cache
      infarr = infblk.getDataFloat();
      // Get output data array and check that there is memory to put the
      // quantized coeffs in
      outarr = cblk.getData() as Int32List? ?? Int32List(0);
      if (outarr.length < infblk.w * infblk.h) {
        outarr = Int32List(infblk.w * infblk.h);
        cblk.setData(outarr);
      }
      cblk.m = infblk.m;
      cblk.n = infblk.n;
      cblk.sb = infblk.sb;
      cblk.ulx = infblk.ulx;
      cblk.uly = infblk.uly;
      cblk.w = infblk.w;
      cblk.h = infblk.h;
      cblk.wmseScaling = infblk.wmseScaling;
      cblk.offset = 0;
      cblk.scanw = cblk.w;
    }

    // Cache width, height and subband of code-block
    w = cblk.w;
    h = cblk.h;
    sb = cblk.sb!;

    if (isReversible(tIdx, c)) {
      // Reversible only for int data
      cblk.magbits = g - 1 + src.getNomRangeBits(c) + sb.anGainExp;
      shiftBits = 31 - cblk.magbits;

      // Update the convertFactor field
      cblk.convertFactor = (1 << shiftBits).toDouble();

      // Since we used getNextCodeBlock() to get the int data then
      // 'offset' is 0 and 'scanw' is the width of the code-block The
      // input and output arrays are the same (i.e. "in place")
      for (j = w * h - 1; j >= 0; j--) {
        tmp = (outarr[j] << shiftBits);
        outarr[j] = ((tmp < 0) ? (1 << 31) | (-tmp) : tmp);
      }
    } else {
      // Non-reversible, use step size
      double baseStep = (qsss.getTileCompVal(tIdx, c) as double);

      // Calculate magnitude bits and quantization step size
      if (isDerived(tIdx, c)) {
        cblk.magbits = g -
            1 +
            sb.level -
            (math.log(baseStep) / log2).floor();
        stepUDR = baseStep / (1 << sb.level);
      } else {
        cblk.magbits = g -
            1 -
            (math.log(baseStep / (sb.l2Norm * (1 << sb.anGainExp))) / log2)
                .floor();
        stepUDR = baseStep / (sb.l2Norm * (1 << sb.anGainExp));
      }
      shiftBits = 31 - cblk.magbits;
      // Calculate step that decoder will get and use that one.
      stepUDR = convertFromExpMantissa(convertToExpMantissa(stepUDR));
      invstep = 1.0 /
          ((1 << (src.getNomRangeBits(c) + sb.anGainExp)) * stepUDR);
      // Normalize to magnitude bits (output fractional point)
      invstep *= (1 << (shiftBits - src.getFixedPoint(c)));

      // Update convertFactor and stepSize fields
      cblk.convertFactor = invstep;
      cblk.stepSize =
          ((1 << (src.getNomRangeBits(c) + sb.anGainExp)) * stepUDR);

      if (intq) {
        // Quantizing int data
        // Since we used getNextCodeBlock() to get the int data then
        // 'offset' is 0 and 'scanw' is the width of the code-block
        // The input and output arrays are the same (i.e. "in place")
        for (j = w * h - 1; j >= 0; j--) {
          tmp = (outarr[j] * invstep).toInt();
          outarr[j] = ((tmp < 0) ? (1 << 31) | (-tmp) : tmp);
        }
      } else {
        // Quantizing float data
        j = w * h - 1;
        k = infblk!.offset + (h - 1) * infblk.scanw + w - 1;
        jmin = w * (h - 1);
        for (; j >= 0; jmin -= w) {
          for (; j >= jmin; k--, j--) {
            tmp = (infarr![k] * invstep).toInt();
            outarr[j] = ((tmp < 0) ? (1 << 31) | (-tmp) : tmp);
          }
          // Jump to beggining of previous line in input
          k -= infblk.scanw - w;
        }
      }
    }
    // Return the quantized code-block
    return cblk;
  }

  /// Calculates the parameters of the SubbandAn objects that depend on the
  /// Quantizer. The 'stepWMSE' field is calculated for each subband which is
  /// a leaf in the tree rooted at 'sb', for the specified component. The
  /// subband tree 'sb' must be the one for the component 'n'.
  ///
  /// [sb] The root of the subband tree.
  ///
  /// [c] The component index
  ///
  /// @see SubbandAn#stepWMSE
  @override
  void calcSbParams(SubbandAn sb, int c) {
    double baseStep;
    final tIdx = getTileIdx();

    if (sb.stepWMSE > 0.0) // parameters already calculated
      return;
    if (!sb.isNode) {
      if (isReversible(tIdx, c)) {
        sb.stepWMSE = math.pow(2, -(src.getNomRangeBits(c) << 1)) *
            sb.l2Norm *
            sb.l2Norm;
      } else {
        baseStep = (qsss.getTileCompVal(tIdx, c) as double);
        if (isDerived(tIdx, c)) {
          sb.stepWMSE = baseStep *
              baseStep *
              math.pow(2, (sb.anGainExp - sb.level) << 1) *
              sb.l2Norm *
              sb.l2Norm;
        } else {
          sb.stepWMSE = baseStep * baseStep;
        }
      }
    } else {
      calcSbParams(sb.getLL() as SubbandAn, c);
      calcSbParams(sb.getHL() as SubbandAn, c);
      calcSbParams(sb.getLH() as SubbandAn, c);
      calcSbParams(sb.getHH() as SubbandAn, c);
      sb.stepWMSE = 1.0; // Signal that we already calculated this branch
    }
  }

  /// Converts the floating point value to its exponent-mantissa
  /// representation. The mantissa occupies the 11 least significant bits
  /// (bits 10-0), and the exponent the previous 5 bits (bits 15-11).
  ///
  /// [step] The quantization step, normalized to a dynamic range of 1.
  ///
  /// Returns The exponent mantissa representation of the step.
  static int convertToExpMantissa(double step) {
    int exp;

    exp = (-math.log(step) / log2).ceil();
    if (exp > QSTEP_MAX_EXPONENT) {
      // If step size is too small for exponent representation, use the
      // minimum, which is exponent QSTEP_MAX_EXPONENT and mantissa 0.
      return (QSTEP_MAX_EXPONENT << QSTEP_MANTISSA_BITS);
    }
    // NOTE: this formula does not support more than 5 bits for the
    // exponent, otherwise (-1<<exp) might overflow (the - is used to be
    // able to represent 2**31)
    return (exp << QSTEP_MANTISSA_BITS) |
        (((-step * (-1 << exp) - 1.0) * (1 << QSTEP_MANTISSA_BITS) + 0.5)
            .toInt());
  }

  /// Converts the exponent-mantissa representation to its floating-point
  /// value. The mantissa occupies the 11 least significant bits (bits 10-0),
  /// and the exponent the previous 5 bits (bits 15-11).
  ///
  /// [ems] The exponent-mantissa representation of the step.
  ///
  /// Returns The floating point representation of the step, normalized to a
  /// dynamic range of 1.
  static double convertFromExpMantissa(int ems) {
    // NOTE: this formula does not support more than 5 bits for the
    // exponent, otherwise (-1<<exp) might overflow (the - is used to be
    // able to represent 2**31)
    return (-1.0 -
            ((ems & QSTEP_MAX_MANTISSA).toDouble()) /
                ((1 << QSTEP_MANTISSA_BITS).toDouble())) /
        ((-1 << ((ems >> QSTEP_MANTISSA_BITS) & QSTEP_MAX_EXPONENT))
            .toDouble());
  }

  /// Returns the maximum number of magnitude bits in any subband of the
  /// current tile.
  ///
  /// [c] the component number
  ///
  /// Returns The maximum number of magnitude bits in all subbands of the
  /// current tile.
  @override
  int getMaxMagBits(int c) {
    final tIdx = getTileIdx();
    Subband sb = getAnSubbandTree(tIdx, c);
    if (isReversible(tIdx, c)) {
      return getMaxMagBitsRev(sb, c);
    } else {
      if (isDerived(tIdx, c)) {
        return getMaxMagBitsDerived(sb, tIdx, c);
      } else {
        return getMaxMagBitsExpounded(sb, tIdx, c);
      }
    }
  }

  /// Returns the maximum number of magnitude bits in any subband of the
  /// current tile if reversible quantization is used
  ///
  /// [sb] The root of the subband tree of the current tile
  ///
  /// [c] the component number
  ///
  /// Returns The highest number of magnitude bit-planes
  int getMaxMagBitsRev(Subband sb, int c) {
    int tmp, max = 0;
    final tIdx = getTileIdx();
    int g = (gbs.getTileCompVal(tIdx, c) as int);

    if (!sb.isNode) {
      return g - 1 + src.getNomRangeBits(c) + (sb as SubbandAn).anGainExp;
    }

    max = getMaxMagBitsRev(sb.getLL(), c);
    tmp = getMaxMagBitsRev(sb.getLH(), c);
    if (tmp > max) max = tmp;
    tmp = getMaxMagBitsRev(sb.getHL(), c);
    if (tmp > max) max = tmp;
    tmp = getMaxMagBitsRev(sb.getHH(), c);
    if (tmp > max) max = tmp;

    return max;
  }

  /// Returns the maximum number of magnitude bits in any subband in the
  /// given tile-component if derived quantization is used
  ///
  /// [sb] The root of the subband tree of the tile-component
  ///
  /// [t] Tile index
  ///
  /// [c] Component index
  ///
  /// Returns The highest number of magnitude bit-planes
  int getMaxMagBitsDerived(Subband sb, int t, int c) {
    int tmp, max = 0;
    int g = (gbs.getTileCompVal(t, c) as int);

    if (!sb.isNode) {
      double baseStep = (qsss.getTileCompVal(t, c) as double);
      return g - 1 + sb.level - (math.log(baseStep) / log2).floor();
    }

    max = getMaxMagBitsDerived(sb.getLL(), t, c);
    tmp = getMaxMagBitsDerived(sb.getLH(), t, c);
    if (tmp > max) max = tmp;
    tmp = getMaxMagBitsDerived(sb.getHL(), t, c);
    if (tmp > max) max = tmp;
    tmp = getMaxMagBitsDerived(sb.getHH(), t, c);
    if (tmp > max) max = tmp;

    return max;
  }

  /// Returns the maximum number of magnitude bits in any subband in the
  /// given tile-component if expounded quantization is used
  ///
  /// [sb] The root of the subband tree of the tile-component
  ///
  /// [t] Tile index
  ///
  /// [c] Component index
  ///
  /// Returns The highest number of magnitude bit-planes
  int getMaxMagBitsExpounded(Subband sb, int t, int c) {
    int tmp, max = 0;
    int g = (gbs.getTileCompVal(t, c) as int);

    if (!sb.isNode) {
      double baseStep = (qsss.getTileCompVal(t, c) as double);
      return g -
          1 -
          (math.log(baseStep /
                      ((sb as SubbandAn).l2Norm * (1 << sb.anGainExp))) /
                  log2)
              .floor();
    }

    max = getMaxMagBitsExpounded(sb.getLL(), t, c);
    tmp = getMaxMagBitsExpounded(sb.getLH(), t, c);
    if (tmp > max) max = tmp;
    tmp = getMaxMagBitsExpounded(sb.getHL(), t, c);
    if (tmp > max) max = tmp;
    tmp = getMaxMagBitsExpounded(sb.getHH(), t, c);
    if (tmp > max) max = tmp;

    return max;
  }
}



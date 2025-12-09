import 'dart:typed_data';
import '../WaveletFilter.dart';
import '../FilterTypes.dart';
import 'AnWtFilterFloat.dart';

/// This class inherits from the analysis wavelet filter definition
/// for int data. It implements the forward wavelet transform
/// specifically for the 9x7 filter. The implementation is based on
/// the lifting scheme.
///
/// See the AnWTFilter class for details such as
/// normalization, how to split odd-length signals, etc. In particular,
/// this method assumes that the low-pass coefficient is computed first.
class AnWTFilterFloatLift9x7 extends AnWTFilterFloat {
  /// The low-pass synthesis filter of the 9x7 wavelet transform
  static const List<double> lpSynthesisFilter = [
    -0.091272,
    -0.057544,
    0.591272,
    1.115087,
    0.591272,
    -0.057544,
    -0.091272
  ];

  /// The high-pass synthesis filter of the 9x7 wavelet transform
  static const List<double> hpSynthesisFilter = [
    0.026749,
    0.016864,
    -0.078223,
    -0.266864,
    0.602949,
    -0.266864,
    -0.078223,
    0.016864,
    0.026749
  ];

  /// The value of the first lifting step coefficient
  static const double alpha = -1.586134342;

  /// The value of the second lifting step coefficient
  static const double beta = -0.05298011854;

  /// The value of the third lifting step coefficient
  static const double gamma = 0.8829110762;

  /// The value of the fourth lifting step coefficient
  static const double delta = 0.4435068522;

  /// The value of the low-pass subband normalization factor
  static const double kl = 0.8128930655;

  /// The value of the high-pass subband normalization factor
  static const double kh = 1.230174106;

  /// An implementation of the analyze_lpf() method that works on int
  /// data, for the forward 9x7 wavelet transform using the
  /// lifting scheme. See the general description of the analyze_lpf()
  /// method in the AnWTFilter class for more details.
  ///
  /// The coefficients of the first lifting step are [ALPHA 1 ALPHA].
  ///
  /// The coefficients of the second lifting step are [BETA 1 BETA].
  ///
  /// The coefficients of the third lifting step are [GAMMA 1 GAMMA].
  ///
  /// The coefficients of the fourth lifting step are [DELTA 1 DELTA].
  ///
  /// The low-pass and high-pass subbands are normalized by respectively
  /// a factor of KL and a factor of KH
  @override
  void analyzeLpfFloat(
      Float32List inSig,
      int inOff,
      int inLen,
      int inStep,
      Float32List lowSig,
      int lowOff,
      int lowStep,
      Float32List highSig,
      int highOff,
      int highStep) {
    int i, maxi;
    int iStep = 2 * inStep; //Subsampling in inSig
    int ik; //Indexing inSig
    int lk; //Indexing lowSig
    int hk; //Indexing highSig

    // Generate intermediate high frequency subband

    //Initialize counters
    ik = inOff + inStep;
    lk = lowOff;
    hk = highOff;

    //Apply first lifting step to each "inner" sample
    maxi = inLen - 1;
    for (i = 1; i < maxi; i += 2) {
      highSig[hk] =
          inSig[ik] + alpha * (inSig[ik - inStep] + inSig[ik + inStep]);

      ik += iStep;
      hk += highStep;
    }

    //Handle head boundary effect if input signal has even length
    if (inLen % 2 == 0) {
      highSig[hk] = inSig[ik] + 2 * alpha * inSig[ik - inStep];
    }

    // Generate intermediate low frequency subband

    //Initialize counters
    ik = inOff;
    lk = lowOff;
    hk = highOff;

    if (inLen > 1) {
      lowSig[lk] = inSig[ik] + 2 * beta * highSig[hk];
    } else {
      lowSig[lk] = inSig[ik];
    }

    ik += iStep;
    lk += lowStep;
    hk += highStep;

    //Apply lifting step to each "inner" sample
    maxi = inLen - 1;
    for (i = 2; i < maxi; i += 2) {
      lowSig[lk] = inSig[ik] + beta * (highSig[hk - highStep] + highSig[hk]);

      ik += iStep;
      lk += lowStep;
      hk += highStep;
    }

    //Handle head boundary effect if input signal has odd length
    if ((inLen % 2 == 1) && (inLen > 2)) {
      lowSig[lk] = inSig[ik] + 2 * beta * highSig[hk - highStep];
    }

    // Generate high frequency subband

    //Initialize counters
    lk = lowOff;
    hk = highOff;

    //Apply first lifting step to each "inner" sample
    maxi = inLen - 1;
    for (i = 1; i < maxi; i += 2) {
      highSig[hk] += gamma * (lowSig[lk] + lowSig[lk + lowStep]);

      lk += lowStep;
      hk += highStep;
    }

    //Handle head boundary effect if input signal has even length
    if (inLen % 2 == 0) {
      highSig[hk] += 2 * gamma * lowSig[lk];
    }

    // Generate low frequency subband

    //Initialize counters
    lk = lowOff;
    hk = highOff;

    //Handle tail boundary effect
    //If access the overlap then perform the lifting step
    if (inLen > 1) {
      lowSig[lk] += 2 * delta * highSig[hk];
    }

    lk += lowStep;
    hk += highStep;

    //Apply lifting step to each "inner" sample
    maxi = inLen - 1;
    for (i = 2; i < maxi; i += 2) {
      lowSig[lk] += delta * (highSig[hk - highStep] + highSig[hk]);

      lk += lowStep;
      hk += highStep;
    }

    //Handle head boundary effect if input signal has odd length
    if ((inLen % 2 == 1) && (inLen > 2)) {
      lowSig[lk] += 2 * delta * highSig[hk - highStep];
    }

    // Normalize low and high frequency subbands

    //Re-initialize counters
    lk = lowOff;
    hk = highOff;

    //Normalize each sample
    for (i = 0; i < (inLen >> 1); i++) {
      lowSig[lk] *= kl;
      highSig[hk] *= kh;
      lk += lowStep;
      hk += highStep;
    }
    //If the input signal has odd length then normalize the last low-pass
    //coefficient (if input signal is length one filter is identity)
    if (inLen % 2 == 1 && inLen != 1) {
      lowSig[lk] *= kl;
    }
  }

  /// An implementation of the analyze_hpf() method that works on int
  /// data, for the forward 9x7 wavelet transform using the
  /// lifting scheme. See the general description of the analyze_hpf() method
  /// in the AnWTFilter class for more details.
  ///
  /// The coefficients of the first lifting step are [ALPHA 1 ALPHA].
  ///
  /// The coefficients of the second lifting step are [BETA 1 BETA].
  ///
  /// The coefficients of the third lifting step are [GAMMA 1 GAMMA].
  ///
  /// The coefficients of the fourth lifting step are [DELTA 1 DELTA].
  ///
  /// The low-pass and high-pass subbands are normalized by respectively
  /// a factor of KL and a factor of KH
  @override
  void analyzeHpfFloat(
      Float32List inSig,
      int inOff,
      int inLen,
      int inStep,
      Float32List lowSig,
      int lowOff,
      int lowStep,
      Float32List highSig,
      int highOff,
      int highStep) {
    int i;
    int iStep = 2 * inStep; //Subsampling in inSig
    int ik; //Indexing inSig
    int lk; //Indexing lowSig
    int hk; //Indexing highSig

    // Generate intermediate high frequency subband

    //Initialize counters
    ik = inOff;
    lk = lowOff;
    hk = highOff;

    if (inLen > 1) {
      // apply symmetric extension.
      highSig[hk] = inSig[ik] + 2 * alpha * inSig[ik + inStep];
    } else {
      // Normalize for Nyquist gain
      highSig[hk] = inSig[ik] * 2;
    }

    ik += iStep;
    hk += highStep;

    //Apply first lifting step to each "inner" sample
    for (i = 2; i < inLen - 1; i += 2) {
      highSig[hk] =
          inSig[ik] + alpha * (inSig[ik - inStep] + inSig[ik + inStep]);
      ik += iStep;
      hk += highStep;
    }

    //If input signal has odd length then we perform the lifting step
    // i.e. apply a symmetric extension.
    if ((inLen % 2 == 1) && (inLen > 1)) {
      highSig[hk] = inSig[ik] + 2 * alpha * inSig[ik - inStep];
    }

    // Generate intermediate low frequency subband

    //Initialize counters
    //ik = inOff + inStep;
    ik = inOff + inStep;
    lk = lowOff;
    hk = highOff;

    //Apply lifting step to each "inner" sample
    // we are at the component boundary
    for (i = 1; i < inLen - 1; i += 2) {
      lowSig[lk] = inSig[ik] + beta * (highSig[hk] + highSig[hk + highStep]);

      ik += iStep;
      lk += lowStep;
      hk += highStep;
    }
    if (inLen > 1 && inLen % 2 == 0) {
      // symetric extension
      lowSig[lk] = inSig[ik] + 2 * beta * highSig[hk];
    }

    // Generate high frequency subband

    //Initialize counters
    lk = lowOff;
    hk = highOff;

    if (inLen > 1) {
      // symmetric extension.
      highSig[hk] += gamma * 2 * lowSig[lk];
    }
    //lk += lowStep;
    hk += highStep;

    //Apply first lifting step to each "inner" sample
    for (i = 2; i < inLen - 1; i += 2) {
      highSig[hk] += gamma * (lowSig[lk] + lowSig[lk + lowStep]);
      lk += lowStep;
      hk += highStep;
    }

    //Handle head boundary effect
    if (inLen > 1 && inLen % 2 == 1) {
      // symmetric extension.
      highSig[hk] += gamma * 2 * lowSig[lk];
    }

    // Generate low frequency subband

    //Initialize counters
    lk = lowOff;
    hk = highOff;

    // we are at the component boundary
    for (i = 1; i < inLen - 1; i += 2) {
      lowSig[lk] += delta * (highSig[hk] + highSig[hk + highStep]);
      lk += lowStep;
      hk += highStep;
    }

    if (inLen > 1 && inLen % 2 == 0) {
      lowSig[lk] += delta * 2 * highSig[hk];
    }

    // Normalize low and high frequency subbands

    //Re-initialize counters
    lk = lowOff;
    hk = highOff;

    //Normalize each sample
    for (i = 0; i < (inLen >> 1); i++) {
      lowSig[lk] *= kl;
      highSig[hk] *= kh;
      lk += lowStep;
      hk += highStep;
    }
    //If the input signal has odd length then normalize the last high-pass
    //coefficient (if input signal is length one filter is identity)
    if (inLen % 2 == 1 && inLen != 1) {
      highSig[hk] *= kh;
    }
  }

  @override
  int getAnLowNegSupport() {
    return 4;
  }

  @override
  int getAnLowPosSupport() {
    return 4;
  }

  @override
  int getAnHighNegSupport() {
    return 3;
  }

  @override
  int getAnHighPosSupport() {
    return 3;
  }

  @override
  int getSynLowNegSupport() {
    return 3;
  }

  @override
  int getSynLowPosSupport() {
    return 3;
  }

  @override
  int getSynHighNegSupport() {
    return 4;
  }

  @override
  int getSynHighPosSupport() {
    return 4;
  }

  @override
  Float32List getLPSynthesisFilter() {
    return Float32List.fromList(lpSynthesisFilter);
  }

  @override
  Float32List getHPSynthesisFilter() {
    return Float32List.fromList(hpSynthesisFilter);
  }

  @override
  int getImplType() {
    return WaveletFilter.wtFilterFloatLift;
  }

  @override
  bool isReversible() {
    return false;
  }

  @override
  bool isSameAsFullWT(int tailOvrlp, int headOvrlp, int inLen) {
    //If the input signal has even length.
    if (inLen % 2 == 0) {
      if (tailOvrlp >= 4 && headOvrlp >= 3) {
        return true;
      } else {
        return false;
      }
    }
    //Else if the input signal has odd length.
    else {
      if (tailOvrlp >= 4 && headOvrlp >= 4) {
        return true;
      } else {
        return false;
      }
    }
  }

  @override
  bool operator ==(Object other) {
    return other == this || other is AnWTFilterFloatLift9x7;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  int getFilterType() {
    return FilterTypes.W9X7;
  }

  @override
  String toString() {
    return "w9x7";
  }
}


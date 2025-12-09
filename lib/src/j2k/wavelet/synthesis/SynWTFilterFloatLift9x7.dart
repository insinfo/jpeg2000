import 'dart:typed_data';

import 'SynWTFilterFloat.dart';
import '../WaveletFilter.dart';

/// Synthesis lifting implementation for the irreversible 9/7 wavelet.
class SynWTFilterFloatLift9x7 extends SynWTFilterFloat {
  static const double alpha = -1.586134342;
  static const double beta = -0.05298011854;
  static const double gamma = 0.8829110762;
  static const double delta = 0.4435068522;
  static const double kL = 0.8128930655;
  static const double kH = 1.230174106;

  @override
  void synthetizeLpfFloat(
    Float32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Float32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Float32List outSig,
    int outOff,
    int outStep,
  ) {
    final outLen = lowLen + highLen;
    final iStep = 2 * outStep;
    var lk = lowOff;
    var hk = highOff;
    var ik = outOff;

    if (outLen > 1) {
      outSig[ik] = lowSig[lk] / kL - 2 * delta * (highSig[hk] / kH);
    } else {
      outSig[ik] = lowSig[lk];
    }

    lk += lowStep;
    hk += highStep;
    ik += iStep;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] =
          lowSig[lk] / kL - delta * ((highSig[hk - highStep] + highSig[hk]) / kH);
      ik += iStep;
      lk += lowStep;
      hk += highStep;
    }

    if (outLen.isOdd) {
      if (outLen > 2) {
        outSig[ik] =
            lowSig[lk] / kL - 2 * delta * (highSig[hk - highStep] / kH);
      }
    }

    lk = lowOff;
    hk = highOff;
    ik = outOff + outStep;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] = highSig[hk] / kH -
          gamma * (outSig[ik - outStep] + outSig[ik + outStep]);
      ik += iStep;
      hk += highStep;
      lk += lowStep;
    }

    if (outLen.isEven) {
      outSig[ik] = highSig[hk] / kH - 2 * gamma * outSig[ik - outStep];
    }

    ik = outOff;

    if (outLen > 1) {
      outSig[ik] -= 2 * beta * outSig[ik + outStep];
    }
    ik += iStep;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] -= beta * (outSig[ik - outStep] + outSig[ik + outStep]);
      ik += iStep;
    }

    if (outLen.isOdd && outLen > 2) {
      outSig[ik] -= 2 * beta * outSig[ik - outStep];
    }

    ik = outOff + outStep;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] -= alpha * (outSig[ik - outStep] + outSig[ik + outStep]);
      ik += iStep;
    }

    if (outLen.isEven) {
      outSig[ik] -= 2 * alpha * outSig[ik - outStep];
    }
  }

  @override
  void synthetizeHpfFloat(
    Float32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Float32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Float32List outSig,
    int outOff,
    int outStep,
  ) {
    final outLen = lowLen + highLen;
    final iStep = 2 * outStep;
    var lk = lowOff;
    var hk = highOff;

    if (outLen != 1) {
      final outLen2 = outLen >> 1;
      for (var i = 0; i < outLen2; i++) {
        lowSig[lk] /= kL;
        highSig[hk] /= kH;
        lk += lowStep;
        hk += highStep;
      }
      if (outLen.isOdd) {
        highSig[hk] /= kH;
      }
    } else {
      highSig[highOff] /= 2;
    }

    lk = lowOff;
    hk = highOff;
    var ik = outOff + outStep;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] = lowSig[lk] -
          delta * (highSig[hk] + highSig[hk + highStep]);
      ik += iStep;
      lk += lowStep;
      hk += highStep;
    }

    if (outLen.isEven && outLen > 1) {
      outSig[ik] = lowSig[lk] - 2 * delta * highSig[hk];
    }

    hk = highOff;
    ik = outOff;

    if (outLen > 1) {
      outSig[ik] = highSig[hk] - 2 * gamma * outSig[ik + outStep];
    } else {
      outSig[ik] = highSig[hk];
    }

    ik += iStep;
    hk += highStep;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] = highSig[hk] -
          gamma * (outSig[ik - outStep] + outSig[ik + outStep]);
      ik += iStep;
      hk += highStep;
    }

    if (outLen.isOdd && outLen > 1) {
      outSig[ik] = highSig[hk] - 2 * gamma * outSig[ik - outStep];
    }

    ik = outOff + outStep;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] -= beta * (outSig[ik - outStep] + outSig[ik + outStep]);
      ik += iStep;
    }

    if (outLen.isEven && outLen > 1) {
      outSig[ik] -= 2 * beta * outSig[ik - outStep];
    }

    ik = outOff;

    if (outLen > 1) {
      outSig[ik] -= 2 * alpha * outSig[ik + outStep];
    }
    ik += iStep;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] -= alpha * (outSig[ik - outStep] + outSig[ik + outStep]);
      ik += iStep;
    }

    if (outLen.isOdd && outLen > 1) {
      outSig[ik] -= 2 * alpha * outSig[ik - outStep];
    }
  }

  @override
  int getAnLowNegSupport() => 4;

  @override
  int getAnLowPosSupport() => 4;

  @override
  int getAnHighNegSupport() => 3;

  @override
  int getAnHighPosSupport() => 3;

  @override
  int getSynLowNegSupport() => 3;

  @override
  int getSynLowPosSupport() => 3;

  @override
  int getSynHighNegSupport() => 4;

  @override
  int getSynHighPosSupport() => 4;

  @override
  int getImplType() => WaveletFilter.wtFilterFloatLift;

  @override
  bool isReversible() => false;

  @override
  bool isSameAsFullWT(int tailOverlap, int headOverlap, int inputLength) {
    if (inputLength.isEven) {
      return tailOverlap >= 2 && headOverlap >= 1;
    }
    return tailOverlap >= 2 && headOverlap >= 2;
  }

  @override
  String toString() => 'w9x7 (lifting)';
}



import 'SynWTFilterInt.dart';
import '../WaveletFilter.dart';

/// Synthesis lifting implementation for the reversible 5/3 wavelet.
class SynWTFilterIntLift5x3 extends SynWTFilterInt {
  @override
  void synthetizeLpfInt(
    List<int> lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    List<int> highSig,
    int highOff,
    int highLen,
    int highStep,
    List<int> outSig,
    int outOff,
    int outStep,
  ) {
    final outLen = lowLen + highLen;
    final iStep = 2 * outStep;
    var lk = lowOff;
    var hk = highOff;
    var ik = outOff;

    if (outLen > 1) {
      outSig[ik] = lowSig[lk] - ((highSig[hk] + 1) >> 1);
    } else {
      outSig[ik] = lowSig[lk];
    }

    lk += lowStep;
    hk += highStep;
    ik += iStep;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] = lowSig[lk] -
          ((highSig[hk - highStep] + highSig[hk] + 2) >> 2);
      lk += lowStep;
      hk += highStep;
      ik += iStep;
    }

    if (outLen.isOdd && outLen > 2) {
      outSig[ik] = lowSig[lk] - ((2 * highSig[hk - highStep] + 2) >> 2);
    }

    hk = highOff;
    ik = outOff + outStep;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] = highSig[hk] +
          ((outSig[ik - outStep] + outSig[ik + outStep]) >> 1);
      hk += highStep;
      ik += iStep;
    }

    if (outLen.isEven && outLen > 1) {
      outSig[ik] = highSig[hk] + outSig[ik - outStep];
    }
  }

  @override
  void synthetizeHpfInt(
    List<int> lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    List<int> highSig,
    int highOff,
    int highLen,
    int highStep,
    List<int> outSig,
    int outOff,
    int outStep,
  ) {
    final outLen = lowLen + highLen;
    final iStep = 2 * outStep;
    var lk = lowOff;
    var hk = highOff;
    var ik = outOff + outStep;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] = lowSig[lk] -
          ((highSig[hk] + highSig[hk + highStep] + 2) >> 2);
      lk += lowStep;
      hk += highStep;
      ik += iStep;
    }

    if (outLen > 1 && outLen.isEven) {
      outSig[ik] = lowSig[lk] - ((2 * highSig[hk] + 2) >> 2);
    }

    hk = highOff;
    ik = outOff;

    if (outLen > 1) {
      outSig[ik] = highSig[hk] + outSig[ik + outStep];
    } else {
      outSig[ik] = highSig[hk] >> 1;
    }

    hk += highStep;
    ik += iStep;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] = highSig[hk] +
          ((outSig[ik - outStep] + outSig[ik + outStep]) >> 1);
      hk += highStep;
      ik += iStep;
    }

    if (outLen.isOdd && outLen > 1) {
      outSig[ik] = highSig[hk] + outSig[ik - outStep];
    }
  }

  @override
  int getAnLowNegSupport() => 2;

  @override
  int getAnLowPosSupport() => 2;

  @override
  int getAnHighNegSupport() => 1;

  @override
  int getAnHighPosSupport() => 1;

  @override
  int getSynLowNegSupport() => 1;

  @override
  int getSynLowPosSupport() => 1;

  @override
  int getSynHighNegSupport() => 2;

  @override
  int getSynHighPosSupport() => 2;

  @override
  int getImplType() => WaveletFilter.wtFilterIntLift;

  @override
  bool isReversible() => true;

  @override
  bool isSameAsFullWT(int tailOverlap, int headOverlap, int inputLength) {
    if (inputLength.isEven) {
      return tailOverlap >= 2 && headOverlap >= 1;
    }
    return tailOverlap >= 2 && headOverlap >= 2;
  }

  @override
  String toString() => 'w5x3 (lifting)';
}


import 'dart:typed_data';

import '../FilterTypes.dart';
import '../WaveletFilter.dart';
import 'AnWtFilterInt.dart';

/// Integer lifting implementation of the 5x3 analysis wavelet filter.
class AnWTFilterIntLift5x3 extends AnWTFilterInt {
  static final Float32List _lpSynthesisFilter =
      Float32List.fromList(<double>[0.5, 1.0, 0.5]);
  static final Float32List _hpSynthesisFilter =
      Float32List.fromList(<double>[-0.125, -0.25, 0.75, -0.25, -0.125]);

  @override
  void analyzeLpfInt(
    List<int> inSig,
    int inOff,
    int inLen,
    int inStep,
    List<int> lowSig,
    int lowOff,
    int lowStep,
    List<int> highSig,
    int highOff,
    int highStep,
  ) {
    var ik = inOff + inStep;
    var hk = highOff;
    final iStep = 2 * inStep;

    // High frequency subband.
    for (var i = 1; i < inLen - 1; i += 2) {
      highSig[hk] = inSig[ik] - ((inSig[ik - inStep] + inSig[ik + inStep]) >> 1);
      ik += iStep;
      hk += highStep;
    }

    if (inLen.isEven) {
      highSig[hk] = inSig[ik] - ((2 * inSig[ik - inStep]) >> 1);
    }

    // Low frequency subband.
    ik = inOff;
    var lk = lowOff;
    hk = highOff;

    if (inLen > 1) {
      lowSig[lk] = inSig[ik] + ((highSig[hk] + 1) >> 1);
    } else {
      lowSig[lk] = inSig[ik];
    }

    ik += iStep;
    lk += lowStep;
    hk += highStep;

    for (var i = 2; i < inLen - 1; i += 2) {
      lowSig[lk] =
          inSig[ik] + ((highSig[hk - highStep] + highSig[hk] + 2) >> 2);
      ik += iStep;
      lk += lowStep;
      hk += highStep;
    }

    if (inLen.isOdd && inLen > 2) {
      lowSig[lk] = inSig[ik] + ((2 * highSig[hk - highStep] + 2) >> 2);
    }
  }

  @override
  void analyzeHpfInt(
    List<int> inSig,
    int inOff,
    int inLen,
    int inStep,
    List<int> lowSig,
    int lowOff,
    int lowStep,
    List<int> highSig,
    int highOff,
    int highStep,
  ) {
    var ik = inOff;
    var hk = highOff;
    final iStep = 2 * inStep;

    if (inLen > 1) {
      highSig[hk] = inSig[ik] - inSig[ik + inStep];
    } else {
      highSig[hk] = inSig[ik] << 1;
    }

    ik += iStep;
    hk += highStep;

    if (inLen > 3) {
      for (var i = 2; i < inLen - 1; i += 2) {
        highSig[hk] =
            inSig[ik] - ((inSig[ik - inStep] + inSig[ik + inStep]) >> 1);
        ik += iStep;
        hk += highStep;
      }
    }

    if (inLen.isOdd && inLen > 1) {
      highSig[hk] = inSig[ik] - inSig[ik - inStep];
    }

    ik = inOff + inStep;
    var lk = lowOff;
    hk = highOff;

    for (var i = 1; i < inLen - 1; i += 2) {
      lowSig[lk] =
          inSig[ik] + ((highSig[hk] + highSig[hk + highStep] + 2) >> 2);
      ik += iStep;
      lk += lowStep;
      hk += highStep;
    }

    if (inLen > 1 && inLen.isEven) {
      lowSig[lk] = inSig[ik] + ((2 * highSig[hk] + 2) >> 2);
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
  Float32List getLPSynthesisFilter() => _lpSynthesisFilter;

  @override
  Float32List getHPSynthesisFilter() => _hpSynthesisFilter;

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
  int getFilterType() => FilterTypes.w5x3;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AnWTFilterIntLift5x3;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'w5x3 (lifting)';
}




import 'dart:typed_data';

import 'syn_wt_filter_float.dart';
import '../wavelet_filter.dart';

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
      outSig[ik] = lowSig[lk] / kL -
          delta * ((highSig[hk - highStep] + highSig[hk]) / kH);
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
      outSig[ik] = lowSig[lk] - delta * (highSig[hk] + highSig[hk + highStep]);
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
      outSig[ik] =
          highSig[hk] - gamma * (outSig[ik - outStep] + outSig[ik + outStep]);
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

  static final Float32x4 _kL4 = Float32x4.splat(kL);
  static final Float32x4 _kH4 = Float32x4.splat(kH);
  static final Float32x4 _delta4 = Float32x4.splat(delta);
  static final Float32x4 _twoDelta4 = Float32x4.splat(2 * delta);
  static final Float32x4 _gamma4 = Float32x4.splat(gamma);
  static final Float32x4 _twoGamma4 = Float32x4.splat(2 * gamma);
  static final Float32x4 _beta4 = Float32x4.splat(beta);
  static final Float32x4 _twoBeta4 = Float32x4.splat(2 * beta);
  static final Float32x4 _alpha4 = Float32x4.splat(alpha);
  static final Float32x4 _twoAlpha4 = Float32x4.splat(2 * alpha);
  static final Float32x4 _two4 = Float32x4.splat(2);

  /// [synthetizeLpfFloat] on four signals at once, one per SIMD lane, all
  /// with unit stride.
  ///
  /// `Float32x4` arithmetic is single precision at every operation, which is
  /// exactly what JJ2000's `float` code does; the scalar path computes in
  /// double and rounds on store. The inverse wavelet uses this for four
  /// image columns per pass: the gather of four adjacent columns reads one
  /// cache line per row instead of four, and the lifting runs on SIMD.
  void synthetizeLpfFloat4(
    Float32x4List lowSig,
    int lowOff,
    int lowLen,
    Float32x4List highSig,
    int highOff,
    int highLen,
    Float32x4List outSig,
    int outOff,
  ) {
    final kL4 = _kL4;
    final kH4 = _kH4;
    final delta4 = _delta4;
    final twoDelta4 = _twoDelta4;
    final gamma4 = _gamma4;
    final twoGamma4 = _twoGamma4;
    final beta4 = _beta4;
    final twoBeta4 = _twoBeta4;
    final alpha4 = _alpha4;
    final twoAlpha4 = _twoAlpha4;

    final outLen = lowLen + highLen;
    var lk = lowOff;
    var hk = highOff;
    var ik = outOff;

    if (outLen > 1) {
      outSig[ik] = lowSig[lk] / kL4 - twoDelta4 * (highSig[hk] / kH4);
    } else {
      outSig[ik] = lowSig[lk];
    }

    lk++;
    hk++;
    ik += 2;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] =
          lowSig[lk] / kL4 - delta4 * ((highSig[hk - 1] + highSig[hk]) / kH4);
      ik += 2;
      lk++;
      hk++;
    }

    if (outLen.isOdd) {
      if (outLen > 2) {
        outSig[ik] = lowSig[lk] / kL4 - twoDelta4 * (highSig[hk - 1] / kH4);
      }
    }

    hk = highOff;
    ik = outOff + 1;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] =
          highSig[hk] / kH4 - gamma4 * (outSig[ik - 1] + outSig[ik + 1]);
      ik += 2;
      hk++;
    }

    if (outLen.isEven) {
      outSig[ik] = highSig[hk] / kH4 - twoGamma4 * outSig[ik - 1];
    }

    ik = outOff;

    if (outLen > 1) {
      outSig[ik] = outSig[ik] - twoBeta4 * outSig[ik + 1];
    }
    ik += 2;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] = outSig[ik] - beta4 * (outSig[ik - 1] + outSig[ik + 1]);
      ik += 2;
    }

    if (outLen.isOdd && outLen > 2) {
      outSig[ik] = outSig[ik] - twoBeta4 * outSig[ik - 1];
    }

    ik = outOff + 1;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] = outSig[ik] - alpha4 * (outSig[ik - 1] + outSig[ik + 1]);
      ik += 2;
    }

    if (outLen.isEven) {
      outSig[ik] = outSig[ik] - twoAlpha4 * outSig[ik - 1];
    }
  }

  /// [synthetizeHpfFloat] on four signals at once; see
  /// [synthetizeLpfFloat4]. Like the scalar version it scales the input
  /// halves in place.
  void synthetizeHpfFloat4(
    Float32x4List lowSig,
    int lowOff,
    int lowLen,
    Float32x4List highSig,
    int highOff,
    int highLen,
    Float32x4List outSig,
    int outOff,
  ) {
    final kL4 = _kL4;
    final kH4 = _kH4;
    final delta4 = _delta4;
    final twoDelta4 = _twoDelta4;
    final gamma4 = _gamma4;
    final twoGamma4 = _twoGamma4;
    final beta4 = _beta4;
    final twoBeta4 = _twoBeta4;
    final alpha4 = _alpha4;
    final twoAlpha4 = _twoAlpha4;

    final outLen = lowLen + highLen;
    var lk = lowOff;
    var hk = highOff;

    if (outLen != 1) {
      final outLen2 = outLen >> 1;
      for (var i = 0; i < outLen2; i++) {
        lowSig[lk] = lowSig[lk] / kL4;
        highSig[hk] = highSig[hk] / kH4;
        lk++;
        hk++;
      }
      if (outLen.isOdd) {
        highSig[hk] = highSig[hk] / kH4;
      }
    } else {
      highSig[highOff] = highSig[highOff] / _two4;
    }

    lk = lowOff;
    hk = highOff;
    var ik = outOff + 1;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] = lowSig[lk] - delta4 * (highSig[hk] + highSig[hk + 1]);
      ik += 2;
      lk++;
      hk++;
    }

    if (outLen.isEven && outLen > 1) {
      outSig[ik] = lowSig[lk] - twoDelta4 * highSig[hk];
    }

    hk = highOff;
    ik = outOff;

    if (outLen > 1) {
      outSig[ik] = highSig[hk] - twoGamma4 * outSig[ik + 1];
    } else {
      outSig[ik] = highSig[hk];
    }

    ik += 2;
    hk++;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] = highSig[hk] - gamma4 * (outSig[ik - 1] + outSig[ik + 1]);
      ik += 2;
      hk++;
    }

    if (outLen.isOdd && outLen > 1) {
      outSig[ik] = highSig[hk] - twoGamma4 * outSig[ik - 1];
    }

    ik = outOff + 1;

    for (var i = 1; i < outLen - 1; i += 2) {
      outSig[ik] = outSig[ik] - beta4 * (outSig[ik - 1] + outSig[ik + 1]);
      ik += 2;
    }

    if (outLen.isEven && outLen > 1) {
      outSig[ik] = outSig[ik] - twoBeta4 * outSig[ik - 1];
    }

    ik = outOff;

    if (outLen > 1) {
      outSig[ik] = outSig[ik] - twoAlpha4 * outSig[ik + 1];
    }
    ik += 2;

    for (var i = 2; i < outLen - 1; i += 2) {
      outSig[ik] = outSig[ik] - alpha4 * (outSig[ik - 1] + outSig[ik + 1]);
      ik += 2;
    }

    if (outLen.isOdd && outLen > 1) {
      outSig[ik] = outSig[ik] - twoAlpha4 * outSig[ik - 1];
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

  /// [synthetizeLpfFloat] on one contiguous row, four samples per SIMD op.
  ///
  /// The row is split into its low-pass half (`lowLen` samples, the even
  /// output positions) and high-pass half (`highLen`, the odd positions),
  /// each copied into an aligned buffer of [scratch]. The four lifting
  /// steps then run as whole-vector passes over the even and odd sample
  /// arrays, with the `x[j-1]` / `x[j+1]` neighbours built by lane shuffles
  /// from the adjacent vectors, and the boundary samples are recomputed
  /// afterwards with the same single-precision arithmetic. The interleaved
  /// result is left in `scratch.out`, `lowLen + highLen` samples long.
  ///
  /// Requires `lowLen + highLen >= 2` and `lowLen - highLen` in `{0, 1}`.
  void synthetizeLpfRow4(SynRow97Scratch scratch, int lowLen, int highLen) {
    final kL4 = _kL4;
    final kH4 = _kH4;
    final delta4 = _delta4;
    final gamma4 = _gamma4;
    final beta4 = _beta4;
    final alpha4 = _alpha4;
    final low4 = scratch.low4;
    final high4 = scratch.high4;
    final e4 = scratch.e4;
    final o4 = scratch.o4;
    final out4 = scratch.out4;
    final low = scratch.low;
    final high = scratch.high;
    final e = scratch.e;
    final o = scratch.o;
    final outLen = lowLen + highLen;
    final vE = (lowLen + 3) >> 2;
    final vO = (highLen + 3) >> 2;
    final lastE = lowLen - 1;
    final lastO = highLen - 1;

    // Step 1, even: E[j] = L[j]/kL - delta*((H[j-1] + H[j])/kH).
    var prev = Float32x4.zero();
    for (var v = 0; v < vE; v++) {
      final h = high4[v];
      final hm1 = _shiftRight(prev, h);
      e4[v] = low4[v] / kL4 - delta4 * ((hm1 + h) / kH4);
      prev = h;
    }
    e[0] = (Float32x4.splat(low[0]) / kL4 -
            _twoDelta4 * (Float32x4.splat(high[0]) / kH4))
        .x;
    if (outLen.isOdd) {
      e[lastE] = (Float32x4.splat(low[lastE]) / kL4 -
              _twoDelta4 * (Float32x4.splat(high[lastE - 1]) / kH4))
          .x;
    }

    // Step 2, odd: O[j] = H[j]/kH - gamma*(E[j] + E[j+1]).
    for (var v = 0; v < vO; v++) {
      final ev = e4[v];
      final ep1 = _shiftLeft(ev, e4[v + 1]);
      o4[v] = high4[v] / kH4 - gamma4 * (ev + ep1);
    }
    if (outLen.isEven) {
      o[lastO] = (Float32x4.splat(high[lastO]) / kH4 -
              _twoGamma4 * Float32x4.splat(e[lastO]))
          .x;
    }

    // Step 3, even: E[j] -= beta*(O[j-1] + O[j]).
    final e0 = (Float32x4.splat(e[0]) - _twoBeta4 * Float32x4.splat(o[0])).x;
    final eLast = outLen.isOdd
        ? (Float32x4.splat(e[lastE]) -
                _twoBeta4 * Float32x4.splat(o[lastE - 1]))
            .x
        : 0.0;
    prev = Float32x4.zero();
    for (var v = 0; v < vE; v++) {
      final ov = o4[v];
      final om1 = _shiftRight(prev, ov);
      e4[v] = e4[v] - beta4 * (om1 + ov);
      prev = ov;
    }
    e[0] = e0;
    if (outLen.isOdd) {
      e[lastE] = eLast;
    }

    // Step 4, odd: O[j] -= alpha*(E[j] + E[j+1]).
    final oLast = outLen.isEven
        ? (Float32x4.splat(o[lastO]) - _twoAlpha4 * Float32x4.splat(e[lastO])).x
        : 0.0;
    for (var v = 0; v < vO; v++) {
      final ev = e4[v];
      final ep1 = _shiftLeft(ev, e4[v + 1]);
      o4[v] = o4[v] - alpha4 * (ev + ep1);
    }
    if (outLen.isEven) {
      o[lastO] = oLast;
    }

    _interleave(e4, o4, out4, vE);
  }

  /// [synthetizeHpfFloat] on one contiguous row; see [synthetizeLpfRow4].
  /// Here the high-pass half holds the even output positions (`highLen`
  /// samples) and the low-pass half the odd ones (`lowLen`), with
  /// `highLen - lowLen` in `{0, 1}`; the interleaved output is written to
  /// `scratch.out`. The halves are scaled in place first, as JJ2000 does.
  void synthetizeHpfRow4(SynRow97Scratch scratch, int lowLen, int highLen) {
    final kL4 = _kL4;
    final kH4 = _kH4;
    final delta4 = _delta4;
    final gamma4 = _gamma4;
    final beta4 = _beta4;
    final alpha4 = _alpha4;
    final low4 = scratch.low4;
    final high4 = scratch.high4;
    final e4 = scratch.e4;
    final o4 = scratch.o4;
    final out4 = scratch.out4;
    final low = scratch.low;
    final high = scratch.high;
    final e = scratch.e;
    final o = scratch.o;
    final outLen = lowLen + highLen;
    // Even outputs come from the high half, odd from the low half.
    final vE = (highLen + 3) >> 2;
    final vO = (lowLen + 3) >> 2;
    final lastE = highLen - 1;
    final lastO = lowLen - 1;

    for (var v = 0; v < vO; v++) {
      low4[v] = low4[v] / kL4;
    }
    for (var v = 0; v < vE; v++) {
      high4[v] = high4[v] / kH4;
    }

    // Step 1, odd: O[j] = L[j] - delta*(H[j] + H[j+1]).
    for (var v = 0; v < vO; v++) {
      final hv = high4[v];
      final hp1 = _shiftLeft(hv, high4[v + 1]);
      o4[v] = low4[v] - delta4 * (hv + hp1);
    }
    if (outLen.isEven) {
      o[lastO] = (Float32x4.splat(low[lastO]) -
              _twoDelta4 * Float32x4.splat(high[lastO]))
          .x;
    }

    // Step 2, even: E[j] = H[j] - gamma*(O[j-1] + O[j]).
    var prev = Float32x4.zero();
    for (var v = 0; v < vE; v++) {
      final ov = o4[v];
      final om1 = _shiftRight(prev, ov);
      e4[v] = high4[v] - gamma4 * (om1 + ov);
      prev = ov;
    }
    e[0] = (Float32x4.splat(high[0]) - _twoGamma4 * Float32x4.splat(o[0])).x;
    if (outLen.isOdd) {
      e[lastE] = (Float32x4.splat(high[lastE]) -
              _twoGamma4 * Float32x4.splat(o[lastE - 1]))
          .x;
    }

    // Step 3, odd: O[j] -= beta*(E[j] + E[j+1]).
    final oLast = outLen.isEven
        ? (Float32x4.splat(o[lastO]) - _twoBeta4 * Float32x4.splat(e[lastO])).x
        : 0.0;
    for (var v = 0; v < vO; v++) {
      final ev = e4[v];
      final ep1 = _shiftLeft(ev, e4[v + 1]);
      o4[v] = o4[v] - beta4 * (ev + ep1);
    }
    if (outLen.isEven) {
      o[lastO] = oLast;
    }

    // Step 4, even: E[j] -= alpha*(O[j-1] + O[j]).
    final e0 = (Float32x4.splat(e[0]) - _twoAlpha4 * Float32x4.splat(o[0])).x;
    final eLast = outLen.isOdd
        ? (Float32x4.splat(e[lastE]) -
                _twoAlpha4 * Float32x4.splat(o[lastE - 1]))
            .x
        : 0.0;
    prev = Float32x4.zero();
    for (var v = 0; v < vE; v++) {
      final ov = o4[v];
      final om1 = _shiftRight(prev, ov);
      e4[v] = e4[v] - alpha4 * (om1 + ov);
      prev = ov;
    }
    e[0] = e0;
    if (outLen.isOdd) {
      e[lastE] = eLast;
    }

    _interleave(e4, o4, out4, vE);
  }

  /// `[prev.w, cur.x, cur.y, cur.z]`: the vector one lane behind [cur].
  @pragma('vm:prefer-inline')
  static Float32x4 _shiftRight(Float32x4 prev, Float32x4 cur) {
    final t = prev.shuffleMix(cur, Float32x4.wwxy);
    return t.shuffleMix(cur, Float32x4.xzyz);
  }

  /// `[cur.y, cur.z, cur.w, next.x]`: the vector one lane ahead of [cur].
  @pragma('vm:prefer-inline')
  static Float32x4 _shiftLeft(Float32x4 cur, Float32x4 next) {
    final t = cur.shuffleMix(next, Float32x4.zwxx);
    return cur.shuffleMix(t, Float32x4.yzyz);
  }

  /// Writes `e0 o0 e1 o1 ...` into [out4] for [count] vectors of each.
  static void _interleave(
      Float32x4List e4, Float32x4List o4, Float32x4List out4, int count) {
    for (var v = 0, w = 0; v < count; v++, w += 2) {
      final ev = e4[v];
      final ov = o4[v];
      out4[w] = ev.shuffleMix(ov, Float32x4.xyxy).shuffle(Float32x4.xzyw);
      out4[w + 1] = ev.shuffleMix(ov, Float32x4.zwzw).shuffle(Float32x4.xzyw);
    }
  }
}

/// Aligned row buffers for [SynWTFilterFloatLift9x7.synthetizeLpfRow4] and
/// [SynWTFilterFloatLift9x7.synthetizeHpfRow4], sized for rows up to
/// [capacity] samples. Each half buffer has one spare vector past the data so
/// the neighbour shuffles can read one vector beyond the last valid one.
class SynRow97Scratch {
  SynRow97Scratch(this.capacity) {
    final vectors = ((((capacity + 1) >> 1) + 3) >> 2) + 1;
    low4 = Float32x4List(vectors);
    high4 = Float32x4List(vectors);
    e4 = Float32x4List(vectors);
    o4 = Float32x4List(vectors);
    out4 = Float32x4List(2 * vectors);
    low = low4.buffer.asFloat32List();
    high = high4.buffer.asFloat32List();
    e = e4.buffer.asFloat32List();
    o = o4.buffer.asFloat32List();
    out = out4.buffer.asFloat32List();
  }

  final int capacity;
  late final Float32x4List low4;
  late final Float32x4List high4;
  late final Float32x4List e4;
  late final Float32x4List o4;
  late final Float32x4List out4;
  late final Float32List low;
  late final Float32List high;
  late final Float32List e;
  late final Float32List o;
  late final Float32List out;
}

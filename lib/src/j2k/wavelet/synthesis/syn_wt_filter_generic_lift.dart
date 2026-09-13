import 'dart:typed_data';

import '../atk_kernel.dart';
import '../wavelet_filter.dart';
import 'syn_wt_filter.dart';
import 'syn_wt_filter_float.dart';
import 'syn_wt_filter_int.dart';

/// Synthesis for any kernel described by an ATK marker segment.
///
/// ISO/IEC 15444-2 (ITU-T T.801) Annex G specifies the reconstruction of a
/// whole-sample symmetric kernel as the `1D_SR_WS` procedure: interleave the
/// low-pass and high-pass coefficients, scale the two parities (irreversible
/// kernels only, G-4 and G-5), then run the signalled lifting steps backwards,
/// from `s = NLS - 1` down to `s = 0`. Each step replaces the samples of one
/// parity with
/// `V(2n+m) - sum(k) a[s][k] * (V(2n+m-(2k+1)) + V(2n+m+(2k+1)))`,
/// rounded through `floor((sum + beta) / 2^eps)` when the kernel is reversible
/// (G-2, G-6). Out-of-range indices are folded back with the `PSEO` extension
/// of ISO/IEC 15444-1 F-4, which the annex makes part of the step rather than
/// a separate extension pass.
///
/// The 5-3 and 9-7 kernels of ISO/IEC 15444-1 are particular cases of this
/// procedure (T.801 G.4.1.1 and G.4.2.3) but keep their own hand-written,
/// bit-exact implementations; this class exists for the kernels a codestream
/// defines for itself.
abstract class SynWTFilterGenericLift implements SynWTFilter {
  /// The kernel this filter runs.
  AtkKernel get kernel;

  /// Folds [position] back inside `[0, length)` by whole-sample symmetric
  /// extension, the `PSEO` function of ISO/IEC 15444-1 F-4 expressed in
  /// positions relative to the first sample.
  static int foldPosition(int position, int length) {
    if (length == 1) {
      return 0;
    }
    final period = 2 * (length - 1);
    var folded = position % period;
    if (folded < 0) {
      folded += period;
    }
    return folded < length ? folded : period - folded;
  }

  /// A support bound wide enough for every lifting step of [kernel].
  ///
  /// Only the region-of-interest mask generator of the encoder reads the
  /// support of a synthesis filter, and it only needs an upper bound, so the
  /// reach of the steps is summed rather than composed exactly.
  static int supportBound(AtkKernel kernel) {
    var reach = 0;
    for (final step in kernel.steps) {
      reach += 2 * step.coefficients.length - 1;
    }
    return reach < 1 ? 1 : reach;
  }

  /// Rejects kernels this implementation cannot run.
  ///
  /// Arbitrary (`Filt_Cat = ARB`) kernels use the different procedure of
  /// T.801 Annex H, with per-step tap offsets and a choice of boundary
  /// extension; they are not implemented.
  static void checkSupported(AtkKernel kernel) {
    if (!kernel.wholeSampleSymmetric) {
      throw UnsupportedError(
        'Arbitrary transformation kernel ${kernel.index} is signalled as '
        'Filt_Cat = ARB, whose reconstruction is specified by ISO/IEC '
        '15444-2 Annex H; only whole-sample symmetric kernels (Filt_Cat = WS, '
        'Annex G) are implemented.',
      );
    }
    if (kernel.steps.isEmpty) {
      throw UnsupportedError(
        'Arbitrary transformation kernel ${kernel.index} declares no lifting '
        'step, so it describes no transformation.',
      );
    }
    for (final step in kernel.steps) {
      if (step.coefficients.isEmpty) {
        throw UnsupportedError(
          'Arbitrary transformation kernel ${kernel.index} has a lifting step '
          'with no coefficient.',
        );
      }
    }
    if (!kernel.reversible && kernel.scale == 0) {
      throw UnsupportedError(
        'Arbitrary transformation kernel ${kernel.index} is irreversible with '
        'a zero scaling factor K, which cannot be inverted.',
      );
    }
  }

  /// Builds the synthesis filter for [kernel].
  ///
  /// Reversible kernels work on integer samples and irreversible ones on
  /// floats, the same split ISO/IEC 15444-1 makes between the 5-3 and the 9-7.
  static SynWTFilter create(AtkKernel kernel) {
    checkSupported(kernel);
    return kernel.reversible
        ? SynWTFilterGenericIntLift(kernel)
        : SynWTFilterGenericFloatLift(kernel);
  }
}

/// Reversible (`WT_Typ = REV`) generic lifting synthesis, on integer samples.
class SynWTFilterGenericIntLift extends SynWTFilterInt
    implements SynWTFilterGenericLift {
  /// Wraps [kernel]; it must be reversible and whole-sample symmetric.
  SynWTFilterGenericIntLift(this.kernel)
      : _coefficients = <Int32List>[
          for (final step in kernel.steps)
            Int32List.fromList(step.integerCoefficients),
        ],
        _exponents = Int32List.fromList(<int>[
          for (final step in kernel.steps) step.exponent,
        ]),
        _residues = Int32List.fromList(<int>[
          for (final step in kernel.steps) step.residue,
        ]),
        _parities = Int32List.fromList(<int>[
          for (var s = 0; s < kernel.steps.length; s++) kernel.parityOfStep(s),
        ]),
        _support = SynWTFilterGenericLift.supportBound(kernel) {
    SynWTFilterGenericLift.checkSupported(kernel);
    if (!kernel.reversible) {
      throw ArgumentError.value(
        kernel,
        'kernel',
        'an irreversible kernel needs SynWTFilterGenericFloatLift',
      );
    }
  }

  @override
  final AtkKernel kernel;

  final List<Int32List> _coefficients;
  final Int32List _exponents;
  final Int32List _residues;
  final Int32List _parities;
  final int _support;

  Int32List _scratch = Int32List(0);

  Int32List _buffer(int length) {
    if (_scratch.length < length) {
      _scratch = Int32List(length);
    }
    return _scratch;
  }

  @override
  void synthetizeLpfInt(
    Int32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Int32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Int32List outSig,
    int outOff,
    int outStep,
  ) =>
      _synthesize(lowSig, lowOff, lowLen, lowStep, highSig, highOff, highLen,
          highStep, outSig, outOff, outStep,
          lowFirst: true);

  @override
  void synthetizeHpfInt(
    Int32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Int32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Int32List outSig,
    int outOff,
    int outStep,
  ) =>
      _synthesize(lowSig, lowOff, lowLen, lowStep, highSig, highOff, highLen,
          highStep, outSig, outOff, outStep,
          lowFirst: false);

  void _synthesize(
    Int32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Int32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Int32List outSig,
    int outOff,
    int outStep, {
    required bool lowFirst,
  }) {
    final outLen = lowLen + highLen;
    if (outLen <= 0) {
      return;
    }
    final signal = _buffer(outLen);

    // T.801 G.2.2.1: a signal of one sample is passed through when it starts
    // on an even index and halved when it starts on an odd one.
    if (outLen == 1) {
      outSig[outOff] = lowFirst ? lowSig[lowOff] : highSig[highOff] >> 1;
      return;
    }

    // Interleave. Position p holds the sample of coordinate i0 + p, and i0 is
    // even exactly when the low-pass band comes first.
    var lk = lowOff;
    var hk = highOff;
    for (var p = lowFirst ? 0 : 1; p < outLen; p += 2) {
      signal[p] = lowSig[lk];
      lk += lowStep;
    }
    for (var p = lowFirst ? 1 : 0; p < outLen; p += 2) {
      signal[p] = highSig[hk];
      hk += highStep;
    }

    // The reconstruction runs the steps backwards (T.801 G-2).
    for (var s = _coefficients.length - 1; s >= 0; s--) {
      final taps = _coefficients[s];
      final exponent = _exponents[s];
      final residue = _residues[s];
      // `parity` is the parity of the coordinate the step updates; the first
      // position of that parity is 0 when the signal starts on it.
      final start = (lowFirst ? _parities[s] : 1 - _parities[s]);
      for (var p = start; p < outLen; p += 2) {
        var sum = residue;
        for (var k = 0; k < taps.length; k++) {
          final distance = 2 * k + 1;
          sum += taps[k] *
              (signal[SynWTFilterGenericLift.foldPosition(
                      p - distance, outLen)] +
                  signal[SynWTFilterGenericLift.foldPosition(
                      p + distance, outLen)]);
        }
        signal[p] -= sum >> exponent;
      }
    }

    var ik = outOff;
    for (var p = 0; p < outLen; p++) {
      outSig[ik] = signal[p];
      ik += outStep;
    }
  }

  @override
  int getAnLowNegSupport() => _support;

  @override
  int getAnLowPosSupport() => _support;

  @override
  int getAnHighNegSupport() => _support;

  @override
  int getAnHighPosSupport() => _support;

  @override
  int getSynLowNegSupport() => _support;

  @override
  int getSynLowPosSupport() => _support;

  @override
  int getSynHighNegSupport() => _support;

  @override
  int getSynHighPosSupport() => _support;

  @override
  int getImplType() => WaveletFilter.wtFilterIntLift;

  @override
  bool isReversible() => true;

  @override
  bool isSameAsFullWT(int tailOverlap, int headOverlap, int inputLength) =>
      tailOverlap >= _support && headOverlap >= _support;

  @override
  String toString() => 'ATK ${kernel.index} (reversible lifting, '
      '${kernel.stepCount} steps)';
}

/// Irreversible (`WT_Typ = IRR`) generic lifting synthesis, on float samples.
class SynWTFilterGenericFloatLift extends SynWTFilterFloat
    implements SynWTFilterGenericLift {
  /// Wraps [kernel]; it must be irreversible and whole-sample symmetric.
  SynWTFilterGenericFloatLift(this.kernel)
      : _coefficients = <Float32List>[
          for (final step in kernel.steps)
            Float32List.fromList(step.coefficients),
        ],
        _parities = Int32List.fromList(<int>[
          for (var s = 0; s < kernel.steps.length; s++) kernel.parityOfStep(s),
        ]),
        _evenScale = kernel.scale,
        _oddScale = 1 / kernel.scale,
        _support = SynWTFilterGenericLift.supportBound(kernel) {
    SynWTFilterGenericLift.checkSupported(kernel);
    if (kernel.reversible) {
      throw ArgumentError.value(
        kernel,
        'kernel',
        'a reversible kernel needs SynWTFilterGenericIntLift',
      );
    }
  }

  @override
  final AtkKernel kernel;

  final List<Float32List> _coefficients;
  final Int32List _parities;
  final double _evenScale;
  final double _oddScale;
  final int _support;

  Float32List _scratch = Float32List(0);

  Float32List _buffer(int length) {
    if (_scratch.length < length) {
      _scratch = Float32List(length);
    }
    return _scratch;
  }

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
  ) =>
      _synthesize(lowSig, lowOff, lowLen, lowStep, highSig, highOff, highLen,
          highStep, outSig, outOff, outStep,
          lowFirst: true);

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
  ) =>
      _synthesize(lowSig, lowOff, lowLen, lowStep, highSig, highOff, highLen,
          highStep, outSig, outOff, outStep,
          lowFirst: false);

  void _synthesize(
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
    int outStep, {
    required bool lowFirst,
  }) {
    final outLen = lowLen + highLen;
    if (outLen <= 0) {
      return;
    }

    if (outLen == 1) {
      outSig[outOff] = lowFirst ? lowSig[lowOff] : highSig[highOff] / 2;
      return;
    }

    final signal = _buffer(outLen);
    var lk = lowOff;
    var hk = highOff;
    for (var p = lowFirst ? 0 : 1; p < outLen; p += 2) {
      signal[p] = lowSig[lk];
      lk += lowStep;
    }
    for (var p = lowFirst ? 1 : 0; p < outLen; p += 2) {
      signal[p] = highSig[hk];
      hk += highStep;
    }

    // T.801 G-4 and G-5: even-indexed samples are multiplied by K and
    // odd-indexed ones by 1/K before any lifting step.
    for (var p = lowFirst ? 0 : 1; p < outLen; p += 2) {
      signal[p] = signal[p] * _evenScale;
    }
    for (var p = lowFirst ? 1 : 0; p < outLen; p += 2) {
      signal[p] = signal[p] * _oddScale;
    }

    for (var s = _coefficients.length - 1; s >= 0; s--) {
      final taps = _coefficients[s];
      final start = (lowFirst ? _parities[s] : 1 - _parities[s]);
      for (var p = start; p < outLen; p += 2) {
        var sum = 0.0;
        for (var k = 0; k < taps.length; k++) {
          final distance = 2 * k + 1;
          sum += taps[k] *
              (signal[SynWTFilterGenericLift.foldPosition(
                      p - distance, outLen)] +
                  signal[SynWTFilterGenericLift.foldPosition(
                      p + distance, outLen)]);
        }
        signal[p] = signal[p] - sum;
      }
    }

    var ik = outOff;
    for (var p = 0; p < outLen; p++) {
      outSig[ik] = signal[p];
      ik += outStep;
    }
  }

  @override
  int getAnLowNegSupport() => _support;

  @override
  int getAnLowPosSupport() => _support;

  @override
  int getAnHighNegSupport() => _support;

  @override
  int getAnHighPosSupport() => _support;

  @override
  int getSynLowNegSupport() => _support;

  @override
  int getSynLowPosSupport() => _support;

  @override
  int getSynHighNegSupport() => _support;

  @override
  int getSynHighPosSupport() => _support;

  @override
  int getImplType() => WaveletFilter.wtFilterFloatLift;

  @override
  bool isReversible() => false;

  @override
  bool isSameAsFullWT(int tailOverlap, int headOverlap, int inputLength) =>
      tailOverlap >= _support && headOverlap >= _support;

  @override
  String toString() => 'ATK ${kernel.index} (irreversible lifting, '
      '${kernel.stepCount} steps)';
}

/// Description of an arbitrary transformation kernel (ATK).
///
/// ISO/IEC 15444-2 (ITU-T T.801) A.3.5 lets a codestream carry its own wavelet
/// kernel instead of one of the two kernels ISO/IEC 15444-1 defines. The
/// kernel is described as a sequence of lifting steps, which makes a single
/// generic synthesis routine enough to run any of them: Annex G of the same
/// standard specifies the reconstruction (`1D_SR_WS` / `1D_FILTR_WS`) purely
/// in terms of these parameters.
library;

/// One lifting step of an [AtkKernel].
///
/// A step updates either the even- or the odd-indexed samples of the
/// interleaved signal with a weighted sum of the samples of the other parity,
/// taken symmetrically around the updated sample:
/// `V(2n + m) -= sum(k) a[k] * (V(2n + m - (2k+1)) + V(2n + m + (2k+1)))`
/// for irreversible kernels, and the same sum rounded with
/// `floor((sum + residue) / 2^exponent)` for reversible ones (T.801 G-2, G-6).
class AtkLiftingStep {
  /// Creates a step; [coefficients] is `Aatk[s][k]`, one per tap.
  const AtkLiftingStep({
    required this.coefficients,
    this.offset = 0,
    this.exponent = 0,
    this.residue = 0,
  });

  /// `off_s`, the tap offset of an arbitrary (`Filt_Cat = ARB`) kernel.
  ///
  /// Always zero for whole-sample symmetric kernels, which is the only
  /// category the synthesis implementation supports.
  final int offset;

  /// `eps_s`, the base-two scaling exponent; reversible kernels only.
  final int exponent;

  /// `beta_s`, the additive residue; reversible kernels only.
  final int residue;

  /// `alpha_s,k`, the lifting coefficients, `k` from 0 to `LCatk_s - 1`.
  final List<double> coefficients;

  /// The lifting coefficients as integers, for reversible kernels.
  List<int> get integerCoefficients =>
      <int>[for (final value in coefficients) value.toInt()];

  @override
  String toString() => 'AtkLiftingStep(coefficients: $coefficients, '
      'offset: $offset, exponent: $exponent, residue: $residue)';
}

/// A wavelet kernel read from an ATK marker segment (T.801 A.3.5).
class AtkKernel {
  /// Creates a kernel description.
  const AtkKernel({
    required this.index,
    required this.coefficientType,
    required this.wholeSampleSymmetric,
    required this.reversible,
    required this.initialParity,
    required this.constantExtension,
    required this.scale,
    required this.steps,
  });

  /// `Iatk`, the index tile-components refer to through `SPcod`/`SPcoc`.
  ///
  /// Runs from 2 to 255; 0 and 1 are taken by the two kernels of
  /// ISO/IEC 15444-1 (T.801 Table A.10).
  final int index;

  /// `Coeff_Typ`: 0 and 1 are 8- and 16-bit signed integers, 2, 3 and 4 are
  /// 32-, 64- and 128-bit binary floating point.
  final int coefficientType;

  /// `Filt_Cat`: true for a whole-sample symmetric kernel (`WS`), false for an
  /// arbitrary one (`ARB`, T.801 Annex H).
  final bool wholeSampleSymmetric;

  /// `WT_Typ`: true for a reversible kernel (`REV`), false for an irreversible
  /// one (`IRR`).
  final bool reversible;

  /// `minit`: the parity the last reconstruction lifting step updates, 0 for
  /// even-indexed samples and 1 for odd-indexed ones.
  final int initialParity;

  /// `Exten`: true when the boundary extension of an arbitrary kernel is
  /// constant (`CON`) rather than whole-sample symmetric (`WS`).
  final bool constantExtension;

  /// `K`, the scaling factor of an irreversible kernel; 1 for a reversible one.
  final double scale;

  /// The `NLS` lifting steps, in signalling order (`s` from 0 upwards).
  final List<AtkLiftingStep> steps;

  /// Number of lifting steps, `NLS`.
  int get stepCount => steps.length;

  /// Whether the coefficients are signalled as integers.
  bool get hasIntegerCoefficients => coefficientType <= 1;

  /// Parity of the samples updated by step [step] during reconstruction.
  ///
  /// T.801 G-2 fixes `m` for the last step (`s = NLS - 1`) at `minit` and
  /// alternates downwards: `m_s = 1 - m_(s+1)`.
  int parityOfStep(int step) {
    final distance = steps.length - 1 - step;
    return distance.isEven ? initialParity : 1 - initialParity;
  }

  @override
  String toString() => 'AtkKernel(index: $index, '
      '${reversible ? 'reversible' : 'irreversible'}, '
      '${wholeSampleSymmetric ? 'WS' : 'ARB'}, '
      'minit: $initialParity, steps: ${steps.length})';
}

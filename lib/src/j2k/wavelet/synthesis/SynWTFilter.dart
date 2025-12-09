import '../WaveletFilter.dart';

/// Abstract synthesis wavelet filter contract mirroring JJ2000's `SynWTFilter`.
abstract class SynWTFilter implements WaveletFilter {
  /// Reconstructs the output signal by recombining low-pass and high-pass inputs.
  void synthetize_lpf(
    Object lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Object highSig,
    int highOff,
    int highLen,
    int highStep,
    Object outSig,
    int outOff,
    int outStep,
  );

  /// Same as [synthetize_lpf] but with the high-pass branch filtered first.
  void synthetize_hpf(
    Object lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Object highSig,
    int highOff,
    int highLen,
    int highStep,
    Object outSig,
    int outOff,
    int outStep,
  );
}


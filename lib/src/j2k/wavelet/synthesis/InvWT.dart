import '../WaveletTransform.dart';

/// Specialization of [WaveletTransform] for inverse wavelet reconstruction.
abstract class InvWT extends WaveletTransform {
  /// Sets the reconstruction resolution level (0 is the coarsest level).
  void setImgResLevel(int resLevel);
}


import '../image/ImgData.dart';

/// Shared contract for forward or inverse wavelet transforms.
abstract class WaveletTransform implements ImgData {
  /// Identifier for line-based wavelet implementations.
  static const int wtImplLine = 0;

  /// Identifier for full-page wavelet implementations.
  static const int wtImplFull = 2;

  /// Whether the transform preserves lossless reconstruction for the
  /// specified tile/component.
  bool isReversible(int tile, int component);

  /// Returns the implementation type advertised for the component in the
  /// current tile (for example [wtImplLine] or [wtImplFull]).
  int getImplementationType(int component);
}


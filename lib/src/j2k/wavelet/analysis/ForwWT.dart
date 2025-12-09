import '../WaveletTransform.dart';
import 'AnWtFilter.dart';
import 'ForwWTDataProps.dart';

/// This interface extends the WaveletTransform with the specifics of forward
/// wavelet transforms. Classes that implement forward wavelet transfoms should
/// implement this interface.
///
/// This class does not define the methods to transfer data, just the
/// specifics to forward wavelet transform. Different data transfer methods are
/// evisageable for different transforms.
abstract class ForwWT implements WaveletTransform, ForwWTDataProps {
  /// Returns the horizontal analysis wavelet filters used in each level, for
  /// the specified tile-component. The first element in the array is the
  /// filter used to obtain the lowest resolution (resolution level 0)
  /// subbands (i.e. lowest frequency LL subband), the second element is the
  /// one used to generate the resolution level 1 subbands, and so on. If
  /// there are less elements in the array than the number of resolution
  /// levels, then the last one is assumed to repeat itself.
  ///
  /// The returned filters are applicable only to the specified component
  /// and in the current tile.
  ///
  /// The resolution level of a subband is the resolution level to which a
  /// subband contributes, which is different from its decomposition
  /// level.
  ///
  /// @param t The index of the tile for which to return the filters.
  ///
  /// @param c The index of the component for which to return the filters.
  ///
  /// @return The horizontal analysis wavelet filters used in each level.
  List<AnWTFilter> getHorAnWaveletFilters(int t, int c);

  /// Returns the vertical analysis wavelet filters used in each level, for
  /// the specified tile-component. The first element in the array is the
  /// filter used to obtain the lowest resolution (resolution level 0)
  /// subbands (i.e. lowest frequency LL subband), the second element is the
  /// one used to generate the resolution level 1 subbands, and so on. If
  /// there are less elements in the array than the number of resolution
  /// levels, then the last one is assumed to repeat itself.
  ///
  /// The returned filters are applicable only to the specified component
  /// and in the current tile.
  ///
  /// The resolution level of a subband is the resolution level to which a
  /// subband contributes, which is different from its decomposition
  /// level.
  ///
  /// @param t The index of the tile for which to return the filters.
  ///
  /// @param c The index of the component for which to return the filters.
  ///
  /// @return The vertical analysis wavelet filters used in each level.
  List<AnWTFilter> getVertAnWaveletFilters(int t, int c);

  /// Returns the number of decomposition levels that are applied to obtain
  /// the LL band, in the specified tile-component. A value of 0 means that
  /// no wavelet transform is applied.
  ///
  /// @param t The tile index
  ///
  /// @param c The index of the component.
  ///
  /// @return The number of decompositions applied to obtain the LL subband
  /// (0 for no wavelet transform).
  int getDecompLevels(int t, int c);

  /// Returns the wavelet tree decomposition. Only WT_DECOMP_DYADIC is
  /// supported by JPEG 2000 part I.
  ///
  /// @param t The tile index
  ///
  /// @param c The index of the component.
  ///
  /// @return The wavelet decomposition.
  int getDecomp(int t, int c);
}


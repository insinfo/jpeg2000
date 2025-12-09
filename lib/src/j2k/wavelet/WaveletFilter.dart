/// Shared contract for JJ2000 wavelet filters.
abstract class WaveletFilter {
  static const int wtFilterIntLift = 0;
  static const int wtFilterFloatLift = 1;
  static const int wtFilterFloatConvolution = 2;

  int getAnLowNegSupport();
  int getAnLowPosSupport();
  int getAnHighNegSupport();
  int getAnHighPosSupport();
  int getSynLowNegSupport();
  int getSynLowPosSupport();
  int getSynHighNegSupport();
  int getSynHighPosSupport();
  int getImplType();
  int getDataType();
  bool isReversible();
  bool isSameAsFullWT(int tailOverlap, int headOverlap, int inputLength);
}

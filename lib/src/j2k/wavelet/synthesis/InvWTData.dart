import 'MultiResImgData.dart';


/// Extension over [MultiResImgData] for sources feeding the inverse wavelet transform.
abstract class InvWTData extends MultiResImgData {
  /// Horizontal code-block partition origin (0 or 1).
  int getCbULX();

  /// Vertical code-block partition origin (0 or 1).
  int getCbULY();
}


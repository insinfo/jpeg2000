import '../icc_profile.dart';

class XYZNumber {
  static const int size = 3 * ICCProfile.intSize;

  /// x value
  int dwX; // X tristimulus value
  /// y value
  int dwY; // Y tristimulus value
  /// z value
  int dwZ; // Z tristimulus value

  /// Construct from constituent parts.
  XYZNumber(this.dwX, this.dwY, this.dwZ);

  /// Normalization utility
  static int doubleToXyz(double x) {
    return (x * 65536.0 + 0.5).floor();
  }

  /// Normalization utility
  static double xyzToDouble(int x) {
    return x / 65536.0;
  }

  /// String representation of class instance.
  @override
  String toString() {
    return "[$dwX, $dwY, $dwZ]";
  }
}

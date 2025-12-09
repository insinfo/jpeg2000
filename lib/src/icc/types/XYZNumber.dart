import '../ICCProfile.dart';

class XYZNumber {
  static const int size = 3 * ICCProfile.int_size;

  /** x value */
  int dwX; // X tristimulus value
  /** y value */
  int dwY; // Y tristimulus value
  /** z value */
  int dwZ; // Z tristimulus value

  /** Construct from constituent parts. */
  XYZNumber(this.dwX, this.dwY, this.dwZ);

  /** Normalization utility */
  static int DoubleToXYZ(double x) {
    return (x * 65536.0 + 0.5).floor();
  }

  /** Normalization utility */
  static double XYZToDouble(int x) {
    return x / 65536.0;
  }

  /** String representation of class instance. */
  @override
  String toString() {
    return "[$dwX, $dwY, $dwZ]";
  }
}


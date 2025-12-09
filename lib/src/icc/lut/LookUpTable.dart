import '../tags/ICCCurveType.dart';

/// Toplevel class for a lut.  All lookup tables must
/// extend this class.
abstract class LookUpTable {
  /// End of line string.
  static const String eol = '\n'; // System.getProperty ("line.separator");

  /// The curve data
  ICCCurveType? curve;

  /// Number of values in created lut
  int dwNumInput = 0;

  /// For subclass usage.
  ///   @param curve The curve data
  ///   @param dwNumInput Number of values in created lut
  LookUpTable(this.curve, this.dwNumInput);
}


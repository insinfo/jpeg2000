import 'dart:typed_data';
import '../tags/ICCCurveType.dart';
import 'LookUpTable.dart';
import 'LookUpTable16Gamma.dart';
import 'LookUpTable16Interp.dart';

/// Base class for 16-bit lookup tables.
abstract class LookUpTable16 extends LookUpTable {
  /// Maximum output value of the table.
  final int dwMaxOutput;

  /// Lookup values stored as unsigned 16-bit integers.
  late final Uint16List lut;

  /// Factory for building gamma or interpolated tables.
  static LookUpTable16 createInstance(
      ICCCurveType curve, int dwNumInput, int dwMaxOutput) {
    if (curve.count == 1) {
      return LookUpTable16Gamma(curve, dwNumInput, dwMaxOutput);
    }
    return LookUpTable16Interp(curve, dwNumInput, dwMaxOutput);
  }

  LookUpTable16(int dwNumInput, this.dwMaxOutput)
      : super(null, dwNumInput) {
    lut = Uint16List(dwNumInput);
  }

  LookUpTable16.fromCurve(
      ICCCurveType curve, int dwNumInput, this.dwMaxOutput)
      : super(curve, dwNumInput) {
    lut = Uint16List(dwNumInput);
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer('[LookUpTable16 ');
    rep.write('max= $dwMaxOutput');
    rep.write(', nentries= $dwNumInput');
    return (rep..write(']')).toString();
  }

  String toStringWholeLut() {
    StringBuffer rep = StringBuffer('[LookUpTable16${LookUpTable.eol}');
    int row;
    rep.write('max output = $dwMaxOutput${LookUpTable.eol}');
    for (row = 0; row < dwNumInput ~/ 10; ++row) {
      rep.write('lut[${10 * row}] : ');
      for (int col = 0; col < 10; ++col) {
        rep.write('${lut[10 * row + col]} ');
      }
      rep.write(LookUpTable.eol);
    }
    rep.write('lut[${10 * row}] : ');
    for (int col = 0; col < dwNumInput % 10; ++col) {
      rep.write('${lut[10 * row + col]} ');
    }
    rep.write('${LookUpTable.eol}${LookUpTable.eol}');
    return rep.toString();
  }

  int elementAt(int index) => lut[index];
}

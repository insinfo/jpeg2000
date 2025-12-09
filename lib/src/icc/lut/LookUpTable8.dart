import 'dart:typed_data';
import '../tags/ICCCurveType.dart';
import 'LookUpTable.dart';

/// Base class for 8-bit lookup tables.
abstract class LookUpTable8 extends LookUpTable {
  /// Maximum output value.
  final int dwMaxOutput;

  /// Lookup values.
  late final Uint8List lut;

  LookUpTable8(int dwNumInput, this.dwMaxOutput)
      : super(null, dwNumInput) {
    lut = Uint8List(dwNumInput);
  }

  LookUpTable8.fromCurve(
      ICCCurveType curve, int dwNumInput, this.dwMaxOutput)
      : super(curve, dwNumInput) {
    lut = Uint8List(dwNumInput);
  }

  /// Abbreviated representation.
  @override
  String toString() {
    StringBuffer rep = StringBuffer('[LookUpTable8 ');
    rep.write('max= $dwMaxOutput');
    rep.write(', nentries= $dwNumInput');
    return (rep..write(']')).toString();
  }

  /// Dump the entire LUT.
  String toStringWholeLut() {
    StringBuffer rep = StringBuffer('LookUpTable8${LookUpTable.eol}');
    rep.write('maxOutput = $dwMaxOutput${LookUpTable.eol}');
    for (int i = 0; i < dwNumInput; ++i) {
      rep.write('lut[$i] = ${lut[i]}${LookUpTable.eol}');
    }
    return (rep..write(']')).toString();
  }

  /// Accessor for LUT entries.
  int elementAt(int index) => lut[index];
}

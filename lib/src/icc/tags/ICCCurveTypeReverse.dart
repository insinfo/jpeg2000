import 'dart:typed_data';
import '../ICCProfile.dart';
import 'ICCTag.dart';
import 'ICCCurveType.dart';

/// The ICCCurveReverse tag
class ICCCurveTypeReverse extends ICCTag {
  static const String eol = '\n'; // System.getProperty ("line.separator");

  /// Tag fields
  final int type;

  /// Tag fields
  final int reserved;

  /// Tag fields
  final int nEntries;

  /// Tag fields
  final Int32List entry;

  /// Return the string rep of this tag.
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[")
      ..write(super.toString())
      ..write(eol)
      ..write("num entries = $nEntries$eol")
      ..write("data length = ${entry.length}$eol");
    for (int i = 0; i < nEntries; ++i) {
      rep.write("${ICCProfile.toHexStringShort(entry[i])}$eol");
    }
    return (rep..write("]")).toString();
  }

  /// Normalization utility
  static double curveToDouble(int entry) {
    return ICCCurveType.curveToDouble(entry);
  }

  /// Normalization utility
  static int doubleToCurve(double entry) {
    return ICCCurveType.doubleToCurve(entry);
  }

  /// Normalization utility
  static double curveGammaToDouble(int entry) {
    return ICCCurveType.curveGammaToDouble(entry);
  }

  /// Construct this tag from its constituant parts
  ICCCurveTypeReverse(int signature, Uint8List data, int offset, int length)
      : type = ICCProfile.getInt(data, offset),
        reserved = ICCProfile.getInt(data, offset + ICCProfile.int_size),
        nEntries = ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size),
        entry = Int32List(ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size)),
        super(signature, data, offset, offset + 2 * ICCProfile.int_size) {
    
    for (int i = 0; i < nEntries; ++i) {
      // Reverse the storage order.
      // Assuming the Java code meant nEntries - 1 - i
      entry[nEntries - 1 - i] = ICCProfile.getShort(
              data, offset + 3 * ICCProfile.int_size + i * ICCProfile.short_size) &
          0xFFFF;
    }
  }

  /// Accessor for curve entry at index.
  int entryAt(int i) {
    return entry[i];
  }
}


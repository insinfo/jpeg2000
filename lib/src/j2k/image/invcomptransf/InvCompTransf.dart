import 'dart:math' as math;

import '../../util/MathUtil.dart';

/// Helper utilities for inverse component transformations.
abstract class InvCompTransf {
  static const int none = 0;
  static const int invRct = 1;
  static const int invIct = 2;
  /// JJ2000 option prefix reserved for inverse component transform toggles.
  static const String optionPrefix = 'M';

  /// Computes the bit depths of components after applying the inverse
  /// component transform designated by [ttype].
  static List<int> calcMixedBitDepths(
    List<int> utDepth,
    int ttype, [
    List<int>? reuse,
  ]) {
    if (utDepth.length < 3 && ttype != none) {
      throw ArgumentError('At least three components required for ICT/RCT');
    }

    final result = reuse ?? List<int>.filled(utDepth.length, 0, growable: false);

    switch (ttype) {
      case none:
        for (var i = 0; i < utDepth.length; i++) {
          result[i] = utDepth[i];
        }
        break;
      case invRct:
        if (utDepth.length > 3) {
          for (var i = 3; i < utDepth.length; i++) {
            result[i] = utDepth[i];
          }
        }
        final term0 = (1 << utDepth[0]) + (2 << utDepth[1]) + (1 << utDepth[2]) - 1;
        final term1 = (1 << utDepth[2]) + (1 << utDepth[1]) - 1;
        final term2 = (1 << utDepth[0]) + (1 << utDepth[1]) - 1;
        result[0] = MathUtil.log2(math.max(1, term0)) - 2 + 1;
        result[1] = MathUtil.log2(math.max(1, term1)) + 1;
        result[2] = MathUtil.log2(math.max(1, term2)) + 1;
        break;
      case invIct:
        if (utDepth.length > 3) {
          for (var i = 3; i < utDepth.length; i++) {
            result[i] = utDepth[i];
          }
        }
        final val0 = ((1 << utDepth[0]) * 0.299072 +
                (1 << utDepth[1]) * 0.586914 +
                (1 << utDepth[2]) * 0.114014)
            .floor();
        final val1 = ((1 << utDepth[0]) * 0.168701 +
                (1 << utDepth[1]) * 0.331299 +
                (1 << utDepth[2]) * 0.5)
            .floor();
        final val2 = ((1 << utDepth[0]) * 0.5 +
                (1 << utDepth[1]) * 0.418701 +
                (1 << utDepth[2]) * 0.081299)
            .floor();
        result[0] = MathUtil.log2(math.max(1, val0 - 1)) + 1;
        result[1] = MathUtil.log2(math.max(1, val1 - 1)) + 1;
        result[2] = MathUtil.log2(math.max(1, val2 - 1)) + 1;
        break;
      default:
        throw ArgumentError('Unsupported component transform type: $ttype');
    }

    return result;
  }
}


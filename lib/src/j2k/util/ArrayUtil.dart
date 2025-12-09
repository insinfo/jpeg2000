import 'dart:typed_data';

/// Utilities for working with primitive lists.
class ArrayUtil {
  static const int maxElementCopying = 8;
  static const int initialElementCopying = 4;

  static void intArraySet(List<int> array, int value) {
    _fill(array, value);
  }

  static void byteArraySet(List<int> array, int value) {
    final masked = value & 0xFF;
    _fill(array, masked);
  }

  static void _fill(List<int> array, int value) {
    final length = array.length;
    if (length == 0) {
      return;
    }
    if (length < maxElementCopying) {
      for (var i = 0; i < length; i++) {
        array[i] = value;
      }
      return;
    }

    final cappedInit = initialElementCopying < length
        ? initialElementCopying
        : length;
    var i = 0;
    for (; i < cappedInit; i++) {
      array[i] = value;
    }

    var limit = length >> 1;
    while (i <= limit) {
      _copyRange(array, 0, i, i);
      i <<= 1;
    }

    if (i < length) {
      _copyRange(array, 0, length - i, i);
    }
  }

  static void _copyRange(List<int> array, int start, int count, int target) {
    if (count <= 0) {
      return;
    }
    if (array is Uint8List) {
      array.setRange(target, target + count, array, start);
    } else if (array is Int32List) {
      array.setRange(target, target + count, array, start);
    } else {
      array.setRange(target, target + count, array, start);
    }
  }
}

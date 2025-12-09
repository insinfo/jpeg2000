import 'dart:typed_data';
import '../ICCProfile.dart';
import '../types/ICCProfileHeader.dart';
import 'ICCTag.dart';
import '../../colorspace/ColorSpace.dart';

/// This class models an ICCTagTable as a HashTable which maps
/// ICCTag signatures (as Integers) to ICCTags.
class ICCTagTable {
  static const String eol = '\n'; // System.getProperty("line.separator");
  static const int offTagCount = ICCProfileHeader.size;
  static const int offTags = offTagCount + ICCProfile.int_size;

  final List<_Triplet> _trios = [];
  final Map<int, ICCTag> _tags = {};

  int tagCount = 0;

  /// Representation of a tag table
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ICCTagTable containing $tagCount tags:");
    StringBuffer body = StringBuffer("  ");
    for (var key in _tags.keys) {
      ICCTag tag = _tags[key]!;
      body.write("$eol$tag");
    }
    rep.write(ColorSpace.indent("  ", body.toString()));
    return (rep..write("]")).toString();
  }

  /// Factory method for creating a tag table from raw input.
  static ICCTagTable createInstance(Uint8List data) {
    return ICCTagTable(data);
  }

  /// Ctor used by factory method.
  ICCTagTable(Uint8List data) {
    tagCount = ICCProfile.getInt(data, offTagCount);

    int offset = offTags;
    for (int i = 0; i < tagCount; ++i) {
      int signature = ICCProfile.getInt(data, offset);
      int tagOffset = ICCProfile.getInt(data, offset + ICCProfile.int_size);
      int length = ICCProfile.getInt(data, offset + 2 * ICCProfile.int_size);
      _trios.add(_Triplet(signature, tagOffset, length));
      offset += 3 * ICCProfile.int_size;
    }

    for (var trio in _trios) {
      ICCTag tag =
          ICCTag.createInstance(trio.signature, data, trio.offset, trio.count);
      _tags[tag.signature] = tag;
    }
  }

  ICCTag? get(int signature) {
    return _tags[signature];
  }
}

class _Triplet {
  /// Tag identifier
  final int signature;

  /// absolute offset of tag data
  final int offset;

  /// length of tag data
  final int count;

  /// size of an entry
  // static const int size = 3 * ICCProfile.int_size; // Unused

  _Triplet(this.signature, this.offset, this.count);
}


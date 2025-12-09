import 'dart:typed_data';
import '../ICCProfile.dart';
import 'ICCTextDescriptionType.dart';
import 'ICCTextType.dart';
import 'ICCXYZType.dart';
import 'ICCXYZTypeReverse.dart';
import 'ICCCurveType.dart';
import 'ICCCurveTypeReverse.dart';

/// An ICC profile contains a 128-byte header followed by a variable
/// number of tags contained in a tag table. Each tag is a structured
/// block of ints. The tags share a common format on disk starting with
/// a signature, an offset to the tag data, and a length of the tag data.
/// The tag data itself is found at the given offset in the file and
/// consists of a tag type int, followed by a reserved int, followed by
/// a data block, the structure of which is unique to the tag type.
///
/// This class is the abstract super class of all tags. It models that
/// part of the structure which is common among tags of all types.
/// It also contains the definitions of the various tag types.
abstract class ICCTag {
  // Tag Signature Strings
  static const String sdwCprtSignature = "cprt";
  static const String sdwDescSignature = "desc";
  static const String sdwWtPtSignature = "wtpt";
  static const String sdwBkPtSignature = "bkpt";
  static const String sdwRXYZSignature = "rXYZ";
  static const String sdwGXYZSignature = "gXYZ";
  static const String sdwBXYZSignature = "bXYZ";
  static const String sdwKXYZSignature = "kXYZ";
  static const String sdwRTRCSignature = "rTRC";
  static const String sdwGTRCSignature = "gTRC";
  static const String sdwBTRCSignature = "bTRC";
  static const String sdwKTRCSignature = "kTRC";
  static const String sdwDmndSignature = "dmnd";
  static const String sdwDmddSignature = "dmdd";

  // Tag Signatures
  static final int kdwCprtSignature = ICCProfile.getIntFromString(sdwCprtSignature);
  static final int kdwDescSignature = ICCProfile.getIntFromString(sdwDescSignature);
  static final int kdwWtPtSignature = ICCProfile.getIntFromString(sdwWtPtSignature);
  static final int kdwBkPtSignature = ICCProfile.getIntFromString(sdwBkPtSignature);
  static final int kdwRXYZSignature = ICCProfile.getIntFromString(sdwRXYZSignature);
  static final int kdwGXYZSignature = ICCProfile.getIntFromString(sdwGXYZSignature);
  static final int kdwBXYZSignature = ICCProfile.getIntFromString(sdwBXYZSignature);
  static final int kdwKXYZSignature = ICCProfile.getIntFromString(sdwKXYZSignature);
  static final int kdwRTRCSignature = ICCProfile.getIntFromString(sdwRTRCSignature);
  static final int kdwGTRCSignature = ICCProfile.getIntFromString(sdwGTRCSignature);
  static final int kdwBTRCSignature = ICCProfile.getIntFromString(sdwBTRCSignature);
  static final int kdwKTRCSignature = ICCProfile.getIntFromString(sdwKTRCSignature);
  static final int kdwDmndSignature = ICCProfile.getIntFromString(sdwDmndSignature);
  static final int kdwDmddSignature = ICCProfile.getIntFromString(sdwDmddSignature);

  // Tag Type Strings
  static const String sdwTextDescType = "desc";
  static const String sdwTextType = "text";
  static const String sdwCurveType = "curv";
  static const String sdwCurveTypeReverse = "vruc";
  static const String sdwXYZType = "XYZ ";
  static const String sdwXYZTypeReverse = " ZYX";

  // Tag Types
  static final int kdwTextDescType = ICCProfile.getIntFromString(sdwTextDescType);
  static final int kdwTextType = ICCProfile.getIntFromString(sdwTextType);
  static final int kdwCurveType = ICCProfile.getIntFromString(sdwCurveType);
  static final int kdwCurveTypeReverse = ICCProfile.getIntFromString(sdwCurveTypeReverse);
  static final int kdwXYZType = ICCProfile.getIntFromString(sdwXYZType);
  static final int kdwXYZTypeReverse = ICCProfile.getIntFromString(sdwXYZTypeReverse);

  /// Tag signature
  final int signature;

  /// Tag type
  final int type;

  /// Tag data
  final Uint8List data;

  /// offset to tag data in the array
  final int offset;

  /// size of the tag data in the array
  final int count;

  /// Create a string representation of the tag type
  static String typeString(int type) {
    if (type == kdwTextDescType)
      return sdwTextDescType;
    else if (type == kdwTextType)
      return sdwTextDescType;
    else if (type == kdwCurveType)
      return sdwCurveType;
    else if (type == kdwCurveTypeReverse)
      return sdwCurveTypeReverse;
    else if (type == kdwXYZType)
      return sdwXYZType;
    else if (type == kdwXYZTypeReverse)
      return sdwXYZTypeReverse;
    else
      return "bad tag type";
  }

  /// Create a string representation of the signature
  static String signatureString(int signature) {
    if (signature == kdwCprtSignature)
      return sdwCprtSignature;
    else if (signature == kdwDescSignature)
      return sdwDescSignature;
    else if (signature == kdwWtPtSignature)
      return sdwWtPtSignature;
    else if (signature == kdwBkPtSignature)
      return sdwBkPtSignature;
    else if (signature == kdwRXYZSignature)
      return sdwRXYZSignature;
    else if (signature == kdwGXYZSignature)
      return sdwGXYZSignature;
    else if (signature == kdwBXYZSignature)
      return sdwBXYZSignature;
    else if (signature == kdwRTRCSignature)
      return sdwRTRCSignature;
    else if (signature == kdwGTRCSignature)
      return sdwGTRCSignature;
    else if (signature == kdwBTRCSignature)
      return sdwBTRCSignature;
    else if (signature == kdwKTRCSignature)
      return sdwKTRCSignature;
    else if (signature == kdwDmndSignature)
      return sdwDmndSignature;
    else if (signature == kdwDmddSignature)
      return sdwDmddSignature;
    else
      return "bad tag signature";
  }

  /// Factory method for creating a tag of a specific type.
  static ICCTag createInstance(
      int signature, Uint8List data, int offset, int count) {
    int type = ICCProfile.getInt(data, offset);

    if (type == kdwTextDescType)
      return ICCTextDescriptionType(signature, data, offset, count);
    else if (type == kdwTextType)
      return ICCTextType(signature, data, offset, count);
    else if (type == kdwXYZType)
      return ICCXYZType(signature, data, offset, count);
    else if (type == kdwXYZTypeReverse)
      return ICCXYZTypeReverse(signature, data, offset, count);
    else if (type == kdwCurveType)
      return ICCCurveType(signature, data, offset, count);
    else if (type == kdwCurveTypeReverse)
      return ICCCurveTypeReverse(signature, data, offset, count);
    else
      throw ArgumentError("bad tag type");
  }

  /// Used by subclass initialization to store the state common to all tags
  ICCTag(this.signature, this.data, this.offset, this.count)
      : type = ICCProfile.getInt(data, offset);

  @override
  String toString() {
    return "${signatureString(signature)}:${typeString(type)}";
  }
}


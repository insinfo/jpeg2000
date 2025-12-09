import 'dart:typed_data';
import 'types/XyzNumber.dart';
import 'types/ICCProfileVersion.dart';
import 'types/ICCDateTime.dart';
import 'types/ICCProfileHeader.dart';
import 'tags/ICCTagTable.dart';
import 'tags/ICCCurveType.dart';
import 'tags/ICCXYZType.dart';
import 'RestrictedICCProfile.dart';
import 'ICCProfileInvalidException.dart';
import '../colorspace/ColorSpace.dart';
import '../j2k/util/ParameterList.dart';
import '../j2k/util/FacilityManager.dart';
import '../j2k/util/MsgLogger.dart';
import '../j2k/fileformat/FileFormatBoxes.dart';

abstract class ICCProfile {
  static const String eol = '\n'; // System.getProperty("line.separator");

  // Renamed for convenience:
  /** Gray index. */
  static const int GRAY = 0;
  /** RGB index.  */
  static const int RED = 0;
  /** RGB index.  */
  static const int GREEN = 1;
  /** RGB index.  */
  static const int BLUE = 2;

  /** Size of native type */
  static const int boolean_size = 1;
  /** Size of native type */
  static const int byte_size = 1;
  /** Size of native type */
  static const int char_size = 2;
  /** Size of native type */
  static const int short_size = 2;
  /** Size of native type */
  static const int int_size = 4;
  /** Size of native type */
  static const int float_size = 4;
  /** Size of native type */
  static const int long_size = 8;
  /** Size of native type */
  static const int double_size = 8;

  /* Bit twiddling constant for integral types. */
  static const int BITS_PER_BYTE = 8;
  /* Bit twiddling constant for integral types. */
  static const int BITS_PER_SHORT = 16;
  /* Bit twiddling constant for integral types. */
  static const int BITS_PER_INT = 32;
  /* Bit twiddling constant for integral types. */
  static const int BITS_PER_LONG = 64;
  /* Bit twiddling constant for integral types. */
  static const int BYTES_PER_SHORT = 2;
  /* Bit twiddling constant for integral types. */
  static const int BYTES_PER_INT = 4;
  /* Bit twiddling constant for integral types. */
  static const int BYTES_PER_LONG = 8;

  /* JP2 Box structure analysis help */
  static final Map<int, String> _boxTypeMap = {
    FileFormatBoxes.bitsPerComponentBox: "BITS_PER_COMPONENT_BOX",
    FileFormatBoxes.captureResolutionBox: "CAPTURE_RESOLUTION_BOX",
    FileFormatBoxes.channelDefinitionBox: "CHANNEL_DEFINITION_BOX",
    FileFormatBoxes.colourSpecificationBox: "COLOUR_SPECIFICATION_BOX",
    FileFormatBoxes.componentMappingBox: "COMPONENT_MAPPING_BOX",
    FileFormatBoxes.contiguousCodestreamBox: "CONTIGUOUS_CODESTREAM_BOX",
    FileFormatBoxes.defaultDisplayResolutionBox: "DEFAULT_DISPLAY_RESOLUTION_BOX",
    FileFormatBoxes.fileTypeBox: "FILE_TYPE_BOX",
    FileFormatBoxes.imageHeaderBox: "IMAGE_HEADER_BOX",
    FileFormatBoxes.intellectualPropertyBox: "INTELLECTUAL_PROPERTY_BOX",
    FileFormatBoxes.jp2HeaderBox: "JP2_HEADER_BOX",
    FileFormatBoxes.jp2SignatureBox: "JP2_SIGNATURE_BOX",
    FileFormatBoxes.paletteBox: "PALETTE_BOX",
    FileFormatBoxes.resolutionBox: "RESOLUTION_BOX",
    FileFormatBoxes.urlBox: "URL_BOX",
    FileFormatBoxes.uuidBox: "UUID_BOX",
    FileFormatBoxes.uuidInfoBox: "UUID_INFO_BOX",
    FileFormatBoxes.uuidListBox: "UUID_LIST_BOX",
    FileFormatBoxes.xmlBox: "XML_BOX",
  };

  static String? getBoxTypeString(int type) {
    return _boxTypeMap[type];
  }

  static String colorSpecMethod(int meth) {
    switch (meth) {
      case 2:
        return "Restricted ICC Profile";
      case 1:
        return "Enumerated Color Space";
      default:
        return "Undefined Color Spec Method";
    }
  }

  /**
   * Creates an int from a 4 character String
   *   @param fourChar string representation of an integer
   * @return the integer which is denoted by the input String.
   */
  static int getIntFromString(String fourChar) {
    List<int> bytes = fourChar.codeUnits;
    return getInt(Uint8List.fromList(bytes), 0);
  }

  /**
   * Create an XYZNumber from byte [] input
   *   @param data array containing the XYZNumber representation
   *   @param offset start of the rep in the array
   * @return the created XYZNumber
   */
  static XYZNumber getXYZNumber(Uint8List data, int offset) {
    int x, y, z;
    x = getInt(data, offset);
    y = getInt(data, offset + int_size);
    z = getInt(data, offset + 2 * int_size);
    return XYZNumber(x, y, z);
  }

  /**
   * Create an ICCProfileVersion from byte [] input
   *   @param data array containing the ICCProfileVersion representation
   *   @param offset start of the rep in the array
   * @return  the created ICCProfileVersion
   */
  static ICCProfileVersion getICCProfileVersion(Uint8List data, int offset) {
    int major = data[offset];
    int minor = data[offset + byte_size];
    int resv1 = data[offset + 2 * byte_size];
    int resv2 = data[offset + 3 * byte_size];
    return ICCProfileVersion(major, minor, resv1, resv2);
  }

  /**
   * Create an ICCDateTime from byte [] input
   *   @param data array containing the ICCProfileVersion representation
   *   @param offset start of the rep in the array
   * @return the created ICCProfileVersion
   */
  static ICCDateTime getICCDateTime(Uint8List data, int offset) {
    int wYear = getShort(data, offset); // Number of the actual year (i.e. 1994)
    int wMonth = getShort(
        data, offset + ICCProfile.short_size); // Number of the month (1-12)
    int wDay = getShort(
        data, offset + 2 * ICCProfile.short_size); // Number of the day
    int wHours = getShort(
        data, offset + 3 * ICCProfile.short_size); // Number of hours (0-23)
    int wMinutes = getShort(
        data, offset + 4 * ICCProfile.short_size); // Number of minutes (0-59)
    int wSeconds = getShort(
        data, offset + 5 * ICCProfile.short_size); // Number of seconds (0-59)
    return ICCDateTime(wYear, wMonth, wDay, wHours, wMinutes, wSeconds);
  }

  /**
   * Create a String from a byte []. Optionally swap adjacent byte
   * pairs.  Intended to be used to create integer String representations
   * allowing for endian translations.
   *   @param bfr data array
   *   @param offset start of data in array
   *   @param length length of data in array
   *   @param swap swap adjacent bytes?
   * @return String rep of data
   */
  static String getString(
      Uint8List bfr, int offset, int length, bool swap) {
    Uint8List result = Uint8List(length);
    int incr = swap ? -1 : 1;
    int start = swap ? offset + length - 1 : offset;
    for (int i = 0, j = start; i < length; ++i) {
      result[i] = bfr[j];
      j += incr;
    }
    return String.fromCharCodes(result);
  }

  /**
   * Create a short from a two byte [], with optional byte swapping.
   *   @param bfr data array
   *   @param off start of data in array
   *   @param swap swap bytes?
   * @return native type from representation.
   */
  static int getShort(Uint8List bfr, int off, [bool swap = false]) {
    int tmp0 = bfr[off] & 0xff; // Clear the sign extended bits in the int.
    int tmp1 = bfr[off + 1] & 0xff;

    return (swap
        ? (tmp1 << BITS_PER_BYTE | tmp0)
        : (tmp0 << BITS_PER_BYTE | tmp1));
  }

  /**
   * Separate bytes in an int into a byte array lsb to msb order.
   *   @param d integer to separate
   * @return byte [] containing separated int.
   */
  static Uint8List setInt(int d, [Uint8List? b]) {
    if (b == null) b = Uint8List(BYTES_PER_INT);
    for (int i = 0; i < BYTES_PER_INT; ++i) {
      b[i] = (d & 0x0ff);
      d = d >> BITS_PER_BYTE;
    }
    return b;
  }

  /**
   * Separate bytes in a long into a byte array lsb to msb order.
   *   @param d long to separate
   * @return byte [] containing separated int.
   */
  static Uint8List setLong(int d, [Uint8List? b]) {
    if (b == null) b = Uint8List(BYTES_PER_LONG);
    for (int i = 0; i < BYTES_PER_LONG; ++i) {
      b[i] = (d & 0x0ff);
      d = d >> BITS_PER_BYTE;
    }
    return b;
  }

  /**
   * Create an int from a byte [4], with optional byte swapping.
   *   @param bfr data array
   *   @param off start of data in array
   *   @param swap swap bytes?
   * @return native type from representation.
   */
  static int getInt(Uint8List bfr, int off, [bool swap = false]) {
    int tmp0 =
        getShort(bfr, off, swap) & 0xffff; // Clear the sign extended bits in the int.
    int tmp1 = getShort(bfr, off + 2, swap) & 0xffff;

    return (swap
        ? (tmp1 << BITS_PER_SHORT | tmp0)
        : (tmp0 << BITS_PER_SHORT | tmp1));
  }

  /**
   * Create an long from a byte [8].
   *   @param bfr data array
   *   @param off start of data in array
   * @return native type from representation.
   */
  static int getLong(Uint8List bfr, int off) {
    int tmp0 =
        getInt(bfr, off) & 0xffffffff; // Clear the sign extended bits in the int.
    int tmp1 = getInt(bfr, off + 4) & 0xffffffff;

    return (tmp0 << BITS_PER_INT | tmp1);
  }

  // Define the set of standard signature and type values
  // Because of the endian issues and byte swapping, the profile codes must
  // be stored in memory and be addressed by address. As such, only those
  // codes required for Restricted ICC use are defined here

  /** signature    */
  static final int kdwProfileSignature =
      ICCProfile.getIntFromString("acsp");
  /** signature    */
  static final int kdwProfileSigReverse =
      ICCProfile.getIntFromString("psca");
  /** profile type */
  static final int kdwInputProfile =
      ICCProfile.getIntFromString("scnr");
  /** tag type     */
  static final int kdwDisplayProfile =
      ICCProfile.getIntFromString("mntr");
  /** tag type     */
  static final int kdwRGBData = ICCProfile.getIntFromString("RGB ");
  /** tag type     */
  static final int kdwGrayData = ICCProfile.getIntFromString("GRAY");
  /** tag type     */
  static final int kdwXYZData = ICCProfile.getIntFromString("XYZ ");
  /** input type   */
  static const int kMonochromeInput = 0;
  /** input type   */
  static const int kThreeCompInput = 1;

  /** tag signature */
  static final int kdwGrayTRCTag = ICCProfile.getIntFromString("kTRC");
  /** tag signature */
  static final int kdwRedColorantTag =
      ICCProfile.getIntFromString("rXYZ");
  /** tag signature */
  static final int kdwGreenColorantTag =
      ICCProfile.getIntFromString("gXYZ");
  /** tag signature */
  static final int kdwBlueColorantTag =
      ICCProfile.getIntFromString("bXYZ");
  /** tag signature */
  static final int kdwRedTRCTag = ICCProfile.getIntFromString("rTRC");
  /** tag signature */
  static final int kdwGreenTRCTag = ICCProfile.getIntFromString("gTRC");
  /** tag signature */
  static final int kdwBlueTRCTag = ICCProfile.getIntFromString("bTRC");
  /** tag signature */
  static final int kdwCopyrightTag = ICCProfile.getIntFromString("cprt");
  /** tag signature */
  static final int kdwMediaWhiteTag =
      ICCProfile.getIntFromString("wtpt");
  /** tag signature */
  static final int kdwProfileDescTag =
      ICCProfile.getIntFromString("desc");

  /**
   * Create a two character hex representation of a byte
   *   @param i byte to represent
   * @return representation
   */
  static String toHexStringByte(int i) {
    String rep = (i >= 0 && i < 16 ? "0" : "") + i.toRadixString(16);
    if (rep.length > 2) rep = rep.substring(rep.length - 2);
    return rep;
  }

  /**
   * Create a 4 character hex representation of a short
   *   @param i short to represent
   * @return representation
   */
  static String toHexStringShort(int i) {
    String rep;

    if (i >= 0 && i < 0x10)
      rep = "000" + i.toRadixString(16);
    else if (i >= 0 && i < 0x100)
      rep = "00" + i.toRadixString(16);
    else if (i >= 0 && i < 0x1000)
      rep = "0" + i.toRadixString(16);
    else
      rep = "" + i.toRadixString(16);

    if (rep.length > 4) rep = rep.substring(rep.length - 4);
    return rep;
  }

  /**
   * Create a 8 character hex representation of a int
   *   @param i int to represent
   * @return representation
   */
  static String toHexStringInt(int i) {
    String rep;

    if (i >= 0 && i < 0x10)
      rep = "0000000" + i.toRadixString(16);
    else if (i >= 0 && i < 0x100)
      rep = "000000" + i.toRadixString(16);
    else if (i >= 0 && i < 0x1000)
      rep = "00000" + i.toRadixString(16);
    else if (i >= 0 && i < 0x10000)
      rep = "0000" + i.toRadixString(16);
    else if (i >= 0 && i < 0x100000)
      rep = "000" + i.toRadixString(16);
    else if (i >= 0 && i < 0x1000000)
      rep = "00" + i.toRadixString(16);
    else if (i >= 0 && i < 0x10000000)
      rep = "0" + i.toRadixString(16);
    else
      rep = "" + i.toRadixString(16);

    if (rep.length > 8) rep = rep.substring(rep.length - 8);
    return rep;
  }

  late ICCProfileHeader header;
  late ICCTagTable tags;
  late Uint8List profile;

  int getProfileSize() {
    return header.dwProfileSize;
  }

  int getCMMTypeSignature() {
    return header.dwCMMTypeSignature;
  }

  int getProfileClass() {
    return header.dwProfileClass;
  }

  int getColorSpaceType() {
    return header.dwColorSpaceType;
  }

  int getPCSType() {
    return header.dwPCSType;
  }

  int getProfileSignature() {
    return header.dwProfileSignature;
  }

  int getPlatformSignature() {
    return header.dwPlatformSignature;
  }

  int getCMMFlags() {
    return header.dwCMMFlags;
  }

  int getDeviceManufacturer() {
    return header.dwDeviceManufacturer;
  }

  int getDeviceModel() {
    return header.dwDeviceModel;
  }

  int getDeviceAttributes1() {
    return header.dwDeviceAttributes1;
  }

  int getDeviceAttributesReserved() {
    return header.dwDeviceAttributesReserved;
  }

  int getRenderingIntent() {
    return header.dwRenderingIntent;
  }

  int getCreatorSig() {
    return header.dwCreatorSig;
  }

  ICCProfileVersion getProfileVersion() {
    return header.profileVersion;
  }

  // Setters omitted as they are private in Java and not used in the provided code snippet

  // private byte [] data = null; // Not used?
  ParameterList? pl;

  /// ParameterList constructor
  ///   @param csb provides colorspace information
  ICCProfile(ColorSpace csm) {
    this.pl = csm.pl;
    List<int>? p = csm.getICCProfile();
    if (p == null) throw ArgumentError("ICC Profile not found in ColorSpace");
    profile = Uint8List.fromList(p);
    initProfile(profile);
  }

  /// Read the header and tags into memory and verify
  /// that the correct type of profile is being used. for encoding.
  ///   @param data ICCProfile
  /// @exception ICCProfileInvalidException for bad signature and class and bad type
  void initProfile(Uint8List data) {
    header = ICCProfileHeader.fromData(data);
    tags = ICCTagTable.createInstance(data);

    // Verify that the data pointed to by ICC is indeed a valid profile
    // and that it is possibly of one of the Restricted ICC types. The simplest way to check
    // this is to verify that the profile signature is correct, that it is an input profile,
    // and that the PCS used is XYX.

    // However, a common error in profiles will be to create Monitor profiles rather
    // than input profiles. If this is the only error found, it's still useful to let this
    // go through with an error written to stderr.

    if (getProfileClass() == kdwDisplayProfile) {
      String message =
          "NOTE!! Technically, this profile is a Display profile, not an" +
              " Input Profile, and thus is not a valid Restricted ICC profile." +
              " However, it is quite possible that this profile is usable as" +
              " a Restricted ICC profile, so this code will ignore this state" +
              " and proceed with processing.";

      FacilityManager.getMsgLogger().printmsg(MsgLogger.warning, message);
    }

    if ((getProfileSignature() != kdwProfileSignature) ||
        ((getProfileClass() != kdwInputProfile) &&
            (getProfileClass() != kdwDisplayProfile)) ||
        (getPCSType() != kdwXYZData)) {
      throw ICCProfileInvalidException();
    }
  }

  /// Provide a suitable string representation for the class
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ICCProfile:");
    StringBuffer body = StringBuffer();
    body.write("$eol$header");
    body.write("$eol$eol$tags");
    rep.write(ColorSpace.indent("  ", body.toString()));
    return (rep..write("]")).toString();
  }

  /// Access the profile header
  /// @return ICCProfileHeader
  ICCProfileHeader getHeader() {
    return header;
  }

  /// Access the profile tag table
  /// @return ICCTagTable
  ICCTagTable getTagTable() {
    return tags;
  }

  /// Parse this ICCProfile into a RestrictedICCProfile
  /// which is appropriate to the data in this profile.
  /// Either a MonochromeInputRestrictedProfile or
  /// MatrixBasedRestrictedProfile is returned
  /// @return RestrictedICCProfile
  /// @exception ICCProfileInvalidException no curve data
  RestrictedICCProfile parse() {
    // The next step is to determine which Restricted ICC type is used by this profile.
    // Unfortunately, the only way to do this is to look through the tag table for
    // the tags required by the two types.

    // First look for the gray TRC tag. If the profile is indeed an input profile, and this
    // tag exists, then the profile is a Monochrome Input profile

    ICCCurveType? grayTag = tags.get(kdwGrayTRCTag) as ICCCurveType?;
    if (grayTag != null) {
      return RestrictedICCProfile.createInstanceGray(grayTag);
    }

    // If it wasn't a Monochrome Input profile, look for the Red Colorant tag. If that
    // tag is found and the profile is indeed an input profile, then this profile is
    // a Three-Component Matrix-Based Input profile

    ICCCurveType? rTRCTag = tags.get(kdwRedTRCTag) as ICCCurveType?;

    if (rTRCTag != null) {
      ICCCurveType? gTRCTag = tags.get(kdwGreenTRCTag) as ICCCurveType?;
      ICCCurveType? bTRCTag = tags.get(kdwBlueTRCTag) as ICCCurveType?;
      ICCXYZType? rColorantTag = tags.get(kdwRedColorantTag) as ICCXYZType?;
      ICCXYZType? gColorantTag = tags.get(kdwGreenColorantTag) as ICCXYZType?;
      ICCXYZType? bColorantTag = tags.get(kdwBlueColorantTag) as ICCXYZType?;
      
      if (gTRCTag != null && bTRCTag != null && rColorantTag != null && gColorantTag != null && bColorantTag != null) {
          return RestrictedICCProfile.createInstance3Comp(
              rTRCTag, gTRCTag, bTRCTag, rColorantTag, gColorantTag, bColorantTag);
      }
    }

    throw ICCProfileInvalidException("curve data not found in profile");
  }
}


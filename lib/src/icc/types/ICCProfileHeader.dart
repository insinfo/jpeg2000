import 'dart:typed_data';
import '../ICCProfile.dart';
import 'ICCProfileVersion.dart';
import 'ICCDateTime.dart';
import 'XyzNumber.dart';

/// An ICC profile contains a 128-byte header followed by a variable
/// number of tags contained in a tag table. This class models the header
/// portion of the profile.
class ICCProfileHeader {
  static const String eol = '\n'; // System.getProperty("line.separator");

  /// ICCProfile header byte array.
  // Uint8List? header;

  // Define the set of standard signature and type values. Only
  // those codes required for Restricted ICC use are defined here.

  /// Profile header signature
  static final int kdwProfileSignature =
      ICCProfile.getIntFromString("acsp");

  /// Profile header signature
  static final int kdwProfileSigReverse =
      ICCProfile.getIntFromString("psca");

  static const String kdwInputProfile = "scnr";
  static const String kdwDisplayProfile = "mntr";
  static const String kdwRGBData = "RGB ";
  static const String kdwGrayData = "GRAY";
  static const String kdwXYZData = "XYZ ";
  static const String kdwGrayTRCTag = "kTRC";
  static const String kdwRedColorantTag = "rXYZ";
  static const String kdwGreenColorantTag = "gXYZ";
  static const String kdwBlueColorantTag = "bXYZ";
  static const String kdwRedTRCTag = "rTRC";
  static const String kdwGreenTRCTag = "gTRC";
  static const String kdwBlueTRCTag = "bTRC";

  /* Offsets into ICCProfile header byte array. */

  static const int offProfileSize = 0;
  static const int offCMMTypeSignature = offProfileSize + ICCProfile.int_size;
  static const int offProfileVersion = offCMMTypeSignature + ICCProfile.int_size;
  static const int offProfileClass = offProfileVersion + ICCProfileVersion.size;
  static const int offColorSpaceType = offProfileClass + ICCProfile.int_size;
  static const int offPCSType = offColorSpaceType + ICCProfile.int_size;
  static const int offDateTime = offPCSType + ICCProfile.int_size;
  static const int offProfileSignature = offDateTime + ICCDateTime.size;
  static const int offPlatformSignature = offProfileSignature + ICCProfile.int_size;
  static const int offCMMFlags = offPlatformSignature + ICCProfile.int_size;
  static const int offDeviceManufacturer = offCMMFlags + ICCProfile.int_size;
  static const int offDeviceModel = offDeviceManufacturer + ICCProfile.int_size;
  static const int offDeviceAttributes1 = offDeviceModel + ICCProfile.int_size;
  static const int offDeviceAttributesReserved =
      offDeviceAttributes1 + ICCProfile.int_size;
  static const int offRenderingIntent =
      offDeviceAttributesReserved + ICCProfile.int_size;
  static const int offPCSIlluminant = offRenderingIntent + ICCProfile.int_size;
  static const int offCreatorSig = offPCSIlluminant + XYZNumber.size;
  static const int offReserved = offCreatorSig + ICCProfile.int_size;

  /// Size of the header
  static const int size = offReserved + 44 * ICCProfile.byte_size;

  /* Header fields mapped to primitive types. */
  /// Size of the entire profile in bytes
  late int dwProfileSize;

  /// The preferred CMM for this profile
  late int dwCMMTypeSignature;

  /// Profile/Device class signature
  late int dwProfileClass;

  /// Colorspace signature
  late int dwColorSpaceType;

  /// PCS type signature
  late int dwPCSType;

  /// Must be 'acsp' (0x61637370)
  late int dwProfileSignature;

  /// Primary platform for which this profile was created
  late int dwPlatformSignature;

  /// Flags to indicate various hints for the CMM
  late int dwCMMFlags;

  /// Signature of device manufacturer
  late int dwDeviceManufacturer;

  /// Signature of device model
  late int dwDeviceModel;

  /// Attributes of the device
  late int dwDeviceAttributes1;

  late int dwDeviceAttributesReserved;

  /// Desired rendering intent for this profile
  late int dwRenderingIntent;

  /// Profile creator signature
  late int dwCreatorSig;

  final Uint8List reserved = Uint8List(44);

  /* Header fields mapped to ggregate types. */
  /// Version of the profile format on which this profile is based
  late ICCProfileVersion profileVersion;

  /// Date and time of profile creation
  late ICCDateTime dateTime;

  /// Illuminant used for this profile
  late XYZNumber PCSIlluminant;

  /// Construct and empty header
  ICCProfileHeader();

  /// Construct a header from a complete ICCProfile
  ICCProfileHeader.fromData(Uint8List data) {
    dwProfileSize = ICCProfile.getInt(data, offProfileSize);
    dwCMMTypeSignature = ICCProfile.getInt(data, offCMMTypeSignature);
    dwProfileClass = ICCProfile.getInt(data, offProfileClass);
    dwColorSpaceType = ICCProfile.getInt(data, offColorSpaceType);
    dwPCSType = ICCProfile.getInt(data, offPCSType);
    dwProfileSignature = ICCProfile.getInt(data, offProfileSignature);
    dwPlatformSignature = ICCProfile.getInt(data, offPlatformSignature);
    dwCMMFlags = ICCProfile.getInt(data, offCMMFlags);
    dwDeviceManufacturer = ICCProfile.getInt(data, offDeviceManufacturer);
    dwDeviceModel = ICCProfile.getInt(data, offDeviceModel);
    dwDeviceAttributes1 = ICCProfile.getInt(data, offDeviceAttributesReserved);
    dwDeviceAttributesReserved =
        ICCProfile.getInt(data, offDeviceAttributesReserved);
    dwRenderingIntent = ICCProfile.getInt(data, offRenderingIntent);
    dwCreatorSig = ICCProfile.getInt(data, offCreatorSig);
    profileVersion = ICCProfile.getICCProfileVersion(data, offProfileVersion);
    dateTime = ICCProfile.getICCDateTime(data, offDateTime);
    PCSIlluminant = ICCProfile.getXYZNumber(data, offPCSIlluminant);

    for (int i = 0; i < reserved.length; ++i) {
      reserved[i] = data[offReserved + i];
    }
  }

  /// String representation of class
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ICCProfileHeader: ");

    rep.write("$eol         ProfileSize: ${ICCProfile.toHexStringInt(dwProfileSize)}");
    rep.write("$eol    CMMTypeSignature: ${ICCProfile.toHexStringInt(dwCMMTypeSignature)}");
    rep.write("$eol        ProfileClass: ${ICCProfile.toHexStringInt(dwProfileClass)}");
    rep.write("$eol      ColorSpaceType: ${ICCProfile.toHexStringInt(dwColorSpaceType)}");
    rep.write("$eol           dwPCSType: ${ICCProfile.toHexStringInt(dwPCSType)}");
    rep.write("$eol  dwProfileSignature: ${ICCProfile.toHexStringInt(dwProfileSignature)}");
    rep.write("$eol dwPlatformSignature: ${ICCProfile.toHexStringInt(dwPlatformSignature)}");
    rep.write("$eol          dwCMMFlags: ${ICCProfile.toHexStringInt(dwCMMFlags)}");
    rep.write("${eol}dwDeviceManufacturer: ${ICCProfile.toHexStringInt(dwDeviceManufacturer)}");
    rep.write("$eol       dwDeviceModel: ${ICCProfile.toHexStringInt(dwDeviceModel)}");
    rep.write("$eol dwDeviceAttributes1: ${ICCProfile.toHexStringInt(dwDeviceAttributes1)}");
    rep.write("$eol   dwRenderingIntent: ${ICCProfile.toHexStringInt(dwRenderingIntent)}");
    rep.write("$eol        dwCreatorSig: ${ICCProfile.toHexStringInt(dwCreatorSig)}");
    rep.write("$eol      profileVersion: $profileVersion");
    rep.write("$eol            dateTime: $dateTime");
    rep.write("$eol       PCSIlluminant: $PCSIlluminant");
    return (rep..write("]")).toString();
  }
}


import 'dart:typed_data';
import '../../j2k/io/RandomAccessIO.dart';
import '../../j2k/fileformat/FileFormatBoxes.dart';
import '../ColorSpaceException.dart';
import '../../icc/IccProfile.dart';

abstract class JP2Box {
  /** Platform dependant line terminator */
  static const String eol = '\n';

  /** Return a String representation of the Box type. */
  static String getTypeStringFromType(int t) => BoxType.get(t);

  /** Length of the box.             */
  late final int length;
  /** input file                     */
  final RandomAccessIO in_io;
  /** offset to start of box         */
  final int boxStart;
  /** offset to end of box           */
  late final int boxEnd;
  /** offset to start of data in box */
  late final int dataStart;

  JP2Box(this.in_io, this.boxStart) {
    final boxHeader = Uint8List(16);
    in_io.seek(boxStart);
    in_io.readFully(boxHeader, 0, 8);
    dataStart = boxStart + 8;
    length = ICCProfile.getInt(boxHeader, 0);
    boxEnd = boxStart + length;
    if (length == 1) {
      throw ColorSpaceException('extended length boxes not supported');
    }
  }

  /// Returns the four-character box type marker.
  int get type;

  /** Return the box type as a String. */
  String getTypeString() => BoxType.get(type);
}

/** JP2 Box structure analysis help */
class BoxType {
  static final Map<int, String> map = {};

  static void _init() {
    put(FileFormatBoxes.bitsPerComponentBox, "BITS_PER_COMPONENT_BOX");
    put(FileFormatBoxes.captureResolutionBox, "CAPTURE_RESOLUTION_BOX");
    put(FileFormatBoxes.channelDefinitionBox, "CHANNEL_DEFINITION_BOX");
    put(FileFormatBoxes.colourSpecificationBox, "COLOUR_SPECIFICATION_BOX");
    put(FileFormatBoxes.componentMappingBox, "COMPONENT_MAPPING_BOX");
    put(FileFormatBoxes.contiguousCodestreamBox, "CONTIGUOUS_CODESTREAM_BOX");
    put(FileFormatBoxes.defaultDisplayResolutionBox,
        "DEFAULT_DISPLAY_RESOLUTION_BOX");
    put(FileFormatBoxes.fileTypeBox, "FILE_TYPE_BOX");
    put(FileFormatBoxes.imageHeaderBox, "IMAGE_HEADER_BOX");
    put(FileFormatBoxes.intellectualPropertyBox, "INTELLECTUAL_PROPERTY_BOX");
    put(FileFormatBoxes.jp2HeaderBox, "JP2_HEADER_BOX");
    put(FileFormatBoxes.jp2SignatureBox, "JP2_SIGNATURE_BOX");
    put(FileFormatBoxes.paletteBox, "PALETTE_BOX");
    put(FileFormatBoxes.resolutionBox, "RESOLUTION_BOX");
    put(FileFormatBoxes.urlBox, "URL_BOX");
    put(FileFormatBoxes.uuidBox, "UUID_BOX");
    put(FileFormatBoxes.uuidInfoBox, "UUID_INFO_BOX");
    put(FileFormatBoxes.uuidListBox, "UUID_LIST_BOX");
    put(FileFormatBoxes.xmlBox, "XML_BOX");
  }

  static void put(int type, String desc) {
    map[type] = desc;
  }

  static String get(int type) {
    if (map.isEmpty) _init();
    return map[type] ?? "Unknown Box Type";
  }
}


/// JPEG 2000 Part I file format box identifiers replicated from JJ2000.
///
/// These constants are used by the JP2 reader/writer to navigate the
/// top-level boxes defined by ISO/IEC 15444-1.
abstract class FileFormatBoxes {
  FileFormatBoxes._();

  /// "jP  " signature box (section I.5.1).
  static const int jp2SignatureBox = 0x6a502020;

  /// File type box (section I.5.2).
  static const int fileTypeBox = 0x66747970;

  /// JP2 header super-box (section I.5.3).
  static const int jp2HeaderBox = 0x6a703268;

  /// Contiguous codestream box (section I.5.7).
  static const int contiguousCodestreamBox = 0x6a703263;

  static const int intellectualPropertyBox = 0x64703269;
  static const int xmlBox = 0x786d6c20;
  static const int uuidBox = 0x75756964;
  static const int uuidInfoBox = 0x75696e66;

  /// JP2 header sub-boxes (section I.5.4).
  static const int imageHeaderBox = 0x69686472;
  static const int bitsPerComponentBox = 0x62706363;
  static const int colourSpecificationBox = 0x636f6c72;
  static const int paletteBox = 0x70636c72;
  static const int componentMappingBox = 0x636d6170;
  static const int channelDefinitionBox = 0x63646566;
  static const int resolutionBox = 0x72657320;
  static const int captureResolutionBox = 0x72657363;
  static const int defaultDisplayResolutionBox = 0x72657364;

  /// UUID info sub-boxes.
  static const int uuidListBox = 0x75637374;
  static const int urlBox = 0x75726c20;

  /// Image header fields defaults.
  static const int imbVers = 0x0100;
  static const int imbC = 7;
  static const int imbUnkC = 1;
  static const int imbIpr = 0;

  /// Colour specification defaults.
  static const int csbMeth = 1;
  static const int csbPrec = 0;
  static const int csbApprox = 0;
  static const int csbEnumSrgb = 16;
  static const int csbEnumGrey = 17;

  /// File type compatibility brand.
  static const int ftBr = 0x6a703220;
}

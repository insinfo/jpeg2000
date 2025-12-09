import 'dart:typed_data';

import '../j2k/util/ParameterList.dart';
import '../j2k/codestream/reader/HeaderDecoder.dart';
import '../j2k/io/RandomAccessIO.dart';
import '../j2k/fileformat/FileFormatBoxes.dart';
import '../icc/IccProfile.dart';
import 'ColorSpaceException.dart';
import 'boxes/PaletteBox.dart';
import 'boxes/ComponentMappingBox.dart';
import 'boxes/ColorSpecificationBox.dart';
import 'boxes/ChannelDefinitionBox.dart';
import 'boxes/ImageHeaderBox.dart';

class ColorSpace {
  static const String eol = '\n';

  // Renamed for convenience:
  static const int GRAY = 0;
  static const int RED = 1;
  static const int GREEN = 2;
  static const int BLUE = 3;

  /** Parameter Specs */
  final ParameterList pl;

  /** Header decoder */
  final HeaderDecoder hd;

  /** Input image */
  final RandomAccessIO input;

  /* Image box structure as pertains to colorspacees. */
  PaletteBox? pbox;
  ComponentMappingBox? cmbox;
  ColorSpecificationBox? csbox;
  ChannelDefinitionBox? cdbox;
  ImageHeaderBox? ihbox;
  final List<ColorSpecificationBox> csboxes = <ColorSpecificationBox>[];

  /**
     * Retrieve the ICC profile from the images as
     * a byte array.
     * @return the ICC Profile as a byte [].
     */
  Uint8List? getICCProfile() => csbox?.getICCProfile();

  /** Indent a String that contains newlines. */
  static String indent(String ident, String instr) {
    final buffer = StringBuffer()..write(ident);
    for (var i = 0; i < instr.length; i++) {
      final ch = instr[i];
      buffer.write(ch);
      if (ch == '\n' && i + 1 < instr.length) {
        buffer.write(ident);
      }
    }
    return buffer.toString();
  }

  ColorSpace(this.input, this.hd, this.pl) {
    _getBoxes();
  }

  /**
     * Retrieve the various boxes from the JP2 file.
     * @exception ColorSpaceException, IOException
     */
  void _getBoxes() {
    int type;
    var len = 0;
    var boxStart = 0;
    final boxHeader = Uint8List(16);
    var i = 0;
    var headerUsesExtendedLength = false;

    // Search the toplevel boxes for the header box
    while (true) {
      input.seek(boxStart);
      input.readFully(boxHeader, 0, 16);
      final rawLen = ICCProfile.getInt(boxHeader, 0);
      headerUsesExtendedLength = rawLen == 1;
      len = headerUsesExtendedLength ? ICCProfile.getLong(boxHeader, 8) : rawLen;
      type = ICCProfile.getInt(boxHeader, 4);

      // Verify the contents of the file so far.
      if (i == 0 && type != FileFormatBoxes.jp2SignatureBox) {
        throw ColorSpaceException("first box in image not signature");
      } else if (i == 1 && type != FileFormatBoxes.fileTypeBox) {
        throw ColorSpaceException("second box in image not file");
      } else if (type == FileFormatBoxes.contiguousCodestreamBox) {
        throw ColorSpaceException("header box not found in image");
      } else if (type == FileFormatBoxes.jp2HeaderBox) {
        break;
      }

      // Progress to the next box.
      ++i;
      boxStart += len;
    }

    // boxStart indexes the start of the JP2_HEADER_BOX,
    // make headerBoxEnd index the end of the box.
    final headerBoxEnd = boxStart + len;

    if (headerUsesExtendedLength) {
      boxStart += 8; // Extended length header
    }

    for (boxStart += 8; boxStart < headerBoxEnd; boxStart += len) {
      input.seek(boxStart);
      input.readFully(boxHeader, 0, 16);
      final rawLen = ICCProfile.getInt(boxHeader, 0);
      if (rawLen == 1) {
        throw ColorSpaceException('Extended length boxes not supported');
      }
      len = rawLen;
      type = ICCProfile.getInt(boxHeader, 4);

      switch (type) {
        case FileFormatBoxes.imageHeaderBox:
          ihbox = ImageHeaderBox(input, boxStart);
          break;
        case FileFormatBoxes.colourSpecificationBox:
          csbox = ColorSpecificationBox(input, boxStart);
          csboxes.add(csbox!);
          break;
        case FileFormatBoxes.channelDefinitionBox:
          cdbox = ChannelDefinitionBox(input, boxStart);
          break;
        case FileFormatBoxes.componentMappingBox:
          cmbox = ComponentMappingBox(input, boxStart);
          break;
        case FileFormatBoxes.paletteBox:
          pbox = PaletteBox(input, boxStart);
          break;
        default:
          break;
      }
    }

    if (ihbox == null) {
      throw ColorSpaceException('image header box not found');
    }

    final hasPalette = pbox != null;
    final hasComponentMap = cmbox != null;
    if (hasPalette != hasComponentMap) {
      throw ColorSpaceException(
          'palette box and component mapping box inconsistency');
    }
  }

  /** Return the channel definition of the input component. */
  int getChannelDefinition(int c) {
    final defs = cdbox;
    if (defs == null) {
      return c;
    }
    final mapped = defs.tryGetCn(c + 1);
    return mapped ?? c;
  }

  /** Return the colorspace method (Profiled, enumerated, or palettized). */
  MethodEnum getMethod() {
    final spec = csbox;
    if (spec == null) {
      throw StateError('Color specification box not found');
    }
    return spec.getMethod();
  }

  /** Return the colorspace (sYCC, sRGB, sGreyScale). */
  CSEnum getColorSpace() {
    final spec = csbox;
    if (spec == null) {
      throw StateError('Color specification box not found');
    }
    return spec.getColorSpace();
  }

  /** Return number of channels in the palette. */
  PaletteBox? getPaletteBox() {
    return pbox;
  }

  List<ColorSpecificationBox> getColorSpecificationBoxes() =>
      List.unmodifiable(csboxes);

  /** Return number of channels in the palette. */
  int getPaletteChannels() {
    return pbox == null ? 0 : pbox!.getNumColumns();
  }

  /** Return bitdepth of the palette entries. */
  int getPaletteChannelBits(int c) {
    return pbox == null ? 0 : pbox!.getBitDepth(c);
  }

  /**
     * Return a palettized sample
     *   @param channel requested 
     *   @param index of entry
     * @return palettized sample
     */
  int getPalettizedSample(int channel, int index) {
    return pbox == null ? 0 : pbox!.getEntry(channel, index);
  }

  /** Is palettized predicate. */
  bool isPalettized() {
    return pbox != null;
  }

  /** Signed output predicate. */
  bool isOutputSigned(int channel) {
    return (pbox != null)
      ? pbox!.isSigned(channel)
      : hd.isOriginalSigned(channel);
  }

  @override
  String toString() {
    final spec = csbox;
    if (spec == null) {
      return '[ColorSpace missing color specification]';
    }
    final rep = StringBuffer("[ColorSpace is ");
    rep.write(spec.getMethodString());
    rep.write(isPalettized() ? "  and palettized " : " ");
    rep.write(getMethod() == ENUMERATED ? spec.getColorSpaceString() : "");
    if (ihbox != null) {
      rep.write(eol);
      rep.write(indent("    ", ihbox.toString()));
    }
    if (cdbox != null) {
      rep.write(eol);
      rep.write(indent("    ", cdbox.toString()));
    }
    if (csbox != null) {
      rep.write(eol);
      rep.write(indent("    ", csbox.toString()));
    }
    if (pbox != null) {
      rep.write(eol);
      rep.write(indent("    ", pbox.toString()));
    }
    if (cmbox != null) {
      rep.write(eol);
      rep.write(indent("    ", cmbox.toString()));
    }
    rep.write("]");
    return rep.toString();
  }

  /**
     * Are profiling diagnostics turned on
     * @return yes or no
     */
  bool debugging() {
    final flag = pl.getParameter('colorspace_debug');
    return flag != null && flag.toLowerCase() == 'on';
  }

  /* Enumeration Class */
  /** method enumeration */
  static final MethodEnum ICC_PROFILED = MethodEnum("profiled");
  /** method enumeration */
  static final MethodEnum ENUMERATED = MethodEnum("enumerated");

  /** colorspace enumeration */
  static final CSEnum sRGB = CSEnum("sRGB");
  /** colorspace enumeration */
  static final CSEnum GreyScale = CSEnum("GreyScale");
  /** colorspace enumeration */
  static final CSEnum sYCC = CSEnum("sYCC");
  /** colorspace enumeration */
  static final CSEnum Illegal = CSEnum("Illegal");
  /** colorspace enumeration */
  static final CSEnum Unknown = CSEnum("Unknown");
}

class Enumeration {
  final String value;
  const Enumeration(this.value);
  @override
  String toString() {
    return value;
  }
}

class MethodEnum extends Enumeration {
  const MethodEnum(String value) : super(value);
}

class CSEnum extends Enumeration {
  const CSEnum(String value) : super(value);
}


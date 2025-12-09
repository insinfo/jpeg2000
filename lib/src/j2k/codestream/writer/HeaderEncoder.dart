import 'dart:io';
import 'dart:typed_data';

import '../../wavelet/analysis/ForwardWT.dart';
import '../../entropy/encoder/PostCompRateAllocator.dart';
import '../../roi/encoder/RoiScaler.dart';
import '../../encoder/EncoderSpecs.dart';
import '../../entropy/StdEntropyCoderOptions.dart';
import '../../image/ImgData.dart';
import '../../util/ParameterList.dart';
import '../../io/BinaryDataOutput.dart';
import '../../Jj2kInfo.dart';
import '../markers.dart';
import '../../util/MathUtil.dart';
import '../../image/tiler.dart';
import '../../wavelet/analysis/AnWtFilter.dart';
import '../../wavelet/analysis/SubbandAn.dart';
import '../../quantization/quantizer/StdQuantizer.dart';

import '../../entropy/progression.dart';
import '../../ModuleSpec.dart';
import '../../image/Coord.dart';

/// This class writes almost of the markers and marker segments in main header
/// and in tile-part headers.
class HeaderEncoder implements Markers, StdEntropyCoderOptions {
  /// The prefix for the header encoder options: 'H'
  static const String OPT_PREFIX = 'H';

  /// The list of parameters that are accepted for the header encoder
  /// module. Options for this modules start with 'H'.
  static const List<List<String?>> pinfo = [
    [
      "Hjj2000_COM",
      null,
      "Writes or not the JJ2000 COM marker in the " + "codestream",
      "on"
    ],
    [
      "HCOM",
      "<Comment 1>[#<Comment 2>[#<Comment3...>]]",
      "Adds COM marker segments in the codestream. Comments must be " +
          "separated with '#' and are written into distinct maker segments.",
      null
    ]
  ];

  /// Nominal range bit of the component defining default values in QCD for
  /// main header
  int defimgn = 0;

  /// Nominal range bit of the component defining default values in QCD for
  /// tile headers
  int deftilenr = 0;

  /// The number of components in the image
  int nComp = 0;

  /// Whether or not to write the JJ2000 COM marker segment
  bool enJJ2KMarkSeg = true;

  /// Other COM marker segments specified in the command line
  String? otherCOMMarkSeg;

  /// The BytesBuilder to store header data.
  BytesBuilder baos = BytesBuilder();

  /// The image data reader. Source of original data info
  ImgData origSrc;

  /// An array specifying, for each component,if the data was signed or not
  List<bool> isOrigSig;

  /// Reference to the rate allocator
  PostCompRateAllocator ralloc;

  /// Reference to the DWT module
  ForwardWT dwt;

  /// Reference to the tiler module
  Tiler tiler;

  /// Reference to the ROI module
  ROIScaler roiSc;

  /// The encoder specifications
  EncoderSpecs encSpec;

  /// Initializes the header writer with the references to the coding chain.
  HeaderEncoder(
      this.origSrc,
      this.isOrigSig,
      this.dwt,
      this.tiler,
      this.encSpec,
      this.roiSc,
      this.ralloc,
      ParameterList pl) {
    pl.checkList(
        [OPT_PREFIX.codeUnitAt(0)], ParameterList.toNameArray(pinfo));
    if (origSrc.getNumComps() != isOrigSig.length) {
      throw ArgumentError();
    }

    nComp = origSrc.getNumComps();
    enJJ2KMarkSeg = pl.getBooleanParameter("Hjj2000_COM");
    otherCOMMarkSeg = pl.getParameter("HCOM");
  }

  /// Resets the contents of this HeaderEncoder to its initial state. It
  /// erases all the data in the header buffer.
  void reset() {
    baos.clear();
  }

  /// Returns the byte-buffer used to store the codestream header.
  Uint8List getBuffer() {
    return baos.toBytes();
  }

  /// Returns the length of the header.
  int getLength() {
    return baos.length;
  }

  /// Writes the header to the specified IOSink.
  void writeTo(IOSink out) {
    out.add(getBuffer());
  }

  /// Writes the header to the specified BinaryDataOutput.
  void writeToBinaryDataOutput(BinaryDataOutput out) {
    Uint8List buf = getBuffer();
    for (int i = 0; i < buf.length; i++) {
      out.writeByte(buf[i]);
    }
  }

  void writeByte(int v) {
    baos.addByte(v);
  }

  void writeShort(int v) {
    baos.addByte((v >> 8) & 0xFF);
    baos.addByte(v & 0xFF);
  }

  void writeInt(int v) {
    baos.addByte((v >> 24) & 0xFF);
    baos.addByte((v >> 16) & 0xFF);
    baos.addByte((v >> 8) & 0xFF);
    baos.addByte(v & 0xFF);
  }

  /// Start Of Codestream marker (SOC) signalling the beginning of a
  /// codestream.
  void writeSOC() {
    writeShort(Markers.SOC);
  }

  /// Writes SIZ marker segment of the codestream header.
  void writeSIZ() {
    int tmp;

    // SIZ marker
    writeShort(Markers.SIZ);

    // Lsiz (Marker length)
    int markSegLen = 38 + 3 * nComp;
    writeShort(markSegLen);

    // Rsiz (codestream capabilities)
    writeShort(0); // JPEG 2000 - Part I

    // Xsiz (original image width)
    writeInt(tiler.getImgWidth() + tiler.getImgULX());

    // Ysiz (original image height)
    writeInt(tiler.getImgHeight() + tiler.getImgULY());

    // XOsiz
    writeInt(tiler.getImgULX());

    // YOsiz
    writeInt(tiler.getImgULY());

    // XTsiz (nominal tile width)
    writeInt(tiler.getNomTileWidth());

    // YTsiz (nominal tile height)
    writeInt(tiler.getNomTileHeight());

    Coord torig = tiler.getTilingOrigin(null);
    // XTOsiz
    writeInt(torig.x);

    // YTOsiz
    writeInt(torig.y);

    // Csiz (number of components)
    writeShort(nComp);

    // Bit-depth and downsampling factors.
    for (int c = 0; c < nComp; c++) {
      // Ssiz bit-depth before mixing
      tmp = origSrc.getNomRangeBits(c) - 1;

      tmp |= ((isOrigSig[c] ? 1 : 0) << Markers.SSIZ_DEPTH_BITS);
      writeByte(tmp);

      // XRsiz (component sub-sampling value x-wise)
      writeByte(tiler.getCompSubsX(c));

      // YRsiz (component sub-sampling value y-wise)
      writeByte(tiler.getCompSubsY(c));
    }
  }

  /// Writes COD marker segment.
  void writeCOD(bool mh, int tileIdx) {
    List<List<AnWTFilter>> filt;
    bool precinctPartitionUsed;
    int tmp;
    int mrl = 0, a = 0;
    int ppx = 0, ppy = 0;
    late List<Progression> prog;

    if (mh) {
      mrl = (encSpec.dls.getDefault() as int);
      // get default precinct size
      ppx = encSpec.pss.getPPX(-1, -1, mrl);
      ppy = encSpec.pss.getPPY(-1, -1, mrl);
      prog = (encSpec.pocs.getDefault() as List<Progression>);
    } else {
      mrl = (encSpec.dls.getTileDef(tileIdx) as int);
      // get precinct size for specified tile
      ppx = encSpec.pss.getPPX(tileIdx, -1, mrl);
      ppy = encSpec.pss.getPPY(tileIdx, -1, mrl);
      prog = (encSpec.pocs.getTileDef(tileIdx) as List<Progression>);
    }

    if (ppx != Markers.PRECINCT_PARTITION_DEF_SIZE ||
        ppy != Markers.PRECINCT_PARTITION_DEF_SIZE) {
      precinctPartitionUsed = true;
    } else {
      precinctPartitionUsed = false;
    }

    if (precinctPartitionUsed) {
      // If precinct partition is used we add one byte per resolution
      // level i.e. mrl+1 (+1 for resolution 0).
      a = mrl + 1;
    }

    // Write COD marker
    writeShort(Markers.COD);

    // Lcod
    int markSegLen = 12 + a;
    writeShort(markSegLen);

    // Scod (coding style parameter)
    tmp = 0;
    if (precinctPartitionUsed) {
      tmp = Markers.SCOX_PRECINCT_PARTITION;
    }

    // Are SOP markers used ?
    if (mh) {
      if ((encSpec.sops.getDefault().toString()).toLowerCase() == "on") {
        tmp |= Markers.SCOX_USE_SOP;
      }
    } else {
      if ((encSpec.sops.getTileDef(tileIdx).toString()).toLowerCase() == "on") {
        tmp |= Markers.SCOX_USE_SOP;
      }
    }

    // Are EPH markers used ?
    if (mh) {
      if ((encSpec.ephs.getDefault().toString()).toLowerCase() == "on") {
        tmp |= Markers.SCOX_USE_EPH;
      }
    } else {
      if ((encSpec.ephs.getTileDef(tileIdx).toString()).toLowerCase() == "on") {
        tmp |= Markers.SCOX_USE_EPH;
      }
    }
    if (dwt.getCbULX() != 0) tmp |= Markers.SCOX_HOR_CB_PART;
    if (dwt.getCbULY() != 0) tmp |= Markers.SCOX_VER_CB_PART;
    writeByte(tmp);

    // SGcod
    // Progression order
    writeByte(prog[0].type);

    // Number of layers
    writeShort(ralloc.getNumLayers());

    // Multiple component transform
    // CSsiz (Color transform)
    String str = "";
    if (mh) {
      str = (encSpec.cts.getDefault() as String);
    } else {
      str = (encSpec.cts.getTileDef(tileIdx) as String);
    }

    if (str == "none") {
      writeByte(0);
    } else {
      writeByte(1);
    }

    // SPcod
    // Number of decomposition levels
    writeByte(mrl);

    // Code-block width and height
    if (mh) {
      // main header, get default values
      tmp = encSpec.cblks.getCBlkWidth(ModuleSpec.SPEC_DEF, -1, -1);
      writeByte(MathUtil.log2(tmp) - 2);
      tmp = encSpec.cblks.getCBlkHeight(ModuleSpec.SPEC_DEF, -1, -1);
      writeByte(MathUtil.log2(tmp) - 2);
    } else {
      // tile header, get tile default values
      tmp = encSpec.cblks.getCBlkWidth(ModuleSpec.SPEC_TILE_DEF, tileIdx, -1);
      writeByte(MathUtil.log2(tmp) - 2);
      tmp = encSpec.cblks.getCBlkHeight(ModuleSpec.SPEC_TILE_DEF, tileIdx, -1);
      writeByte(MathUtil.log2(tmp) - 2);
    }

    // Style of the code-block coding passes
    tmp = 0;
    if (mh) {
      // Main header
      if ((encSpec.bms.getDefault() as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_BYPASS;
      }
      if ((encSpec.mqrs.getDefault() as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_RESET_MQ;
      }
      if ((encSpec.rts.getDefault() as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_TERM_PASS;
      }
      if ((encSpec.css.getDefault() as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL;
      }
      if ((encSpec.tts.getDefault() as String) == "predict") {
        tmp |= StdEntropyCoderOptions.OPT_PRED_TERM;
      }
      if ((encSpec.sss.getDefault() as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_SEG_SYMBOLS;
      }
    } else {
      // Tile header
      if ((encSpec.bms.getTileDef(tileIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_BYPASS;
      }
      if ((encSpec.mqrs.getTileDef(tileIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_RESET_MQ;
      }
      if ((encSpec.rts.getTileDef(tileIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_TERM_PASS;
      }
      if ((encSpec.css.getTileDef(tileIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL;
      }
      if ((encSpec.tts.getTileDef(tileIdx) as String) == "predict") {
        tmp |= StdEntropyCoderOptions.OPT_PRED_TERM;
      }
      if ((encSpec.sss.getTileDef(tileIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_SEG_SYMBOLS;
      }
    }
    writeByte(tmp);

    // Wavelet transform
    // Wavelet Filter
    if (mh) {
      filt = (encSpec.wfs.getDefault() as List<List<AnWTFilter>>);
      writeByte(filt[0][0].getFilterType());
    } else {
      filt = (encSpec.wfs.getTileDef(tileIdx) as List<List<AnWTFilter>>);
      writeByte(filt[0][0].getFilterType());
    }

    // Precinct partition
    if (precinctPartitionUsed) {
      List<List<int>>? v;
      if (mh) {
        v = (encSpec.pss.getDefault() as List<List<int>>);
      } else {
        v = (encSpec.pss.getTileDef(tileIdx) as List<List<int>>);
      }
      for (int r = mrl; r >= 0; r--) {
        if (r >= v[1].length) {
          tmp = v[1][v[1].length - 1];
        } else {
          tmp = v[1][r];
        }
        int yExp = (MathUtil.log2(tmp) << 4) & 0x00F0;

        if (r >= v[0].length) {
          tmp = v[0][v[0].length - 1];
        } else {
          tmp = v[0][r];
        }
        int xExp = MathUtil.log2(tmp) & 0x000F;
        writeByte(yExp | xExp);
      }
    }
  }

  /// Writes COC marker segment.
  void writeCOC(bool mh, int tileIdx, int compIdx) {
    List<List<AnWTFilter>> filt;
    bool precinctPartitionUsed;
    int tmp;
    int mrl = 0, a = 0;
    int ppx = 0, ppy = 0;

    if (mh) {
      mrl = (encSpec.dls.getCompDef(compIdx) as int);
      // Get precinct size for specified component
      ppx = encSpec.pss.getPPX(-1, compIdx, mrl);
      ppy = encSpec.pss.getPPY(-1, compIdx, mrl);
    } else {
      mrl = (encSpec.dls.getTileCompVal(tileIdx, compIdx) as int);
      // Get precinct size for specified component/tile
      ppx = encSpec.pss.getPPX(tileIdx, compIdx, mrl);
      ppy = encSpec.pss.getPPY(tileIdx, compIdx, mrl);
    }

    if (ppx != Markers.PRECINCT_PARTITION_DEF_SIZE ||
        ppy != Markers.PRECINCT_PARTITION_DEF_SIZE) {
      precinctPartitionUsed = true;
    } else {
      precinctPartitionUsed = false;
    }
    if (precinctPartitionUsed) {
      // If precinct partition is used we add one byte per resolution
      // level  i.e. mrl+1 (+1 for resolution 0).
      a = mrl + 1;
    }

    // COC marker
    writeShort(Markers.COC);

    // Lcoc (marker segment length (in bytes))
    // Basic: Lcoc(2 bytes)+Scoc(1)+ Ccoc(1 or 2)+SPcod(5+a)
    int markSegLen = 8 + ((nComp < 257) ? 1 : 2) + a;

    // Rounded to the nearest even value greater or equals
    writeShort(markSegLen);

    // Ccoc
    if (nComp < 257) {
      writeByte(compIdx);
    } else {
      writeShort(compIdx);
    }

    // Scod (coding style parameter)
    tmp = 0;
    if (precinctPartitionUsed) {
      tmp = Markers.SCOX_PRECINCT_PARTITION;
    }
    writeByte(tmp);

    // SPcoc

    // Number of decomposition levels
    writeByte(mrl);

    // Code-block width and height
    if (mh) {
      // main header, get component default values
      tmp = encSpec.cblks.getCBlkWidth(ModuleSpec.SPEC_COMP_DEF, -1, compIdx);
      writeByte(MathUtil.log2(tmp) - 2);
      tmp = encSpec.cblks.getCBlkHeight(ModuleSpec.SPEC_COMP_DEF, -1, compIdx);
      writeByte(MathUtil.log2(tmp) - 2);
    } else {
      // tile header, get tile component values
      tmp = encSpec.cblks
          .getCBlkWidth(ModuleSpec.SPEC_TILE_COMP, tileIdx, compIdx);
      writeByte(MathUtil.log2(tmp) - 2);
      tmp = encSpec.cblks
          .getCBlkHeight(ModuleSpec.SPEC_TILE_COMP, tileIdx, compIdx);
      writeByte(MathUtil.log2(tmp) - 2);
    }

    // Entropy coding mode options
    tmp = 0;
    if (mh) {
      // Main header
      // Lazy coding mode ?
      if ((encSpec.bms.getCompDef(compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_BYPASS;
      }
      // MQ reset after each coding pass ?
      if ((encSpec.mqrs.getCompDef(compIdx) as String).toLowerCase() == "on") {
        tmp |= StdEntropyCoderOptions.OPT_RESET_MQ;
      }
      // MQ termination after each arithmetically coded coding pass ?
      if ((encSpec.rts.getCompDef(compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_TERM_PASS;
      }
      // Vertically stripe-causal context mode ?
      if ((encSpec.css.getCompDef(compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL;
      }
      // Predictable termination ?
      if ((encSpec.tts.getCompDef(compIdx) as String) == "predict") {
        tmp |= StdEntropyCoderOptions.OPT_PRED_TERM;
      }
      // Error resilience segmentation symbol insertion ?
      if ((encSpec.sss.getCompDef(compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_SEG_SYMBOLS;
      }
    } else {
      // Tile Header
      if ((encSpec.bms.getTileCompVal(tileIdx, compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_BYPASS;
      }
      // MQ reset after each coding pass ?
      if ((encSpec.mqrs.getTileCompVal(tileIdx, compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_RESET_MQ;
      }
      // MQ termination after each arithmetically coded coding pass ?
      if ((encSpec.rts.getTileCompVal(tileIdx, compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_TERM_PASS;
      }
      // Vertically stripe-causal context mode ?
      if ((encSpec.css.getTileCompVal(tileIdx, compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL;
      }
      // Predictable termination ?
      if ((encSpec.tts.getTileCompVal(tileIdx, compIdx) as String) ==
          "predict") {
        tmp |= StdEntropyCoderOptions.OPT_PRED_TERM;
      }
      // Error resilience segmentation symbol insertion ?
      if ((encSpec.sss.getTileCompVal(tileIdx, compIdx) as String) == "on") {
        tmp |= StdEntropyCoderOptions.OPT_SEG_SYMBOLS;
      }
    }
    writeByte(tmp);

    // Wavelet transform
    // Wavelet Filter
    if (mh) {
      filt = (encSpec.wfs.getCompDef(compIdx) as List<List<AnWTFilter>>);
      writeByte(filt[0][0].getFilterType());
    } else {
      filt = (encSpec.wfs.getTileCompVal(tileIdx, compIdx)
          as List<List<AnWTFilter>>);
      writeByte(filt[0][0].getFilterType());
    }

    // Precinct partition
    if (precinctPartitionUsed) {
      // Write the precinct size for each resolution level + 1
      // (resolution 0) if precinct partition is used.
      List<List<int>>? v;
      if (mh) {
        v = (encSpec.pss.getCompDef(compIdx) as List<List<int>>);
      } else {
        v = (encSpec.pss.getTileCompVal(tileIdx, compIdx) as List<List<int>>);
      }
      for (int r = mrl; r >= 0; r--) {
        if (r >= v[1].length) {
          tmp = v[1][v[1].length - 1];
        } else {
          tmp = v[1][r];
        }
        int yExp = (MathUtil.log2(tmp) << 4) & 0x00F0;

        if (r >= v[0].length) {
          tmp = v[0][v[0].length - 1];
        } else {
          tmp = v[0][r];
        }
        int xExp = MathUtil.log2(tmp) & 0x000F;
        writeByte(yExp | xExp);
      }
    }
  }

  /// Writes QCD marker segment in main header.
  void writeMainQCD() {
    int mrl;
    int qstyle;

    double step;

    String qType = (encSpec.qts.getDefault() as String);
    double baseStep = (encSpec.qsss.getDefault() as double);
    int gb = (encSpec.gbs.getDefault() as int);

    bool isDerived = qType == "derived";
    bool isReversible = qType == "reversible";

    mrl = (encSpec.dls.getDefault() as int);

    int nt = dwt.getNumTiles();
    int nc = dwt.getNumComps();
    int tmpI;
    List<int> tcIdx = [0, 0];
    String tmpStr;
    bool notFound = true;
    for (int t = 0; t < nt && notFound; t++) {
      for (int c = 0; c < nc && notFound; c++) {
        tmpI = (encSpec.dls.getTileCompVal(t, c) as int);
        tmpStr = (encSpec.qts.getTileCompVal(t, c) as String);
        if (tmpI == mrl && tmpStr == qType) {
          tcIdx[0] = t;
          tcIdx[1] = c;
          notFound = false;
        }
      }
    }
    if (notFound) {
      throw Error(); // "Default representative for quantization type..."
    }
    SubbandAn? sb, csb;
    SubbandAn sbRoot = dwt.getAnSubbandTree(tcIdx[0], tcIdx[1]);
    defimgn = dwt.getNomRangeBits(tcIdx[1]);

    int nqcd = 0; // Number of quantization step-size to transmit

    // Get the quantization style
    qstyle = (isReversible)
        ? StdQuantizer.SQCX_NO_QUANTIZATION
        : ((isDerived)
            ? StdQuantizer.SQCX_SCALAR_DERIVED
            : StdQuantizer.SQCX_SCALAR_EXPOUNDED);

    // QCD marker
    writeShort(Markers.QCD);

    // Compute the number of steps to send
    switch (qstyle) {
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        nqcd = 1; // Just the LL value
        break;
      case StdQuantizer.SQCX_NO_QUANTIZATION:
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        // One value per subband
        nqcd = 0;

        sb = sbRoot;

        // Get the subband at first resolution level
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Count total number of subbands
        for (int j = 0; j <= mrl; j++) {
          csb = sb;
          while (csb != null) {
            nqcd++;
            csb = (csb.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }

    // Lqcd (marker segment length (in bytes))
    // Lqcd(2 bytes)+Sqcd(1)+ SPqcd (2*Nqcd)
    int markSegLen = 3 + ((isReversible) ? nqcd : 2 * nqcd);

    // Rounded to the nearest even value greater or equals
    writeShort(markSegLen);

    // Sqcd
    writeByte(qstyle + (gb << StdQuantizer.SQCX_GB_SHIFT));

    // SPqcd
    switch (qstyle) {
      case StdQuantizer.SQCX_NO_QUANTIZATION:
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Output one exponent per subband
        for (int j = 0; j <= mrl; j++) {
          csb = sb;
          while (csb != null) {
            int tmp = (defimgn + csb.anGainExp);
            writeByte(tmp << StdQuantizer.SQCX_EXP_SHIFT);

            csb = (csb.nextSubband() as SubbandAn?);
            // Go up one resolution level
          }
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Calculate subband step (normalized to unit
        // dynamic range)
        step = baseStep / (1 << sb.level);

        // Write exponent-mantissa, 16 bits
        writeShort(StdQuantizer.convertToExpMantissa(step));
        break;
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Output one step per subband
        for (int j = 0; j <= mrl; j++) {
          csb = sb;
          while (csb != null) {
            // Calculate subband step (normalized to unit
            // dynamic range)
            step = baseStep / (csb.l2Norm * (1 << csb.anGainExp));

            // Write exponent-mantissa, 16 bits
            writeShort(StdQuantizer.convertToExpMantissa(step));

            csb = (csb.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }
  }

  /// Writes QCC marker segment in main header.
  void writeMainQCC(int compIdx) {
    int mrl;
    int qstyle;
    int tIdx = 0;
    double step;

    SubbandAn? sb, sb2;
    SubbandAn sbRoot;

    int imgnr = dwt.getNomRangeBits(compIdx);
    String qType = (encSpec.qts.getCompDef(compIdx) as String);
    double baseStep = (encSpec.qsss.getCompDef(compIdx) as double);
    int gb = (encSpec.gbs.getCompDef(compIdx) as int);

    bool isReversible = qType == "reversible";
    bool isDerived = qType == "derived";

    mrl = (encSpec.dls.getCompDef(compIdx) as int);

    int nt = dwt.getNumTiles();
    int nc = dwt.getNumComps();
    int tmpI;
    String tmpStr;
    bool notFound = true;
    for (int t = 0; t < nt && notFound; t++) {
      for (int c = 0; c < nc && notFound; c++) {
        tmpI = (encSpec.dls.getTileCompVal(t, c) as int);
        tmpStr = (encSpec.qts.getTileCompVal(t, c) as String);
        if (tmpI == mrl && tmpStr == qType) {
          tIdx = t;
          notFound = false;
        }
      }
    }
    if (notFound) {
      throw Error();
    }
    sbRoot = dwt.getAnSubbandTree(tIdx, compIdx);

    int nqcc = 0; // Number of quantization step-size to transmit

    // Get the quantization style
    if (isReversible) {
      qstyle = StdQuantizer.SQCX_NO_QUANTIZATION;
    } else if (isDerived) {
      qstyle = StdQuantizer.SQCX_SCALAR_DERIVED;
    } else {
      qstyle = StdQuantizer.SQCX_SCALAR_EXPOUNDED;
    }

    // QCC marker
    writeShort(Markers.QCC);

    // Compute the number of steps to send
    switch (qstyle) {
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        nqcc = 1; // Just the LL value
        break;
      case StdQuantizer.SQCX_NO_QUANTIZATION:
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        // One value per subband
        nqcc = 0;

        sb = sbRoot;
        mrl = sb.resLvl;

        // Get the subband at first resolution level
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Find root element for LL subband
        while (sb!.resLvl != 0) {
          sb = (sb.subbLL as SubbandAn);
        }

        // Count total number of subbands
        for (int j = 0; j <= mrl; j++) {
          sb2 = sb;
          while (sb2 != null) {
            nqcc++;
            sb2 = (sb2.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }

    // Lqcc (marker segment length (in bytes))
    // Lqcc(2 bytes)+Cqcc(1 or 2)+Sqcc(1)+ SPqcc (2*Nqcc)
    int markSegLen = 3 +
        ((nComp < 257) ? 1 : 2) +
        ((isReversible) ? nqcc : 2 * nqcc);
    writeShort(markSegLen);

    // Cqcc
    if (nComp < 257) {
      writeByte(compIdx);
    } else {
      writeShort(compIdx);
    }

    // Sqcc (quantization style)
    writeByte(qstyle + (gb << StdQuantizer.SQCX_GB_SHIFT));

    // SPqcc
    switch (qstyle) {
      case StdQuantizer.SQCX_NO_QUANTIZATION:
        // Get resolution level 0 subband
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Output one exponent per subband
        for (int j = 0; j <= mrl; j++) {
          sb2 = sb;
          while (sb2 != null) {
            int tmp = (imgnr + sb2.anGainExp);
            writeByte(tmp << StdQuantizer.SQCX_EXP_SHIFT);

            sb2 = (sb2.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        // Get resolution level 0 subband
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Calculate subband step (normalized to unit
        // dynamic range)
        step = baseStep / (1 << sb.level);

        // Write exponent-mantissa, 16 bits
        writeShort(StdQuantizer.convertToExpMantissa(step));
        break;
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        // Get resolution level 0 subband
        sb = sbRoot;
        mrl = sb.resLvl;

        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        for (int j = 0; j <= mrl; j++) {
          sb2 = sb;
          while (sb2 != null) {
            // Calculate subband step (normalized to unit
            // dynamic range)
            step = baseStep / (sb2.l2Norm * (1 << sb2.anGainExp));

            // Write exponent-mantissa, 16 bits
            writeShort(StdQuantizer.convertToExpMantissa(step));
            sb2 = (sb2.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }
  }

  /// Writes QCD marker segment in tile header.
  void writeTileQCD(int tIdx) {
    int mrl;
    int qstyle;

    double step;
    SubbandAn? sb, csb, sbRoot;

    String qType = (encSpec.qts.getTileDef(tIdx) as String);
    double baseStep = (encSpec.qsss.getTileDef(tIdx) as double);
    mrl = (encSpec.dls.getTileDef(tIdx) as int);

    int nc = dwt.getNumComps();
    int tmpI;
    String tmpStr;
    bool notFound = true;
    int compIdx = 0;
    for (int c = 0; c < nc && notFound; c++) {
      tmpI = (encSpec.dls.getTileCompVal(tIdx, c) as int);
      tmpStr = (encSpec.qts.getTileCompVal(tIdx, c) as String);
      if (tmpI == mrl && tmpStr == qType) {
        compIdx = c;
        notFound = false;
      }
    }
    if (notFound) {
      throw Error();
    }

    sbRoot = dwt.getAnSubbandTree(tIdx, compIdx);
    deftilenr = dwt.getNomRangeBits(compIdx);
    int gb = (encSpec.gbs.getTileDef(tIdx) as int);

    bool isDerived = qType == "derived";
    bool isReversible = qType == "reversible";

    int nqcd = 0; // Number of quantization step-size to transmit

    // Get the quantization style
    qstyle = (isReversible)
        ? StdQuantizer.SQCX_NO_QUANTIZATION
        : ((isDerived)
            ? StdQuantizer.SQCX_SCALAR_DERIVED
            : StdQuantizer.SQCX_SCALAR_EXPOUNDED);

    // QCD marker
    writeShort(Markers.QCD);

    // Compute the number of steps to send
    switch (qstyle) {
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        nqcd = 1; // Just the LL value
        break;
      case StdQuantizer.SQCX_NO_QUANTIZATION:
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        // One value per subband
        nqcd = 0;

        sb = sbRoot;

        // Get the subband at first resolution level
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Count total number of subbands
        for (int j = 0; j <= mrl; j++) {
          csb = sb;
          while (csb != null) {
            nqcd++;
            csb = (csb.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }

    // Lqcd (marker segment length (in bytes))
    // Lqcd(2 bytes)+Sqcd(1)+ SPqcd (2*Nqcd)
    int markSegLen = 3 + ((isReversible) ? nqcd : 2 * nqcd);

    // Rounded to the nearest even value greater or equals
    writeShort(markSegLen);

    // Sqcd
    writeByte(qstyle + (gb << StdQuantizer.SQCX_GB_SHIFT));

    // SPqcd
    switch (qstyle) {
      case StdQuantizer.SQCX_NO_QUANTIZATION:
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Output one exponent per subband
        for (int j = 0; j <= mrl; j++) {
          csb = sb;
          while (csb != null) {
            int tmp = (deftilenr + csb.anGainExp);
            writeByte(tmp << StdQuantizer.SQCX_EXP_SHIFT);

            csb = (csb.nextSubband() as SubbandAn?);
            // Go up one resolution level
          }
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Calculate subband step (normalized to unit
        // dynamic range)
        step = baseStep / (1 << sb.level);

        // Write exponent-mantissa, 16 bits
        writeShort(StdQuantizer.convertToExpMantissa(step));
        break;
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Output one step per subband
        for (int j = 0; j <= mrl; j++) {
          csb = sb;
          while (csb != null) {
            // Calculate subband step (normalized to unit
            // dynamic range)
            step = baseStep / (csb.l2Norm * (1 << csb.anGainExp));

            // Write exponent-mantissa, 16 bits
            writeShort(StdQuantizer.convertToExpMantissa(step));

            csb = (csb.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }
  }

  /// Writes QCC marker segment in tile header.
  void writeTileQCC(int t, int compIdx) {
    int mrl;
    int qstyle;
    double step;

    SubbandAn? sb, sb2;
    int nqcc = 0; // Number of quantization step-size to transmit

    SubbandAn sbRoot = dwt.getAnSubbandTree(t, compIdx);
    int imgnr = dwt.getNomRangeBits(compIdx);
    String qType = (encSpec.qts.getTileCompVal(t, compIdx) as String);
    double baseStep = (encSpec.qsss.getTileCompVal(t, compIdx) as double);
    int gb = (encSpec.gbs.getTileCompVal(t, compIdx) as int);

    bool isReversible = qType == "reversible";
    bool isDerived = qType == "derived";

    mrl = (encSpec.dls.getTileCompVal(t, compIdx) as int);

    // Get the quantization style
    if (isReversible) {
      qstyle = StdQuantizer.SQCX_NO_QUANTIZATION;
    } else if (isDerived) {
      qstyle = StdQuantizer.SQCX_SCALAR_DERIVED;
    } else {
      qstyle = StdQuantizer.SQCX_SCALAR_EXPOUNDED;
    }

    // QCC marker
    writeShort(Markers.QCC);

    // Compute the number of steps to send
    switch (qstyle) {
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        nqcc = 1; // Just the LL value
        break;
      case StdQuantizer.SQCX_NO_QUANTIZATION:
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        // One value per subband
        nqcc = 0;

        sb = sbRoot;
        mrl = sb.resLvl;

        // Get the subband at first resolution level
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Find root element for LL subband
        while (sb!.resLvl != 0) {
          sb = (sb.subbLL as SubbandAn);
        }

        // Count total number of subbands
        for (int j = 0; j <= mrl; j++) {
          sb2 = sb;
          while (sb2 != null) {
            nqcc++;
            sb2 = (sb2.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }

    // Lqcc (marker segment length (in bytes))
    // Lqcc(2 bytes)+Cqcc(1 or 2)+Sqcc(1)+ SPqcc (2*Nqcc)
    int markSegLen = 3 +
        ((nComp < 257) ? 1 : 2) +
        ((isReversible) ? nqcc : 2 * nqcc);
    writeShort(markSegLen);

    // Cqcc
    if (nComp < 257) {
      writeByte(compIdx);
    } else {
      writeShort(compIdx);
    }

    // Sqcc (quantization style)
    writeByte(qstyle + (gb << StdQuantizer.SQCX_GB_SHIFT));

    // SPqcc
    switch (qstyle) {
      case StdQuantizer.SQCX_NO_QUANTIZATION:
        // Get resolution level 0 subband
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Output one exponent per subband
        for (int j = 0; j <= mrl; j++) {
          sb2 = sb;
          while (sb2 != null) {
            int tmp = (imgnr + sb2.anGainExp);
            writeByte(tmp << StdQuantizer.SQCX_EXP_SHIFT);

            sb2 = (sb2.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      case StdQuantizer.SQCX_SCALAR_DERIVED:
        // Get resolution level 0 subband
        sb = sbRoot;
        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        // Calculate subband step (normalized to unit
        // dynamic range)
        step = baseStep / (1 << sb.level);

        // Write exponent-mantissa, 16 bits
        writeShort(StdQuantizer.convertToExpMantissa(step));
        break;
      case StdQuantizer.SQCX_SCALAR_EXPOUNDED:
        // Get resolution level 0 subband
        sb = sbRoot;
        mrl = sb.resLvl;

        sb = (sb.getSubbandByIdx(0, 0) as SubbandAn);

        for (int j = 0; j <= mrl; j++) {
          sb2 = sb;
          while (sb2 != null) {
            // Calculate subband step (normalized to unit
            // dynamic range)
            step = baseStep / (sb2.l2Norm * (1 << sb2.anGainExp));

            // Write exponent-mantissa, 16 bits
            writeShort(StdQuantizer.convertToExpMantissa(step));
            sb2 = (sb2.nextSubband() as SubbandAn?);
          }
          // Go up one resolution level
          sb = (sb!.getNextResLevel() as SubbandAn?);
        }
        break;
      default:
        throw Error();
    }
  }

  /// Writes POC marker segment.
  void writePOC(bool mh, int tileIdx) {
    int markSegLen = 0; // Segment marker length
    int lenCompField; // Holds the size of any component field as
    // this size depends on the number of
    //components
    List<Progression> prog; // Holds the progression(s)
    int npoc; // Number of progression order changes

    // Get the progression order changes, their number and checks
    // if it is ok
    if (mh) {
      prog = (encSpec.pocs.getDefault() as List<Progression>);
    } else {
      prog = (encSpec.pocs.getTileDef(tileIdx) as List<Progression>);
    }

    // Calculate the length of a component field (depends on the number of
    // components)
    lenCompField = (nComp < 257 ? 1 : 2);

    // POC marker
    writeShort(Markers.POC);

    // Lpoc (marker segment length (in bytes))
    // Basic: Lpoc(2 bytes) + npoc * [ RSpoc(1) + CSpoc(1 or 2) +
    // LYEpoc(2) + REpoc(1) + CEpoc(1 or 2) + Ppoc(1) ]
    npoc = prog.length;
    markSegLen = 2 + npoc * (1 + lenCompField + 2 + 1 + lenCompField + 1);
    writeShort(markSegLen);

    // Write each progression order change
    for (int i = 0; i < npoc; i++) {
      // RSpoc(i)
      writeByte(prog[i].rs);
      // CSpoc(i)
      if (lenCompField == 2) {
        writeShort(prog[i].cs);
      } else {
        writeByte(prog[i].cs);
      }
      // LYEpoc(i)
      writeShort(prog[i].lye);
      // REpoc(i)
      writeByte(prog[i].re);
      // CEpoc(i)
      if (lenCompField == 2) {
        writeShort(prog[i].ce);
      } else {
        writeByte(prog[i].ce);
      }
      // Ppoc(i)
      writeByte(prog[i].type);
    }
  }

  void encodeMainHeader() {
    int i;

    // +---------------------------------+
    // |    SOC marker segment           |
    // +---------------------------------+
    writeSOC();

    // +---------------------------------+
    // |    Image and tile SIZe (SIZ)    |
    // +---------------------------------+
    writeSIZ();

    // +-------------------------------+
    // |   COding style Default (COD)  |
    // +-------------------------------+
    bool isEresUsed = (encSpec.tts.getDefault() as String) == "predict";
    writeCOD(true, 0);

    // +---------------------------------+
    // |   COding style Component (COC)  |
    // +---------------------------------+
    for (i = 0; i < nComp; i++) {
      bool isEresUsedinComp =
          (encSpec.tts.getCompDef(i) as String) == "predict";
      if (encSpec.wfs.isCompSpecified(i) ||
          encSpec.dls.isCompSpecified(i) ||
          encSpec.bms.isCompSpecified(i) ||
          encSpec.mqrs.isCompSpecified(i) ||
          encSpec.rts.isCompSpecified(i) ||
          encSpec.sss.isCompSpecified(i) ||
          encSpec.css.isCompSpecified(i) ||
          encSpec.pss.isCompSpecified(i) ||
          encSpec.cblks.isCompSpecified(i) ||
          (isEresUsed != isEresUsedinComp))
        // Some component non-default stuff => need COC
        writeCOC(true, 0, i);
    }

    // +-------------------------------+
    // |   Quantization Default (QCD)  |
    // +-------------------------------+
    writeMainQCD();

    // +-------------------------------+
    // | Quantization Component (QCC)  |
    // +-------------------------------+
    // Write needed QCC markers
    for (i = 0; i < nComp; i++) {
      if (dwt.getNomRangeBits(i) != defimgn ||
          encSpec.qts.isCompSpecified(i) ||
          encSpec.qsss.isCompSpecified(i) ||
          encSpec.dls.isCompSpecified(i) ||
          encSpec.gbs.isCompSpecified(i)) {
        writeMainQCC(i);
      }
    }

    // +--------------------------+
    // |    POC maker segment     |
    // +--------------------------+
    List<Progression> prog = (encSpec.pocs.getDefault() as List<Progression>);
    if (prog.length > 1) writePOC(true, 0);

    // +---------------------------+
    // |      Comments (COM)       |
    // +---------------------------+
    writeCOM();
  }

  void writeCOM() {
    if (enJJ2KMarkSeg) {
      String str = "Created by: JJ2000 version " + JJ2KInfo.version;
      int markSegLen;

      writeShort(Markers.COM);
      markSegLen = 2 + 2 + str.length;
      writeShort(markSegLen);
      writeShort(1); // General use

      for (int i = 0; i < str.length; i++) {
        writeByte(str.codeUnitAt(i));
      }
    }
  }

  /// Writes the RGN marker segment in the tile header.
  void writeRGN(int tIdx) {
    int i;
    int markSegLen; // the marker length

    // Write one RGN marker per component
    for (i = 0; i < nComp; i++) {
      // RGN marker
      writeShort(Markers.RGN);

      // Calculate length (Lrgn)
      // Basic: Lrgn (2) + Srgn (1) + SPrgn + one byte
      // or two for component number
      markSegLen = 4 + ((nComp < 257) ? 1 : 2);
      writeShort(markSegLen);

      // Write component (Crgn)
      if (nComp < 257) {
        writeByte(i);
      } else {
        writeShort(i);
      }

      // Write type of ROI (Srgn)
      writeByte(Markers.SRGN_IMPLICIT);

      // Write ROI info (SPrgn)
      writeByte((encSpec.rois.getTileCompVal(tIdx, i) as int));
    }
  }

  void encodeTilePartHeader(int tileLength, int tileIdx) {
    int tmp;
    Coord numTiles = ralloc.getNumTilesCoord(null);
    ralloc.setTile(tileIdx % numTiles.x, tileIdx ~/ numTiles.x);

    // +--------------------------+
    // |    SOT maker segment     |
    // +--------------------------+
    // SOT marker
    writeByte(Markers.SOT >> 8);
    writeByte(Markers.SOT);

    // Lsot (10 bytes)
    writeByte(0);
    writeByte(10);

    // Isot
    if (tileIdx > 65534) {
      throw ArgumentError("Trying to write a tile-part " +
          "header whose tile index is " +
          "too high");
    }
    writeByte(tileIdx >> 8);
    writeByte(tileIdx);

    // Psot
    tmp = tileLength;
    writeByte(tmp >> 24);
    writeByte(tmp >> 16);
    writeByte(tmp >> 8);
    writeByte(tmp);

    // TPsot
    writeByte(0); // Only one tile-part currently supported !

    // TNsot
    writeByte(1); // Only one tile-part currently supported !

    // +--------------------------+
    // |    COD maker segment     |
    // +--------------------------+
    bool isEresUsed = (encSpec.tts.getDefault() as String) == "predict";
    bool isEresUsedInTile =
        (encSpec.tts.getTileDef(tileIdx) as String) == "predict";
    bool tileCODwritten = false;
    if (encSpec.wfs.isTileSpecified(tileIdx) ||
        encSpec.cts.isTileSpecified(tileIdx) ||
        encSpec.dls.isTileSpecified(tileIdx) ||
        encSpec.bms.isTileSpecified(tileIdx) ||
        encSpec.mqrs.isTileSpecified(tileIdx) ||
        encSpec.rts.isTileSpecified(tileIdx) ||
        encSpec.css.isTileSpecified(tileIdx) ||
        encSpec.pss.isTileSpecified(tileIdx) ||
        encSpec.sops.isTileSpecified(tileIdx) ||
        encSpec.sss.isTileSpecified(tileIdx) ||
        encSpec.pocs.isTileSpecified(tileIdx) ||
        encSpec.ephs.isTileSpecified(tileIdx) ||
        encSpec.cblks.isTileSpecified(tileIdx) ||
        (isEresUsed != isEresUsedInTile)) {
      writeCOD(false, tileIdx);
      tileCODwritten = true;
    }

    // +--------------------------+
    // |    COC maker segment     |
    // +--------------------------+
    for (int c = 0; c < nComp; c++) {
      bool isEresUsedInTileComp =
          (encSpec.tts.getTileCompVal(tileIdx, c) as String) == "predict";

      if (encSpec.wfs.isTileCompSpecified(tileIdx, c) ||
          encSpec.dls.isTileCompSpecified(tileIdx, c) ||
          encSpec.bms.isTileCompSpecified(tileIdx, c) ||
          encSpec.mqrs.isTileCompSpecified(tileIdx, c) ||
          encSpec.rts.isTileCompSpecified(tileIdx, c) ||
          encSpec.css.isTileCompSpecified(tileIdx, c) ||
          encSpec.pss.isTileCompSpecified(tileIdx, c) ||
          encSpec.sss.isTileCompSpecified(tileIdx, c) ||
          encSpec.cblks.isTileCompSpecified(tileIdx, c) ||
          (isEresUsedInTileComp != isEresUsed)) {
        writeCOC(false, tileIdx, c);
      } else if (tileCODwritten) {
        if (encSpec.wfs.isCompSpecified(c) ||
            encSpec.dls.isCompSpecified(c) ||
            encSpec.bms.isCompSpecified(c) ||
            encSpec.mqrs.isCompSpecified(c) ||
            encSpec.rts.isCompSpecified(c) ||
            encSpec.sss.isCompSpecified(c) ||
            encSpec.css.isCompSpecified(c) ||
            encSpec.pss.isCompSpecified(c) ||
            encSpec.cblks.isCompSpecified(c) ||
            (encSpec.tts.isCompSpecified(c) &&
                (encSpec.tts.getCompDef(c) as String) == "predict")) {
          writeCOC(false, tileIdx, c);
        }
      }
    }

    // +--------------------------+
    // |    QCD maker segment     |
    // +--------------------------+
    bool tileQCDwritten = false;
    if (encSpec.qts.isTileSpecified(tileIdx) ||
        encSpec.qsss.isTileSpecified(tileIdx) ||
        encSpec.dls.isTileSpecified(tileIdx) ||
        encSpec.gbs.isTileSpecified(tileIdx)) {
      writeTileQCD(tileIdx);
      tileQCDwritten = true;
    } else {
      deftilenr = defimgn;
    }

    // +--------------------------+
    // |    QCC maker segment     |
    // +--------------------------+
    for (int c = 0; c < nComp; c++) {
      if (dwt.getNomRangeBits(c) != deftilenr ||
          encSpec.qts.isTileCompSpecified(tileIdx, c) ||
          encSpec.qsss.isTileCompSpecified(tileIdx, c) ||
          encSpec.dls.isTileCompSpecified(tileIdx, c) ||
          encSpec.gbs.isTileCompSpecified(tileIdx, c)) {
        writeTileQCC(tileIdx, c);
      } else if (tileQCDwritten) {
        if (encSpec.qts.isCompSpecified(c) ||
            encSpec.qsss.isCompSpecified(c) ||
            encSpec.dls.isCompSpecified(c) ||
            encSpec.gbs.isCompSpecified(c)) {
          writeTileQCC(tileIdx, c);
        }
      }
    }

    // +--------------------------+
    // |    RGN maker segment     |
    // +--------------------------+
    if (roiSc.useRoi() && (!roiSc.getBlockAligned())) writeRGN(tileIdx);

    // +--------------------------+
    // |    POC maker segment     |
    // +--------------------------+
    List<Progression> prog;
    if (encSpec.pocs.isTileSpecified(tileIdx)) {
      prog = (encSpec.pocs.getTileDef(tileIdx) as List<Progression>);
      if (prog.length > 1) writePOC(false, tileIdx);
    }

    // +--------------------------+
    // |         SOD maker        |
    // +--------------------------+
    writeByte(Markers.SOD >> 8);
    writeByte(Markers.SOD);
  }
}



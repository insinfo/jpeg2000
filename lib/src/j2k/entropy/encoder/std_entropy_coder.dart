import 'dart:math' as math;
import 'dart:typed_data';

import '../../image/coord.dart';
import '../../util/array_util.dart';
import '../../util/facility_manager.dart';
import '../../util/msg_logger.dart';
import '../../string_spec.dart';
import '../../quantization/quantizer/c_blk_quant_data_src_enc.dart';
import '../../module_spec.dart';
import '../c_blk_size_spec.dart';
import '../precinct_size_spec.dart';
import '../../wavelet/analysis/c_blk_wt_data.dart';
import '../../wavelet/subband.dart';
import 'c_blk_rate_dist_stats.dart';
import 'entropy_coder.dart';
import 'mq_coder.dart';
import 'bit_to_byte_output.dart';
import 'byte_output_buffer.dart';
import '../std_entropy_coder_options.dart';

/// This class implements the JPEG 2000 entropy coder, which codes stripes in
/// code-blocks. This entropy coding engine is based on the MQ-coder, as
/// specified in the JPEG 2000 standard.
class StdEntropyCoder extends EntropyCoder {
  /// The identifier for the termination of each coding pass option
  static const int optTermPass = StdEntropyCoderOptions.optTermPass;

  /// The identifier for the reset MQ coder option
  static const int optResetMq = StdEntropyCoderOptions.optResetMq;

  /// The identifier for the vertically stripe causal context option
  static const int optVertStrCausal = StdEntropyCoderOptions.optVertStrCausal;

  /// The identifier for the lazy coding mode option (bypass MQ coder)
  static const int optBypass = StdEntropyCoderOptions.optBypass;

  /// The identifier for the segmentation symbols option
  static const int optSegSymbols = StdEntropyCoderOptions.optSegSymbols;

  /// The identifier for the predictable termination option
  static const int optPredTerm = StdEntropyCoderOptions.optPredTerm;

  static const int numNonBypassMsBp = StdEntropyCoderOptions.numNonBypassMsBp;

  /// The mask for the significant state bit.
  static const int stateSigR1 = 1 << 15;

  /// The mask for the visited state bit.
  static const int stateVisitedR1 = 1 << 14;

  /// The mask for the "non-zero context" state bit.
  static const int stateNzCtxtR1 = 1 << 13;

  /// The mask for the "horizontal high-pass sign" state bit.
  static const int stateHLSignR1 = 1 << 12;

  /// The mask for the "horizontal low-pass sign" state bit.
  static const int stateHRSignR1 = 1 << 11;

  /// The mask for the "vertical high-pass sign" state bit.
  static const int stateVUSignR1 = 1 << 10;

  /// The mask for the "vertical low-pass sign" state bit.
  static const int stateVDSignR1 = 1 << 9;

  /// The mask for the "previous MR" state bit.
  static const int statePrevMrR1 = 1 << 8;

  /// The mask for the "horizontal high-pass" state bit.
  static const int stateHLR1 = 1 << 7;

  /// The mask for the "horizontal low-pass" state bit.
  static const int stateHRR1 = 1 << 6;

  /// The mask for the "vertical high-pass" state bit.
  static const int stateVUR1 = 1 << 5;

  /// The mask for the "vertical low-pass" state bit.
  static const int stateVDR1 = 1 << 4;

  /// The mask for the "diagonal high-pass" state bit.
  static const int stateDUlR1 = 1 << 3;

  /// The mask for the "diagonal low-pass" state bit.
  static const int stateDUrR1 = 1 << 2;

  /// The mask for the "diagonal low-pass" state bit.
  static const int stateDDlR1 = 1 << 1;

  /// The mask for the "diagonal low-pass" state bit.
  static const int stateDDrR1 = 1;

  /// The separation between the row 1 and row 2 states.
  static const int stateSep = 16;

  /// The mask for the significant state bit.
  static const int stateSigR2 = stateSigR1 << stateSep;

  /// The mask for the visited state bit.
  static const int stateVisitedR2 = stateVisitedR1 << stateSep;

  /// The mask for the "non-zero context" state bit.
  static const int stateNzCtxtR2 = stateNzCtxtR1 << stateSep;

  /// The mask for the "horizontal high-pass sign" state bit.
  static const int stateHLSignR2 = stateHLSignR1 << stateSep;

  /// The mask for the "horizontal low-pass sign" state bit.
  static const int stateHRSignR2 = stateHRSignR1 << stateSep;

  /// The mask for the "vertical high-pass sign" state bit.
  static const int stateVUSignR2 = stateVUSignR1 << stateSep;

  /// The mask for the "vertical low-pass sign" state bit.
  static const int stateVDSignR2 = stateVDSignR1 << stateSep;

  /// The mask for the "previous MR" state bit.
  static const int statePrevMrR2 = statePrevMrR1 << stateSep;

  /// The mask for the "horizontal high-pass" state bit.
  static const int stateHLR2 = stateHLR1 << stateSep;

  /// The mask for the "horizontal low-pass" state bit.
  static const int stateHRR2 = stateHRR1 << stateSep;

  /// The mask for the "vertical high-pass" state bit.
  static const int stateVUR2 = stateVUR1 << stateSep;

  /// The mask for the "vertical low-pass" state bit.
  static const int stateVDR2 = stateVDR1 << stateSep;

  /// The mask for the "diagonal high-pass" state bit.
  static const int stateDUlR2 = stateDUlR1 << stateSep;

  /// The mask for the "diagonal low-pass" state bit.
  static const int stateDUrR2 = stateDUrR1 << stateSep;

  /// The mask for the "diagonal low-pass" state bit.
  static const int stateDDlR2 = stateDDlR1 << stateSep;

  /// The mask for the "diagonal low-pass" state bit.
  static const int stateDDrR2 = stateDDrR1 << stateSep;

  /// The mask to isolate the significance bits for row 1 and 2 of the state
  /// array.
  static const int sigMaskR1r2 = stateSigR1 | stateSigR2;

  /// The mask to isolate the visited bits for row 1 and 2 of the state
  /// array.
  static const int vstdMaskR1r2 = stateVisitedR1 | stateVisitedR2;

  /// The mask to isolate the bits necessary to identify RLC coding state
  /// (significant, visited and non-zero context, for row 1 and 2).
  static const int rlcMaskR1r2 = stateSigR1 |
      stateSigR2 |
      stateVisitedR1 |
      stateVisitedR2 |
      stateNzCtxtR1 |
      stateNzCtxtR2;

  /// The mask to obtain the ZC_LUT index from the state information
  static const int zcMask = (1 << 8) - 1;

  /// The shift to obtain the SC index to 'SC_LUT' from the state
  /// information, for row 1.
  static const int scShiftR1 = 4;

  /// The shift to obtain the SC index to 'SC_LUT' from the state
  /// information, for row 2.
  static const int scShiftR2 = scShiftR1 + stateSep;

  /// The number of bits used for the Sign Coding lookup table
  static const int scLutBits = 9;

  /// The bit mask to isolate the state bits relative to the sign coding
  /// lookup table ('SC_LUT').
  static const int scMask = (1 << scLutBits) - 1;

  /// The number of bits used for the Magnitude Refinement lookup table
  static const int mrLutBits = 9;

  /// The mask to obtain the MR index to 'MR_LUT' from the 'state'
  /// information. It is to be applied after the 'MR_SHIFT'.
  static const int mrMask = (1 << mrLutBits) - 1;

  /// The number of bits used to index in the 'fm' lookup table, 7. The 'fs'
  /// table is indexed with one less bit.
  static const int mseLkpBits = 7;

  /// The number of fractional bits used to store data in the 'fm' and 'fs'
  /// lookup tables.
  static const int mseLkpFracBits = 13;

  /// The stripe height.
  static const int stripeHeight = StdEntropyCoderOptions.stripeHeight;

  /// The context for the RLC coding.
  static const int rlcCtxt = 1;

  /// The context for the uniform coding.
  static const int unifCtxt = 0;

  /// The number of contexts used
  static const int numCtxts = 19;

  /// The sign bit for int data
  static const int intSignBit = 1 << 31;

  /// The initial states for the MQ coder
  static final List<int> mqInit = [
    46,
    3,
    4,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0
  ];

  /// The 4 bits of the error resilience segmentation symbol (1010)
  static final List<int> segSymbols = [1, 0, 1, 0];

  /// The 4 contexts for the error resilience segmentation symbol (always
  /// the UNIFORM context, UNIF_CTXT)
  static final List<int> segSymbCtxts = [
    unifCtxt,
    unifCtxt,
    unifCtxt,
    unifCtxt
  ];

  /// Number of bits used for the Zero Coding lookup table
  static const int zcLutBits = 8;

  /// Zero Coding context lookup tables for the LH global orientation
  static final List<int> zcLutLh = List<int>.filled(1 << zcLutBits, 0);

  /// Zero Coding context lookup tables for the HL global orientation
  static final List<int> zcLutHl = List<int>.filled(1 << zcLutBits, 0);

  /// Zero Coding context lookup tables for the HH global orientation
  static final List<int> zcLutHh = List<int>.filled(1 << zcLutBits, 0);

  /// Sign Coding context lookup table.
  static final List<int> scLut = List<int>.filled(1 << scLutBits, 0);

  /// The mask to obtain the context index from the 'SC_LUT'
  static const int scLutMask = (1 << 4) - 1;

  /// The shift to obtain the sign predictor from the 'SC_LUT'. It must be
  /// an unsigned shift.
  static const int scSpredShift = 31;

  /// Magnitude Refinement context lookup table
  static final List<int> mrLut = List<int>.filled(1 << mrLutBits, 0);

  /// Distortion estimation lookup table for bits coded using the sign-code
  /// (SC) primative, for lossy coding (i.e. normal).
  static final List<int> fsLossy = List<int>.filled(1 << (mseLkpBits - 1), 0);

  /// Distortion estimation lookup table for bits coded using the
  /// magnitude-refinement (MR) primative, for lossy coding (i.e. normal)
  static final List<int> fmLossy = List<int>.filled(1 << mseLkpBits, 0);

  /// Distortion estimation lookup table for bits coded using the sign-code
  /// (SC) primative, for lossless coding and last bit-plane.
  static final List<int> fsLossless =
      List<int>.filled(1 << (mseLkpBits - 1), 0);

  /// Distortion estimation lookup table for bits coded using the
  /// magnitude-refinement (MR) primative, for lossless coding and last
  /// bit-plane.
  static final List<int> fmLossless = List<int>.filled(1 << mseLkpBits, 0);

  /// The code-block size specifications
  late CBlkSizeSpec cblks;

  /// The precinct partition specifications
  late PrecinctSizeSpec pss;

  /// By-pass mode specifications
  late StringSpec bms;

  /// MQ reset specifications
  late StringSpec mqrs;

  /// Regular termination specifications
  late StringSpec rts;

  /// Causal stripes specifications
  late StringSpec css;

  /// Error resilience segment symbol use specifications
  late StringSpec sss;

  /// The length calculation specifications
  late StringSpec lcs;

  /// The termination type specifications
  late StringSpec tts;

  /// The options that are turned on, as flag bits. One element for each
  /// tile-component.
  late List<List<int>> opts;

  /// The length calculation type for each tile-component
  late List<List<int>> lenCalc;

  /// The termination type for each tile-component
  late List<List<int>> tType;

  /// The MQ coder used, for each thread (single thread here)
  late List<MQCoder> mqT;

  /// The raw bit output used, for each thread
  late List<BitToByteOutput?> boutT;

  /// The output stream used, for each thread
  late List<ByteOutputBuffer> outT;

  /// The state array for each thread.
  late List<List<int>> stateT;

  /// The buffer for distortion values
  late List<List<double>> distbufT;

  /// The buffer for rate values
  late List<List<int>> ratebufT;

  /// The buffer for indicating terminated passes
  late List<List<bool>> istermbufT;

  /// The source code-block to entropy code
  late List<CBlkWTData?> srcblkT;

  /// Buffer for symbols to send to the MQ-coder
  late List<List<int>> symbufT;

  /// Buffer for the contexts to use when sending buffered symbols to the
  /// MQ-coder
  late List<List<int>> ctxtbufT;

  /// boolean used to signal if the precinct partition is used for
  /// each component and each tile.
  late List<List<bool>> precinctPartition;

  static bool _staticInitialized = false;

  static void _staticInit() {
    if (_staticInitialized) return;
    _staticInitialized = true;

    int i, j;
    double val, deltaMSE;
    List<int>? interScLut;
    int ds, us, rs, ls;
    int dsgn, usgn, rsgn, lsgn;
    int h, v;

    // Initialize the zero coding lookup tables

    // LH

    // - No neighbors significant
    zcLutLh[0] = 2;

    // - No horizontal or vertical neighbors significant
    for (i = 1; i < 16; i++) {
      // Two or more diagonal coeffs significant
      zcLutLh[i] = 4;
    }
    for (i = 0; i < 4; i++) {
      // Only one diagonal coeff significant
      zcLutLh[1 << i] = 3;
    }
    // - No horizontal neighbors significant, diagonal irrelevant
    for (i = 0; i < 16; i++) {
      // Only one vertical coeff significant
      zcLutLh[stateVUR1 | i] = 5;
      zcLutLh[stateVDR1 | i] = 5;
      // The two vertical coeffs significant
      zcLutLh[stateVUR1 | stateVDR1 | i] = 6;
    }
    // - One horiz. neighbor significant, diagonal/vertical non-significant
    zcLutLh[stateHLR1] = 7;
    zcLutLh[stateHRR1] = 7;
    // - One horiz. significant, no vertical significant, one or more
    // diagonal significant
    for (i = 1; i < 16; i++) {
      zcLutLh[stateHLR1 | i] = 8;
      zcLutLh[stateHRR1 | i] = 8;
    }
    // - One horiz. significant, one or more vertical significant,
    // diagonal irrelevant
    for (i = 1; i < 4; i++) {
      for (j = 0; j < 16; j++) {
        zcLutLh[stateHLR1 | (i << 4) | j] = 9;
        zcLutLh[stateHRR1 | (i << 4) | j] = 9;
      }
    }
    // - Two horiz. significant, others irrelevant
    for (i = 0; i < 64; i++) {
      zcLutLh[stateHLR1 | stateHRR1 | i] = 10;
    }

    // HL

    // - No neighbors significant
    zcLutHl[0] = 2;
    // - No horizontal or vertical neighbors significant
    for (i = 1; i < 16; i++) {
      // Two or more diagonal coeffs significant
      zcLutHl[i] = 4;
    }
    for (i = 0; i < 4; i++) {
      // Only one diagonal coeff significant
      zcLutHl[1 << i] = 3;
    }
    // - No vertical significant, diagonal irrelevant
    for (i = 0; i < 16; i++) {
      // One horiz. significant
      zcLutHl[stateHLR1 | i] = 5;
      zcLutHl[stateHRR1 | i] = 5;
      // Two horiz. significant
      zcLutHl[stateHLR1 | stateHRR1 | i] = 6;
    }
    // - One vert. significant, diagonal/horizontal non-significant
    zcLutHl[stateVUR1] = 7;
    zcLutHl[stateVDR1] = 7;
    // - One vert. significant, horizontal non-significant, one or more
    // diag. significant
    for (i = 1; i < 16; i++) {
      zcLutHl[stateVUR1 | i] = 8;
      zcLutHl[stateVDR1 | i] = 8;
    }
    // - One vertical significant, one or more horizontal significant,
    // diagonal irrelevant
    for (i = 1; i < 4; i++) {
      for (j = 0; j < 16; j++) {
        zcLutHl[(i << 6) | stateVUR1 | j] = 9;
        zcLutHl[(i << 6) | stateVDR1 | j] = 9;
      }
    }
    // - Two vertical significant, others irrelevant
    for (i = 0; i < 4; i++) {
      for (j = 0; j < 16; j++) {
        zcLutHl[(i << 6) | stateVUR1 | stateVDR1 | j] = 10;
      }
    }

    // HH
    List<int> twoBits = [3, 5, 6, 9, 10, 12];
    List<int> oneBit = [1, 2, 4, 8];
    List<int> twoLeast = [3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15];
    List<int> threeLeast = [7, 11, 13, 14, 15];

    // - None significant
    zcLutHh[0] = 2;

    // - One horizontal+vertical significant, none diagonal
    for (i = 0; i < oneBit.length; i++) {
      zcLutHh[oneBit[i] << 4] = 3;
    }

    // - Two or more horizontal+vertical significant, diagonal non-signif
    for (i = 0; i < twoLeast.length; i++) {
      zcLutHh[twoLeast[i] << 4] = 4;
    }

    // - One diagonal significant, horiz./vert. non-significant
    for (i = 0; i < oneBit.length; i++) {
      zcLutHh[oneBit[i]] = 5;
    }

    // - One diagonal significant, one horiz.+vert. significant
    for (i = 0; i < oneBit.length; i++) {
      for (j = 0; j < oneBit.length; j++) {
        zcLutHh[(oneBit[i] << 4) | oneBit[j]] = 6;
      }
    }

    // - One diag signif, two or more horiz+vert signif
    for (i = 0; i < twoLeast.length; i++) {
      for (j = 0; j < oneBit.length; j++) {
        zcLutHh[(twoLeast[i] << 4) | oneBit[j]] = 7;
      }
    }

    // - Two diagonal significant, none horiz+vert significant
    for (i = 0; i < twoBits.length; i++) {
      zcLutHh[twoBits[i]] = 8;
    }

    // - Two diagonal significant, one or more horiz+vert significant
    for (j = 0; j < twoBits.length; j++) {
      for (i = 1; i < 16; i++) {
        zcLutHh[(i << 4) | twoBits[j]] = 9;
      }
    }

    // - Three or more diagonal significant, horiz+vert irrelevant
    for (i = 0; i < 16; i++) {
      for (j = 0; j < threeLeast.length; j++) {
        zcLutHh[(i << 4) | threeLeast[j]] = 10;
      }
    }

    // Initialize the SC lookup tables
    interScLut = List<int>.filled(36, 0);
    interScLut[(2 << 3) | 2] = 15;
    interScLut[(2 << 3) | 1] = 14;
    interScLut[(2 << 3) | 0] = 13;
    interScLut[(1 << 3) | 2] = 12;
    interScLut[(1 << 3) | 1] = 11;
    interScLut[(1 << 3) | 0] = 12 | intSignBit;
    interScLut[(0 << 3) | 2] = 13 | intSignBit;
    interScLut[(0 << 3) | 1] = 14 | intSignBit;
    interScLut[(0 << 3) | 0] = 15 | intSignBit;

    for (i = 0; i < (1 << scLutBits) - 1; i++) {
      ds = i & 0x01;
      us = (i >> 1) & 0x01;
      rs = (i >> 2) & 0x01;
      ls = (i >> 3) & 0x01;
      dsgn = (i >> 5) & 0x01;
      usgn = (i >> 6) & 0x01;
      rsgn = (i >> 7) & 0x01;
      lsgn = (i >> 8) & 0x01;

      h = ls * (1 - 2 * lsgn) + rs * (1 - 2 * rsgn);
      h = (h >= -1) ? h : -1;
      h = (h <= 1) ? h : 1;
      v = us * (1 - 2 * usgn) + ds * (1 - 2 * dsgn);
      v = (v >= -1) ? v : -1;
      v = (v <= 1) ? v : 1;

      scLut[i] = interScLut[(h + 1) << 3 | (v + 1)];
    }
    interScLut = null;

    // Initialize the MR lookup tables
    mrLut[0] = 16;
    for (i = 1; i < (1 << (mrLutBits - 1)); i++) {
      mrLut[i] = 17;
    }
    for (; i < (1 << mrLutBits); i++) {
      mrLut[i] = 18;
    }

    // Initialize the distortion estimation lookup tables
    for (i = 0; i < (1 << (mseLkpBits - 1)); i++) {
      val = i.toDouble() / (1 << (mseLkpBits - 1)) + 1.0;
      deltaMSE = val * val;
      fsLossless[i] =
          (deltaMSE * ((1 << mseLkpFracBits).toDouble()) + 0.5).floor();
      val -= 1.5;
      deltaMSE -= val * val;
      fsLossy[i] =
          (deltaMSE * ((1 << mseLkpFracBits).toDouble()) + 0.5).floor();
    }

    for (i = 0; i < (1 << mseLkpBits); i++) {
      val = i.toDouble() / (1 << (mseLkpBits - 1));
      deltaMSE = (val - 1.0) * (val - 1.0);
      fmLossless[i] =
          (deltaMSE * ((1 << mseLkpFracBits).toDouble()) + 0.5).floor();
      val -= (i < (1 << (mseLkpBits - 1))) ? 0.5 : 1.5;
      deltaMSE -= val * val;
      fmLossy[i] =
          (deltaMSE * ((1 << mseLkpFracBits).toDouble()) + 0.5).floor();
    }
  }

  StdEntropyCoder(CBlkQuantDataSrcEnc src, this.cblks, this.pss, this.bms,
      this.mqrs, this.rts, this.css, this.sss, this.lcs, this.tts)
      : super(src) {
    _staticInit();
    int maxCBlkWidth, maxCBlkHeight;
    int tsl = 1; // Single threaded

    maxCBlkWidth = cblks.getMaxCBlkWidth();
    maxCBlkHeight = cblks.getMaxCBlkHeight();

    outT = List.generate(tsl, (_) => ByteOutputBuffer());
    mqT = List.generate(tsl, (idx) => MQCoder(outT[idx], numCtxts, mqInit));
    boutT = List.filled(tsl, null);
    stateT = List.generate(
        tsl,
        (_) => List<int>.filled(
            (maxCBlkWidth + 2) * ((maxCBlkHeight + 1) ~/ 2 + 2), 0));
    symbufT = List.generate(
        tsl, (_) => List<int>.filled(maxCBlkWidth * (stripeHeight * 2 + 2), 0));
    ctxtbufT = List.generate(
        tsl, (_) => List<int>.filled(maxCBlkWidth * (stripeHeight * 2 + 2), 0));
    distbufT = List.generate(tsl,
        (_) => List<double>.filled(32 * StdEntropyCoderOptions.numPasses, 0.0));
    ratebufT = List.generate(
        tsl, (_) => List<int>.filled(32 * StdEntropyCoderOptions.numPasses, 0));
    istermbufT = List.generate(tsl,
        (_) => List<bool>.filled(32 * StdEntropyCoderOptions.numPasses, false));
    srcblkT = List.filled(tsl, null);

    precinctPartition = List.generate(
        src.getNumComps(), (_) => List<bool>.filled(src.getNumTiles(), false));

    Coord numTiles = src.getNumTilesCoord(null);
    initTileComp(src.getNumTiles(), src.getNumComps());

    for (int c = 0; c < src.getNumComps(); c++) {
      for (int tY = 0; tY < numTiles.y; tY++) {
        for (int tX = 0; tX < numTiles.x; tX++) {
          // precinctPartition[c][tIdx] = false; // tIdx not available here easily, but initialized to false anyway
        }
      }
    }
  }

  @override
  int getCBlkWidth(int t, int c) {
    return cblks.getCBlkWidth(ModuleSpec.specTileComp, t, c);
  }

  @override
  int getCBlkHeight(int t, int c) {
    return cblks.getCBlkHeight(ModuleSpec.specTileComp, t, c);
  }

  @override
  CBlkRateDistStats? getNextCodeBlock(int c, CBlkRateDistStats? ccb) {
    // Single threaded implementation
    srcblkT[0] = src.getNextInternCodeBlock(c, srcblkT[0]);

    if (srcblkT[0] == null) {
      return null;
    }

    final tIdx = getTileIdx();

    if ((opts[tIdx][c] & optBypass) != 0 && boutT[0] == null) {
      boutT[0] = BitToByteOutput(outT[0]);
    }

    ccb ??= CBlkRateDistStats();

    compressCodeBlock(
        c,
        ccb,
        srcblkT[0]!,
        mqT[0],
        boutT[0],
        outT[0],
        stateT[0],
        distbufT[0],
        ratebufT[0],
        istermbufT[0],
        symbufT[0],
        ctxtbufT[0],
        opts[tIdx][c],
        isReversible(tIdx, c),
        lenCalc[tIdx][c],
        tType[tIdx][c]);

    return ccb;
  }

  void initTileComp(int nt, int nc) {
    opts = List.generate(nt, (_) => List<int>.filled(nc, 0));
    lenCalc = List.generate(nt, (_) => List<int>.filled(nc, 0));
    tType = List.generate(nt, (_) => List<int>.filled(nc, 0));

    for (int t = 0; t < nt; t++) {
      for (int c = 0; c < nc; c++) {
        opts[t][c] = 0;

        if ((bms.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= optBypass;
        }
        if ((mqrs.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= optResetMq;
        }
        if ((rts.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= optTermPass;
        }
        if ((css.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= optVertStrCausal;
        }
        if ((sss.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= optSegSymbols;
        }

        String lCalcType = lcs.getTileCompVal(t, c) as String;
        if (lCalcType == "near_opt") {
          lenCalc[t][c] = MQCoder.lengthNearOpt;
        } else if (lCalcType == "lazy_good") {
          lenCalc[t][c] = MQCoder.lengthLazyGood;
        } else if (lCalcType == "lazy") {
          lenCalc[t][c] = MQCoder.lengthLazy;
        } else {
          throw ArgumentError(
              "Unrecognized or unsupported MQ length calculation.");
        }

        String termType = tts.getTileCompVal(t, c) as String;
        if (termType.toLowerCase() == "easy") {
          tType[t][c] = MQCoder.termEasy;
        } else if (termType.toLowerCase() == "full") {
          tType[t][c] = MQCoder.termFull;
        } else if (termType.toLowerCase() == "near_opt") {
          tType[t][c] = MQCoder.termNearOpt;
        } else if (termType.toLowerCase() == "predict") {
          tType[t][c] = MQCoder.termPredEr;
          opts[t][c] |= optPredTerm;
          if ((opts[t][c] & (optTermPass | optBypass)) == 0) {
            FacilityManager.getMsgLogger().printmsg(
                MsgLogger.info,
                "Using error resilient MQ termination, but terminating only at "
                "the end of code-blocks. The error protection offered by this "
                "option will be very weak. Specify the 'Cterminate' and/or "
                "'Cbypass' option for increased error resilience.");
          }
        } else {
          throw ArgumentError(
              "Unrecognized or unsupported MQ coder termination.");
        }
      }
    }
  }

  static void compressCodeBlock(
      int c,
      CBlkRateDistStats ccb,
      CBlkWTData srcblk,
      MQCoder mq,
      BitToByteOutput? bout,
      ByteOutputBuffer out,
      List<int> state,
      List<double> distbuf,
      List<int> ratebuf,
      List<bool> istermbuf,
      List<int> symbuf,
      List<int> ctxtbuf,
      int options,
      bool rev,
      int lcType,
      int tType) {
    List<int> zcLut;
    int skipbp;
    int curbp;
    List<int> fm;
    List<int> fs;
    int lmb;
    int npass;
    double msew;
    double totdist;
    int ltpidx;

    if ((options & optPredTerm) != 0 && tType != MQCoder.termPredEr) {
      throw ArgumentError("Embedded error-resilient info in MQ termination "
          "option specified but incorrect MQ termination policy specified");
    }

    mq.setLenCalcType(lcType);
    mq.setTermType(tType);

    lmb = 30 - srcblk.magbits + 1;
    lmb = (lmb < 0) ? 0 : lmb;

    ArrayUtil.intArraySet(state, 0);

    skipbp = calcSkipMSBP(srcblk, lmb);

    ccb.m = srcblk.m;
    ccb.n = srcblk.n;
    ccb.sb = srcblk.sb;
    ccb.nROIcoeff = srcblk.nROIcoeff;
    ccb.skipMSBP = skipbp;
    if (ccb.nROIcoeff != 0) {
      ccb.nROIcp = 3 * (srcblk.nROIbp - skipbp - 1) + 1;
    } else {
      ccb.nROIcp = 0;
    }

    switch (srcblk.sb!.orientation) {
      case Subband.wtOrientHl:
        zcLut = zcLutHl;
        break;
      case Subband.wtOrientLl:
      case Subband.wtOrientLh:
        zcLut = zcLutLh;
        break;
      case Subband.wtOrientHh:
        zcLut = zcLutHh;
        break;
      default:
        throw Error();
    }

    curbp = 30 - skipbp;
    fs = fsLossy;
    fm = fmLossy;
    msew = math.pow(2, ((curbp - lmb) << 1) - mseLkpFracBits) *
        srcblk.sb!.stepWMSE *
        srcblk.wmseScaling;
    totdist = 0.0;
    npass = 0;
    ltpidx = -1;

    if (curbp >= lmb) {
      if (rev && curbp == lmb) {
        fs = fmLossless;
      }
      istermbuf[npass] = (options & optTermPass) != 0 ||
          curbp == lmb ||
          ((options & optBypass) != 0 &&
              (31 - numNonBypassMsBp - skipbp) >= curbp);
      totdist += cleanuppass(srcblk, mq, istermbuf[npass], curbp, state, fs,
              zcLut, symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
          msew;
      distbuf[npass] = totdist;
      if (istermbuf[npass]) ltpidx = npass;
      npass++;
      msew *= 0.25;
      curbp--;
    }

    while (curbp >= lmb) {
      if (rev && curbp == lmb) {
        fs = fsLossless;
        fm = fmLossless;
      }

      istermbuf[npass] = (options & optTermPass) != 0;
      if ((options & optBypass) == 0 ||
          (31 - numNonBypassMsBp - skipbp <= curbp)) {
        totdist += sigProgPass(srcblk, mq, istermbuf[npass], curbp, state, fs,
                zcLut, symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
            msew;
      } else {
        bout!.setPredTerm((options & optPredTerm) != 0);
        totdist += rawSigProgPass(srcblk, bout, istermbuf[npass], curbp, state,
                fs, ratebuf, npass, ltpidx, options) *
            msew;
      }
      distbuf[npass] = totdist;
      if (istermbuf[npass]) ltpidx = npass;
      npass++;

      istermbuf[npass] = (options & optTermPass) != 0 ||
          ((options & optBypass) != 0 &&
              (31 - numNonBypassMsBp - skipbp > curbp));
      if ((options & optBypass) == 0 ||
          (31 - numNonBypassMsBp - skipbp <= curbp)) {
        totdist += magRefPass(srcblk, mq, istermbuf[npass], curbp, state, fm,
                symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
            msew;
      } else {
        bout!.setPredTerm((options & optPredTerm) != 0);
        totdist += rawMagRefPass(srcblk, bout, istermbuf[npass], curbp, state,
                fm, ratebuf, npass, ltpidx, options) *
            msew;
      }
      distbuf[npass] = totdist;
      if (istermbuf[npass]) ltpidx = npass;
      npass++;

      istermbuf[npass] = (options & optTermPass) != 0 ||
          curbp == lmb ||
          ((options & optBypass) != 0 &&
              (31 - numNonBypassMsBp - skipbp) >= curbp);
      totdist += cleanuppass(srcblk, mq, istermbuf[npass], curbp, state, fs,
              zcLut, symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
          msew;
      distbuf[npass] = totdist;

      if (istermbuf[npass]) ltpidx = npass;
      npass++;

      msew *= 0.25;
      curbp--;
    }

    ccb.data = Uint8List(out.size());
    out.toByteArray(0, out.size(), ccb.data!, 0);
    checkEndOfPassFF(ccb.data!, ratebuf, istermbuf, npass);
    ccb.selectConvexHull(
        ratebuf,
        distbuf,
        (options & (optBypass | optTermPass)) != 0 ? istermbuf : null,
        npass,
        rev);

    mq.reset();
    if (bout != null) bout.reset();
  }

  static int calcSkipMSBP(CBlkWTData cblk, int lmb) {
    int k, kmax, mask;
    List<int> data;
    int maxmag;
    int mag;
    int w, h;
    int msbp;
    int l;

    data = cblk.getData() as List<int>;
    w = cblk.w;
    h = cblk.h;

    maxmag = 0;
    mask = 0x7FFFFFFF & (~((1 << lmb) - 1));
    k = cblk.offset;
    for (l = h - 1; l >= 0; l--) {
      for (kmax = k + w; k < kmax; k++) {
        mag = data[k] & mask;
        if (mag > maxmag) maxmag = mag;
      }
      k += cblk.scanw - w;
    }

    msbp = 30;
    do {
      if (((1 << msbp) & maxmag) != 0) break;
      msbp--;
    } while (msbp >= lmb);

    return 30 - msbp;
  }

  static int sigProgPass(
      CBlkWTData srcblk,
      MQCoder mq,
      bool doterm,
      int bp,
      List<int> state,
      List<int> fs,
      List<int> zcLut,
      List<int> symbuf,
      List<int> ctxtbuf,
      List<int> ratebuf,
      int pidx,
      int ltpidx,
      int options) {
    int j, sj;
    int k, sk;
    int nsym = 0;
    int dscanw;
    int sscanw;
    int jstep;
    int kstep;
    int stopsk;
    int csj;
    int mask;
    int sym;
    int ctxt;
    List<int> data;
    int dist;
    int shift;
    int upshift;
    int downshift;
    int normval;
    int s;
    bool causal;
    int nstripes;
    int sheight;
    int offUl, offUr, offDr, offDl;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * stripeHeight ~/ 2 - srcblk.w;
    kstep = dscanw * stripeHeight - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + stripeHeight - 1) ~/ stripeHeight;
    dist = 0;
    shift = bp - (mseLkpBits - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;
    causal = (options & optVertStrCausal) != 0;

    offUl = -sscanw - 1;
    offUr = -sscanw + 1;
    offDr = sscanw + 1;
    offDl = sscanw - 1;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight =
          (s != 0) ? stripeHeight : srcblk.h - (nstripes - 1) * stripeHeight;
      stopsk = sk + srcblk.w;
      for (nsym = 0; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & sigMaskR1r2) != 0) {
          k = sk;
          if ((csj & (stateSigR1 | stateNzCtxtR1)) == stateNzCtxtR1) {
            ctxtbuf[nsym] = zcLut[csj & zcMask];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = (data[k] >> 31) & 1;
              ctxt = scLut[(csj >> scShiftR1) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              if (!causal) {
                state[j + offUl] |= stateNzCtxtR2 | stateDDrR2;
                state[j + offUr] |= stateNzCtxtR2 | stateDDlR2;
              }
              if (sym != 0) {
                csj |= stateSigR1 |
                    stateVisitedR1 |
                    stateNzCtxtR2 |
                    stateVUR2 |
                    stateVUSignR2;
                if (!causal) {
                  state[j - sscanw] |=
                      stateNzCtxtR2 | stateVDR2 | stateVDSignR2;
                }
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHLR1 |
                    stateHLSignR1 |
                    stateDUlR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHRR1 |
                    stateHRSignR1 |
                    stateDUrR2;
              } else {
                csj |= stateSigR1 | stateVisitedR1 | stateNzCtxtR2 | stateVUR2;
                if (!causal) {
                  state[j - sscanw] |= stateNzCtxtR2 | stateVDR2;
                }
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHLR1 | stateDUlR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHRR1 | stateDUrR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR1;
            }
          }
          if (sheight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (stateSigR2 | stateNzCtxtR2)) == stateNzCtxtR2) {
            k += dscanw;
            ctxtbuf[nsym] = zcLut[(csj >> stateSep) & zcMask];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = (data[k] >> 31) & 1;
              ctxt = scLut[(csj >> scShiftR2) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              state[j + offDl] |= stateNzCtxtR1 | stateDUrR1;
              state[j + offDr] |= stateNzCtxtR1 | stateDUlR1;
              if (sym != 0) {
                csj |= stateSigR2 |
                    stateVisitedR2 |
                    stateNzCtxtR1 |
                    stateVDR1 |
                    stateVDSignR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1 | stateVUSignR1;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDlR1 |
                    stateHLR2 |
                    stateHLSignR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDrR1 |
                    stateHRR2 |
                    stateHRSignR2;
              } else {
                csj |= stateSigR2 | stateVisitedR2 | stateNzCtxtR1 | stateVDR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDlR1 | stateHLR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDrR1 | stateHRR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR2;
            }
          }
          state[j] = csj;
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & sigMaskR1r2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (stateSigR1 | stateNzCtxtR1)) == stateNzCtxtR1) {
            ctxtbuf[nsym] = zcLut[csj & zcMask];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = (data[k] >> 31) & 1;
              ctxt = scLut[(csj >> scShiftR1) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              state[j + offUl] |= stateNzCtxtR2 | stateDDrR2;
              state[j + offUr] |= stateNzCtxtR2 | stateDDlR2;
              if (sym != 0) {
                csj |= stateSigR1 |
                    stateVisitedR1 |
                    stateNzCtxtR2 |
                    stateVUR2 |
                    stateVUSignR2;
                state[j - sscanw] |= stateNzCtxtR2 | stateVDR2 | stateVDSignR2;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHLR1 |
                    stateHLSignR1 |
                    stateDUlR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHRR1 |
                    stateHRSignR1 |
                    stateDUrR2;
              } else {
                csj |= stateSigR1 | stateVisitedR1 | stateNzCtxtR2 | stateVUR2;
                state[j - sscanw] |= stateNzCtxtR2 | stateVDR2;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHLR1 | stateDUlR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHRR1 | stateDUrR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR1;
            }
          }
          if (sheight < 4) {
            state[j] = csj;
            continue;
          }
          if ((csj & (stateSigR2 | stateNzCtxtR2)) == stateNzCtxtR2) {
            k += dscanw;
            ctxtbuf[nsym] = zcLut[(csj >> stateSep) & zcMask];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = (data[k] >> 31) & 1;
              ctxt = scLut[(csj >> scShiftR2) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              state[j + offDl] |= stateNzCtxtR1 | stateDUrR1;
              state[j + offDr] |= stateNzCtxtR1 | stateDUlR1;
              if (sym != 0) {
                csj |= stateSigR2 |
                    stateVisitedR2 |
                    stateNzCtxtR1 |
                    stateVDR1 |
                    stateVDSignR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1 | stateVUSignR1;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDlR1 |
                    stateHLR2 |
                    stateHLSignR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDrR1 |
                    stateHRR2 |
                    stateHRSignR2;
              } else {
                csj |= stateSigR2 | stateVisitedR2 | stateNzCtxtR1 | stateVDR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDlR1 | stateHLR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDrR1 | stateHRR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR2;
            }
          }
          state[j] = csj;
        }
      }
      mq.codeSymbols(symbuf, ctxtbuf, nsym);
    }

    if ((options & optResetMq) != 0) {
      mq.resetCtxts();
    }

    if (doterm) {
      ratebuf[pidx] = mq.terminate();
    } else {
      ratebuf[pidx] = mq.getNumCodedBytes();
    }
    if (ltpidx >= 0) {
      ratebuf[pidx] += ratebuf[ltpidx];
    }
    if (doterm) {
      mq.finishLengthCalculation(ratebuf, pidx);
    }

    return dist;
  }

  static int rawSigProgPass(
      CBlkWTData srcblk,
      BitToByteOutput bout,
      bool doterm,
      int bp,
      List<int> state,
      List<int> fs,
      List<int> ratebuf,
      int pidx,
      int ltpidx,
      int options) {
    int j, sj;
    int k, sk;
    int dscanw;
    int sscanw;
    int jstep;
    int kstep;
    int stopsk;
    int csj;
    int mask;
    int sym;
    List<int> data;
    int dist;
    int shift;
    int upshift;
    int downshift;
    int normval;
    int s;
    bool causal;
    int nstripes;
    int sheight;
    int offUl, offUr, offDr, offDl;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * stripeHeight ~/ 2 - srcblk.w;
    kstep = dscanw * stripeHeight - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + stripeHeight - 1) ~/ stripeHeight;
    dist = 0;
    shift = bp - (mseLkpBits - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;
    causal = (options & optVertStrCausal) != 0;

    offUl = -sscanw - 1;
    offUr = -sscanw + 1;
    offDr = sscanw + 1;
    offDl = sscanw - 1;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight =
          (s != 0) ? stripeHeight : srcblk.h - (nstripes - 1) * stripeHeight;
      stopsk = sk + srcblk.w;
      for (; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & sigMaskR1r2) != 0) {
          k = sk;
          if ((csj & (stateSigR1 | stateNzCtxtR1)) == stateNzCtxtR1) {
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = (data[k] >> 31) & 1;
              bout.writeBit(sym);
              if (!causal) {
                state[j + offUl] |= stateNzCtxtR2 | stateDDrR2;
                state[j + offUr] |= stateNzCtxtR2 | stateDDlR2;
              }
              if (sym != 0) {
                csj |= stateSigR1 |
                    stateVisitedR1 |
                    stateNzCtxtR2 |
                    stateVUR2 |
                    stateVUSignR2;
                if (!causal) {
                  state[j - sscanw] |=
                      stateNzCtxtR2 | stateVDR2 | stateVDSignR2;
                }
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHLR1 |
                    stateHLSignR1 |
                    stateDUlR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHRR1 |
                    stateHRSignR1 |
                    stateDUrR2;
              } else {
                csj |= stateSigR1 | stateVisitedR1 | stateNzCtxtR2 | stateVUR2;
                if (!causal) {
                  state[j - sscanw] |= stateNzCtxtR2 | stateVDR2;
                }
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHLR1 | stateDUlR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHRR1 | stateDUrR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR1;
            }
          }
          if (sheight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (stateSigR2 | stateNzCtxtR2)) == stateNzCtxtR2) {
            k += dscanw;
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = (data[k] >> 31) & 1;
              bout.writeBit(sym);
              state[j + offDl] |= stateNzCtxtR1 | stateDUrR1;
              state[j + offDr] |= stateNzCtxtR1 | stateDUlR1;
              if (sym != 0) {
                csj |= stateSigR2 |
                    stateVisitedR2 |
                    stateNzCtxtR1 |
                    stateVDR1 |
                    stateVDSignR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1 | stateVUSignR1;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDlR1 |
                    stateHLR2 |
                    stateHLSignR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDrR1 |
                    stateHRR2 |
                    stateHRSignR2;
              } else {
                csj |= stateSigR2 | stateVisitedR2 | stateNzCtxtR1 | stateVDR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDlR1 | stateHLR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDrR1 | stateHRR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR2;
            }
          }
          state[j] = csj;
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & sigMaskR1r2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (stateSigR1 | stateNzCtxtR1)) == stateNzCtxtR1) {
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = (data[k] >> 31) & 1;
              bout.writeBit(sym);
              state[j + offUl] |= stateNzCtxtR2 | stateDDrR2;
              state[j + offUr] |= stateNzCtxtR2 | stateDDlR2;
              if (sym != 0) {
                csj |= stateSigR1 |
                    stateVisitedR1 |
                    stateNzCtxtR2 |
                    stateVUR2 |
                    stateVUSignR2;
                state[j - sscanw] |= stateNzCtxtR2 | stateVDR2 | stateVDSignR2;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHLR1 |
                    stateHLSignR1 |
                    stateDUlR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHRR1 |
                    stateHRSignR1 |
                    stateDUrR2;
              } else {
                csj |= stateSigR1 | stateVisitedR1 | stateNzCtxtR2 | stateVUR2;
                state[j - sscanw] |= stateNzCtxtR2 | stateVDR2;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHLR1 | stateDUlR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHRR1 | stateDUrR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR1;
            }
          }
          if (sheight < 4) {
            state[j] = csj;
            continue;
          }
          if ((csj & (stateSigR2 | stateNzCtxtR2)) == stateNzCtxtR2) {
            k += dscanw;
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = (data[k] >> 31) & 1;
              bout.writeBit(sym);
              state[j + offDl] |= stateNzCtxtR1 | stateDUrR1;
              state[j + offDr] |= stateNzCtxtR1 | stateDUlR1;
              if (sym != 0) {
                csj |= stateSigR2 |
                    stateVisitedR2 |
                    stateNzCtxtR1 |
                    stateVDR1 |
                    stateVDSignR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1 | stateVUSignR1;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDlR1 |
                    stateHLR2 |
                    stateHLSignR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDrR1 |
                    stateHRR2 |
                    stateHRSignR2;
              } else {
                csj |= stateSigR2 | stateVisitedR2 | stateNzCtxtR1 | stateVDR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDlR1 | stateHLR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDrR1 | stateHRR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            } else {
              csj |= stateVisitedR2;
            }
          }
          state[j] = csj;
        }
      }
    }

    if (doterm) {
      ratebuf[pidx] = bout.terminate();
    } else {
      ratebuf[pidx] = bout.length();
    }
    if (ltpidx >= 0) {
      ratebuf[pidx] += ratebuf[ltpidx];
    }

    return dist;
  }

  static int magRefPass(
      CBlkWTData srcblk,
      MQCoder mq,
      bool doterm,
      int bp,
      List<int> state,
      List<int> fm,
      List<int> symbuf,
      List<int> ctxtbuf,
      List<int> ratebuf,
      int pidx,
      int ltpidx,
      int options) {
    int j, sj;
    int k, sk;
    int nsym = 0;
    int dscanw;
    int sscanw;
    int jstep;
    int kstep;
    int stopsk;
    int csj;
    int mask;
    List<int> data;
    int dist;
    int shift;
    int upshift;
    int downshift;
    int normval;
    int s;
    int nstripes;
    int sheight;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * stripeHeight ~/ 2 - srcblk.w;
    kstep = dscanw * stripeHeight - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + stripeHeight - 1) ~/ stripeHeight;
    dist = 0;
    shift = bp - (mseLkpBits - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight =
          (s != 0) ? stripeHeight : srcblk.h - (nstripes - 1) * stripeHeight;
      stopsk = sk + srcblk.w;
      for (nsym = 0; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & vstdMaskR1r2) != 0) {
          k = sk;
          if ((csj & (stateSigR1 | stateVisitedR1)) == stateSigR1) {
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = mrLut[csj & mrMask];
            csj |= statePrevMrR1;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
          if (sheight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (stateSigR2 | stateVisitedR2)) == stateSigR2) {
            k += dscanw;
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = mrLut[(csj >> stateSep) & mrMask];
            csj |= statePrevMrR2;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
          state[j] = csj;
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & vstdMaskR1r2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (stateSigR1 | stateVisitedR1)) == stateSigR1) {
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = mrLut[csj & mrMask];
            csj |= statePrevMrR1;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
          if (sheight < 4) {
            state[j] = csj;
            continue;
          }
          if ((state[j] & (stateSigR2 | stateVisitedR2)) == stateSigR2) {
            k += dscanw;
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = mrLut[(csj >> stateSep) & mrMask];
            csj |= statePrevMrR2;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
          state[j] = csj;
        }
      }
      if (nsym > 0) mq.codeSymbols(symbuf, ctxtbuf, nsym);
    }

    if ((options & optResetMq) != 0) {
      mq.resetCtxts();
    }

    if (doterm) {
      ratebuf[pidx] = mq.terminate();
    } else {
      ratebuf[pidx] = mq.getNumCodedBytes();
    }
    if (ltpidx >= 0) {
      ratebuf[pidx] += ratebuf[ltpidx];
    }
    if (doterm) {
      mq.finishLengthCalculation(ratebuf, pidx);
    }

    return dist;
  }

  static int rawMagRefPass(
      CBlkWTData srcblk,
      BitToByteOutput bout,
      bool doterm,
      int bp,
      List<int> state,
      List<int> fm,
      List<int> ratebuf,
      int pidx,
      int ltpidx,
      int options) {
    int j, sj;
    int k, sk;
    int dscanw;
    int sscanw;
    int jstep;
    int kstep;
    int stopsk;
    int csj;
    int mask;
    List<int> data;
    int dist;
    int shift;
    int upshift;
    int downshift;
    int normval;
    int s;
    int nstripes;
    int sheight;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * stripeHeight ~/ 2 - srcblk.w;
    kstep = dscanw * stripeHeight - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + stripeHeight - 1) ~/ stripeHeight;
    dist = 0;
    shift = bp - (mseLkpBits - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight =
          (s != 0) ? stripeHeight : srcblk.h - (nstripes - 1) * stripeHeight;
      stopsk = sk + srcblk.w;
      for (; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & vstdMaskR1r2) != 0) {
          k = sk;
          if ((csj & (stateSigR1 | stateVisitedR1)) == stateSigR1) {
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
          if (sheight < 2) continue;
          if ((csj & (stateSigR2 | stateVisitedR2)) == stateSigR2) {
            k += dscanw;
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & vstdMaskR1r2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (stateSigR1 | stateVisitedR1)) == stateSigR1) {
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
          if (sheight < 4) continue;
          if ((state[j] & (stateSigR2 | stateVisitedR2)) == stateSigR2) {
            k += dscanw;
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << mseLkpBits) - 1)];
          }
        }
      }
    }

    if (doterm) {
      ratebuf[pidx] = bout.terminate();
    } else {
      ratebuf[pidx] = bout.length();
    }

    if (ltpidx >= 0) {
      ratebuf[pidx] += ratebuf[ltpidx];
    }

    return dist;
  }

  static int cleanuppass(
      CBlkWTData srcblk,
      MQCoder mq,
      bool doterm,
      int bp,
      List<int> state,
      List<int> fs,
      List<int> zcLut,
      List<int> symbuf,
      List<int> ctxtbuf,
      List<int> ratebuf,
      int pidx,
      int ltpidx,
      int options) {
    int j, sj;
    int k, sk;
    int nsym = 0;
    int dscanw;
    int sscanw;
    int jstep;
    int kstep;
    int stopsk;
    int csj;
    int mask;
    int sym;
    int rlclen;
    int ctxt;
    List<int> data;
    int dist;
    int shift;
    int upshift;
    int downshift;
    int normval;
    int s;
    bool causal;
    int nstripes;
    int sheight;
    int offUl, offUr, offDr, offDl;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * stripeHeight ~/ 2 - srcblk.w;
    kstep = dscanw * stripeHeight - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + stripeHeight - 1) ~/ stripeHeight;
    dist = 0;
    shift = bp - (mseLkpBits - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;
    causal = (options & optVertStrCausal) != 0;

    offUl = -sscanw - 1;
    offUr = -sscanw + 1;
    offDr = sscanw + 1;
    offDl = sscanw - 1;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight =
          (s != 0) ? stripeHeight : srcblk.h - (nstripes - 1) * stripeHeight;
      stopsk = sk + srcblk.w;
      for (nsym = 0; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        bool broken = false;

        // top_half:
        {
          if (csj == 0 && state[j + sscanw] == 0 && sheight == stripeHeight) {
            k = sk;
            if ((data[k] & mask) != 0) {
              rlclen = 0;
            } else if ((data[k += dscanw] & mask) != 0) {
              rlclen = 1;
            } else if ((data[k += dscanw] & mask) != 0) {
              rlclen = 2;
              j += sscanw;
              csj = state[j];
            } else if ((data[k += dscanw] & mask) != 0) {
              rlclen = 3;
              j += sscanw;
              csj = state[j];
            } else {
              symbuf[nsym] = 0;
              ctxtbuf[nsym++] = rlcCtxt;
              continue;
            }
            symbuf[nsym] = 1;
            ctxtbuf[nsym++] = rlcCtxt;
            symbuf[nsym] = rlclen >> 1;
            ctxtbuf[nsym++] = unifCtxt;
            symbuf[nsym] = rlclen & 0x01;
            ctxtbuf[nsym++] = unifCtxt;
            normval = (data[k] >> downshift) << upshift;
            dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            sym = (data[k] >> 31) & 1;
            if ((rlclen & 0x01) == 0) {
              ctxt = scLut[(csj >> scShiftR1) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              if (rlclen != 0 || !causal) {
                state[j + offUl] |= stateNzCtxtR2 | stateDDrR2;
                state[j + offUr] |= stateNzCtxtR2 | stateDDlR2;
              }
              if (sym != 0) {
                csj |= stateSigR1 |
                    stateVisitedR1 |
                    stateNzCtxtR2 |
                    stateVUR2 |
                    stateVUSignR2;
                if (rlclen != 0 || !causal) {
                  state[j - sscanw] |=
                      stateNzCtxtR2 | stateVDR2 | stateVDSignR2;
                }
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHLR1 |
                    stateHLSignR1 |
                    stateDUlR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHRR1 |
                    stateHRSignR1 |
                    stateDUrR2;
              } else {
                csj |= stateSigR1 | stateVisitedR1 | stateNzCtxtR2 | stateVUR2;
                if (rlclen != 0 || !causal) {
                  state[j - sscanw] |= stateNzCtxtR2 | stateVDR2;
                }
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHLR1 | stateDUlR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHRR1 | stateDUrR2;
              }
              if ((rlclen >> 1) != 0) {
                broken = true;
              }
            } else {
              ctxt = scLut[(csj >> scShiftR2) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              state[j + offDl] |= stateNzCtxtR1 | stateDUrR1;
              state[j + offDr] |= stateNzCtxtR1 | stateDUlR1;
              if (sym != 0) {
                csj |= stateSigR2 | stateNzCtxtR1 | stateVDR1 | stateVDSignR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1 | stateVUSignR1;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDlR1 |
                    stateHLR2 |
                    stateHLSignR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDrR1 |
                    stateHRR2 |
                    stateHRSignR2;
              } else {
                csj |= stateSigR2 | stateNzCtxtR1 | stateVDR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDlR1 | stateHLR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDrR1 | stateHRR2;
              }
              state[j] = csj;
              if ((rlclen >> 1) != 0) {
                continue;
              }
              j += sscanw;
              csj = state[j];
              broken = true;
            }
          }
        }

        if (!broken) {
          if ((((csj >> 1) | csj) & vstdMaskR1r2) != vstdMaskR1r2) {
            k = sk;
            if ((csj & (stateSigR1 | stateVisitedR1)) == 0) {
              ctxtbuf[nsym] = zcLut[csj & zcMask];
              if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
                sym = (data[k] >> 31) & 1;
                ctxt = scLut[(csj >> scShiftR1) & scMask];
                symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
                ctxtbuf[nsym++] = ctxt & scLutMask;
                if (!causal) {
                  state[j + offUl] |= stateNzCtxtR2 | stateDDrR2;
                  state[j + offUr] |= stateNzCtxtR2 | stateDDlR2;
                }
                if (sym != 0) {
                  csj |= stateSigR1 |
                      stateVisitedR1 |
                      stateNzCtxtR2 |
                      stateVUR2 |
                      stateVUSignR2;
                  if (!causal) {
                    state[j - sscanw] |=
                        stateNzCtxtR2 | stateVDR2 | stateVDSignR2;
                  }
                  state[j + 1] |= stateNzCtxtR1 |
                      stateNzCtxtR2 |
                      stateHLR1 |
                      stateHLSignR1 |
                      stateDUlR2;
                  state[j - 1] |= stateNzCtxtR1 |
                      stateNzCtxtR2 |
                      stateHRR1 |
                      stateHRSignR1 |
                      stateDUrR2;
                } else {
                  csj |=
                      stateSigR1 | stateVisitedR1 | stateNzCtxtR2 | stateVUR2;
                  if (!causal) {
                    state[j - sscanw] |= stateNzCtxtR2 | stateVDR2;
                  }
                  state[j + 1] |=
                      stateNzCtxtR1 | stateNzCtxtR2 | stateHLR1 | stateDUlR2;
                  state[j - 1] |=
                      stateNzCtxtR1 | stateNzCtxtR2 | stateHRR1 | stateDUrR2;
                }
                normval = (data[k] >> downshift) << upshift;
                dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
              }
            }
            if (sheight < 2) {
              csj &= ~(stateVisitedR1 | stateVisitedR2);
              state[j] = csj;
              continue;
            }
            if ((csj & (stateSigR2 | stateVisitedR2)) == 0) {
              k += dscanw;
              ctxtbuf[nsym] = zcLut[(csj >> stateSep) & zcMask];
              if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
                sym = (data[k] >> 31) & 1;
                ctxt = scLut[(csj >> scShiftR2) & scMask];
                symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
                ctxtbuf[nsym++] = ctxt & scLutMask;
                state[j + offDl] |= stateNzCtxtR1 | stateDUrR1;
                state[j + offDr] |= stateNzCtxtR1 | stateDUlR1;
                if (sym != 0) {
                  csj |= stateSigR2 |
                      stateVisitedR2 |
                      stateNzCtxtR1 |
                      stateVDR1 |
                      stateVDSignR1;
                  state[j + sscanw] |=
                      stateNzCtxtR1 | stateVUR1 | stateVUSignR1;
                  state[j + 1] |= stateNzCtxtR1 |
                      stateNzCtxtR2 |
                      stateDDlR1 |
                      stateHLR2 |
                      stateHLSignR2;
                  state[j - 1] |= stateNzCtxtR1 |
                      stateNzCtxtR2 |
                      stateDDrR1 |
                      stateHRR2 |
                      stateHRSignR2;
                } else {
                  csj |=
                      stateSigR2 | stateVisitedR2 | stateNzCtxtR1 | stateVDR1;
                  state[j + sscanw] |= stateNzCtxtR1 | stateVUR1;
                  state[j + 1] |=
                      stateNzCtxtR1 | stateNzCtxtR2 | stateDDlR1 | stateHLR2;
                  state[j - 1] |=
                      stateNzCtxtR1 | stateNzCtxtR2 | stateDDrR1 | stateHRR2;
                }
                normval = (data[k] >> downshift) << upshift;
                dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
              }
            }
          }
          csj &= ~(stateVisitedR1 | stateVisitedR2);
          state[j] = csj;
          if (sheight < 3) continue;
          j += sscanw;
          csj = state[j];
        }

        if ((((csj >> 1) | csj) & vstdMaskR1r2) != vstdMaskR1r2) {
          k = sk + (dscanw << 1);
          if ((csj & (stateSigR1 | stateVisitedR1)) == 0) {
            ctxtbuf[nsym] = zcLut[csj & zcMask];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = (data[k] >> 31) & 1;
              ctxt = scLut[(csj >> scShiftR1) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              state[j + offUl] |= stateNzCtxtR2 | stateDDrR2;
              state[j + offUr] |= stateNzCtxtR2 | stateDDlR2;
              if (sym != 0) {
                csj |= stateSigR1 |
                    stateVisitedR1 |
                    stateNzCtxtR2 |
                    stateVUR2 |
                    stateVUSignR2;
                state[j - sscanw] |= stateNzCtxtR2 | stateVDR2 | stateVDSignR2;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHLR1 |
                    stateHLSignR1 |
                    stateDUlR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateHRR1 |
                    stateHRSignR1 |
                    stateDUrR2;
              } else {
                csj |= stateSigR1 | stateVisitedR1 | stateNzCtxtR2 | stateVUR2;
                state[j - sscanw] |= stateNzCtxtR2 | stateVDR2;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHLR1 | stateDUlR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateHRR1 | stateDUrR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            }
          }
          if (sheight < 4) {
            csj &= ~(stateVisitedR1 | stateVisitedR2);
            state[j] = csj;
            continue;
          }
          if ((csj & (stateSigR2 | stateVisitedR2)) == 0) {
            k += dscanw;
            ctxtbuf[nsym] = zcLut[(csj >> stateSep) & zcMask];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = (data[k] >> 31) & 1;
              ctxt = scLut[(csj >> scShiftR2) & scMask];
              symbuf[nsym] = sym ^ (ctxt >> scSpredShift);
              ctxtbuf[nsym++] = ctxt & scLutMask;
              state[j + offDl] |= stateNzCtxtR1 | stateDUrR1;
              state[j + offDr] |= stateNzCtxtR1 | stateDUlR1;
              if (sym != 0) {
                csj |= stateSigR2 |
                    stateVisitedR2 |
                    stateNzCtxtR1 |
                    stateVDR1 |
                    stateVDSignR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1 | stateVUSignR1;
                state[j + 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDlR1 |
                    stateHLR2 |
                    stateHLSignR2;
                state[j - 1] |= stateNzCtxtR1 |
                    stateNzCtxtR2 |
                    stateDDrR1 |
                    stateHRR2 |
                    stateHRSignR2;
              } else {
                csj |= stateSigR2 | stateVisitedR2 | stateNzCtxtR1 | stateVDR1;
                state[j + sscanw] |= stateNzCtxtR1 | stateVUR1;
                state[j + 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDlR1 | stateHLR2;
                state[j - 1] |=
                    stateNzCtxtR1 | stateNzCtxtR2 | stateDDrR1 | stateHRR2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (mseLkpBits - 1)) - 1)];
            }
          }
        }
        csj &= ~(stateVisitedR1 | stateVisitedR2);
        state[j] = csj;
      }
      if (nsym > 0) mq.codeSymbols(symbuf, ctxtbuf, nsym);
    }

    if ((options & optSegSymbols) != 0) {
      mq.codeSymbols(segSymbols, segSymbCtxts, segSymbols.length);
    }

    if ((options & optResetMq) != 0) {
      mq.resetCtxts();
    }

    if (doterm) {
      ratebuf[pidx] = mq.terminate();
    } else {
      ratebuf[pidx] = mq.getNumCodedBytes();
    }
    if (ltpidx >= 0) {
      ratebuf[pidx] += ratebuf[ltpidx];
    }
    if (doterm) {
      mq.finishLengthCalculation(ratebuf, pidx);
    }
    return dist;
  }

  static void checkEndOfPassFF(
      Uint8List data, List<int> rates, List<bool>? isterm, int n) {
    int dp;

    if (isterm == null) {
      for (n--; n >= 0; n--) {
        dp = rates[n] - 1;
        if (dp >= 0 && (data[dp] == 0xFF)) {
          rates[n]--;
        }
      }
    } else {
      for (n--; n >= 0; n--) {
        if (!isterm[n]) {
          dp = rates[n] - 1;
          if (dp >= 0 && (data[dp] == 0xFF)) {
            rates[n]--;
          }
        }
      }
    }
  }

  @override
  int getPPX(int t, int c, int rl) {
    return pss.getPPX(t, c, rl);
  }

  @override
  int getPPY(int t, int c, int rl) {
    return pss.getPPY(t, c, rl);
  }

  @override
  bool precinctPartitionUsed(int c, int t) {
    return precinctPartition[c][t];
  }
}

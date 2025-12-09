import 'dart:math' as math;
import 'dart:typed_data';

import '../../image/Coord.dart';
import '../../util/ArrayUtil.dart';
import '../../util/FacilityManager.dart';
import '../../util/MsgLogger.dart';
import '../../StringSpec.dart';
import '../../quantization/quantizer/CBlkQuantDataSrcEnc.dart';
import '../../ModuleSpec.dart';
import '../CBlkSizeSpec.dart';
import '../PrecinctSizeSpec.dart';
import '../../wavelet/analysis/CBlkWTData.dart';
import '../../wavelet/subband.dart';
import 'CBlkRateDistStats.dart';
import 'EntropyCoder.dart';
import 'MqCoder.dart';
import 'BitToByteOutput.dart';
import 'ByteOutputBuffer.dart';
import '../StdEntropyCoderOptions.dart';

/// This class implements the JPEG 2000 entropy coder, which codes stripes in
/// code-blocks. This entropy coding engine is based on the MQ-coder, as
/// specified in the JPEG 2000 standard.
class StdEntropyCoder extends EntropyCoder {
  /// The identifier for the termination of each coding pass option
  static const int OPT_TERM_PASS = StdEntropyCoderOptions.OPT_TERM_PASS;

  /// The identifier for the reset MQ coder option
  static const int OPT_RESET_MQ = StdEntropyCoderOptions.OPT_RESET_MQ;

  /// The identifier for the vertically stripe causal context option
  static const int OPT_VERT_STR_CAUSAL = StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL;

  /// The identifier for the lazy coding mode option (bypass MQ coder)
  static const int OPT_BYPASS = StdEntropyCoderOptions.OPT_BYPASS;

  /// The identifier for the segmentation symbols option
  static const int OPT_SEG_SYMBOLS = StdEntropyCoderOptions.OPT_SEG_SYMBOLS;

  /// The identifier for the predictable termination option
  static const int OPT_PRED_TERM = StdEntropyCoderOptions.OPT_PRED_TERM;

  static const int NUM_NON_BYPASS_MS_BP =
      StdEntropyCoderOptions.NUM_NON_BYPASS_MS_BP;

  /// The mask for the significant state bit.
  static const int STATE_SIG_R1 = 1 << 15;

  /// The mask for the visited state bit.
  static const int STATE_VISITED_R1 = 1 << 14;

  /// The mask for the "non-zero context" state bit.
  static const int STATE_NZ_CTXT_R1 = 1 << 13;

  /// The mask for the "horizontal high-pass sign" state bit.
  static const int STATE_H_L_SIGN_R1 = 1 << 12;

  /// The mask for the "horizontal low-pass sign" state bit.
  static const int STATE_H_R_SIGN_R1 = 1 << 11;

  /// The mask for the "vertical high-pass sign" state bit.
  static const int STATE_V_U_SIGN_R1 = 1 << 10;

  /// The mask for the "vertical low-pass sign" state bit.
  static const int STATE_V_D_SIGN_R1 = 1 << 9;

  /// The mask for the "previous MR" state bit.
  static const int STATE_PREV_MR_R1 = 1 << 8;

  /// The mask for the "horizontal high-pass" state bit.
  static const int STATE_H_L_R1 = 1 << 7;

  /// The mask for the "horizontal low-pass" state bit.
  static const int STATE_H_R_R1 = 1 << 6;

  /// The mask for the "vertical high-pass" state bit.
  static const int STATE_V_U_R1 = 1 << 5;

  /// The mask for the "vertical low-pass" state bit.
  static const int STATE_V_D_R1 = 1 << 4;

  /// The mask for the "diagonal high-pass" state bit.
  static const int STATE_D_UL_R1 = 1 << 3;

  /// The mask for the "diagonal low-pass" state bit.
  static const int STATE_D_UR_R1 = 1 << 2;

  /// The mask for the "diagonal low-pass" state bit.
  static const int STATE_D_DL_R1 = 1 << 1;

  /// The mask for the "diagonal low-pass" state bit.
  static const int STATE_D_DR_R1 = 1;

  /// The separation between the row 1 and row 2 states.
  static const int STATE_SEP = 16;

  /// The mask for the significant state bit.
  static const int STATE_SIG_R2 = STATE_SIG_R1 << STATE_SEP;

  /// The mask for the visited state bit.
  static const int STATE_VISITED_R2 = STATE_VISITED_R1 << STATE_SEP;

  /// The mask for the "non-zero context" state bit.
  static const int STATE_NZ_CTXT_R2 = STATE_NZ_CTXT_R1 << STATE_SEP;

  /// The mask for the "horizontal high-pass sign" state bit.
  static const int STATE_H_L_SIGN_R2 = STATE_H_L_SIGN_R1 << STATE_SEP;

  /// The mask for the "horizontal low-pass sign" state bit.
  static const int STATE_H_R_SIGN_R2 = STATE_H_R_SIGN_R1 << STATE_SEP;

  /// The mask for the "vertical high-pass sign" state bit.
  static const int STATE_V_U_SIGN_R2 = STATE_V_U_SIGN_R1 << STATE_SEP;

  /// The mask for the "vertical low-pass sign" state bit.
  static const int STATE_V_D_SIGN_R2 = STATE_V_D_SIGN_R1 << STATE_SEP;

  /// The mask for the "previous MR" state bit.
  static const int STATE_PREV_MR_R2 = STATE_PREV_MR_R1 << STATE_SEP;

  /// The mask for the "horizontal high-pass" state bit.
  static const int STATE_H_L_R2 = STATE_H_L_R1 << STATE_SEP;

  /// The mask for the "horizontal low-pass" state bit.
  static const int STATE_H_R_R2 = STATE_H_R_R1 << STATE_SEP;

  /// The mask for the "vertical high-pass" state bit.
  static const int STATE_V_U_R2 = STATE_V_U_R1 << STATE_SEP;

  /// The mask for the "vertical low-pass" state bit.
  static const int STATE_V_D_R2 = STATE_V_D_R1 << STATE_SEP;

  /// The mask for the "diagonal high-pass" state bit.
  static const int STATE_D_UL_R2 = STATE_D_UL_R1 << STATE_SEP;

  /// The mask for the "diagonal low-pass" state bit.
  static const int STATE_D_UR_R2 = STATE_D_UR_R1 << STATE_SEP;

  /// The mask for the "diagonal low-pass" state bit.
  static const int STATE_D_DL_R2 = STATE_D_DL_R1 << STATE_SEP;

  /// The mask for the "diagonal low-pass" state bit.
  static const int STATE_D_DR_R2 = STATE_D_DR_R1 << STATE_SEP;

  /// The mask to isolate the significance bits for row 1 and 2 of the state
  /// array.
  static const int SIG_MASK_R1R2 = STATE_SIG_R1 | STATE_SIG_R2;

  /// The mask to isolate the visited bits for row 1 and 2 of the state
  /// array.
  static const int VSTD_MASK_R1R2 = STATE_VISITED_R1 | STATE_VISITED_R2;

  /// The mask to isolate the bits necessary to identify RLC coding state
  /// (significant, visited and non-zero context, for row 1 and 2).
  static const int RLC_MASK_R1R2 = STATE_SIG_R1 |
      STATE_SIG_R2 |
      STATE_VISITED_R1 |
      STATE_VISITED_R2 |
      STATE_NZ_CTXT_R1 |
      STATE_NZ_CTXT_R2;

  /// The mask to obtain the ZC_LUT index from the state information
  static const int ZC_MASK = (1 << 8) - 1;

  /// The shift to obtain the SC index to 'SC_LUT' from the state
  /// information, for row 1.
  static const int SC_SHIFT_R1 = 4;

  /// The shift to obtain the SC index to 'SC_LUT' from the state
  /// information, for row 2.
  static const int SC_SHIFT_R2 = SC_SHIFT_R1 + STATE_SEP;

  /// The number of bits used for the Sign Coding lookup table
  static const int SC_LUT_BITS = 9;

  /// The bit mask to isolate the state bits relative to the sign coding
  /// lookup table ('SC_LUT').
  static const int SC_MASK = (1 << SC_LUT_BITS) - 1;

  /// The number of bits used for the Magnitude Refinement lookup table
  static const int MR_LUT_BITS = 9;

  /// The mask to obtain the MR index to 'MR_LUT' from the 'state'
  /// information. It is to be applied after the 'MR_SHIFT'.
  static const int MR_MASK = (1 << MR_LUT_BITS) - 1;

  /// The number of bits used to index in the 'fm' lookup table, 7. The 'fs'
  /// table is indexed with one less bit.
  static const int MSE_LKP_BITS = 7;

  /// The number of fractional bits used to store data in the 'fm' and 'fs'
  /// lookup tables.
  static const int MSE_LKP_FRAC_BITS = 13;

  /// The stripe height.
  static const int STRIPE_HEIGHT = StdEntropyCoderOptions.STRIPE_HEIGHT;

  /// The context for the RLC coding.
  static const int RLC_CTXT = 1;

  /// The context for the uniform coding.
  static const int UNIF_CTXT = 0;

  /// The number of contexts used
  static const int NUM_CTXTS = 19;

  /// The sign bit for int data
  static const int INT_SIGN_BIT = 1 << 31;

  /// The initial states for the MQ coder
  static final List<int> MQ_INIT = [
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
  static final List<int> SEG_SYMBOLS = [1, 0, 1, 0];

  /// The 4 contexts for the error resilience segmentation symbol (always
  /// the UNIFORM context, UNIF_CTXT)
  static final List<int> SEG_SYMB_CTXTS = [
    UNIF_CTXT,
    UNIF_CTXT,
    UNIF_CTXT,
    UNIF_CTXT
  ];

  /// Number of bits used for the Zero Coding lookup table
  static const int ZC_LUT_BITS = 8;

  /// Zero Coding context lookup tables for the LH global orientation
  static final List<int> ZC_LUT_LH = List<int>.filled(1 << ZC_LUT_BITS, 0);

  /// Zero Coding context lookup tables for the HL global orientation
  static final List<int> ZC_LUT_HL = List<int>.filled(1 << ZC_LUT_BITS, 0);

  /// Zero Coding context lookup tables for the HH global orientation
  static final List<int> ZC_LUT_HH = List<int>.filled(1 << ZC_LUT_BITS, 0);

  /// Sign Coding context lookup table.
  static final List<int> SC_LUT = List<int>.filled(1 << SC_LUT_BITS, 0);

  /// The mask to obtain the context index from the 'SC_LUT'
  static const int SC_LUT_MASK = (1 << 4) - 1;

  /// The shift to obtain the sign predictor from the 'SC_LUT'. It must be
  /// an unsigned shift.
  static const int SC_SPRED_SHIFT = 31;

  /// Magnitude Refinement context lookup table
  static final List<int> MR_LUT = List<int>.filled(1 << MR_LUT_BITS, 0);

  /// Distortion estimation lookup table for bits coded using the sign-code
  /// (SC) primative, for lossy coding (i.e. normal).
  static final List<int> FS_LOSSY = List<int>.filled(1 << (MSE_LKP_BITS - 1), 0);

  /// Distortion estimation lookup table for bits coded using the
  /// magnitude-refinement (MR) primative, for lossy coding (i.e. normal)
  static final List<int> FM_LOSSY = List<int>.filled(1 << MSE_LKP_BITS, 0);

  /// Distortion estimation lookup table for bits coded using the sign-code
  /// (SC) primative, for lossless coding and last bit-plane.
  static final List<int> FS_LOSSLESS =
      List<int>.filled(1 << (MSE_LKP_BITS - 1), 0);

  /// Distortion estimation lookup table for bits coded using the
  /// magnitude-refinement (MR) primative, for lossless coding and last
  /// bit-plane.
  static final List<int> FM_LOSSLESS = List<int>.filled(1 << MSE_LKP_BITS, 0);

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
    List<int>? inter_sc_lut;
    int ds, us, rs, ls;
    int dsgn, usgn, rsgn, lsgn;
    int h, v;

    // Initialize the zero coding lookup tables

    // LH

    // - No neighbors significant
    ZC_LUT_LH[0] = 2;

    // - No horizontal or vertical neighbors significant
    for (i = 1; i < 16; i++) {
      // Two or more diagonal coeffs significant
      ZC_LUT_LH[i] = 4;
    }
    for (i = 0; i < 4; i++) {
      // Only one diagonal coeff significant
      ZC_LUT_LH[1 << i] = 3;
    }
    // - No horizontal neighbors significant, diagonal irrelevant
    for (i = 0; i < 16; i++) {
      // Only one vertical coeff significant
      ZC_LUT_LH[STATE_V_U_R1 | i] = 5;
      ZC_LUT_LH[STATE_V_D_R1 | i] = 5;
      // The two vertical coeffs significant
      ZC_LUT_LH[STATE_V_U_R1 | STATE_V_D_R1 | i] = 6;
    }
    // - One horiz. neighbor significant, diagonal/vertical non-significant
    ZC_LUT_LH[STATE_H_L_R1] = 7;
    ZC_LUT_LH[STATE_H_R_R1] = 7;
    // - One horiz. significant, no vertical significant, one or more
    // diagonal significant
    for (i = 1; i < 16; i++) {
      ZC_LUT_LH[STATE_H_L_R1 | i] = 8;
      ZC_LUT_LH[STATE_H_R_R1 | i] = 8;
    }
    // - One horiz. significant, one or more vertical significant,
    // diagonal irrelevant
    for (i = 1; i < 4; i++) {
      for (j = 0; j < 16; j++) {
        ZC_LUT_LH[STATE_H_L_R1 | (i << 4) | j] = 9;
        ZC_LUT_LH[STATE_H_R_R1 | (i << 4) | j] = 9;
      }
    }
    // - Two horiz. significant, others irrelevant
    for (i = 0; i < 64; i++) {
      ZC_LUT_LH[STATE_H_L_R1 | STATE_H_R_R1 | i] = 10;
    }

    // HL

    // - No neighbors significant
    ZC_LUT_HL[0] = 2;
    // - No horizontal or vertical neighbors significant
    for (i = 1; i < 16; i++) {
      // Two or more diagonal coeffs significant
      ZC_LUT_HL[i] = 4;
    }
    for (i = 0; i < 4; i++) {
      // Only one diagonal coeff significant
      ZC_LUT_HL[1 << i] = 3;
    }
    // - No vertical significant, diagonal irrelevant
    for (i = 0; i < 16; i++) {
      // One horiz. significant
      ZC_LUT_HL[STATE_H_L_R1 | i] = 5;
      ZC_LUT_HL[STATE_H_R_R1 | i] = 5;
      // Two horiz. significant
      ZC_LUT_HL[STATE_H_L_R1 | STATE_H_R_R1 | i] = 6;
    }
    // - One vert. significant, diagonal/horizontal non-significant
    ZC_LUT_HL[STATE_V_U_R1] = 7;
    ZC_LUT_HL[STATE_V_D_R1] = 7;
    // - One vert. significant, horizontal non-significant, one or more
    // diag. significant
    for (i = 1; i < 16; i++) {
      ZC_LUT_HL[STATE_V_U_R1 | i] = 8;
      ZC_LUT_HL[STATE_V_D_R1 | i] = 8;
    }
    // - One vertical significant, one or more horizontal significant,
    // diagonal irrelevant
    for (i = 1; i < 4; i++) {
      for (j = 0; j < 16; j++) {
        ZC_LUT_HL[(i << 6) | STATE_V_U_R1 | j] = 9;
        ZC_LUT_HL[(i << 6) | STATE_V_D_R1 | j] = 9;
      }
    }
    // - Two vertical significant, others irrelevant
    for (i = 0; i < 4; i++) {
      for (j = 0; j < 16; j++) {
        ZC_LUT_HL[(i << 6) | STATE_V_U_R1 | STATE_V_D_R1 | j] = 10;
      }
    }

    // HH
    List<int> twoBits = [3, 5, 6, 9, 10, 12];
    List<int> oneBit = [1, 2, 4, 8];
    List<int> twoLeast = [3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15];
    List<int> threeLeast = [7, 11, 13, 14, 15];

    // - None significant
    ZC_LUT_HH[0] = 2;

    // - One horizontal+vertical significant, none diagonal
    for (i = 0; i < oneBit.length; i++) {
      ZC_LUT_HH[oneBit[i] << 4] = 3;
    }

    // - Two or more horizontal+vertical significant, diagonal non-signif
    for (i = 0; i < twoLeast.length; i++) {
      ZC_LUT_HH[twoLeast[i] << 4] = 4;
    }

    // - One diagonal significant, horiz./vert. non-significant
    for (i = 0; i < oneBit.length; i++) {
      ZC_LUT_HH[oneBit[i]] = 5;
    }

    // - One diagonal significant, one horiz.+vert. significant
    for (i = 0; i < oneBit.length; i++) {
      for (j = 0; j < oneBit.length; j++) {
        ZC_LUT_HH[(oneBit[i] << 4) | oneBit[j]] = 6;
      }
    }

    // - One diag signif, two or more horiz+vert signif
    for (i = 0; i < twoLeast.length; i++) {
      for (j = 0; j < oneBit.length; j++) {
        ZC_LUT_HH[(twoLeast[i] << 4) | oneBit[j]] = 7;
      }
    }

    // - Two diagonal significant, none horiz+vert significant
    for (i = 0; i < twoBits.length; i++) {
      ZC_LUT_HH[twoBits[i]] = 8;
    }

    // - Two diagonal significant, one or more horiz+vert significant
    for (j = 0; j < twoBits.length; j++) {
      for (i = 1; i < 16; i++) {
        ZC_LUT_HH[(i << 4) | twoBits[j]] = 9;
      }
    }

    // - Three or more diagonal significant, horiz+vert irrelevant
    for (i = 0; i < 16; i++) {
      for (j = 0; j < threeLeast.length; j++) {
        ZC_LUT_HH[(i << 4) | threeLeast[j]] = 10;
      }
    }

    // Initialize the SC lookup tables
    inter_sc_lut = List<int>.filled(36, 0);
    inter_sc_lut[(2 << 3) | 2] = 15;
    inter_sc_lut[(2 << 3) | 1] = 14;
    inter_sc_lut[(2 << 3) | 0] = 13;
    inter_sc_lut[(1 << 3) | 2] = 12;
    inter_sc_lut[(1 << 3) | 1] = 11;
    inter_sc_lut[(1 << 3) | 0] = 12 | INT_SIGN_BIT;
    inter_sc_lut[(0 << 3) | 2] = 13 | INT_SIGN_BIT;
    inter_sc_lut[(0 << 3) | 1] = 14 | INT_SIGN_BIT;
    inter_sc_lut[(0 << 3) | 0] = 15 | INT_SIGN_BIT;

    for (i = 0; i < (1 << SC_LUT_BITS) - 1; i++) {
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

      SC_LUT[i] = inter_sc_lut[(h + 1) << 3 | (v + 1)];
    }
    inter_sc_lut = null;

    // Initialize the MR lookup tables
    MR_LUT[0] = 16;
    for (i = 1; i < (1 << (MR_LUT_BITS - 1)); i++) {
      MR_LUT[i] = 17;
    }
    for (; i < (1 << MR_LUT_BITS); i++) {
      MR_LUT[i] = 18;
    }

    // Initialize the distortion estimation lookup tables
    for (i = 0; i < (1 << (MSE_LKP_BITS - 1)); i++) {
      val = i.toDouble() / (1 << (MSE_LKP_BITS - 1)) + 1.0;
      deltaMSE = val * val;
      FS_LOSSLESS[i] =
          (deltaMSE * ((1 << MSE_LKP_FRAC_BITS).toDouble()) + 0.5).floor();
      val -= 1.5;
      deltaMSE -= val * val;
      FS_LOSSY[i] =
          (deltaMSE * ((1 << MSE_LKP_FRAC_BITS).toDouble()) + 0.5).floor();
    }

    for (i = 0; i < (1 << MSE_LKP_BITS); i++) {
      val = i.toDouble() / (1 << (MSE_LKP_BITS - 1));
      deltaMSE = (val - 1.0) * (val - 1.0);
      FM_LOSSLESS[i] =
          (deltaMSE * ((1 << MSE_LKP_FRAC_BITS).toDouble()) + 0.5).floor();
      val -= (i < (1 << (MSE_LKP_BITS - 1))) ? 0.5 : 1.5;
      deltaMSE -= val * val;
      FM_LOSSY[i] =
          (deltaMSE * ((1 << MSE_LKP_FRAC_BITS).toDouble()) + 0.5).floor();
    }
  }

  StdEntropyCoder(
      CBlkQuantDataSrcEnc src,
      this.cblks,
      this.pss,
      this.bms,
      this.mqrs,
      this.rts,
      this.css,
      this.sss,
      this.lcs,
      this.tts)
      : super(src) {
    _staticInit();
    int maxCBlkWidth, maxCBlkHeight;
    int tsl = 1; // Single threaded

    maxCBlkWidth = cblks.getMaxCBlkWidth();
    maxCBlkHeight = cblks.getMaxCBlkHeight();

    outT = List.generate(tsl, (_) => ByteOutputBuffer());
    mqT = List.generate(tsl, (idx) => MQCoder(outT[idx], NUM_CTXTS, MQ_INIT));
    boutT = List.filled(tsl, null);
    stateT = List.generate(
        tsl,
        (_) => List<int>.filled(
            (maxCBlkWidth + 2) * ((maxCBlkHeight + 1) ~/ 2 + 2), 0));
    symbufT = List.generate(
        tsl, (_) => List<int>.filled(maxCBlkWidth * (STRIPE_HEIGHT * 2 + 2), 0));
    ctxtbufT = List.generate(
        tsl, (_) => List<int>.filled(maxCBlkWidth * (STRIPE_HEIGHT * 2 + 2), 0));
    distbufT =
        List.generate(tsl, (_) => List<double>.filled(32 * StdEntropyCoderOptions.NUM_PASSES, 0.0));
    ratebufT = List.generate(tsl, (_) => List<int>.filled(32 * StdEntropyCoderOptions.NUM_PASSES, 0));
    istermbufT =
        List.generate(tsl, (_) => List<bool>.filled(32 * StdEntropyCoderOptions.NUM_PASSES, false));
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
    return cblks.getCBlkWidth(ModuleSpec.SPEC_TILE_COMP, t, c);
  }

  @override
  int getCBlkHeight(int t, int c) {
    return cblks.getCBlkHeight(ModuleSpec.SPEC_TILE_COMP, t, c);
  }

  @override
  CBlkRateDistStats? getNextCodeBlock(int c, CBlkRateDistStats? ccb) {
    // Single threaded implementation
    srcblkT[0] = src.getNextInternCodeBlock(c, srcblkT[0]);

    if (srcblkT[0] == null) {
      return null;
    }

    final tIdx = getTileIdx();

    if ((opts[tIdx][c] & OPT_BYPASS) != 0 && boutT[0] == null) {
      boutT[0] = BitToByteOutput(outT[0]);
    }

    if (ccb == null) {
      ccb = CBlkRateDistStats();
    }

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
          opts[t][c] |= OPT_BYPASS;
        }
        if ((mqrs.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= OPT_RESET_MQ;
        }
        if ((rts.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= OPT_TERM_PASS;
        }
        if ((css.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= OPT_VERT_STR_CAUSAL;
        }
        if ((sss.getTileCompVal(t, c) as String).toLowerCase() == "on") {
          opts[t][c] |= OPT_SEG_SYMBOLS;
        }

        String lCalcType = lcs.getTileCompVal(t, c) as String;
        if (lCalcType == "near_opt") {
          lenCalc[t][c] = MQCoder.LENGTH_NEAR_OPT;
        } else if (lCalcType == "lazy_good") {
          lenCalc[t][c] = MQCoder.LENGTH_LAZY_GOOD;
        } else if (lCalcType == "lazy") {
          lenCalc[t][c] = MQCoder.LENGTH_LAZY;
        } else {
          throw ArgumentError("Unrecognized or unsupported MQ length calculation.");
        }

        String termType = tts.getTileCompVal(t, c) as String;
        if (termType.toLowerCase() == "easy") {
          tType[t][c] = MQCoder.TERM_EASY;
        } else if (termType.toLowerCase() == "full") {
          tType[t][c] = MQCoder.TERM_FULL;
        } else if (termType.toLowerCase() == "near_opt") {
          tType[t][c] = MQCoder.TERM_NEAR_OPT;
        } else if (termType.toLowerCase() == "predict") {
          tType[t][c] = MQCoder.TERM_PRED_ER;
          opts[t][c] |= OPT_PRED_TERM;
          if ((opts[t][c] & (OPT_TERM_PASS | OPT_BYPASS)) == 0) {
            FacilityManager.getMsgLogger().printmsg(
                MsgLogger.info,
                "Using error resilient MQ termination, but terminating only at "
                "the end of code-blocks. The error protection offered by this "
                "option will be very weak. Specify the 'Cterminate' and/or "
                "'Cbypass' option for increased error resilience.");
          }
        } else {
          throw ArgumentError("Unrecognized or unsupported MQ coder termination.");
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
    List<int> zc_lut;
    int skipbp;
    int curbp;
    List<int> fm;
    List<int> fs;
    int lmb;
    int npass;
    double msew;
    double totdist;
    int ltpidx;

    if ((options & OPT_PRED_TERM) != 0 && tType != MQCoder.TERM_PRED_ER) {
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
        zc_lut = ZC_LUT_HL;
        break;
      case Subband.wtOrientLl:
      case Subband.wtOrientLh:
        zc_lut = ZC_LUT_LH;
        break;
      case Subband.wtOrientHh:
        zc_lut = ZC_LUT_HH;
        break;
      default:
        throw Error();
    }

    curbp = 30 - skipbp;
    fs = FS_LOSSY;
    fm = FM_LOSSY;
    msew = math.pow(2, ((curbp - lmb) << 1) - MSE_LKP_FRAC_BITS) *
        srcblk.sb!.stepWMSE *
        srcblk.wmseScaling;
    totdist = 0.0;
    npass = 0;
    ltpidx = -1;

    if (curbp >= lmb) {
      if (rev && curbp == lmb) {
        fs = FM_LOSSLESS;
      }
      istermbuf[npass] = (options & OPT_TERM_PASS) != 0 ||
          curbp == lmb ||
          ((options & OPT_BYPASS) != 0 &&
              (31 - NUM_NON_BYPASS_MS_BP - skipbp) >= curbp);
      totdist += cleanuppass(srcblk, mq, istermbuf[npass], curbp, state, fs,
              zc_lut, symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
          msew;
      distbuf[npass] = totdist;
      if (istermbuf[npass]) ltpidx = npass;
      npass++;
      msew *= 0.25;
      curbp--;
    }

    while (curbp >= lmb) {
      if (rev && curbp == lmb) {
        fs = FS_LOSSLESS;
        fm = FM_LOSSLESS;
      }

      istermbuf[npass] = (options & OPT_TERM_PASS) != 0;
      if ((options & OPT_BYPASS) == 0 ||
          (31 - NUM_NON_BYPASS_MS_BP - skipbp <= curbp)) {
        totdist += sigProgPass(srcblk, mq, istermbuf[npass], curbp, state, fs,
                zc_lut, symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
            msew;
      } else {
        bout!.setPredTerm((options & OPT_PRED_TERM) != 0);
        totdist += rawSigProgPass(srcblk, bout, istermbuf[npass], curbp, state,
                fs, ratebuf, npass, ltpidx, options) *
            msew;
      }
      distbuf[npass] = totdist;
      if (istermbuf[npass]) ltpidx = npass;
      npass++;

      istermbuf[npass] = (options & OPT_TERM_PASS) != 0 ||
          ((options & OPT_BYPASS) != 0 &&
              (31 - NUM_NON_BYPASS_MS_BP - skipbp > curbp));
      if ((options & OPT_BYPASS) == 0 ||
          (31 - NUM_NON_BYPASS_MS_BP - skipbp <= curbp)) {
        totdist += magRefPass(srcblk, mq, istermbuf[npass], curbp, state, fm,
                symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
            msew;
      } else {
        bout!.setPredTerm((options & OPT_PRED_TERM) != 0);
        totdist += rawMagRefPass(srcblk, bout, istermbuf[npass], curbp, state,
                fm, ratebuf, npass, ltpidx, options) *
            msew;
      }
      distbuf[npass] = totdist;
      if (istermbuf[npass]) ltpidx = npass;
      npass++;

      istermbuf[npass] = (options & OPT_TERM_PASS) != 0 ||
          curbp == lmb ||
          ((options & OPT_BYPASS) != 0 &&
              (31 - NUM_NON_BYPASS_MS_BP - skipbp) >= curbp);
      totdist += cleanuppass(srcblk, mq, istermbuf[npass], curbp, state, fs,
              zc_lut, symbuf, ctxtbuf, ratebuf, npass, ltpidx, options) *
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
        (options & (OPT_BYPASS | OPT_TERM_PASS)) != 0 ? istermbuf : null,
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
      List<int> zc_lut,
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
    int off_ul, off_ur, off_dr, off_dl;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * STRIPE_HEIGHT ~/ 2 - srcblk.w;
    kstep = dscanw * STRIPE_HEIGHT - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + STRIPE_HEIGHT - 1) ~/ STRIPE_HEIGHT;
    dist = 0;
    shift = bp - (MSE_LKP_BITS - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;
    causal = (options & OPT_VERT_STR_CAUSAL) != 0;

    off_ul = -sscanw - 1;
    off_ur = -sscanw + 1;
    off_dr = sscanw + 1;
    off_dl = sscanw - 1;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight = (s != 0)
          ? STRIPE_HEIGHT
          : srcblk.h - (nstripes - 1) * STRIPE_HEIGHT;
      stopsk = sk + srcblk.w;
      for (nsym = 0; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & SIG_MASK_R1R2) != 0) {
          k = sk;
          if ((csj & (STATE_SIG_R1 | STATE_NZ_CTXT_R1)) == STATE_NZ_CTXT_R1) {
            ctxtbuf[nsym] = zc_lut[csj & ZC_MASK];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = data[k] >> 31;
              ctxt = SC_LUT[(csj >> SC_SHIFT_R1) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              if (!causal) {
                state[j + off_ul] |= STATE_NZ_CTXT_R2 | STATE_D_DR_R2;
                state[j + off_ur] |= STATE_NZ_CTXT_R2 | STATE_D_DL_R2;
              }
              if (sym != 0) {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2 |
                    STATE_V_U_SIGN_R2;
                if (!causal) {
                  state[j - sscanw] |=
                      STATE_NZ_CTXT_R2 | STATE_V_D_R2 | STATE_V_D_SIGN_R2;
                }
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_H_L_SIGN_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_H_R_SIGN_R1 |
                    STATE_D_UR_R2;
              } else {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2;
                if (!causal) {
                  state[j - sscanw] |= STATE_NZ_CTXT_R2 | STATE_V_D_R2;
                }
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_D_UR_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R1;
            }
          }
          if (sheight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (STATE_SIG_R2 | STATE_NZ_CTXT_R2)) == STATE_NZ_CTXT_R2) {
            k += dscanw;
            ctxtbuf[nsym] = zc_lut[(csj >> STATE_SEP) & ZC_MASK];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = data[k] >> 31;
              ctxt = SC_LUT[(csj >> SC_SHIFT_R2) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              state[j + off_dl] |= STATE_NZ_CTXT_R1 | STATE_D_UR_R1;
              state[j + off_dr] |= STATE_NZ_CTXT_R1 | STATE_D_UL_R1;
              if (sym != 0) {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1 |
                    STATE_V_D_SIGN_R1;
                state[j + sscanw] |=
                    STATE_NZ_CTXT_R1 | STATE_V_U_R1 | STATE_V_U_SIGN_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2 |
                    STATE_H_L_SIGN_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2 |
                    STATE_H_R_SIGN_R2;
              } else {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1;
                state[j + sscanw] |= STATE_NZ_CTXT_R1 | STATE_V_U_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R2;
            }
          }
          state[j] = csj;
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & SIG_MASK_R1R2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (STATE_SIG_R1 | STATE_NZ_CTXT_R1)) == STATE_NZ_CTXT_R1) {
            ctxtbuf[nsym] = zc_lut[csj & ZC_MASK];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = data[k] >> 31;
              ctxt = SC_LUT[(csj >> SC_SHIFT_R1) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              state[j + off_ul] |= STATE_NZ_CTXT_R2 | STATE_D_DR_R2;
              state[j + off_ur] |= STATE_NZ_CTXT_R2 | STATE_D_DL_R2;
              if (sym != 0) {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2 |
                    STATE_V_U_SIGN_R2;
                state[j - sscanw] |=
                    STATE_NZ_CTXT_R2 | STATE_V_D_R2 | STATE_V_D_SIGN_R2;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_H_L_SIGN_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_H_R_SIGN_R1 |
                    STATE_D_UR_R2;
              } else {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2;
                state[j - sscanw] |= STATE_NZ_CTXT_R2 | STATE_V_D_R2;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_D_UR_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R1;
            }
          }
          if (sheight < 4) {
            state[j] = csj;
            continue;
          }
          if ((csj & (STATE_SIG_R2 | STATE_NZ_CTXT_R2)) == STATE_NZ_CTXT_R2) {
            k += dscanw;
            ctxtbuf[nsym] = zc_lut[(csj >> STATE_SEP) & ZC_MASK];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = data[k] >> 31;
              ctxt = SC_LUT[(csj >> SC_SHIFT_R2) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              state[j + off_dl] |= STATE_NZ_CTXT_R1 | STATE_D_UR_R1;
              state[j + off_dr] |= STATE_NZ_CTXT_R1 | STATE_D_UL_R1;
              if (sym != 0) {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1 |
                    STATE_V_D_SIGN_R1;
                state[j + sscanw] |=
                    STATE_NZ_CTXT_R1 | STATE_V_U_R1 | STATE_V_U_SIGN_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2 |
                    STATE_H_L_SIGN_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2 |
                    STATE_H_R_SIGN_R2;
              } else {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1;
                state[j + sscanw] |= STATE_NZ_CTXT_R1 | STATE_V_U_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R2;
            }
          }
          state[j] = csj;
        }
      }
      mq.codeSymbols(symbuf, ctxtbuf, nsym);
    }

    if ((options & OPT_RESET_MQ) != 0) {
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
    int off_ul, off_ur, off_dr, off_dl;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * STRIPE_HEIGHT ~/ 2 - srcblk.w;
    kstep = dscanw * STRIPE_HEIGHT - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + STRIPE_HEIGHT - 1) ~/ STRIPE_HEIGHT;
    dist = 0;
    shift = bp - (MSE_LKP_BITS - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;
    causal = (options & OPT_VERT_STR_CAUSAL) != 0;

    off_ul = -sscanw - 1;
    off_ur = -sscanw + 1;
    off_dr = sscanw + 1;
    off_dl = sscanw - 1;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight = (s != 0)
          ? STRIPE_HEIGHT
          : srcblk.h - (nstripes - 1) * STRIPE_HEIGHT;
      stopsk = sk + srcblk.w;
      for (; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & SIG_MASK_R1R2) != 0) {
          k = sk;
          if ((csj & (STATE_SIG_R1 | STATE_NZ_CTXT_R1)) == STATE_NZ_CTXT_R1) {
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = data[k] >> 31;
              bout.writeBit(sym);
              if (!causal) {
                state[j + off_ul] |= STATE_NZ_CTXT_R2 | STATE_D_DR_R2;
                state[j + off_ur] |= STATE_NZ_CTXT_R2 | STATE_D_DL_R2;
              }
              if (sym != 0) {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2 |
                    STATE_V_U_SIGN_R2;
                if (!causal) {
                  state[j - sscanw] |=
                      STATE_NZ_CTXT_R2 | STATE_V_D_R2 | STATE_V_D_SIGN_R2;
                }
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_H_L_SIGN_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_H_R_SIGN_R1 |
                    STATE_D_UR_R2;
              } else {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2;
                if (!causal) {
                  state[j - sscanw] |= STATE_NZ_CTXT_R2 | STATE_V_D_R2;
                }
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_D_UR_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R1;
            }
          }
          if (sheight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (STATE_SIG_R2 | STATE_NZ_CTXT_R2)) == STATE_NZ_CTXT_R2) {
            k += dscanw;
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = data[k] >> 31;
              bout.writeBit(sym);
              state[j + off_dl] |= STATE_NZ_CTXT_R1 | STATE_D_UR_R1;
              state[j + off_dr] |= STATE_NZ_CTXT_R1 | STATE_D_UL_R1;
              if (sym != 0) {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1 |
                    STATE_V_D_SIGN_R1;
                state[j + sscanw] |=
                    STATE_NZ_CTXT_R1 | STATE_V_U_R1 | STATE_V_U_SIGN_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2 |
                    STATE_H_L_SIGN_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2 |
                    STATE_H_R_SIGN_R2;
              } else {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1;
                state[j + sscanw] |= STATE_NZ_CTXT_R1 | STATE_V_U_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R2;
            }
          }
          state[j] = csj;
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((~csj) & (csj << 2)) & SIG_MASK_R1R2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (STATE_SIG_R1 | STATE_NZ_CTXT_R1)) == STATE_NZ_CTXT_R1) {
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = data[k] >> 31;
              bout.writeBit(sym);
              state[j + off_ul] |= STATE_NZ_CTXT_R2 | STATE_D_DR_R2;
              state[j + off_ur] |= STATE_NZ_CTXT_R2 | STATE_D_DL_R2;
              if (sym != 0) {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2 |
                    STATE_V_U_SIGN_R2;
                state[j - sscanw] |=
                    STATE_NZ_CTXT_R2 | STATE_V_D_R2 | STATE_V_D_SIGN_R2;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_H_L_SIGN_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_H_R_SIGN_R1 |
                    STATE_D_UR_R2;
              } else {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2;
                state[j - sscanw] |= STATE_NZ_CTXT_R2 | STATE_V_D_R2;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_D_UR_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R1;
            }
          }
          if (sheight < 4) {
            state[j] = csj;
            continue;
          }
          if ((csj & (STATE_SIG_R2 | STATE_NZ_CTXT_R2)) == STATE_NZ_CTXT_R2) {
            k += dscanw;
            if ((sym = (data[k] & mask) >> bp) != 0) {
              bout.writeBit(sym);
              sym = data[k] >> 31;
              bout.writeBit(sym);
              state[j + off_dl] |= STATE_NZ_CTXT_R1 | STATE_D_UR_R1;
              state[j + off_dr] |= STATE_NZ_CTXT_R1 | STATE_D_UL_R1;
              if (sym != 0) {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1 |
                    STATE_V_D_SIGN_R1;
                state[j + sscanw] |=
                    STATE_NZ_CTXT_R1 | STATE_V_U_R1 | STATE_V_U_SIGN_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2 |
                    STATE_H_L_SIGN_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2 |
                    STATE_H_R_SIGN_R2;
              } else {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1;
                state[j + sscanw] |= STATE_NZ_CTXT_R1 | STATE_V_U_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            } else {
              csj |= STATE_VISITED_R2;
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
    jstep = sscanw * STRIPE_HEIGHT ~/ 2 - srcblk.w;
    kstep = dscanw * STRIPE_HEIGHT - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + STRIPE_HEIGHT - 1) ~/ STRIPE_HEIGHT;
    dist = 0;
    shift = bp - (MSE_LKP_BITS - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight = (s != 0)
          ? STRIPE_HEIGHT
          : srcblk.h - (nstripes - 1) * STRIPE_HEIGHT;
      stopsk = sk + srcblk.w;
      for (nsym = 0; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & VSTD_MASK_R1R2) != 0) {
          k = sk;
          if ((csj & (STATE_SIG_R1 | STATE_VISITED_R1)) == STATE_SIG_R1) {
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = MR_LUT[csj & MR_MASK];
            csj |= STATE_PREV_MR_R1;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
          }
          if (sheight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (STATE_SIG_R2 | STATE_VISITED_R2)) == STATE_SIG_R2) {
            k += dscanw;
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = MR_LUT[(csj >> STATE_SEP) & MR_MASK];
            csj |= STATE_PREV_MR_R2;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
          }
          state[j] = csj;
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & VSTD_MASK_R1R2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (STATE_SIG_R1 | STATE_VISITED_R1)) == STATE_SIG_R1) {
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = MR_LUT[csj & MR_MASK];
            csj |= STATE_PREV_MR_R1;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
          }
          if (sheight < 4) {
            state[j] = csj;
            continue;
          }
          if ((state[j] & (STATE_SIG_R2 | STATE_VISITED_R2)) == STATE_SIG_R2) {
            k += dscanw;
            symbuf[nsym] = (data[k] & mask) >> bp;
            ctxtbuf[nsym++] = MR_LUT[(csj >> STATE_SEP) & MR_MASK];
            csj |= STATE_PREV_MR_R2;
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
          }
          state[j] = csj;
        }
      }
      if (nsym > 0) mq.codeSymbols(symbuf, ctxtbuf, nsym);
    }

    if ((options & OPT_RESET_MQ) != 0) {
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
    jstep = sscanw * STRIPE_HEIGHT ~/ 2 - srcblk.w;
    kstep = dscanw * STRIPE_HEIGHT - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + STRIPE_HEIGHT - 1) ~/ STRIPE_HEIGHT;
    dist = 0;
    shift = bp - (MSE_LKP_BITS - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight = (s != 0)
          ? STRIPE_HEIGHT
          : srcblk.h - (nstripes - 1) * STRIPE_HEIGHT;
      stopsk = sk + srcblk.w;
      for (; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & VSTD_MASK_R1R2) != 0) {
          k = sk;
          if ((csj & (STATE_SIG_R1 | STATE_VISITED_R1)) == STATE_SIG_R1) {
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
          }
          if (sheight < 2) continue;
          if ((csj & (STATE_SIG_R2 | STATE_VISITED_R2)) == STATE_SIG_R2) {
            k += dscanw;
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
          }
        }
        if (sheight < 3) continue;
        j += sscanw;
        csj = state[j];
        if ((((csj >> 1) & (~csj)) & VSTD_MASK_R1R2) != 0) {
          k = sk + (dscanw << 1);
          if ((csj & (STATE_SIG_R1 | STATE_VISITED_R1)) == STATE_SIG_R1) {
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
          }
          if (sheight < 4) continue;
          if ((state[j] & (STATE_SIG_R2 | STATE_VISITED_R2)) == STATE_SIG_R2) {
            k += dscanw;
            bout.writeBit((data[k] & mask) >> bp);
            normval = (data[k] >> downshift) << upshift;
            dist += fm[normval & ((1 << MSE_LKP_BITS) - 1)];
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
      List<int> zc_lut,
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
    int off_ul, off_ur, off_dr, off_dl;

    dscanw = srcblk.scanw;
    sscanw = srcblk.w + 2;
    jstep = sscanw * STRIPE_HEIGHT ~/ 2 - srcblk.w;
    kstep = dscanw * STRIPE_HEIGHT - srcblk.w;
    mask = 1 << bp;
    data = srcblk.getData() as List<int>;
    nstripes = (srcblk.h + STRIPE_HEIGHT - 1) ~/ STRIPE_HEIGHT;
    dist = 0;
    shift = bp - (MSE_LKP_BITS - 1);
    upshift = (shift >= 0) ? 0 : -shift;
    downshift = (shift <= 0) ? 0 : shift;
    causal = (options & OPT_VERT_STR_CAUSAL) != 0;

    off_ul = -sscanw - 1;
    off_ur = -sscanw + 1;
    off_dr = sscanw + 1;
    off_dl = sscanw - 1;

    sk = srcblk.offset;
    sj = sscanw + 1;
    for (s = nstripes - 1; s >= 0; s--, sk += kstep, sj += jstep) {
      sheight = (s != 0)
          ? STRIPE_HEIGHT
          : srcblk.h - (nstripes - 1) * STRIPE_HEIGHT;
      stopsk = sk + srcblk.w;
      for (nsym = 0; sk < stopsk; sk++, sj++) {
        j = sj;
        csj = state[j];
        bool broken = false;

        // top_half:
        {
          if (csj == 0 && state[j + sscanw] == 0 && sheight == STRIPE_HEIGHT) {
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
              ctxtbuf[nsym++] = RLC_CTXT;
              continue;
            }
            symbuf[nsym] = 1;
            ctxtbuf[nsym++] = RLC_CTXT;
            symbuf[nsym] = rlclen >> 1;
            ctxtbuf[nsym++] = UNIF_CTXT;
            symbuf[nsym] = rlclen & 0x01;
            ctxtbuf[nsym++] = UNIF_CTXT;
            normval = (data[k] >> downshift) << upshift;
            dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            sym = data[k] >> 31;
            if ((rlclen & 0x01) == 0) {
              ctxt = SC_LUT[(csj >> SC_SHIFT_R1) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              if (rlclen != 0 || !causal) {
                state[j + off_ul] |= STATE_NZ_CTXT_R2 | STATE_D_DR_R2;
                state[j + off_ur] |= STATE_NZ_CTXT_R2 | STATE_D_DL_R2;
              }
              if (sym != 0) {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2 |
                    STATE_V_U_SIGN_R2;
                if (rlclen != 0 || !causal) {
                  state[j - sscanw] |=
                      STATE_NZ_CTXT_R2 | STATE_V_D_R2 | STATE_V_D_SIGN_R2;
                }
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_H_L_SIGN_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_H_R_SIGN_R1 |
                    STATE_D_UR_R2;
              } else {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2;
                if (rlclen != 0 || !causal) {
                  state[j - sscanw] |= STATE_NZ_CTXT_R2 | STATE_V_D_R2;
                }
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_D_UR_R2;
              }
              if ((rlclen >> 1) != 0) {
                broken = true;
              }
            } else {
              ctxt = SC_LUT[(csj >> SC_SHIFT_R2) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              state[j + off_dl] |= STATE_NZ_CTXT_R1 | STATE_D_UR_R1;
              state[j + off_dr] |= STATE_NZ_CTXT_R1 | STATE_D_UL_R1;
              if (sym != 0) {
                csj |= STATE_SIG_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1 |
                    STATE_V_D_SIGN_R1;
                state[j + sscanw] |=
                    STATE_NZ_CTXT_R1 | STATE_V_U_R1 | STATE_V_U_SIGN_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2 |
                    STATE_H_L_SIGN_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2 |
                    STATE_H_R_SIGN_R2;
              } else {
                csj |= STATE_SIG_R2 | STATE_NZ_CTXT_R1 | STATE_V_D_R1;
                state[j + sscanw] |= STATE_NZ_CTXT_R1 | STATE_V_U_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2;
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
          if ((((csj >> 1) | csj) & VSTD_MASK_R1R2) != VSTD_MASK_R1R2) {
            k = sk;
            if ((csj & (STATE_SIG_R1 | STATE_VISITED_R1)) == 0) {
              ctxtbuf[nsym] = zc_lut[csj & ZC_MASK];
              if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
                sym = data[k] >> 31;
                ctxt = SC_LUT[(csj >> SC_SHIFT_R1) & SC_MASK];
                symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
                ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
                if (!causal) {
                  state[j + off_ul] |= STATE_NZ_CTXT_R2 | STATE_D_DR_R2;
                  state[j + off_ur] |= STATE_NZ_CTXT_R2 | STATE_D_DL_R2;
                }
                if (sym != 0) {
                  csj |= STATE_SIG_R1 |
                      STATE_VISITED_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_V_U_R2 |
                      STATE_V_U_SIGN_R2;
                  if (!causal) {
                    state[j - sscanw] |=
                        STATE_NZ_CTXT_R2 | STATE_V_D_R2 | STATE_V_D_SIGN_R2;
                  }
                  state[j + 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_H_L_R1 |
                      STATE_H_L_SIGN_R1 |
                      STATE_D_UL_R2;
                  state[j - 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_H_R_R1 |
                      STATE_H_R_SIGN_R1 |
                      STATE_D_UR_R2;
                } else {
                  csj |= STATE_SIG_R1 |
                      STATE_VISITED_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_V_U_R2;
                  if (!causal) {
                    state[j - sscanw] |= STATE_NZ_CTXT_R2 | STATE_V_D_R2;
                  }
                  state[j + 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_H_L_R1 |
                      STATE_D_UL_R2;
                  state[j - 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_H_R_R1 |
                      STATE_D_UR_R2;
                }
                normval = (data[k] >> downshift) << upshift;
                dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
              }
            }
            if (sheight < 2) {
              csj &= ~(STATE_VISITED_R1 | STATE_VISITED_R2);
              state[j] = csj;
              continue;
            }
            if ((csj & (STATE_SIG_R2 | STATE_VISITED_R2)) == 0) {
              k += dscanw;
              ctxtbuf[nsym] = zc_lut[(csj >> STATE_SEP) & ZC_MASK];
              if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
                sym = data[k] >> 31;
                ctxt = SC_LUT[(csj >> SC_SHIFT_R2) & SC_MASK];
                symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
                ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
                state[j + off_dl] |= STATE_NZ_CTXT_R1 | STATE_D_UR_R1;
                state[j + off_dr] |= STATE_NZ_CTXT_R1 | STATE_D_UL_R1;
                if (sym != 0) {
                  csj |= STATE_SIG_R2 |
                      STATE_VISITED_R2 |
                      STATE_NZ_CTXT_R1 |
                      STATE_V_D_R1 |
                      STATE_V_D_SIGN_R1;
                  state[j + sscanw] |=
                      STATE_NZ_CTXT_R1 | STATE_V_U_R1 | STATE_V_U_SIGN_R1;
                  state[j + 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_D_DL_R1 |
                      STATE_H_L_R2 |
                      STATE_H_L_SIGN_R2;
                  state[j - 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_D_DR_R1 |
                      STATE_H_R_R2 |
                      STATE_H_R_SIGN_R2;
                } else {
                  csj |= STATE_SIG_R2 |
                      STATE_VISITED_R2 |
                      STATE_NZ_CTXT_R1 |
                      STATE_V_D_R1;
                  state[j + sscanw] |= STATE_NZ_CTXT_R1 | STATE_V_U_R1;
                  state[j + 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_D_DL_R1 |
                      STATE_H_L_R2;
                  state[j - 1] |= STATE_NZ_CTXT_R1 |
                      STATE_NZ_CTXT_R2 |
                      STATE_D_DR_R1 |
                      STATE_H_R_R2;
                }
                normval = (data[k] >> downshift) << upshift;
                dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
              }
            }
          }
          csj &= ~(STATE_VISITED_R1 | STATE_VISITED_R2);
          state[j] = csj;
          if (sheight < 3) continue;
          j += sscanw;
          csj = state[j];
        }

        if ((((csj >> 1) | csj) & VSTD_MASK_R1R2) != VSTD_MASK_R1R2) {
          k = sk + (dscanw << 1);
          if ((csj & (STATE_SIG_R1 | STATE_VISITED_R1)) == 0) {
            ctxtbuf[nsym] = zc_lut[csj & ZC_MASK];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = data[k] >> 31;
              ctxt = SC_LUT[(csj >> SC_SHIFT_R1) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              state[j + off_ul] |= STATE_NZ_CTXT_R2 | STATE_D_DR_R2;
              state[j + off_ur] |= STATE_NZ_CTXT_R2 | STATE_D_DL_R2;
              if (sym != 0) {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2 |
                    STATE_V_U_SIGN_R2;
                state[j - sscanw] |=
                    STATE_NZ_CTXT_R2 | STATE_V_D_R2 | STATE_V_D_SIGN_R2;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_H_L_SIGN_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_H_R_SIGN_R1 |
                    STATE_D_UR_R2;
              } else {
                csj |= STATE_SIG_R1 |
                    STATE_VISITED_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_V_U_R2;
                state[j - sscanw] |= STATE_NZ_CTXT_R2 | STATE_V_D_R2;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_L_R1 |
                    STATE_D_UL_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_H_R_R1 |
                    STATE_D_UR_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            }
          }
          if (sheight < 4) {
            csj &= ~(STATE_VISITED_R1 | STATE_VISITED_R2);
            state[j] = csj;
            continue;
          }
          if ((csj & (STATE_SIG_R2 | STATE_VISITED_R2)) == 0) {
            k += dscanw;
            ctxtbuf[nsym] = zc_lut[(csj >> STATE_SEP) & ZC_MASK];
            if ((symbuf[nsym++] = (data[k] & mask) >> bp) != 0) {
              sym = data[k] >> 31;
              ctxt = SC_LUT[(csj >> SC_SHIFT_R2) & SC_MASK];
              symbuf[nsym] = sym ^ (ctxt >> SC_SPRED_SHIFT);
              ctxtbuf[nsym++] = ctxt & SC_LUT_MASK;
              state[j + off_dl] |= STATE_NZ_CTXT_R1 | STATE_D_UR_R1;
              state[j + off_dr] |= STATE_NZ_CTXT_R1 | STATE_D_UL_R1;
              if (sym != 0) {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1 |
                    STATE_V_D_SIGN_R1;
                state[j + sscanw] |=
                    STATE_NZ_CTXT_R1 | STATE_V_U_R1 | STATE_V_U_SIGN_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2 |
                    STATE_H_L_SIGN_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2 |
                    STATE_H_R_SIGN_R2;
              } else {
                csj |= STATE_SIG_R2 |
                    STATE_VISITED_R2 |
                    STATE_NZ_CTXT_R1 |
                    STATE_V_D_R1;
                state[j + sscanw] |= STATE_NZ_CTXT_R1 | STATE_V_U_R1;
                state[j + 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DL_R1 |
                    STATE_H_L_R2;
                state[j - 1] |= STATE_NZ_CTXT_R1 |
                    STATE_NZ_CTXT_R2 |
                    STATE_D_DR_R1 |
                    STATE_H_R_R2;
              }
              normval = (data[k] >> downshift) << upshift;
              dist += fs[normval & ((1 << (MSE_LKP_BITS - 1)) - 1)];
            }
          }
        }
        csj &= ~(STATE_VISITED_R1 | STATE_VISITED_R2);
        state[j] = csj;
      }
      if (nsym > 0) mq.codeSymbols(symbuf, ctxtbuf, nsym);
    }

    if ((options & OPT_SEG_SYMBOLS) != 0) {
      mq.codeSymbols(SEG_SYMBOLS, SEG_SYMB_CTXTS, SEG_SYMBOLS.length);
    }

    if ((options & OPT_RESET_MQ) != 0) {
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



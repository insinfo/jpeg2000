/// JPEG 2000 marker constants mirrored from JJ2000.
///
/// The values follow the Big-Endian 16-bit marker numbers defined by the
/// specification. Only the subset used by the current port is exposed.
class Markers {
  Markers._();

  // Delimiting markers and marker segments
  static const int soc = 0xff4f;
  static const int sot = 0xff90;
  static const int sod = 0xff93;
  static const int eoc = 0xffd9;

  // Fixed information marker segments
  static const int siz = 0xff51;
  static const int rsizBaseline = 0x00;
  static const int rsizErFlag = 0x01;
  static const int rsizRoi = 0x02;
  static const int ssizDepthBits = 7;
  static const int maxComponentBitDepth = 38;

  // Coding style markers
  static const int cod = 0xff52;
  static const int coc = 0xff53;
  static const int scoxPrecinctPartition = 1;
  static const int scoxUseSop = 2;
  static const int scoxUseEph = 4;
  static const int scoxHorCbPart = 8;
  static const int scoxVerCbPart = 16;
  static const int precinctPartitionDefaultSize = 0xffff;

  // Region-of-interest
  static const int rgn = 0xff5e;
  static const int srgnImplicit = 0x00;

  // Quantization
  static const int qcd = 0xff5c;
  static const int qcc = 0xff5d;
  static const int sqcxGbShift = 5;
  static const int sqcxGbMask = 7;
  static const int sqcxNoQuantization = 0x00;
  static const int sqcxScalarDerived = 0x01;
  static const int sqcxScalarExpounded = 0x02;
  static const int sqcxExpShift = 3;
  static const int sqcxExpMask = (1 << 5) - 1;
  static const int ersSop = 1;
  static const int ersSegSymbols = 2;

  static const int poc = 0xff5f;

  // Pointer marker segments
  static const int tlm = 0xff55;
  static const int plm = 0xff57;
  static const int plt = 0xff58;
  static const int ppm = 0xff60;
  static const int ppt = 0xff61;
  static const int maxLppt = 65535;
  static const int maxLppm = 65535;

  // In-bit-stream markers
  static const int sop = 0xff91;
  static const int sopLength = 6;
  static const int eph = 0xff92;
  static const int ephLength = 2;

  // Informational markers
  static const int crg = 0xff63;
  static const int com = 0xff64;
  static const int rcomGeneralUse = 0x0001;

  // Java parity aliases (uppercase) to simplify straight ports.
  static const int SOC = soc;
  static const int SOT = sot;
  static const int SOD = sod;
  static const int EOC = eoc;
  static const int SIZ = siz;
  static const int COD = cod;
  static const int COC = coc;
  static const int RGN = rgn;
  static const int SRGN_IMPLICIT = srgnImplicit;
  static const int QCD = qcd;
  static const int QCC = qcc;
  static const int POC = poc;
  static const int TLM = tlm;
  static const int PLM = plm;
  static const int PLT = plt;
  static const int PPM = ppm;
  static const int PPT = ppt;
  static const int MAX_LPPT = maxLppt;
  static const int MAX_LPPM = maxLppm;
  static const int SOP = sop;
  static const int SOP_LENGTH = sopLength;
  static const int EPH = eph;
  static const int EPH_LENGTH = ephLength;
  static const int CRG = crg;
  static const int COM = com;
  static const int RCOM_GENERAL_USE = rcomGeneralUse;
  static const int SSIZ_DEPTH_BITS = ssizDepthBits;
  static const int MAX_COMPONENT_BIT_DEPTH = maxComponentBitDepth;
  static const int SCOX_PRECINCT_PARTITION = scoxPrecinctPartition;
  static const int SCOX_USE_SOP = scoxUseSop;
  static const int SCOX_USE_EPH = scoxUseEph;
  static const int SCOX_HOR_CB_PART = scoxHorCbPart;
  static const int SCOX_VER_CB_PART = scoxVerCbPart;
  static const int PRECINCT_PARTITION_DEF_SIZE = precinctPartitionDefaultSize;
  static const int SQCX_GB_SHIFT = sqcxGbShift;
  static const int SQCX_GB_MSK = sqcxGbMask;
  static const int SQCX_NO_QUANTIZATION = sqcxNoQuantization;
  static const int SQCX_SCALAR_DERIVED = sqcxScalarDerived;
  static const int SQCX_SCALAR_EXPOUNDED = sqcxScalarExpounded;
  static const int SQCX_EXP_SHIFT = sqcxExpShift;
  static const int SQCX_EXP_MASK = sqcxExpMask;
  static const int ERS_SOP = ersSop;
  static const int ERS_SEG_SYMBOLS = ersSegSymbols;
}

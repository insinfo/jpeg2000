/// Progression order identifiers used in JPEG 2000 codestreams.
class ProgressionType {
  ProgressionType._();

  static const int lyResCompPosProg = 0;
  static const int resLyCompPosProg = 1;
  static const int resPosCompLyProg = 2;
  static const int posCompResLyProg = 3;
  static const int compPosResLyProg = 4;

  // Java-compat aliases to keep parity with the original API.
  static const int LY_RES_COMP_POS_PROG = lyResCompPosProg;
  static const int RES_LY_COMP_POS_PROG = resLyCompPosProg;
  static const int RES_POS_COMP_LY_PROG = resPosCompLyProg;
  static const int POS_COMP_RES_LY_PROG = posCompResLyProg;
  static const int COMP_POS_RES_LY_PROG = compPosResLyProg;
}

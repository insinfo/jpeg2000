/// Progression order identifiers used in JPEG 2000 codestreams.
class ProgressionType {
  ProgressionType._();

  static const int lyResCompPosProg = 0;
  static const int resLyCompPosProg = 1;
  static const int resPosCompLyProg = 2;
  static const int posCompResLyProg = 3;
  static const int compPosResLyProg = 4;
}

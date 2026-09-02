import '../codestream/progression_type.dart';

/// Holds a single progression order segment definition for the codestream.
class Progression {
  Progression(this.type, this.cs, this.ce, this.rs, this.re, this.lye);

  int type;
  int cs;
  int ce;
  int rs;
  int re;
  int lye;

  Progression copy() => Progression(type, cs, ce, rs, re, lye);

  @override
  String toString() {
    final typeLabel = () {
      switch (type) {
        case ProgressionType.lyResCompPosProg:
          return 'layer';
        case ProgressionType.resLyCompPosProg:
          return 'res';
        case ProgressionType.resPosCompLyProg:
          return 'res-pos';
        case ProgressionType.posCompResLyProg:
          return 'pos-comp';
        case ProgressionType.compPosResLyProg:
          return 'comp-pos';
        default:
          return 'unknown';
      }
    }();
    return 'type=$typeLabel, comp: $cs-$ce, res: $rs-$re, layer < $lye';
  }
}

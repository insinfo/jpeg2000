import '../codestream/ProgressionType.dart';

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
        case ProgressionType.LY_RES_COMP_POS_PROG:
          return 'layer';
        case ProgressionType.RES_LY_COMP_POS_PROG:
          return 'res';
        case ProgressionType.RES_POS_COMP_LY_PROG:
          return 'res-pos';
        case ProgressionType.POS_COMP_RES_LY_PROG:
          return 'pos-comp';
        case ProgressionType.COMP_POS_RES_LY_PROG:
          return 'comp-pos';
        default:
          return 'unknown';
      }
    }();
    return 'type=$typeLabel, comp: $cs-$ce, res: $rs-$re, layer < $lye';
  }
}


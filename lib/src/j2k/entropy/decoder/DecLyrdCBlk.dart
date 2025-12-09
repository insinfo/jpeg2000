import '../CodedCBlk.dart';

/// Decoder-side representation of a layered coded code-block.
class DecLyrdCBlk extends CodedCBlk {
  int ulx = 0;
  int uly = 0;
  int w = 0;
  int h = 0;
  int dl = 0;
  bool prog = false;
  int nl = 0;
  int ftpIdx = 0;
  int nTrunc = 0;
  List<int>? tsLengths;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('Coded code-block ($m,$n): ')
      ..write('$skipMSBP MSB skipped, ')
      ..write('$dl bytes, ')
      ..write('$nTrunc truncation points, ')
      ..write('$nl layers, ')
      ..write('progressive=$prog, ')
      ..write('ulx=$ulx, uly=$uly, w=$w, h=$h, ftpIdx=$ftpIdx');
    final segments = tsLengths;
    if (segments != null) {
      buffer.write(' {');
      for (var i = 0; i < segments.length; i++) {
        buffer.write(' ${segments[i]}');
      }
      buffer.write(' }');
    }
    return buffer.toString();
  }
}



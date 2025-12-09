import 'dart:typed_data';

/// Stores per-layer code-block metadata extracted from the codestream.
class CBlkInfo {
  CBlkInfo(this.ulx, this.uly, this.w, this.h, int numLayers)
      : off = List<int>.filled(numLayers, 0),
        len = List<int>.filled(numLayers, 0),
        ntp = List<int>.filled(numLayers, 0),
        segLen = List<List<int>?>.filled(numLayers, null),
        pktIdx = List<int>.filled(numLayers, -1),
        body = List<Uint8List?>.filled(numLayers, null);

  final int ulx;
  final int uly;
  final int w;
  final int h;

  int msbSkipped = 0;
  final List<int> len;
  final List<int> off;
  final List<int> ntp;
  final List<List<int>?> segLen;
  final List<int> pktIdx;
  final List<Uint8List?> body;
  int ctp = 0;

  void addNTP(int layer, int newTruncationPoints) {
    ntp[layer] = newTruncationPoints;
    var total = 0;
    for (var l = 0; l <= layer; l++) {
      total += ntp[l];
    }
    ctp = total;
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('(ulx,uly,w,h)= ($ulx,$uly,$w,$h) $msbSkipped MSB bit(s) skipped');
    for (var i = 0; i < len.length; i++) {
      buffer.write('\tl:$i, start:${off[i]}, len:${len[i]}, ntp:${ntp[i]}, pktIdx=${pktIdx[i]}');
      final segments = segLen[i];
      if (segments != null) {
        buffer.write(' { ');
        for (final value in segments) {
          buffer.write('$value ');
        }
        buffer.write('}');
      }
      final payload = body[i];
      if (payload != null) {
        buffer.write(' bytes=${payload.length}');
      }
      buffer.writeln();
    }
    buffer.write('\tctp=$ctp');
    return buffer.toString();
  }
}

/// Captures packet-level metadata for a particular code-block contribution.
class PktInfo {
  PktInfo(this.layerIdx, this.packetIdx);

  final int packetIdx;
  final int layerIdx;

  int cbOff = 0;
  int cbLength = 0;
  List<int>? segLengths;
  int numTruncPnts = 0;

  @override
  String toString() {
    return 'packet $packetIdx (lay:$layerIdx, off:$cbOff, len:$cbLength, numTruncPnts:$numTruncPnts)\n';
  }
}

import 'dart:typed_data';

/// Holds the compressed payload and metadata for a single code-block.
class CodedCBlk {
  CodedCBlk();

  CodedCBlk.full(
    this.m,
    this.n,
    this.skipMSBP,
    Uint8List? bytes,
  ) : data = bytes;

  int m = 0;
  int n = 0;
  int skipMSBP = 0;
  Uint8List? data;

  @override
  String toString() {
    final length = data == null ? '(null)' : '${data!.length}';
    return 'm=$m, n=$n, skipMSBP=$skipMSBP, data.length=$length';
  }
}

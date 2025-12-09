

import 'package:jpeg2000/src/j2k/codestream/CBlkCoordInfo.dart';

/// Holds precinct coordinates and code-block references for each subband.
class PrecInfo {
  PrecInfo(
    this.r,
    this.ulx,
    this.uly,
    this.w,
    this.h,
    this.rgulx,
    this.rguly,
    this.rgw,
    this.rgh,
  ) {
    final bands = r == 0 ? 1 : 4;
    cblk = List.generate(bands, (_) => <List<CBlkCoordInfo?>>[]);
    nblk = List.filled(bands, 0);
  }

  int rgulx;
  int rguly;
  int rgw;
  int rgh;
  int ulx;
  int uly;
  int w;
  int h;
  int r;

  late List<List<List<CBlkCoordInfo?>>> cblk;
  late List<int> nblk;

  @override
  String toString() =>
      'ulx=$ulx,uly=$uly,w=$w,h=$h,rgulx=$rgulx,rguly=$rguly,rgw=$rgw,rgh=$rgh';
}



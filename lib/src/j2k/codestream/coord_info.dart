/// Stores the coordinates and size of a codestream entity (code-block, precinct).
abstract class CoordInfo {
  CoordInfo([this.ulx = 0, this.uly = 0, this.w = 0, this.h = 0]);

  int ulx;
  int uly;
  int w;
  int h;

  @override
  String toString() => 'ulx=$ulx,uly=$uly,w=$w,h=$h';
}

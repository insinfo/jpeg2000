import 'CoordInfo.dart';

/// Coordinates of a precinct both in the subband and reference grid.
class PrecCoordInfo extends CoordInfo {
  PrecCoordInfo([int ulx = 0, int uly = 0, int w = 0, int h = 0, this.xref = 0, this.yref = 0])
      : super(ulx, uly, w, h);

  int xref;
  int yref;

  @override
  String toString() => '${super.toString()}, xref=$xref, yref=$yref';
}


import 'coord_info.dart';

/// Coordinates of a precinct both in the subband and reference grid.
class PrecCoordInfo extends CoordInfo {
  PrecCoordInfo(
      [super.ulx, super.uly, super.w, super.h, this.xref = 0, this.yref = 0]);

  int xref;
  int yref;

  @override
  String toString() => '${super.toString()}, xref=$xref, yref=$yref';
}

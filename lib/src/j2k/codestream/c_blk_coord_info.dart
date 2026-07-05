import '../image/coord.dart';
import 'coord_info.dart';

/// Coordinates of a code-block within a subband.
class CBlkCoordInfo extends CoordInfo {
  CBlkCoordInfo() : idx = Coord();

  CBlkCoordInfo.withIndex(int m, int n) : idx = Coord(n, m);

  Coord idx;

  @override
  String toString() => '${super.toString()},idx=$idx';
}

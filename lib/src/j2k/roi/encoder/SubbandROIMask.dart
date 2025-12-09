/// Base node describing ROI bounds for a single subband.
///
/// Each node can either represent a leaf (no further decomposition) or a
/// branch that owns references to the LL, LH, HL and HH descendants. The
/// encoder uses this tree to answer "which bounds apply to the coordinates
/// (x, y) inside the current subband?" quickly.
abstract class SubbandROIMask {
  SubbandROIMask({
    required this.ulx,
    required this.uly,
    required this.width,
    required this.height,
  });

  SubbandROIMask? ll;
  SubbandROIMask? lh;
  SubbandROIMask? hl;
  SubbandROIMask? hh;
  bool isNode = false;

  final int ulx;
  final int uly;
  final int width;
  final int height;

  /// Walks the mask tree and returns the leaf covering the provided point.
  SubbandROIMask locateSubband(int x, int y) {
    if (x < ulx || y < uly || x >= ulx + width || y >= uly + height) {
      throw ArgumentError('Point ($x,$y) outside of subband bounds');
    }

    var current = this;
    while (current.isNode) {
      final hhMask = current.hh;
      if (hhMask == null) {
        throw StateError('Node without HH child');
      }

      if (x < hhMask.ulx) {
        // Horizontal low-pass branch.
        final horizontal = y < hhMask.uly ? current.ll : current.lh;
        if (horizontal == null) {
          throw StateError('Missing child while traversing horizontal low-pass');
        }
        current = horizontal;
      } else {
        // Horizontal high-pass branch.
        final vertical = y < hhMask.uly ? current.hl : current.hh;
        if (vertical == null) {
          throw StateError('Missing child while traversing horizontal high-pass');
        }
        current = vertical;
      }
    }
    return current;
  }
}

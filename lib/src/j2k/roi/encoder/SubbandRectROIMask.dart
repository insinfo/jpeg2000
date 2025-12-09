import '../../wavelet/subband.dart';
import '../../wavelet/WaveletFilter.dart';
import 'SubbandRoiMask.dart';

/// Concrete mask node for scenarios where only rectangular ROIs exist.
class SubbandRectROIMask extends SubbandROIMask {
  SubbandRectROIMask(
    Subband subband,
    List<int> upperLeftXs,
    List<int> upperLeftYs,
    List<int> lowerRightXs,
    List<int> lowerRightYs,
    int roiCount,
  )   : ulxs = upperLeftXs,
        ulys = upperLeftYs,
        lrxs = lowerRightXs,
        lrys = lowerRightYs,
        super(
          ulx: subband.ulx,
          uly: subband.uly,
          width: subband.w,
          height: subband.h,
        ) {
    if (!subband.isNode) {
      return;
    }

    isNode = true;

    final bool lowStartsOnEvenColumn = (subband.ulcx & 1) == 0;
    final bool lowStartsOnEvenRow = (subband.ulcy & 1) == 0;

    final WaveletFilter horizontal = subband.getHorWFilter();
    final WaveletFilter vertical = subband.getVerWFilter();

    final int lowNegHor = horizontal.getSynLowNegSupport();
    final int lowPosHor = horizontal.getSynLowPosSupport();
    final int highNegHor = horizontal.getSynHighNegSupport();
    final int highPosHor = horizontal.getSynHighPosSupport();

    final int lowNegVer = vertical.getSynLowNegSupport();
    final int lowPosVer = vertical.getSynLowPosSupport();
    final int highNegVer = vertical.getSynHighNegSupport();
    final int highPosVer = vertical.getSynHighPosSupport();

    final List<int> llUlx = List<int>.filled(roiCount, 0);
    final List<int> llUly = List<int>.filled(roiCount, 0);
    final List<int> llLrx = List<int>.filled(roiCount, 0);
    final List<int> llLry = List<int>.filled(roiCount, 0);
    final List<int> hhUlx = List<int>.filled(roiCount, 0);
    final List<int> hhUly = List<int>.filled(roiCount, 0);
    final List<int> hhLrx = List<int>.filled(roiCount, 0);
    final List<int> hhLry = List<int>.filled(roiCount, 0);

    for (var index = 0; index < roiCount; index++) {
      final int roiUlx = ulxs[index];
      final int roiUly = ulys[index];
      final int roiLrx = lrxs[index];
      final int roiLry = lrys[index];

      // Horizontal projection for children.
      if (lowStartsOnEvenColumn) {
        llUlx[index] = (roiUlx + 1 - lowNegHor) ~/ 2;
        hhUlx[index] = (roiUlx - highNegHor) ~/ 2;
        llLrx[index] = (roiLrx + lowPosHor) ~/ 2;
        hhLrx[index] = (roiLrx - 1 + highPosHor) ~/ 2;
      } else {
        llUlx[index] = (roiUlx - lowNegHor) ~/ 2;
        hhUlx[index] = (roiUlx + 1 - highNegHor) ~/ 2;
        llLrx[index] = (roiLrx - 1 + lowPosHor) ~/ 2;
        hhLrx[index] = (roiLrx + highPosHor) ~/ 2;
      }

      // Vertical projection for children.
      if (lowStartsOnEvenRow) {
        llUly[index] = (roiUly + 1 - lowNegVer) ~/ 2;
        hhUly[index] = (roiUly - highNegVer) ~/ 2;
        llLry[index] = (roiLry + lowPosVer) ~/ 2;
        hhLry[index] = (roiLry - 1 + highPosVer) ~/ 2;
      } else {
        llUly[index] = (roiUly - lowNegVer) ~/ 2;
        hhUly[index] = (roiUly + 1 - highNegVer) ~/ 2;
        llLry[index] = (roiLry - 1 + lowPosVer) ~/ 2;
        hhLry[index] = (roiLry + highPosVer) ~/ 2;
      }
    }

    hh = SubbandRectROIMask(
      subband.getHH(),
      hhUlx,
      hhUly,
      hhLrx,
      hhLry,
      roiCount,
    );
    lh = SubbandRectROIMask(
      subband.getLH(),
      llUlx,
      hhUly,
      llLrx,
      hhLry,
      roiCount,
    );
    hl = SubbandRectROIMask(
      subband.getHL(),
      hhUlx,
      llUly,
      hhLrx,
      llLry,
      roiCount,
    );
    ll = SubbandRectROIMask(
      subband.getLL(),
      llUlx,
      llUly,
      llLrx,
      llLry,
      roiCount,
    );
  }

  /// Left edges for all active ROIs intersecting the current subband.
  final List<int> ulxs;

  /// Top edges for all active ROIs intersecting the current subband.
  final List<int> ulys;

  /// Right edges (inclusive) for all active ROIs intersecting the subband.
  final List<int> lrxs;

  /// Bottom edges (inclusive) for all active ROIs intersecting the subband.
  final List<int> lrys;
}


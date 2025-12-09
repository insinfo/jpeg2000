import 'dart:typed_data';
import '../../wavelet/analysis/SubbandAn.dart';
import '../CodedCBlk.dart';

/// This class stores coded (compressed) code-blocks with their associated
/// rate-distortion statistics. This object should always contain all the
/// compressed data of the code-block. It is applicable to the encoder engine
/// only. Some data of the coded-block is stored in the super class, see
/// CodedCBlk.
///
/// The rate-distortion statistics (i.e. R-D slope) is stored for valid
/// points only. The set of valid points is determined by the entropy coder
/// engine itself. Normally they are selected so as to lye in a convex hull,
/// which can be achived by using the 'selectConvexHull' method of this class,
/// but some other strategies might be employed.
///
/// The rate (in bytes) for each truncation point (valid or not) is stored
/// in the 'truncRates' array. The rate of a truncation point is the total
/// number of bytes in 'data' (see super class) that have to be decoded to
/// reach the truncation point.
///
/// The slope (reduction of distortion divided by the increase in rate) at
/// each of the valid truncation points is stored in 'truncSlopes'.
///
/// The index of each valid truncation point is stored in 'truncIdxs'. The
/// index should be interpreted in the following way: a valid truncation point
/// at position 'n' has the index 'truncIdxs[n]', the rate
/// 'truncRates[truncIdxs[n]]' and the slope 'truncSlopes[n]'. The arrays
/// 'truncIdxs' and 'truncRates' have at least 'nVldTrunc' elements. The
/// 'truncRates' array has at least 'nTotTrunc' elements.
///
/// In addition the 'isTermPass' array contains a flag for each truncation
/// point (valid and non-valid ones) that tells if the pass is terminated or
/// not. If this variable is null then it means that no pass is terminated,
/// except the last one which always is.
///
/// The compressed data is stored in the 'data' member variable of the super
/// class.
///
/// @see CodedCBlk
class CBlkRateDistStats extends CodedCBlk {
  /// The subband to which the code-block belongs
  SubbandAn? sb;

  /// The total number of truncation points
  int nTotTrunc = 0;

  /// The number of valid truncation points
  int nVldTrunc = 0;

  /// The rate (in bytes) for each truncation point (valid and non-valid
  /// ones)
  late List<int> truncRates;

  /// The distortion for each truncation point (valid and non-valid ones)
  late List<double> truncDists;

  /// The negative of the rate-distortion slope for each valid truncation
  /// point
  late List<double> truncSlopes;

  /// The indices of the valid truncation points, in increasing order.
  late List<int> truncIdxs;

  /// Array of flags indicating terminated passes (valid or non-valid
  /// truncation points).
  List<bool>? isTermPass;

  /// The number of ROI coefficients in the code-block
  int nROIcoeff = 0;

  /// Number of ROI coding passes
  int nROIcp = 0;

  /// Creates a new CBlkRateDistStats object without allocating any space for
  /// 'truncRates', 'truncSlopes', 'truncDists' and 'truncIdxs' or 'data'.
  CBlkRateDistStats() : super();

  /// Creates a new CBlkRateDistStats object and initializes the valid
  /// truncation points, their rates and their slopes, from the 'rates' and
  /// 'dist' arrays. The 'rates', 'dist' and 'termp' arrays must contain the
  /// rate (in bytes), the reduction in distortion (from nothing coded) and
  /// the flag indicating if termination is used, respectively, for each
  /// truncation point.
  ///
  /// The valid truncation points are selected by taking them as lying on
  /// a convex hull. This is done by calling the method
  /// selectConvexHull().
  ///
  /// Note that the arrays 'rates' and 'termp' are copied, not referenced,
  /// so they can be modified after a call to this constructor.
  ///
  /// [m] The horizontal index of the code-block, within the subband.
  ///
  /// [n] The vertical index of the code-block, within the subband.
  ///
  /// [skipMSBP] The number of skipped most significant bit-planes for
  /// this code-block.
  ///
  /// [data] The compressed data. This array is referenced by this
  /// object so it should not be modified after.
  ///
  /// [rates] The rates (in bytes) for each truncation point in the
  /// compressed data. This array is modified by the method but no reference
  /// is kept to it.
  ///
  /// [dists] The reduction in distortion (with respect to no
  /// information coded) for each truncation point. This array is modified by
  /// the method but no reference is kept to it.
  ///
  /// [termp] An array of boolean flags indicating, for each pass, if a
  /// pass is terminated or not (true if terminated). If null then it is
  /// assumed that no pass is terminated except the last one which always is.
  ///
  /// [np] The number of truncation points contained in 'rates', 'dist'
  /// and 'termp'.
  ///
  /// [inclast] If false the convex hull is constructed as for lossy
  /// coding. If true it is constructed as for lossless coding, in which case
  /// it is ensured that all bit-planes are sent (i.e. the last truncation
  /// point is always included).
  CBlkRateDistStats.withStats(
      int m,
      int n,
      int skipMSBP,
      Uint8List data,
      List<int> rates,
      List<double> dists,
      List<bool>? termp,
      int np,
      bool inclast)
      : super.full(m, n, skipMSBP, data) {
    selectConvexHull(rates, dists, termp, np, inclast);
  }

  /// Compute the rate-distorsion slopes and selects those that lie in a
  /// convex hull. It will compute the slopes, select the ones that form the
  /// convex hull and initialize the 'truncIdxs' and 'truncSlopes' arrays, as
  /// well as 'nVldTrunc', with the selected truncation points. It will also
  /// initialize 'truncRates' and 'isTermPass' arrays, as well as
  /// 'nTotTrunc', with all the truncation points (selected or not).
  ///
  /// Note that the arrays 'rates' and 'termp' are copied, not
  /// referenced, so they can be modified after a call to this method.
  ///
  /// [rates] The rates (in bytes) for each truncation point in the
  /// compressed data. This array is modified by the method.
  ///
  /// [dists] The reduction in distortion (with respect to no
  /// information coded) for each truncation point. This array is modified by
  /// the method.
  ///
  /// [termp] An array of boolean flags indicating, for each pass, if a
  /// pass is terminated or not (true if terminated). If null then it is
  /// assumed that no pass is terminated except the last one which always is.
  ///
  /// [n] The number of truncation points contained in 'rates', 'dist'
  /// and 'termp'.
  ///
  /// [inclast] If false the convex hull is constructed as for lossy
  /// coding. If true it is constructed as for lossless coding, in which case
  /// it is ensured that all bit-planes are sent (i.e. the last truncation
  /// point is always included).
  void selectConvexHull(List<int> rates, List<double> dists, List<bool>? termp,
      int n, bool inclast) {
    int firstPnt; // The first point containing some coded data
    int p; // last selected point
    int k; // current point
    int i; // current valid point
    int npnt; // number of selected (i.e. valid) points
    int deltaRate; // Rate difference
    double deltaDist; // Distortion difference
    double kSlope; // R-D slope for the current point
    double pSlope; // R-D slope for the last selected point

    // Convention: when a negative value is stored in 'rates' it meas an
    // invalid point. The absolute value is always the rate for that point.

    // Look for first point with some coded info (rate not 0)
    firstPnt = 0;
    while (firstPnt < n && rates[firstPnt] <= 0) {
      firstPnt++;
    }

    // Select the valid points
    npnt = n - firstPnt;
    pSlope = 0.0; // To keep compiler happy
    
    bool restart = false;
    do {
      restart = false;
      p = -1;
      for (k = firstPnt; k < n; k++) {
        if (rates[k] < 0) {
          // Already invalidated point
          continue;
        }
        // Calculate decrease in distortion and rate
        if (p >= 0) {
          deltaRate = rates[k] - rates[p];
          deltaDist = dists[k] - dists[p];
        } else {
          // This is with respect to no info coded
          deltaRate = rates[k];
          deltaDist = dists[k];
        }
        // If exactly same distortion don't eliminate if the rates are
        // equal, otherwise it can lead to infinite slope in lossless
        // coding.
        if (deltaDist < 0.0 || (deltaDist == 0.0 && deltaRate > 0)) {
          // This point increases distortion => invalidate
          rates[k] = -rates[k];
          npnt--;
          continue; // Goto next point
        }
        kSlope = deltaDist / deltaRate;
        // Check that there is a decrease in distortion, slope is not
        // infinite (i.e. delta_dist is not 0) and slope is
        // decreasing.
        if (p >= 0 && (deltaRate <= 0 || kSlope >= pSlope)) {
          // Last point was not good
          rates[p] = -rates[p]; // Remove p from valid points
          npnt--;
          restart = true;
          break; // Restart from the first one
        } else {
          pSlope = kSlope;
          p = k;
        }
      }
    } while (restart);

    // If in lossless mode make sure we don't eliminate any last
    // bit-planes from being sent.
    if (inclast && n > 0 && rates[n - 1] < 0) {
      rates[n - 1] = -rates[n - 1];
      // This rate can never be equal to any previous selected rate,
      // given the selection algorithm above, so no problem arises of
      // infinite slopes.
      npnt++;
    }

    // Initialize the arrays of this object
    nTotTrunc = n;
    nVldTrunc = npnt;
    truncRates = List<int>.filled(n, 0);
    truncDists = List<double>.filled(n, 0.0);
    truncSlopes = List<double>.filled(npnt, 0.0);
    truncIdxs = List<int>.filled(npnt, 0);
    if (termp != null) {
      isTermPass = List<bool>.filled(n, false);
      for (int j = 0; j < n; j++) {
        isTermPass![j] = termp[j];
      }
    } else {
      isTermPass = null;
    }
    
    for (int j = 0; j < n; j++) {
      truncRates[j] = rates[j];
    }

    p = -1;
    i = 0;
    for (k = firstPnt; k < n; k++) {
      if (rates[k] > 0) {
        // A valid point
        truncDists[k] = dists[k];
        if (p < 0) {
          // Only arrives at first valid point
          truncSlopes[i] = dists[k] / rates[k];
        } else {
          truncSlopes[i] = (dists[k] - dists[p]) / (rates[k] - rates[p]);
        }
        truncIdxs[i] = k;
        i++;
        p = k;
      } else {
        truncDists[k] = -1;
        truncRates[k] = -truncRates[k];
      }
    }
  }

  /// Returns the contents of the object in a string. This is used for
  /// debugging.
  ///
  /// @return A string with the contents of the object
  @override
  String toString() {
    String str = super.toString() +
        "\n nVldTrunc=$nVldTrunc, nTotTrunc=$nTotTrunc, num. ROI" +
        " coeff=$nROIcoeff, num. ROI coding passes=$nROIcp, sb=" +
        (sb?.sbandIdx.toString() ?? "null");
    return str;
  }
}



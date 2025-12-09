import 'ICCProfile.dart';
import 'tags/ICCCurveType.dart';
import 'tags/ICCXYZType.dart';
import 'MatrixBasedRestrictedProfile.dart';
import 'MonochromeInputRestrictedProfile.dart';

/// This profile is constructed by parsing an ICCProfile and
/// is the profile actually applied to the image.
abstract class RestrictedICCProfile {
  static const String eol = '\n'; // System.getProperty("line.separator");

  /// Component index
  static const int GRAY = ICCProfile.GRAY;

  /// Component index
  static const int RED = ICCProfile.RED;

  /// Component index
  static const int GREEN = ICCProfile.GREEN;

  /// Component index
  static const int BLUE = ICCProfile.BLUE;

  /// input type enumerator
  static const int kMonochromeInput = 0;

  /// input type enumerator
  static const int kThreeCompInput = 1;

  /// Curve data
  late final List<ICCCurveType> trc;

  /// Colorant data
  late final List<ICCXYZType?>? colorant;

  /// Returns the appropriate input type enum.
  int getType();

  /// Factory method for creating a RestrictedICCProfile from
  /// 3 component curve and colorant data.
  static RestrictedICCProfile createInstance3Comp(
      ICCCurveType rcurve,
      ICCCurveType gcurve,
      ICCCurveType bcurve,
      ICCXYZType rcolorant,
      ICCXYZType gcolorant,
      ICCXYZType bcolorant) {
    return MatrixBasedRestrictedProfile.createInstance(
        rcurve, gcurve, bcurve, rcolorant, gcolorant, bcolorant);
  }

  /// Factory method for creating a RestrictedICCProfile from
  /// gray curve data.
  static RestrictedICCProfile createInstanceGray(ICCCurveType gcurve) {
    return MonochromeInputRestrictedProfile.createInstance(gcurve);
  }

  /// Construct the common state of all gray RestrictedICCProfiles
  RestrictedICCProfile.gray(ICCCurveType gcurve) {
    trc = List<ICCCurveType>.filled(1, gcurve);
    colorant = null;
    trc[GRAY] = gcurve;
  }

  /// Construct the common state of all 3 component RestrictedICCProfiles
  RestrictedICCProfile.rgb(
      ICCCurveType rcurve,
      ICCCurveType gcurve,
      ICCCurveType bcurve,
      ICCXYZType rcolorant,
      ICCXYZType gcolorant,
      ICCXYZType bcolorant) {
    trc = List<ICCCurveType>.filled(3, rcurve); // Initialize with dummy
    colorant = List<ICCXYZType?>.filled(3, null);

    trc[RED] = rcurve;
    trc[GREEN] = gcurve;
    trc[BLUE] = bcurve;

    colorant![RED] = rcolorant;
    colorant![GREEN] = gcolorant;
    colorant![BLUE] = bcolorant;
  }
}


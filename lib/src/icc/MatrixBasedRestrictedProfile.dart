import 'RestrictedICCProfile.dart';
import 'tags/ICCCurveType.dart';
import 'tags/ICCXYZType.dart';

/// This class is a 3 component RestrictedICCProfile
class MatrixBasedRestrictedProfile extends RestrictedICCProfile {
  /// Factory method which returns a 3 component RestrictedICCProfile
  static RestrictedICCProfile createInstance(
      ICCCurveType rcurve,
      ICCCurveType gcurve,
      ICCCurveType bcurve,
      ICCXYZType rcolorant,
      ICCXYZType gcolorant,
      ICCXYZType bcolorant) {
    return MatrixBasedRestrictedProfile(
        rcurve, gcurve, bcurve, rcolorant, gcolorant, bcolorant);
  }

  /// Construct a 3 component RestrictedICCProfile
  MatrixBasedRestrictedProfile(
      ICCCurveType rcurve,
      ICCCurveType gcurve,
      ICCCurveType bcurve,
      ICCXYZType rcolorant,
      ICCXYZType gcolorant,
      ICCXYZType bcolorant)
      : super.rgb(rcurve, gcurve, bcurve, rcolorant, gcolorant, bcolorant);

  /// Get the type of RestrictedICCProfile for this object
  @override
  int getType() {
    return RestrictedICCProfile.kThreeCompInput;
  }

  /// @return String representation of a MatrixBasedRestrictedProfile
  @override
  String toString() {
    StringBuffer rep =
        StringBuffer("[Matrix-Based Input Restricted ICC profile")..write(RestrictedICCProfile.eol);

    rep
      ..write("trc[RED]:")
      ..write(RestrictedICCProfile.eol)
      ..write(trc[RestrictedICCProfile.RED])
      ..write(RestrictedICCProfile.eol);
    rep
      ..write("trc[GREEN]:")
      ..write(RestrictedICCProfile.eol)
      ..write(trc[RestrictedICCProfile.GREEN])
      ..write(RestrictedICCProfile.eol);
    rep
      ..write("trc[BLUE]:")
      ..write(RestrictedICCProfile.eol)
      ..write(trc[RestrictedICCProfile.BLUE])
      ..write(RestrictedICCProfile.eol);

    rep
      ..write("Red colorant:  ")
      ..write(colorant![RestrictedICCProfile.RED])
      ..write(RestrictedICCProfile.eol);
    rep
      ..write("Green colorant:  ")
      ..write(colorant![RestrictedICCProfile.GREEN])
      ..write(RestrictedICCProfile.eol);
    rep
      ..write("Blue colorant:  ")
      ..write(colorant![RestrictedICCProfile.BLUE])
      ..write(RestrictedICCProfile.eol);

    return (rep..write("]")).toString();
  }
}


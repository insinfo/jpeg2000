import 'RestrictedICCProfile.dart';
import 'tags/ICCCurveType.dart';

/// This class is a 1 component RestrictedICCProfile
class MonochromeInputRestrictedProfile extends RestrictedICCProfile {
  /// Factory method which returns a 1 component RestrictedICCProfile
  static RestrictedICCProfile createInstance(ICCCurveType c) {
    return MonochromeInputRestrictedProfile(c);
  }

  /// Construct a 1 component RestrictedICCProfile
  MonochromeInputRestrictedProfile(ICCCurveType c) : super.gray(c);

  /// Get the type of RestrictedICCProfile for this object
  @override
  int getType() {
    return RestrictedICCProfile.kMonochromeInput;
  }

  /// @return String representation of a MonochromeInputRestrictedProfile
  @override
  String toString() {
    StringBuffer rep = StringBuffer("Monochrome Input Restricted ICC profile${RestrictedICCProfile.eol}");

    rep
      ..write("trc[GRAY]:${RestrictedICCProfile.eol}")
      ..write(trc[RestrictedICCProfile.GRAY])
      ..write(RestrictedICCProfile.eol);

    return rep.toString();
  }
}


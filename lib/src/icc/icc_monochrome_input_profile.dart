import 'icc_profile.dart';
import '../colorspace/color_space.dart';

/// The monochrome ICCProfile.
class ICCMonochromeInputProfile extends ICCProfile {
  /// Return the ICCProfile embedded in the input image
  ///   @param in jp2 image with embedded profile
  /// @return ICCMonochromeInputProfile
  /// @exception ColorSpaceICCProfileInvalidExceptionException
  /// @exception
  static ICCMonochromeInputProfile createInstance(ColorSpace csm) {
    return ICCMonochromeInputProfile(csm);
  }

  /// Construct a ICCMonochromeInputProfile corresponding to the profile file
  ///   @param f disk based ICCMonochromeInputProfile
  /// @return theICCMonochromeInputProfile
  /// @exception ColorSpaceException
  /// @exception ICCProfileInvalidException
  ICCMonochromeInputProfile(ColorSpace csm) : super(csm);
}

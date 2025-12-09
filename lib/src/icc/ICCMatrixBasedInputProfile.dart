import 'ICCProfile.dart';
import '../colorspace/ColorSpace.dart';

/// This class enables an application to construct an 3 component ICCProfile
class ICCMatrixBasedInputProfile extends ICCProfile {
  /// Factory method to create ICCMatrixBasedInputProfile based on a
  /// suppled profile file.
  ///   @param f contains a disk based ICCProfile.
  /// @return the ICCMatrixBasedInputProfile
  /// @exception ICCProfileInvalidException
  /// @exception ColorSpaceException
  static ICCMatrixBasedInputProfile createInstance(ColorSpace csm) {
    return ICCMatrixBasedInputProfile(csm);
  }

  /// Construct an ICCMatrixBasedInputProfile based on a
  /// suppled profile file.
  ///   @param f contains a disk based ICCProfile.
  /// @exception ColorSpaceException
  /// @exception ICCProfileInvalidException
  ICCMatrixBasedInputProfile(ColorSpace csm) : super(csm);
}


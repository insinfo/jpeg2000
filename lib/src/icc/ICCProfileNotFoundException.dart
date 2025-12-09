import 'ICCProfileException.dart';

/// Thrown when an image does not contain an ICC profile.
class ICCProfileNotFoundException extends ICCProfileException {
  ICCProfileNotFoundException([String message = 'no icc profile in image'])
      : super(message);
}

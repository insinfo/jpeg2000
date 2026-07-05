import 'icc_profile_exception.dart';

class ICCProfileInvalidException extends ICCProfileException {
  ICCProfileInvalidException([String? message])
      : super(message ?? "ICC profile is invalid");
}

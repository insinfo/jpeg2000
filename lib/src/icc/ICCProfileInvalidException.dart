import 'ICCProfileException.dart';

class ICCProfileInvalidException extends ICCProfileException {
  ICCProfileInvalidException([String? message])
      : super(message ?? "ICC profile is invalid");
}


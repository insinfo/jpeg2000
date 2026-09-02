/// Why a decode refused, one class per reason.
///
/// Every failure the public API reports for *input* problems is a
/// [Jpeg2000Exception]. Callers can match on the subtype to decide what to do:
/// a truncated download can be retried, a corrupted file cannot, an
/// unsupported feature is a request for the codec and not a bad file, and a
/// budget overrun is a policy decision made by the caller. API misuse (an
/// invalid option combination, a negative tile size) is still an
/// [ArgumentError], because it is a programming error and not a property of
/// the bytes.
sealed class Jpeg2000Exception implements Exception {
  const Jpeg2000Exception(this.message, {this.cause});

  /// Human-readable description of the failure.
  final String message;

  /// The lower-level error that triggered this exception, when there is one.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The bytes are neither a JP2 container nor a raw JPEG 2000 codestream.
final class Jpeg2000FormatException extends Jpeg2000Exception {
  const Jpeg2000FormatException(super.message, {super.cause});
}

/// The data ends before the container or codestream is complete.
final class Jpeg2000TruncatedException extends Jpeg2000Exception {
  const Jpeg2000TruncatedException(super.message, {super.cause});
}

/// The container or codestream carries values that violate the standard.
final class Jpeg2000CorruptedException extends Jpeg2000Exception {
  const Jpeg2000CorruptedException(super.message, {super.cause});
}

/// The input is valid but uses a feature this codec does not implement yet.
final class Jpeg2000UnsupportedException extends Jpeg2000Exception {
  const Jpeg2000UnsupportedException(super.message, {super.cause});
}

/// The image exceeds a limit the caller configured.
///
/// Raised before any pixel buffer is allocated, so a hostile header that
/// declares a gigantic image costs the caller nothing but this exception.
final class Jpeg2000BudgetException extends Jpeg2000Exception {
  const Jpeg2000BudgetException({
    required this.budget,
    required this.limit,
    required this.actual,
    required String message,
  }) : super(message);

  /// Name of the option that was exceeded, such as `maxPixels`.
  final String budget;

  /// The configured limit.
  final int limit;

  /// The value the image declares.
  final int actual;
}

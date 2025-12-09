/// Exception thrown when a JJ2000 command-line style argument has an
/// invalid format.
class StringFormatException implements FormatException {
  StringFormatException(this.message, [this.source, this.offset]);

  @override
  final String? source;

  @override
  final int? offset;

  @override
  final String message;

  @override
  String toString() => 'StringFormatException: $message';
}

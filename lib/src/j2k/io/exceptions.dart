/// Raised when a read operation reaches the end of the underlying data.
class EOFException implements Exception {
  EOFException([this.message]);

  final String? message;

  @override
  String toString() =>
      message == null ? 'EOFException' : 'EOFException: $message';
}

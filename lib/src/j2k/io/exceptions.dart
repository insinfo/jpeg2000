import 'dart:io';

/// Raised when a read operation reaches the end of the underlying data.
class EOFException extends IOException {
  EOFException([this.message]);

  final String? message;

  @override
  String toString() => message == null
      ? 'EOFException'
      : 'EOFException: $message';
}

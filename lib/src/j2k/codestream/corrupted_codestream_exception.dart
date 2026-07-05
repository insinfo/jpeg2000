import 'dart:io';

/// Raised when the codestream contains illegal or corrupted values.
class CorruptedCodestreamException extends IOException {
  CorruptedCodestreamException([this.message]);

  final String? message;

  @override
  String toString() => message == null
      ? 'CorruptedCodestreamException'
      : 'CorruptedCodestreamException: $message';
}

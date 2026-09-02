/// Raised when the codestream contains illegal or corrupted values.
class CorruptedCodestreamException implements Exception {
  CorruptedCodestreamException([this.message]);

  final String? message;

  @override
  String toString() => message == null
      ? 'CorruptedCodestreamException'
      : 'CorruptedCodestreamException: $message';
}

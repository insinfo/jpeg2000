/// Error thrown when an unimplemented JJ2000 feature is invoked.
class NotImplementedError extends Error {
  NotImplementedError([String? message])
      : message =
            message ?? 'The called method has not been implemented yet. Sorry!';

  final String message;

  @override
  String toString() => 'NotImplementedError: $message';
}

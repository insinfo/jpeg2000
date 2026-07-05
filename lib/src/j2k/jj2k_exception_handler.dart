import 'dart:io';

/// Utility that mimics JJ2000's exception handling behaviour.
class JJ2KExceptionHandler {
  JJ2KExceptionHandler._();

  /// Logs the failure and rethrows it so callers can terminate early.
  static Never handleException(Object error, [StackTrace? stackTrace]) {
    stderr.writeln('JJ2000 fatal error: $error');
    final effectiveStack = _stackTraceFor(error, stackTrace);
    if (effectiveStack != null) {
      stderr.writeln(effectiveStack);
    }
    Error.throwWithStackTrace(error, effectiveStack ?? StackTrace.current);
  }

  static StackTrace? _stackTraceFor(Object error, StackTrace? stackTrace) {
    if (stackTrace != null) {
      return stackTrace;
    }
    if (error is Error) {
      return error.stackTrace;
    }
    return null;
  }
}

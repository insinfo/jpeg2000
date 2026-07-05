/// Placeholder for JJ2000 native services.
///
/// The original library relied on OS-specific native methods to adjust POSIX
/// thread concurrency levels. This Dart port executes inside a single isolate,
/// so the calls become no-ops while retaining the API surface for code parity.
class NativeServices {
  NativeServices._();

  static const String sharedLibraryName = 'ucar/jpeg/jj2000';

  static int _libState = _libStateNotLoaded;
  static const int _libStateNotLoaded = 0;
  static const int _libStateLoaded = 1;
  static const int _libStateNotFound = 2;

  static bool loadLibrary() {
    if (_libState == _libStateLoaded) {
      return true;
    }
    _libState = _libStateNotFound;
    return false;
  }

  static void setThreadConcurrency(int level) {
    _checkLibrary();
    if (level < 0) {
      throw ArgumentError.value(level, 'level', 'Concurrency must be >= 0');
    }
    // No-op: Dart does not expose a direct analogue for pthread concurrency.
  }

  static int getThreadConcurrency() {
    _checkLibrary();
    return 0;
  }

  static void _checkLibrary() {
    if (_libState == _libStateLoaded) {
      return;
    }
    if (_libState == _libStateNotLoaded) {
      if (loadLibrary()) {
        return;
      }
    }
    throw UnsatisfiedLinkError(
      'NativeServices: native shared library could not be loaded',
    );
  }
}

/// Mirrors Java's UnsatisfiedLinkError for parity in tests.
class UnsatisfiedLinkError extends Error {
  UnsatisfiedLinkError(this.message);

  final String message;

  @override
  String toString() => 'UnsatisfiedLinkError: $message';
}

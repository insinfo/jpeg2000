/// Logging interface used by the JJ2000 port.
abstract class MsgLogger {
  static const int log = 0;
  static const int info = 1;
  static const int warning = 2;
  static const int error = 3;

  /// Returns the canonical label for [severity].
  static String labelFor(int severity) {
    switch (severity) {
      case log:
        return 'LOG';
      case info:
        return 'INFO';
      case warning:
        return 'WARNING';
      case error:
        return 'ERROR';
      default:
        return 'UNKNOWN';
    }
  }

  void printmsg(int severity, String message);

  void println(String message, int firstLineIndent, int indent);

  void flush();
}

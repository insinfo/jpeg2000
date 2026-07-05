import 'msg_logger.dart';
import '../platform/platform.dart' as platform;

/// Stream-backed implementation of [MsgLogger].
class StreamMsgLogger implements MsgLogger {
  StreamMsgLogger(StringSink out, StringSink err, {int lineWidth = 78})
      : _out = out,
        _err = err;

  factory StreamMsgLogger.stdout({int lineWidth = 78}) => StreamMsgLogger(
        platform.stdoutSink,
        platform.stderrSink,
        lineWidth: lineWidth,
      );

  final StringSink _out;
  final StringSink _err;

  @override
  void printmsg(int severity, String message) {
    final String label;
    switch (severity) {
      case MsgLogger.log:
        label = 'LOG';
        break;
      case MsgLogger.info:
        label = 'INFO';
        break;
      case MsgLogger.warning:
        label = 'WARNING';
        break;
      case MsgLogger.error:
        label = 'ERROR';
        break;
      default:
        throw ArgumentError('Severity $severity not valid.');
    }
    final target = severity >= MsgLogger.warning ? _err : _out;
    target.writeln('[$label]: $message');
  }

  @override
  void println(String message, int firstLineIndent, int indent) {
    _out.writeln('${' ' * firstLineIndent}$message');
  }

  @override
  void flush() {
    platform.flushSink(_out);
    platform.flushSink(_err);
  }
}

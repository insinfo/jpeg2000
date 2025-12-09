import 'dart:io';

import 'MsgLogger.dart';

/// Stream-backed implementation of [MsgLogger].
class StreamMsgLogger implements MsgLogger {
  StreamMsgLogger(StringSink out, StringSink err, {int lineWidth = 78})
      : _out = out,
        _err = err;

  factory StreamMsgLogger.stdout({int lineWidth = 78}) => StreamMsgLogger(
        stdout,
        stderr,
        lineWidth: lineWidth,
      );

  final StringSink _out;
  final StringSink _err;

  @override
  void printmsg(int severity, String message) {
    // if (severity < MsgLogger.log || severity > MsgLogger.error) {
    //   throw ArgumentError('Severity $severity not valid.');
    // }
    // final label = MsgLogger.labelFor(severity);
    // final target = severity >= MsgLogger.warning ? _err : _out;
    // _printer.print(target, 0, '[$label]: '.length, '[$label]: $message');
  }

  @override
  void println(String message, int firstLineIndent, int indent) {
    // _printer.print(_out, firstLineIndent, indent, message);
  }

  @override
  void flush() {
    if (_out case final IOSink outSink) {
      outSink.flush();
    }
    if (_err case final IOSink errSink) {
      errSink.flush();
    }
  }
}


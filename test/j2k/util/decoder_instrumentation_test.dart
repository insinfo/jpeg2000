import 'package:jpeg2000/src/j2k/util/DecoderInstrumentation.dart';
import 'package:jpeg2000/src/j2k/util/FacilityManager.dart';
import 'package:jpeg2000/src/j2k/util/MsgLogger.dart';
import 'package:test/test.dart';

void main() {
  group('DecoderInstrumentation', () {
    late MsgLogger originalLogger;
    late _RecordingLogger recording;

    setUp(() {
      originalLogger = FacilityManager.getMsgLogger();
      recording = _RecordingLogger();
      FacilityManager.registerMsgLogger(recording);
      DecoderInstrumentation.configure(false);
    });

    tearDown(() {
      FacilityManager.registerMsgLogger(originalLogger);
      DecoderInstrumentation.configure(false);
    });

    test('log emits message when enabled', () {
      DecoderInstrumentation.configure(true);
      DecoderInstrumentation.log('SRC', 'hello');

      expect(recording.messages, ['[INST][SRC] hello']);
    });

    test('log is no-op when disabled', () {
      DecoderInstrumentation.configure(false);
      DecoderInstrumentation.log('SRC', 'suppressed');

      expect(recording.messages, isEmpty);
    });

    test('section indents nested logs and restores state', () {
      DecoderInstrumentation.configure(true);

      final section = DecoderInstrumentation.section('SRC', 'outer');
      DecoderInstrumentation.log('SRC', 'inner');
      section.close();
      DecoderInstrumentation.log('SRC', 'after');

      expect(
        recording.messages,
        ['[INST][SRC] outer', '[INST][SRC]   inner', '[INST][SRC] after'],
      );
    });
  });
}

class _RecordingLogger implements MsgLogger {
  final List<String> messages = <String>[];

  @override
  void flush() {}

  @override
  void printmsg(int severity, String message) {
    if (severity == MsgLogger.info) {
      messages.add(message);
    }
  }

  @override
  void println(String message, int firstLineIndent, int indent) {}
}


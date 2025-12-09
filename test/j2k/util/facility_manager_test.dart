import 'dart:async';

import 'package:jpeg2000/src/j2k/util/FacilityManager.dart';
import 'package:jpeg2000/src/j2k/util/MsgLogger.dart';
import 'package:jpeg2000/src/j2k/util/ProgressWatch.dart';
import 'package:test/test.dart';

void main() {
  group('FacilityManager', () {
    late MsgLogger originalLogger;

    setUp(() {
      originalLogger = FacilityManager.getMsgLogger();
    });

    tearDown(() {
      FacilityManager.registerMsgLogger(originalLogger);
    });

    test('getMsgLogger returns default logger', () {
      expect(FacilityManager.getMsgLogger(), isNotNull);
    });

    test('registerMsgLogger without zone replaces default', () {
      final replacement = _RecordingLogger();
      FacilityManager.registerMsgLogger(replacement);
      expect(FacilityManager.getMsgLogger(), same(replacement));
    });

    test('registerMsgLogger associates with zone', () {
      final zoneLogger = _RecordingLogger();
      final outsideLogger = FacilityManager.getMsgLogger();

      runZoned(() {
        FacilityManager.registerMsgLogger(zoneLogger, zone: Zone.current);
        expect(FacilityManager.getMsgLogger(), same(zoneLogger));
      });

      expect(FacilityManager.getMsgLogger(), same(outsideLogger));
    });

    test('registerProgressWatch associates with zone', () {
      final zoneWatch = _RecordingProgressWatch();
      final initialWatch = FacilityManager.getProgressWatch();

      runZoned(() {
        FacilityManager.registerProgressWatch(zoneWatch, zone: Zone.current);
        expect(FacilityManager.getProgressWatch(), same(zoneWatch));
      });

      if (initialWatch == null) {
        expect(FacilityManager.getProgressWatch(), isNull);
      } else {
        expect(FacilityManager.getProgressWatch(), same(initialWatch));
      }
    });

    test('runWithLogger restores previous default', () {
      final replacement = _RecordingLogger();
      final original = FacilityManager.getMsgLogger();

      final result = FacilityManager.runWithLogger<int>(replacement, () {
        expect(FacilityManager.getMsgLogger(), same(replacement));
        return 42;
      });

      expect(result, 42);
      expect(FacilityManager.getMsgLogger(), same(original));
    });
  });
}

class _RecordingLogger implements MsgLogger {
  final List<String> recordedMessages = <String>[];
  final List<String> recordedLines = <String>[];

  @override
  void printmsg(int severity, String message) {
    recordedMessages.add('$severity:$message');
  }

  @override
  void println(String message, int firstLineIndent, int indent) {
    recordedLines.add(message);
  }

  @override
  void flush() {}
}

class _RecordingProgressWatch implements ProgressWatch {
  final List<String> events = <String>[];

  @override
  void initProgressWatch(int min, int max, String info) {
    events.add('init:$min:$max:$info');
  }

  @override
  void updateProgressWatch(int value, String info) {
    events.add('update:$value:$info');
  }

  @override
  void terminateProgressWatch() {
    events.add('terminate');
  }
}


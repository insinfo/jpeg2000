import 'package:jpeg2000/src/j2k/util/FacilityManager.dart';
import 'package:jpeg2000/src/j2k/util/MsgLogger.dart';

/// Mirrors the Java decoder instrumentation helper to keep logging semantics
/// aligned between the ports.
class DecoderInstrumentation {
  DecoderInstrumentation._();

  static bool _enabled = false;
  static int _indent = 0;

  /// Enables or disables instrumentation globally.
  static void configure(bool enable) {
    _enabled = enable;
  }

  /// Returns whether instrumentation output is currently active.
  static bool isEnabled() => _enabled;

  /// Emits a log entry when instrumentation is enabled.
  static void log(String? source, String message) {
    if (!_enabled) {
      return;
    }
    final logger = FacilityManager.getMsgLogger();
    final buffer = StringBuffer('[INST]');
    if (source != null && source.isNotEmpty) {
      buffer..write('[')..write(source)..write(']');
    }
    buffer..write(' ')
        ..write(' ' * (_indent < 0 ? 0 : _indent))
        ..write(message);
    logger.printmsg(MsgLogger.info, buffer.toString());
  }

  /// Opens an indented instrumentation section.
  static InstrumentationSection section(String? source, String message) {
    if (!_enabled) {
      return _NoopSection();
    }
    log(source, message);
    _indent = (_indent + 2).clamp(0, 1 << 30);
    return _ActiveSection();
  }

  static void _closeSection() {
    _indent = (_indent - 2).clamp(0, 1 << 30);
  }
}

/// Handle returned from [DecoderInstrumentation.section].
abstract class InstrumentationSection {
  void close();
}

class _ActiveSection implements InstrumentationSection {
  @override
  void close() {
    DecoderInstrumentation._closeSection();
  }
}

class _NoopSection implements InstrumentationSection {
  @override
  void close() {
    // no-op
  }
}


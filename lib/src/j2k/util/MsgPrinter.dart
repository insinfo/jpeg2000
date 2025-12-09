/// Utility that formats log messages to a fixed line width.
class MsgPrinter {
  MsgPrinter(int lineWidth)
      : assert(lineWidth > 0, 'lineWidth must be positive'),
        _lineWidth = lineWidth;

  int get lineWidth => _lineWidth;
  int _lineWidth;

  set lineWidth(int value) {
    if (value < 1) {
      throw ArgumentError('lineWidth must be positive');
    }
    _lineWidth = value;
  }

  void print(StringSink out, int firstLineIndent, int indent, String message) {
    var start = 0;
    var pend = 0;
    var effectiveWidth = _lineWidth - firstLineIndent;
    var currentIndent = firstLineIndent;

    while (true) {
      final end = _nextLineEnd(message, pend);
      if (end == _isEndOfString) {
        break;
      }

      if (end == _isNewline) {
        _writeIndent(out, currentIndent);
        out.writeln(message.substring(start, pend));
        final nextWordIndex = _nextWord(message, pend);
        if (nextWordIndex == message.length) {
          out.writeln('');
          start = pend;
          break;
        }
      } else {
        if (effectiveWidth > end - pend) {
          effectiveWidth -= end - pend;
          pend = end;
          continue;
        }
        _writeIndent(out, currentIndent);
        if (start == pend) {
          out.writeln(message.substring(start, end));
          pend = end;
        } else {
          out.writeln(message.substring(start, pend));
        }
      }

      currentIndent = indent;
      effectiveWidth = _lineWidth - indent;
      start = _nextWord(message, pend);
      pend = start;
      if (start == _isEndOfString) {
        break;
      }
    }

    if (pend != start) {
      _writeIndent(out, currentIndent);
      out.writeln(message.substring(start, pend));
    }
  }

  static const int _isNewline = -2;
  static const int _isEndOfString = -1;

  static void _writeIndent(StringSink sink, int count) {
    if (count <= 0) {
      return;
    }
    sink.write(''.padLeft(count));
  }

  static int _nextLineEnd(String message, int from) {
    final length = message.length;
    var index = from;
    while (index < length) {
      final code = message.codeUnitAt(index);
      if (code == 0x0A) {
        return _isNewline;
      }
      if (!_isWhitespaceCodeUnit(code)) {
        break;
      }
      index++;
    }
    if (index >= length) {
      return _isEndOfString;
    }
    while (index < length && !_isWhitespaceCodeUnit(message.codeUnitAt(index))) {
      index++;
    }
    return index;
  }

  static int _nextWord(String message, int from) {
    final length = message.length;
    var index = from;
    while (index < length) {
      final code = message.codeUnitAt(index);
      if (code == 0x0A) {
        return index + 1;
      }
      if (!_isWhitespaceCodeUnit(code)) {
        break;
      }
      index++;
    }
    if (index >= length) {
      return _isEndOfString;
    }
    return index;
  }

  static bool _isWhitespaceCodeUnit(int code) {
    switch (code) {
      case 0x09: // tab
      case 0x0A: // line feed
      case 0x0B: // vertical tab
      case 0x0C: // form feed
      case 0x0D: // carriage return
      case 0x20: // space
        return true;
    }
    return false;
  }
}

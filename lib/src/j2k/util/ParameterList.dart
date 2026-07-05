import 'dart:collection';

import 'StringFormatException.dart';
import '../platform/platform.dart' as platform;

/// Container for JJ2000-style parameters and options.
class ParameterList {
  ParameterList([ParameterList? defaults])
      : _defaults = defaults,
        _values = <String, String>{};

  final ParameterList? _defaults;
  final Map<String, String> _values;

  /// Returns the defaults inherited by this list, if any.
  ParameterList? getDefaultParameterList() => _defaults;

  /// Returns an iterable view of the parameter names, including defaults.
  Iterable<String> propertyNames() {
    final ordered = LinkedHashSet<String>()
      ..addAll(_defaults?.propertyNames() ?? const <String>[])
      ..addAll(_values.keys);
    return ordered;
  }

  /// Returns the raw value for [name] if present in this list only.
  String? _getLocal(String name) => _values[name];

  /// Puts [value] under [name].
  void put(String name, String value) {
    _values[name] = value;
  }

  /// Removes the local value assigned to [name].
  void remove(String name) {
    _values.remove(name);
  }

  /// Loads parameters from [file].
  Future<void> loadFromFile(Object file) async {
    final contents = await platform.readTextSource(file);
    loadFromString(contents);
  }

  /// Loads parameters from the given [contents].
  void loadFromString(String contents) {
    for (final line in _logicalPropertyLines(contents)) {
      final parsed = _parsePropertyLine(line);
      if (parsed == null) {
        continue;
      }
      put(parsed.key, parsed.value);
    }
  }

  /// Parses command line style arguments.
  void parseArgs(List<String> argv) {
    var index = 0;

    String takeOptionName(String token) {
      if (token.length <= 1) {
        throw StringFormatException('Option "$token" is too short.');
      }
      final sign = token[0];
      if (sign != '-' && sign != '+') {
        throw StringFormatException(
            'Argument list does not start with an option: $token');
      }
      if (token.length >= 2 && _isDigit(token.codeUnitAt(1))) {
        throw StringFormatException('Numeric option name: $token');
      }
      return token;
    }

    while (index < argv.length) {
      while (index < argv.length && argv[index].isEmpty) {
        index++;
      }
      if (index >= argv.length) {
        return;
      }

      final rawName = takeOptionName(argv[index++]);
      final prefix = rawName[0];
      final name = rawName.substring(1);
      final values = <String>[];

      if (index >= argv.length) {
        values.add(prefix == '-' ? 'on' : 'off');
      } else {
        var token = argv[index];
        if (token.isNotEmpty && _isOptionToken(token)) {
          values.add(prefix == '-' ? 'on' : 'off');
        }
      }

      if (values.isEmpty) {
        if (prefix == '+') {
          throw StringFormatException('Boolean option "$rawName" has a value');
        }
        while (index < argv.length) {
          final token = argv[index];
          if (token.isEmpty) {
            index++;
            continue;
          }
          if (_isOptionToken(token) && !_startsWithDigit(token)) {
            break;
          }
          values.add(token);
          index++;
        }
        if (values.isEmpty) {
          throw StringFormatException('Missing value for option "$rawName"');
        }
      }

      if (containsKey(name)) {
        throw StringFormatException('Option "$rawName" appears more than once');
      }
      put(name, values.join(' '));
    }
  }

  bool containsKey(String name) => _values.containsKey(name);

  /// Returns the string value for [name], checking defaults if needed.
  String? getParameter(String name) {
    final local = _getLocal(name);
    if (local != null) {
      return local;
    }
    return _defaults?.getParameter(name);
  }

  /// Returns the boolean value for [name].
  bool getBooleanParameter(String name) {
    final value = getParameter(name);
    if (value == null) {
      throw ArgumentError('No parameter with name $name');
    }
    if (value == 'on') {
      return true;
    }
    if (value == 'off') {
      return false;
    }
    throw StringFormatException('Parameter "$name" is not boolean: $value');
  }

  /// Returns the integer value for [name].
  int getIntParameter(String name) {
    final value = getParameter(name);
    if (value == null) {
      throw ArgumentError('No parameter with name $name');
    }
    return int.parse(value);
  }

  /// Returns the floating point value for [name].
  double getFloatParameter(String name) {
    final value = getParameter(name);
    if (value == null) {
      throw ArgumentError('No parameter with name $name');
    }
    return double.parse(value);
  }

  /// Validates parameters whose names start with [prefix].
  void checkListSingle(int prefix, List<String>? validNames) {
    for (final name in propertyNames()) {
      if (name.isEmpty) {
        continue;
      }
      if (name.codeUnitAt(0) == prefix) {
        if (validNames == null || !validNames.contains(name)) {
          throw ArgumentError("Option '$name' is not a valid one.");
        }
      }
    }
  }

  /// Validates parameters whose names do not start with any of [prefixes].
  void checkList(List<int> prefixes, List<String>? validNames) {
    final disallowed = prefixes.toSet();
    for (final name in propertyNames()) {
      if (name.isEmpty) {
        continue;
      }
      if (disallowed.contains(name.codeUnitAt(0))) {
        continue;
      }
      if (validNames == null || !validNames.contains(name)) {
        throw ArgumentError("Option '$name' is not a valid one.");
      }
    }
  }

  /// Converts usage metadata into a list of parameter names.
  static List<String>? toNameArray(List<List<String?>>? pinfo) {
    if (pinfo == null) {
      return null;
    }
    final names = List<String>.filled(pinfo.length, '', growable: false);
    for (var i = 0; i < pinfo.length; i++) {
      names[i] = pinfo[i][0]!;
    }
    return names;
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isOptionToken(String token) {
    if (token.length <= 1) {
      return false;
    }
    final first = token[0];
    if (first != '-' && first != '+') {
      return false;
    }
    return !_isDigit(token.codeUnitAt(1));
  }

  static bool _startsWithDigit(String token) {
    if (token.isEmpty) {
      return false;
    }
    return _isDigit(token.codeUnitAt(0));
  }

  static Iterable<String> _logicalPropertyLines(String contents) sync* {
    final physicalLines = contents.split(RegExp(r'\r\n?|\n'));
    String? current;
    var continuing = false;

    for (var rawLine in physicalLines) {
      var line =
          continuing ? rawLine.replaceFirst(RegExp(r'^[ \t\f]*'), '') : rawLine;
      current = (current ?? '') + line;

      if (_continuesPropertyLine(current)) {
        current = current.substring(0, current.length - 1);
        continuing = true;
        continue;
      }

      yield current;
      current = null;
      continuing = false;
    }

    if (current != null) {
      yield current;
    }
  }

  static bool _continuesPropertyLine(String line) {
    var count = 0;
    for (var i = line.length - 1; i >= 0 && line.codeUnitAt(i) == 0x5c; i--) {
      count++;
    }
    return count.isOdd;
  }

  static _PropertyEntry? _parsePropertyLine(String line) {
    var index = 0;
    while (
        index < line.length && _isPropertyWhitespace(line.codeUnitAt(index))) {
      index++;
    }
    if (index == line.length) {
      return null;
    }
    final first = line.codeUnitAt(index);
    if (first == 0x23 || first == 0x21) {
      return null;
    }

    final keyStart = index;
    var escaped = false;
    while (index < line.length) {
      final code = line.codeUnitAt(index);
      if (!escaped &&
          (code == 0x3d || code == 0x3a || _isPropertyWhitespace(code))) {
        break;
      }
      if (code == 0x5c && !escaped) {
        escaped = true;
      } else {
        escaped = false;
      }
      index++;
    }

    final keyEnd = index;
    while (
        index < line.length && _isPropertyWhitespace(line.codeUnitAt(index))) {
      index++;
    }
    if (index < line.length) {
      final code = line.codeUnitAt(index);
      if (code == 0x3d || code == 0x3a) {
        index++;
        while (index < line.length &&
            _isPropertyWhitespace(line.codeUnitAt(index))) {
          index++;
        }
      }
    }

    final key = _unescapeProperty(line.substring(keyStart, keyEnd));
    if (key.isEmpty) {
      throw StringFormatException('Empty parameter name in: $line');
    }
    final value = _unescapeProperty(line.substring(index));
    return _PropertyEntry(key, value);
  }

  static bool _isPropertyWhitespace(int code) {
    return code == 0x20 || code == 0x09 || code == 0x0c;
  }

  static String _unescapeProperty(String raw) {
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      if (code != 0x5c) {
        out.writeCharCode(code);
        continue;
      }
      if (i + 1 >= raw.length) {
        out.writeCharCode(code);
        continue;
      }
      final next = raw[++i];
      switch (next) {
        case 't':
          out.write('\t');
          break;
        case 'r':
          out.write('\r');
          break;
        case 'n':
          out.write('\n');
          break;
        case 'f':
          out.write('\f');
          break;
        case 'u':
          if (i + 4 >= raw.length) {
            throw StringFormatException('Malformed Unicode escape in: $raw');
          }
          final hex = raw.substring(i + 1, i + 5);
          final value = int.tryParse(hex, radix: 16);
          if (value == null) {
            throw StringFormatException('Malformed Unicode escape in: $raw');
          }
          out.writeCharCode(value);
          i += 4;
          break;
        default:
          out.write(next);
          break;
      }
    }
    return out.toString();
  }
}

class _PropertyEntry {
  const _PropertyEntry(this.key, this.value);

  final String key;
  final String value;
}

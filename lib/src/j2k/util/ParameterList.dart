import 'dart:collection';
import 'dart:io';

import 'StringFormatException.dart';

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
  Future<void> loadFromFile(File file) async {
    final contents = await file.readAsString();
    loadFromString(contents);
  }

  /// Loads parameters from the given [contents].
  void loadFromString(String contents) {
    // TODO(jj2000): Support the full Java Properties escaping semantics.
    final lines = contents.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      while (line.endsWith('\\')) {
        line = line.substring(0, line.length - 1);
        if (i + 1 >= lines.length) {
          break;
        }
        line += lines[++i].trim();
      }

      final combined = line;
      final separator = combined.indexOf('=');
      if (separator == -1) {
        throw StringFormatException('Missing "=" in parameter: $combined');
      }
      final key = combined.substring(0, separator).trim();
      final value = combined.substring(separator + 1).trim();
      if (key.isEmpty) {
        throw StringFormatException('Empty parameter name in: $combined');
      }
      put(key, value);
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
}


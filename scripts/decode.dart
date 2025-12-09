import 'dart:io';

import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';
import 'package:jpeg2000/src/j2k/util/StringFormatException.dart';

void main(List<String> args) {
  final baseDefaults = Decoder.buildDefaultParameterList();
  var params = ParameterList(baseDefaults);
  _parseArgs(params, args);

  final pfile = params.getParameter('pfile');
  if (pfile != null && pfile.isNotEmpty) {
    final fileBackedDefaults = ParameterList(baseDefaults);
    _loadParameterFile(fileBackedDefaults, pfile);

    params = ParameterList(fileBackedDefaults);
    _parseArgs(params, args);
  }

  final decoder = Decoder(params);
  decoder.run();
  if (decoder.exitCode != 0) {
    stderr.writeln('Decoder failed with exit code ${decoder.exitCode}.');
    exit(decoder.exitCode);
  }
}

void _parseArgs(ParameterList target, List<String> args) {
  try {
    target.parseArgs(args);
  } on StringFormatException catch (error) {
    stderr.writeln('Invalid arguments: ${error.message}');
    exit(64);
  }
}

void _loadParameterFile(ParameterList target, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln("Argument file '$path' not found.");
    exit(66);
  }

  try {
    target.loadFromString(file.readAsStringSync());
    target.remove('pfile');
  } on IOException catch (error) {
    stderr.writeln('Failed to read argument file $path: $error');
    exit(74);
  } on StringFormatException catch (error) {
    stderr.writeln('Invalid entry in argument file $path: ${error.message}');
    exit(65);
  }
}

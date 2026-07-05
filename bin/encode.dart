import 'dart:io';

import 'package:jpeg2000/src/j2k/encoder/encoder.dart';
import 'package:jpeg2000/src/j2k/util/facility_manager.dart';
import 'package:jpeg2000/src/j2k/util/parameter_list.dart';
import 'package:jpeg2000/src/j2k/util/stream_msg_logger.dart';

/// Runs the JJ2000 encoder from the command line.
///
/// Usage: `dart run jpeg2000:encode -i <input.ppm|.pgm> -o <output.j2k> [options]`
/// Common options: `-lossless on`, `-rate <bpp>`, `-file_format on` (JP2 wrapper),
/// `-Alayers <spec>`, `-Wlev <levels>`.
void main(List<String> args) {
  final defaults = Encoder.buildDefaultParameterList();
  final params = ParameterList(defaults);
  _parseArgs(params, args);

  final logger = StreamMsgLogger.stdout();
  FacilityManager.registerMsgLogger(logger);

  final encoder = Encoder(params);
  encoder.run();
  if (encoder.exitCode != 0) {
    stderr.writeln('Encoder failed with exit code ${encoder.exitCode}.');
    exit(encoder.exitCode);
  }
}

void _parseArgs(ParameterList target, List<String> args) {
  String? currentOption;
  final buffer = StringBuffer();

  void flush() {
    if (currentOption != null) {
      target.put(currentOption, buffer.toString().trim());
      buffer.clear();
    }
  }

  for (final arg in args) {
    // An option starts with '-' followed by a letter; this keeps negative
    // numeric values (e.g. "-1") as arguments of the preceding option.
    final isOption = arg.length > 1 &&
        arg.startsWith('-') &&
        RegExp(r'[a-zA-Z]').hasMatch(arg[1]);
    if (isOption) {
      flush();
      currentOption = arg.substring(1);
    } else {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(arg);
    }
  }
  flush();
}

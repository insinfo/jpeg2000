import 'dart:io';

import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/FacilityManager.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';
import 'package:jpeg2000/src/j2k/util/StreamMsgLogger.dart';



/// Simple helper to run the JJ2000 decoder and emit BMP output from a codestream.
///
/// Usage: `dart run scripts/decode_to_bmp.dart <input.jp2> <output.bmp>`
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run scripts/decode_to_bmp.dart <input.jp2> <output.bmp>');
    exit(64);
  }

  final inputPath = args[0];
  final outputPath = args[1];

  final parameters = ParameterList()
    ..put('i', inputPath)
    ..put('o', outputPath)
    ..put('verbose', 'on')
    ..put('debug', 'off');

  final logger = StreamMsgLogger.stdout();
  final decoder = FacilityManager.runWithLogger(logger, () {
    final instance = Decoder(parameters);
    instance.run();
    return instance;
  });

  if (decoder.exitCode != 0) {
    stderr.writeln('Decoder failed with exit code ${decoder.exitCode}.');
    exit(decoder.exitCode);
  }
}


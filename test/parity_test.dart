import 'dart:io';
import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';
import 'package:test/test.dart';

void main() {
  test('Parity test', () {
    final input = Platform.environment['JJ2000_INPUT'];
    if (input == null) {
      // print('Skipping parity test: JJ2000_INPUT not set');
      return;
    }

    final instrument = Platform.environment['JJ2000_INSTRUMENT'] ?? 'on';

    final args = <String>[
      '-i', input,
      '-o', 'build/parity_out.pgx',
      '-instrument', instrument,
      '-verbose', 'off',
      '-debug', 'off',
    ];
    
    final defaults = Decoder.buildDefaultParameterList();
    final pl = ParameterList(defaults);
    pl.parseArgs(args);
    
    final decoder = Decoder(pl);
    decoder.run();
    
    if (decoder.exitCode != 0) {
      fail('Decoder exited with code ${decoder.exitCode}');
    }
  });
}


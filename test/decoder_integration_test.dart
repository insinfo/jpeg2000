import 'dart:io';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';
import 'test_utils.dart';

void main() {
  group('DecoderIntegrationTest', () {
    test('barras_rgb produces colorful PPM', () {
      final inputPath = 'test_images/barras_rgb.jp2';
      final inputFile = File(inputPath);
      if (!inputFile.existsSync()) {
        fail('Input codestream missing: $inputPath');
      }

      final outputDir = Directory.systemTemp.createTempSync('jj2000_test_');
      final outputPath = '${outputDir.path}/barras_rgb.ppm';

      final params = ParameterList(Decoder.buildDefaultParameterList());
      params.put('u', 'off');
      params.put('v', 'off');
      params.put('verbose', 'off');
      params.put('debug', 'off');
      params.put('i', inputPath);
      params.put('o', outputPath);

      final decoder = Decoder(params);
      decoder.run();

      expect(decoder.exitCode, 0, reason: 'Decoder exited with non-zero code');

      final outputFile = File(outputPath);
      expect(outputFile.existsSync(), isTrue, reason: 'Output file not created');

      final ppmBytes = outputFile.readAsBytesSync();
      final probe = PpmProbe.fromBytes(ppmBytes);

      expect(probe.pixelCount, greaterThan(0), reason: 'Expected at least one pixel');
      expect(probe.uniqueChannelValues.length, greaterThan(3), reason: 'Expected diverse channel values');
      expect(probe.hasChrominance, isTrue, reason: 'Expected at least one pixel with chrominance differences');

      // Cleanup
      outputDir.deleteSync(recursive: true);
    });
  });
}


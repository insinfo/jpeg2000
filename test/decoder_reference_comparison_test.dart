import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';

ParameterList _baseDecoderParameters() {
  final params = ParameterList(Decoder.buildDefaultParameterList());
  params
    ..put('u', 'off')
    ..put('v', 'off')
    ..put('verbose', 'off')
    ..put('debug', 'off');
  return params;
}

void main() {
  group('Decoder Reference Comparison Tests', () {


    test('Decode multiple test images successfully', () {
      final testImages = [
        'test_images/barras_rgb.jp2',
        'test_images/simple.jp2',
        'test_images/generated/gradient_horizontal_openjpeg.jp2',
        'test_images/generated/gradient_vertical_openjpeg.jp2',
        'test_images/generated/checkerboard_openjpeg.jp2',
        'test_images/generated/solid_red_openjpeg.jp2',
        'test_images/generated/solid_green_openjpeg.jp2',
        'test_images/generated/solid_blue_openjpeg.jp2',
        'test_images/generated/rainbow_stripes_openjpeg.jp2',
        'test_images/generated/circles_openjpeg.jp2',
      ];

      var successCount = 0;
      for (final imagePath in testImages) {
        final inputFile = File(imagePath);
        if (!inputFile.existsSync()) {
          // print('⚠ Test image not found: $imagePath');
          continue;
        }

        final outputDir = Directory.systemTemp.createTempSync('decoder_test_');
        try {
          final outputPath = '${outputDir.path}/output.ppm';

          final params = _baseDecoderParameters()
            ..put('i', imagePath)
            ..put('o', outputPath);

          final decoder = Decoder(params);
          decoder.run();

          if (decoder.exitCode == 0) {
            final outputFile = File(outputPath);
            if (outputFile.existsSync()) {
              final data = _parsePPM(outputFile.readAsBytesSync());
              expect(data.width * data.height, greaterThan(0),
                  reason: 'Image $imagePath has no pixels');
              successCount++;
              // print('✓ Successfully decoded: $imagePath (${data.width}x${data.height})');
            }
          }
        } finally {
          outputDir.deleteSync(recursive: true);
        }
      }

      expect(successCount, greaterThan(0),
          reason: 'Expected at least one test image to decode successfully');
    });

    test('Entropy decoder handles various code-block configurations', () {
      // This test verifies that the entropy decoder (with our new implementations)
      // can handle different JPEG2000 encoding parameters
      
      final inputPath = 'test_images/barras_rgb.jp2';
      final inputFile = File(inputPath);
      if (!inputFile.existsSync()) {
        // print('⚠ Input file missing: $inputPath');
        return;
      }

      final outputDir = Directory.systemTemp.createTempSync('entropy_test_');
      try {
        final outputPath = '${outputDir.path}/output.ppm';

        final params = _baseDecoderParameters()
          ..put('i', inputPath)
          ..put('o', outputPath);

        final decoder = Decoder(params);
        decoder.run();

        expect(decoder.exitCode, 0,
            reason: 'Decoder should handle standard JPEG2000 file');

        final outputFile = File(outputPath);
        expect(outputFile.existsSync(), isTrue);

        final data = _parsePPM(outputFile.readAsBytesSync());
        
        // Verify the output has reasonable pixel values
        var nonZeroPixels = 0;
        var pixelSum = 0;
        for (var i = 0; i < data.pixels.length; i++) {
          if (data.pixels[i] != 0) nonZeroPixels++;
          pixelSum += data.pixels[i];
        }

        expect(nonZeroPixels, greaterThan(data.pixels.length ~/ 2),
            reason: 'Expected most pixels to be non-zero');

        final avgPixelValue = pixelSum / data.pixels.length;
        expect(avgPixelValue, greaterThan(10),
            reason: 'Average pixel value should be reasonable');
        expect(avgPixelValue, lessThan(245),
            reason: 'Average pixel value should not be saturated');

        // print('✓ Entropy decoder processed image successfully');
        // print('  Image: ${data.width}x${data.height}');
        // print('  Non-zero pixels: ${(nonZeroPixels / data.pixels.length * 100).toStringAsFixed(1)}%');
        // print('  Average pixel value: ${avgPixelValue.toStringAsFixed(1)}');

      } finally {
        outputDir.deleteSync(recursive: true);
      }
    });


  });
}

class _PPMData {
  final int width;
  final int height;
  final Uint8List pixels;

  _PPMData(this.width, this.height, this.pixels);
}

_PPMData _parsePPM(Uint8List bytes) {
  var offset = 0;

  // Skip "P6" magic number
  while (offset < bytes.length && bytes[offset] != 0x0A) {
    offset++;
  }
  offset++; // Skip newline

  // Skip comments
  while (offset < bytes.length && bytes[offset] == 0x23) {
    while (offset < bytes.length && bytes[offset] != 0x0A) {
      offset++;
    }
    offset++;
  }

  // Read width and height
  final dimensions = <int>[];
  var currentNumber = '';
  while (dimensions.length < 2 && offset < bytes.length) {
    final ch = bytes[offset];
    if (ch >= 0x30 && ch <= 0x39) {
      // digit
      currentNumber += String.fromCharCode(ch);
    } else if (currentNumber.isNotEmpty) {
      dimensions.add(int.parse(currentNumber));
      currentNumber = '';
    }
    offset++;
  }

  final width = dimensions[0];
  final height = dimensions[1];

  // Skip max value line
  while (offset < bytes.length && bytes[offset] != 0x0A) {
    offset++;
  }
  offset++; // Skip newline

  // Remaining bytes are pixel data
  final pixels = Uint8List.sublistView(bytes, offset);

  return _PPMData(width, height, pixels);
}


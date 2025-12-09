import 'dart:io';

import 'package:test/test.dart';

import 'image_test_utils.dart';

class _ConformanceCase {
  final String name;
  final String filename;
  final bool isLossless;

  const _ConformanceCase(this.name, this.filename, {this.isLossless = true});
}

const _conformanceCases = <_ConformanceCase>[
  _ConformanceCase('file1', 'file1.jp2'),
  _ConformanceCase('relax', 'relax.jp2', isLossless: false),
];

void main() {
  group('JJ2000 Conformance Subset', () {
    final baseDir = Directory('resources/j2k_tests/conformance_subset');

    for (final testCase in _conformanceCases) {
      test('${testCase.name} decodes successfully', () async {
        if (!baseDir.existsSync()) {
          fail('Diretório de conformidade ausente: ${baseDir.path}');
        }

        final codestream = File('${baseDir.path}/${testCase.filename}');
        if (!codestream.existsSync()) {
          fail('Arquivo de teste ausente: ${codestream.path}');
        }

        //TODO  We don't have reference images yet, so we just check if it decodes without error
        // and produces a valid image structure.
        final decodedImage = await decodeCodestreamWithJj2000(
          codestream,
          outputExtension: '.ppm', // Default to PPM for now
        );

        expect(decodedImage.width, greaterThan(0));
        expect(decodedImage.height, greaterThan(0));
        expect(decodedImage.data.length, equals(decodedImage.width * decodedImage.height * decodedImage.channels * decodedImage.bytesPerSample));
      });
    }
  });
}

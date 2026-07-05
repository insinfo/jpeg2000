@TestOn('vm')
import 'dart:io';

import 'package:test/test.dart';

import 'image_test_utils.dart';

class _ConformanceCase {
  final String name;
  final String filename;
  final String referenceFilename;

  const _ConformanceCase(
    this.name,
    this.filename,
    this.referenceFilename,
  );
}

const _conformanceCases = <_ConformanceCase>[
  _ConformanceCase('file1', 'file1.jp2', 'file1_reference.ppm'),
  _ConformanceCase('relax', 'relax.jp2', 'relax_reference.ppm'),
];

void main() {
  group('JJ2000 Conformance Subset', () {
    final baseDir = Directory('test/fixtures/j2k_tests/conformance_subset');

    for (final testCase in _conformanceCases) {
      test('${testCase.name} decodes successfully', () async {
        if (!baseDir.existsSync()) {
          fail('Diretório de conformidade ausente: ${baseDir.path}');
        }

        final codestream = File('${baseDir.path}/${testCase.filename}');
        if (!codestream.existsSync()) {
          fail('Arquivo de teste ausente: ${codestream.path}');
        }
        final reference = File('${baseDir.path}/${testCase.referenceFilename}');
        if (!reference.existsSync()) {
          fail('Imagem de referência ausente: ${reference.path}');
        }

        final decodedImage = await decodeCodestreamWithJj2000(
          codestream,
          outputExtension: '.ppm', // Default to PPM for now
        );
        final referenceImage = await loadPortableImage(reference);

        expectImagesAlmostEqual(
          decodedImage,
          referenceImage,
          maxAbsError: 0,
        );
      });
    }
  });
}

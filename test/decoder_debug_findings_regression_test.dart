@TestOn('vm')

import 'dart:io';

import 'package:test/test.dart';

import 'image_test_utils.dart';

void main() {
  group('DEBUG_FINDINGS regressions', () {
    final generated = Directory('test/fixtures/test_images/generated');
    final conformance = Directory('test/fixtures/j2k_tests/conformance_subset');

    final cases = <_ReferenceCase>[
      _ReferenceCase(
        'file1 lossless RCT keeps original range bits and entropy state',
        File('${conformance.path}/file1.jp2'),
        File('${conformance.path}/file1_reference.ppm'),
        0,
      ),
      _ReferenceCase(
        'relax skips degenerate ICC profile and remains bit-exact',
        File('${conformance.path}/relax.jp2'),
        File('${conformance.path}/relax_reference.ppm'),
        0,
      ),
      _ReferenceCase(
        'gradient catches sigProgPass MQ desynchronisation',
        File('${generated.path}/gradient_horizontal_jj2000.j2k'),
        File('${generated.path}/gradient_horizontal_jj2000_decoded.ppm'),
        0,
      ),
      _ReferenceCase(
        'checkerboard catches HH zero-coding LUT context regression',
        File('${generated.path}/checkerboard_jj2000.j2k'),
        File('${generated.path}/checkerboard_jj2000_decoded.ppm'),
        0,
      ),
      _ReferenceCase(
        'circles catches ICT float32 rounding regressions',
        File('${generated.path}/circles_jj2000.j2k'),
        File('${generated.path}/circles_jj2000_decoded.ppm'),
        1,
      ),
      _ReferenceCase(
        'noise catches high-detail entropy and ICT regressions',
        File('${generated.path}/noise_pattern_jj2000.j2k'),
        File('${generated.path}/noise_pattern_jj2000_decoded.ppm'),
        1,
      ),
    ];

    for (final testCase in cases) {
      test(testCase.name, () async {
        expect(testCase.codestream.existsSync(), isTrue);
        expect(testCase.reference.existsSync(), isTrue);

        final decoded = await decodeCodestreamWithJj2000(
          testCase.codestream,
          outputExtension: '.ppm',
        );
        final reference = await loadPortableImage(testCase.reference);

        expectImagesAlmostEqual(
          decoded,
          reference,
          maxAbsError: testCase.maxAbsError,
        );
      });
    }
  });
}

class _ReferenceCase {
  const _ReferenceCase(
    this.name,
    this.codestream,
    this.reference,
    this.maxAbsError,
  );

  final String name;
  final File codestream;
  final File reference;
  final int maxAbsError;
}

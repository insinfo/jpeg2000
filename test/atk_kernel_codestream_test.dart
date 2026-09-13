@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:j2k/j2k.dart';
import 'package:j2k/src/j2k/codestream/markers.dart';
import 'package:j2k/src/j2k/codestream/reader/atk_marker.dart';
import 'package:j2k/src/j2k/wavelet/atk_kernel.dart';
import 'package:test/test.dart';

/// End-to-end decoding of a codestream whose wavelet kernel comes from an ATK
/// marker segment (ISO/IEC 15444-2, ITU-T T.801, A.3.5).
///
/// No encoder in this package writes Part 2 codestreams and no fixture carries
/// one, so the tests build one: an ordinary Part 1 codestream is rewritten so
/// that its `SPcod` transformation field names an ATK index (T.801 Table A.10
/// assigns 2 to 255 to ATK marker segments) and the matching segment is
/// inserted into the header. The kernels used are the two of
/// ISO/IEC 15444-1 written as lifting steps, which T.801 G.4.1.1 and G.4.2.3
/// state are mathematically the same transformations, so the decoded image
/// must equal the one the built-in filters produce.
void main() {
  /// T.801 Table G.2: the 5-3 reversible kernel as lifting steps.
  AtkKernel reversible53(int index) => AtkKernel(
        index: index,
        coefficientType: 0,
        wholeSampleSymmetric: true,
        reversible: true,
        initialParity: 0,
        constantExtension: false,
        scale: 1,
        steps: const <AtkLiftingStep>[
          AtkLiftingStep(coefficients: <double>[-1], exponent: 1, residue: 1),
          AtkLiftingStep(coefficients: <double>[1], exponent: 2, residue: 2),
        ],
      );

  /// T.801 Table G.6: the 9-7 irreversible kernel as lifting steps.
  AtkKernel irreversible97(int index) => AtkKernel(
        index: index,
        coefficientType: 2,
        wholeSampleSymmetric: true,
        reversible: false,
        initialParity: 0,
        constantExtension: false,
        scale: 1.230174104914001,
        steps: const <AtkLiftingStep>[
          AtkLiftingStep(coefficients: <double>[-1.586134342059924]),
          AtkLiftingStep(coefficients: <double>[-0.052980118572961]),
          AtkLiftingStep(coefficients: <double>[0.882911075530934]),
          AtkLiftingStep(coefficients: <double>[0.443506852043971]),
        ],
      );

  Uint8List sourcePixels(int width, int height, int components) {
    final pixels = Uint8List(width * height * components);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        for (var c = 0; c < components; c++) {
          pixels[(y * width + x) * components + c] =
              ((x * 7 + y * y) ^ (x * y + c * 53)) & 0xff;
        }
      }
    }
    return pixels;
  }

  Uint8List encode(
    int width,
    int height,
    int components, {
    required bool lossless,
  }) =>
      encodeJpeg2000Pixels(
        sourcePixels(width, height, components),
        width: width,
        height: height,
        components: components,
        options: Jpeg2000EncodeOptions(
          lossless: lossless,
          rate: lossless ? null : 1.0,
          wrapInJp2: false,
        ),
      );

  /// Where the main header keeps its COD marker segment.
  ({int start, int end, int transformOffset}) locateCod(Uint8List codestream) {
    var position = 2; // past SOC
    while (position + 4 <= codestream.length) {
      final marker = (codestream[position] << 8) | codestream[position + 1];
      if (marker == Markers.sot) {
        break;
      }
      final length = (codestream[position + 2] << 8) | codestream[position + 3];
      if (marker == Markers.cod) {
        // Lcod(2) Scod(1) SGcod(4) then SPcod: NDL(1) xcb(1) ycb(1) style(1)
        // and the transformation byte.
        return (
          start: position,
          end: position + 2 + length,
          transformOffset: position + 2 + 2 + 1 + 4 + 4,
        );
      }
      position += 2 + length;
    }
    throw StateError('The codestream has no COD marker segment.');
  }

  Uint8List markerSegment(int marker, Uint8List payload) => Uint8List.fromList(
        <int>[(marker >> 8) & 0xff, marker & 0xff, ...payload],
      );

  /// Points the main COD at [kernel] and adds its ATK marker segment.
  ///
  /// [atkBeforeCod] puts the definition ahead of the segment that uses it;
  /// T.801 A.3.5 sets no order between the two, so both have to work.
  Uint8List useAtkKernel(
    Uint8List codestream,
    AtkKernel kernel, {
    bool atkBeforeCod = false,
  }) {
    final cod = locateCod(codestream);
    final atk = markerSegment(Markers.atk, AtkMarker.build(kernel));
    final insertAt = atkBeforeCod ? cod.start : cod.end;

    final patched = Uint8List(codestream.length + atk.length);
    patched.setRange(0, insertAt, codestream);
    patched.setRange(insertAt, insertAt + atk.length, atk);
    patched.setRange(
        insertAt + atk.length, patched.length, codestream, insertAt);
    final transformAt = cod.transformOffset + (atkBeforeCod ? atk.length : 0);
    patched[transformAt] = kernel.index;
    return patched;
  }

  /// Copies the main COD into the first tile-part header, pointed at [kernel],
  /// and puts the ATK definition there too.
  ///
  /// This is the override case of T.801 A.3.5: the definition that counts for
  /// a tile is the one in its first tile-part header.
  Uint8List useAtkKernelInTilePart(Uint8List codestream, AtkKernel kernel) {
    final cod = locateCod(codestream);
    final codPayload =
        Uint8List.fromList(codestream.sublist(cod.start + 2, cod.end));
    // Same offset as in the main header, minus the two marker bytes.
    codPayload[cod.transformOffset - cod.start - 2] = kernel.index;

    var sotStart = cod.end;
    while (sotStart + 4 <= codestream.length) {
      final marker = (codestream[sotStart] << 8) | codestream[sotStart + 1];
      if (marker == Markers.sot) {
        break;
      }
      sotStart +=
          2 + ((codestream[sotStart + 2] << 8) | codestream[sotStart + 3]);
    }
    // SOT: marker(2) Lsot(2) Isot(2) Psot(4) TPsot(1) TNsot(1).
    final psotOffset = sotStart + 6;
    var position = sotStart + 12;
    while (true) {
      final marker = (codestream[position] << 8) | codestream[position + 1];
      if (marker == Markers.sod) {
        break;
      }
      position +=
          2 + ((codestream[position + 2] << 8) | codestream[position + 3]);
    }

    final inserted = Uint8List.fromList(<int>[
      ...markerSegment(Markers.cod, codPayload),
      ...markerSegment(Markers.atk, AtkMarker.build(kernel)),
    ]);
    final patched = Uint8List(codestream.length + inserted.length);
    patched.setRange(0, position, codestream);
    patched.setRange(position, position + inserted.length, inserted);
    patched.setRange(
        position + inserted.length, patched.length, codestream, position);

    final psot = (patched[psotOffset] << 24) |
        (patched[psotOffset + 1] << 16) |
        (patched[psotOffset + 2] << 8) |
        patched[psotOffset + 3];
    if (psot != 0) {
      final updated = psot + inserted.length;
      patched[psotOffset] = (updated >> 24) & 0xff;
      patched[psotOffset + 1] = (updated >> 16) & 0xff;
      patched[psotOffset + 2] = (updated >> 8) & 0xff;
      patched[psotOffset + 3] = updated & 0xff;
    }
    return patched;
  }

  void expectSameImage(
    Jpeg2000Image actual,
    Jpeg2000Image expected, {
    int tolerance = 0,
    required String reason,
  }) {
    expect(actual.width, expected.width, reason: reason);
    expect(actual.height, expected.height, reason: reason);
    expect(actual.components, expected.components, reason: reason);
    for (var i = 0; i < expected.pixels.length; i++) {
      final difference = (actual.pixels[i] - expected.pixels[i]).abs();
      if (difference > tolerance) {
        fail('$reason: sample $i is ${actual.pixels[i]}, '
            'expected ${expected.pixels[i]}');
      }
    }
  }

  group('wavelet kernel taken from an ATK marker segment', () {
    test('the 5-3 written as lifting steps decodes bit for bit', () {
      final codestream = encode(96, 64, 1, lossless: true);
      final expected = decodeJpeg2000(codestream);
      final patched = useAtkKernel(codestream, reversible53(0x80));
      expectSameImage(decodeJpeg2000(patched), expected,
          reason: 'ATK 5-3, definition after the COD');
    });

    test('the definition may precede the COD that uses it', () {
      final codestream = encode(96, 64, 1, lossless: true);
      final expected = decodeJpeg2000(codestream);
      final patched =
          useAtkKernel(codestream, reversible53(2), atkBeforeCod: true);
      expectSameImage(decodeJpeg2000(patched), expected,
          reason: 'ATK 5-3, definition before the COD');
    });

    test('the 9-7 written as lifting steps decodes to the same image', () {
      final codestream = encode(96, 64, 1, lossless: false);
      final expected = decodeJpeg2000(codestream);
      final patched = useAtkKernel(codestream, irreversible97(0x42));
      // Both sides run the same lifting steps; they differ only in how many
      // digits of the constants they carry.
      expectSameImage(decodeJpeg2000(patched), expected,
          tolerance: 1, reason: 'ATK 9-7');
    });

    test(
        'a reversible kernel still selects the reversible component '
        'transformation', () {
      // With MCT signalled, the component transformation follows the
      // reversibility of the wavelet kernel, which for an ATK index is only
      // known once the marker segment has been read.
      final codestream = encode(64, 64, 3, lossless: true);
      final expected = decodeJpeg2000(codestream);
      final patched = useAtkKernel(codestream, reversible53(0x11));
      expectSameImage(decodeJpeg2000(patched), expected,
          reason: 'ATK 5-3 with the RCT');
    });

    test(
        'an irreversible kernel still selects the irreversible component '
        'transformation', () {
      final codestream = encode(64, 64, 3, lossless: false);
      final expected = decodeJpeg2000(codestream);
      final patched = useAtkKernel(codestream, irreversible97(0x12));
      expectSameImage(decodeJpeg2000(patched), expected,
          tolerance: 1, reason: 'ATK 9-7 with the ICT');
    });

    test('a definition in the first tile-part header is honoured', () {
      final codestream = encode(80, 48, 1, lossless: true);
      final expected = decodeJpeg2000(codestream);
      final patched = useAtkKernelInTilePart(codestream, reversible53(0x80));
      expectSameImage(decodeJpeg2000(patched), expected,
          reason: 'ATK 5-3 defined in the tile-part header');
    });

    test('a tile-part definition really drives the synthesis', () {
      // Repeating the 5-3 through an ATK segment proves nothing on its own:
      // the decoder would produce the same image if it quietly fell back to
      // the built-in filter. The 13-7 of T.801 Table G.3 is a different
      // kernel, so reading it from the tile-part header has to change the
      // result, and has to change it exactly the way the same definition in
      // the main header does.
      const kernel = AtkKernel(
        index: 0x33,
        coefficientType: 1,
        wholeSampleSymmetric: true,
        reversible: true,
        initialParity: 0,
        constantExtension: false,
        scale: 1,
        steps: <AtkLiftingStep>[
          AtkLiftingStep(
            coefficients: <double>[-9, 1],
            exponent: 4,
            residue: 8,
          ),
          AtkLiftingStep(
            coefficients: <double>[5, -1],
            exponent: 4,
            residue: 8,
          ),
        ],
      );
      final codestream = encode(80, 48, 1, lossless: true);
      final with53 = decodeJpeg2000(codestream);
      final fromTilePart =
          decodeJpeg2000(useAtkKernelInTilePart(codestream, kernel));
      final fromMainHeader = decodeJpeg2000(useAtkKernel(codestream, kernel));

      expect(fromTilePart.pixels, isNot(with53.pixels),
          reason: 'the 13-7 must not reconstruct like the 5-3');
      expectSameImage(fromTilePart, fromMainHeader,
          reason: 'the same kernel from either header');
    });
  });

  group('codestreams the decoder refuses', () {
    test('a transformation index no ATK marker segment defines', () {
      final codestream = encode(64, 64, 1, lossless: true);
      final cod = locateCod(codestream);
      final patched = Uint8List.fromList(codestream);
      patched[cod.transformOffset] = 0x7f;
      expect(
        () => decodeJpeg2000(patched),
        throwsA(isA<Jpeg2000CorruptedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('ATK'), contains('15444-2')),
        )),
      );
    });

    test('an arbitrary (ARB) kernel, which needs T.801 Annex H', () {
      final codestream = encode(64, 64, 1, lossless: true);
      final patched = useAtkKernel(
        codestream,
        AtkKernel(
          index: 0x20,
          coefficientType: 0,
          wholeSampleSymmetric: false,
          reversible: true,
          initialParity: 0,
          constantExtension: true,
          scale: 1,
          steps: const <AtkLiftingStep>[
            AtkLiftingStep(coefficients: <double>[1], exponent: 1),
          ],
        ),
      );
      expect(
        () => decodeJpeg2000(patched),
        throwsA(isA<Jpeg2000UnsupportedException>().having(
          (e) => e.message,
          'message',
          contains('Annex H'),
        )),
      );
    });
  });

  group('ATK marker segment syntax', () {
    void expectRoundTrip(AtkKernel kernel) {
      final parsed = AtkMarker.parse(AtkMarker.build(kernel));
      expect(parsed.index, kernel.index);
      expect(parsed.coefficientType, kernel.coefficientType);
      expect(parsed.wholeSampleSymmetric, kernel.wholeSampleSymmetric);
      expect(parsed.reversible, kernel.reversible);
      expect(parsed.initialParity, kernel.initialParity);
      expect(parsed.stepCount, kernel.stepCount);
      if (!kernel.reversible) {
        expect(parsed.scale, closeTo(kernel.scale, 1e-6));
        expect(parsed.constantExtension, kernel.constantExtension);
      }
      for (var s = 0; s < kernel.stepCount; s++) {
        final expectedStep = kernel.steps[s];
        final actualStep = parsed.steps[s];
        expect(actualStep.coefficients.length, expectedStep.coefficients.length,
            reason: 'step $s');
        for (var k = 0; k < expectedStep.coefficients.length; k++) {
          expect(actualStep.coefficients[k],
              closeTo(expectedStep.coefficients[k], 1e-6),
              reason: 'step $s coefficient $k');
        }
        expect(actualStep.exponent, expectedStep.exponent, reason: 'step $s');
        expect(actualStep.residue, expectedStep.residue, reason: 'step $s');
        if (!kernel.wholeSampleSymmetric) {
          expect(actualStep.offset, expectedStep.offset, reason: 'step $s');
        }
      }
    }

    test('round-trips a reversible kernel with 8-bit coefficients', () {
      expectRoundTrip(reversible53(2));
    });

    test('round-trips a reversible kernel with 16-bit coefficients', () {
      // T.801 Table G.3, the 13-7 reversible kernel.
      expectRoundTrip(const AtkKernel(
        index: 255,
        coefficientType: 1,
        wholeSampleSymmetric: true,
        reversible: true,
        initialParity: 1,
        constantExtension: false,
        scale: 1,
        steps: <AtkLiftingStep>[
          AtkLiftingStep(
            coefficients: <double>[-9, 1],
            exponent: 4,
            residue: 8,
          ),
          AtkLiftingStep(
            coefficients: <double>[5, -1],
            exponent: 4,
            residue: 8,
          ),
        ],
      ));
    });

    test('round-trips an irreversible kernel with 32-bit coefficients', () {
      expectRoundTrip(irreversible97(3));
    });

    test('round-trips an irreversible kernel with 64-bit coefficients', () {
      expectRoundTrip(const AtkKernel(
        index: 7,
        coefficientType: 3,
        wholeSampleSymmetric: true,
        reversible: false,
        initialParity: 0,
        constantExtension: false,
        scale: 1.5,
        steps: <AtkLiftingStep>[
          AtkLiftingStep(coefficients: <double>[0.25, -0.125]),
          AtkLiftingStep(coefficients: <double>[0.5]),
        ],
      ));
    });

    test('round-trips an arbitrary kernel with per-step offsets', () {
      expectRoundTrip(const AtkKernel(
        index: 9,
        coefficientType: 0,
        wholeSampleSymmetric: false,
        reversible: true,
        initialParity: 1,
        constantExtension: true,
        scale: 1,
        steps: <AtkLiftingStep>[
          AtkLiftingStep(
            coefficients: <double>[2],
            offset: -3,
            exponent: 1,
            residue: 1,
          ),
        ],
      ));
    });

    test('decodes the flag bits of Satk as Table A.28 packs them', () {
      // Iatk 0x2a, Coeff_Typ 2, Filt_Cat WS, WT_Typ IRR, minit 1, Exten WS.
      final satk = 0x2a | (2 << 8) | (1 << 11) | (1 << 13) | (1 << 14);
      final payload = Uint8List.fromList(<int>[
        0x00, 0x0e, // Latk
        (satk >> 8) & 0xff, satk & 0xff,
        0x3f, 0x80, 0x00, 0x00, // Katk = 1.0
        0x01, // Natk = 1 lifting step
        0x01, // LCatk = 1 coefficient
        0xbf, 0x00, 0x00, 0x00, // Aatk = -0.5
      ]);
      final kernel = AtkMarker.parse(payload);
      expect(kernel.index, 0x2a);
      expect(kernel.coefficientType, 2);
      expect(kernel.wholeSampleSymmetric, isTrue);
      expect(kernel.reversible, isFalse);
      expect(kernel.initialParity, 1);
      expect(kernel.scale, closeTo(1, 1e-9));
      expect(kernel.steps.single.coefficients, <double>[-0.5]);
    });

    test('refuses an index ISO/IEC 15444-1 already owns', () {
      final payload = Uint8List.fromList(<int>[
        0x00, 0x06,
        0x18, 0x01, // Satk with Iatk = 1
        0x00, // Natk
      ]);
      expect(() => AtkMarker.parse(payload), throwsA(isA<StateError>()));
    });

    test('refuses a segment whose declared length does not match its fields',
        () {
      final payload = AtkMarker.build(reversible53(2));
      final truncated = Uint8List.fromList(payload.sublist(0, payload.length));
      truncated[1] = payload[1] - 1;
      expect(() => AtkMarker.parse(truncated), throwsA(isA<StateError>()));
    });

    test('refuses 128-bit floating point coefficients', () {
      final satk = 0x05 | (4 << 8) | (1 << 11);
      final payload = Uint8List.fromList(<int>[
        0x00,
        0x15,
        (satk >> 8) & 0xff,
        satk & 0xff,
        ...List<int>.filled(16, 0),
        0x00,
      ]);
      expect(() => AtkMarker.parse(payload), throwsA(isA<UnsupportedError>()));
    });
  });
}

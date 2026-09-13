import 'dart:typed_data';

import '../../wavelet/atk_kernel.dart';

/// Reader for the ATK marker segment of ISO/IEC 15444-2 (ITU-T T.801) A.3.5.
///
/// The segment describes one wavelet kernel as a list of lifting steps and
/// gives it an index between 2 and 255; a tile-component claims that kernel by
/// putting the index in the transformation field of its `SPcod`/`SPcoc`
/// (T.801 Table A.10), where ISO/IEC 15444-1 only allows 0 for the 9-7 and 1
/// for the 5-3.
///
/// Figure A.5 lays the fields out as `Latk`, `Satk`, `Katk`, `Natk` and then,
/// once per lifting step, `Oatk`, `Eatk`, `Batk`, `LCatk` followed by `LCatk`
/// coefficients — the per-step fields are interleaved, not grouped by field.
/// Which of them are present, and how wide they are, depends on the flags
/// packed into `Satk` (Table A.27 and Table A.28).
abstract final class AtkMarker {
  /// Bit positions of the flags packed into `Satk` (T.801 Table A.28).
  static const int _indexMask = 0xff;
  static const int _coefficientTypeShift = 8;
  static const int _coefficientTypeMask = 0x7;
  static const int _wholeSampleSymmetricBit = 1 << 11;
  static const int _reversibleBit = 1 << 12;
  static const int _initialParityBit = 1 << 13;
  static const int _wholeSampleExtensionBit = 1 << 14;

  /// Width in bytes of a coefficient of each `Coeff_Typ` (T.801 Table A.27).
  static const List<int> _coefficientWidths = <int>[1, 2, 4, 8, 16];

  /// Parses one ATK marker segment.
  ///
  /// [payload] starts at the `Latk` field, the two length bytes included, the
  /// way every other marker parser of this package receives its segment.
  static AtkKernel parse(Uint8List payload) {
    final view = ByteData.view(
      payload.buffer,
      payload.offsetInBytes,
      payload.lengthInBytes,
    );
    if (payload.lengthInBytes < 5) {
      throw StateError(
        'ATK marker too short: ${payload.lengthInBytes} bytes, the segment '
        'needs at least 5.',
      );
    }
    final length = view.getUint16(0);
    if (length < 5 || length > payload.lengthInBytes) {
      throw StateError('ATK marker declares an impossible length: $length');
    }

    final satk = view.getUint16(2);
    final index = satk & _indexMask;
    if (index < 2) {
      throw StateError(
        'ATK marker segment carries index $index, which ISO/IEC 15444-1 '
        'Table A.20 already assigns to a built-in kernel; T.801 Table A.28 '
        'allows 2 to 255.',
      );
    }
    final coefficientType =
        (satk >> _coefficientTypeShift) & _coefficientTypeMask;
    if (coefficientType >= _coefficientWidths.length) {
      throw StateError(
        'ATK marker segment $index declares Coeff_Typ $coefficientType, which '
        'T.801 Table A.28 leaves reserved.',
      );
    }
    if (coefficientType == 4) {
      throw UnsupportedError(
        'ATK marker segment $index signals 128-bit floating point '
        'coefficients (Coeff_Typ = 4), a precision this package cannot '
        'represent.',
      );
    }
    final coefficientWidth = _coefficientWidths[coefficientType];
    final wholeSampleSymmetric = (satk & _wholeSampleSymmetricBit) != 0;
    final reversible = (satk & _reversibleBit) != 0;
    final initialParity = (satk & _initialParityBit) != 0 ? 1 : 0;
    // Exten only qualifies arbitrary kernels; whole-sample symmetric ones
    // always extend symmetrically.
    final constantExtension =
        wholeSampleSymmetric ? false : (satk & _wholeSampleExtensionBit) == 0;

    var offset = 4;

    double readCoefficient() {
      final at = offset;
      offset += coefficientWidth;
      if (offset > length) {
        throw StateError('ATK marker segment $index is truncated.');
      }
      switch (coefficientType) {
        case 0:
          return view.getInt8(at).toDouble();
        case 1:
          return view.getInt16(at).toDouble();
        case 2:
          return view.getFloat32(at);
        default:
          return view.getFloat64(at);
      }
    }

    int readByte() {
      if (offset >= length) {
        throw StateError('ATK marker segment $index is truncated.');
      }
      return view.getUint8(offset++);
    }

    int readSignedByte() {
      if (offset >= length) {
        throw StateError('ATK marker segment $index is truncated.');
      }
      return view.getInt8(offset++);
    }

    // Katk, the scaling factor K, is present for irreversible kernels only.
    final scale = reversible ? 1.0 : readCoefficient();
    final stepCount = readByte();

    final steps = <AtkLiftingStep>[];
    for (var s = 0; s < stepCount; s++) {
      final stepOffset = wholeSampleSymmetric ? 0 : readSignedByte();
      final exponent = reversible ? readByte() : 0;
      final residue = reversible ? readCoefficient().toInt() : 0;
      final coefficientCount = readByte();
      final coefficients = <double>[
        for (var k = 0; k < coefficientCount; k++) readCoefficient(),
      ];
      steps.add(AtkLiftingStep(
        coefficients: List<double>.unmodifiable(coefficients),
        offset: stepOffset,
        exponent: exponent,
        residue: residue,
      ));
    }

    if (offset != length) {
      throw StateError(
        'ATK marker segment $index declares $length bytes but its fields take '
        '$offset.',
      );
    }

    return AtkKernel(
      index: index,
      coefficientType: coefficientType,
      wholeSampleSymmetric: wholeSampleSymmetric,
      reversible: reversible,
      initialParity: initialParity,
      constantExtension: constantExtension,
      scale: scale,
      steps: List<AtkLiftingStep>.unmodifiable(steps),
    );
  }

  /// Serialises [kernel] back into a marker segment payload.
  ///
  /// The decoder never needs this, but building a Part 2 codestream by hand is
  /// the only way to exercise the parser end to end, and a writer that shares
  /// the field table with the reader keeps the two from drifting apart.
  static Uint8List build(AtkKernel kernel) {
    final coefficientType = kernel.coefficientType;
    if (coefficientType >= _coefficientWidths.length || coefficientType == 4) {
      throw UnsupportedError(
        'Coeff_Typ $coefficientType cannot be written.',
      );
    }
    final width = _coefficientWidths[coefficientType];

    var length = 5;
    if (!kernel.reversible) {
      length += width;
    }
    for (final step in kernel.steps) {
      if (!kernel.wholeSampleSymmetric) {
        length += 1;
      }
      if (kernel.reversible) {
        length += 1 + width;
      }
      length += 1 + width * step.coefficients.length;
    }

    final payload = Uint8List(length);
    final view = ByteData.view(payload.buffer);
    view.setUint16(0, length);

    var satk = kernel.index & _indexMask;
    satk |= (coefficientType & _coefficientTypeMask) << _coefficientTypeShift;
    if (kernel.wholeSampleSymmetric) {
      satk |= _wholeSampleSymmetricBit;
    }
    if (kernel.reversible) {
      satk |= _reversibleBit;
    }
    if (kernel.initialParity == 1) {
      satk |= _initialParityBit;
    }
    if (!kernel.wholeSampleSymmetric && !kernel.constantExtension) {
      satk |= _wholeSampleExtensionBit;
    }
    view.setUint16(2, satk);

    var offset = 4;
    void writeCoefficient(double value) {
      switch (coefficientType) {
        case 0:
          view.setInt8(offset, value.toInt());
          break;
        case 1:
          view.setInt16(offset, value.toInt());
          break;
        case 2:
          view.setFloat32(offset, value);
          break;
        default:
          view.setFloat64(offset, value);
          break;
      }
      offset += width;
    }

    if (!kernel.reversible) {
      writeCoefficient(kernel.scale);
    }
    payload[offset++] = kernel.steps.length;
    for (final step in kernel.steps) {
      if (!kernel.wholeSampleSymmetric) {
        view.setInt8(offset++, step.offset);
      }
      if (kernel.reversible) {
        payload[offset++] = step.exponent;
        writeCoefficient(step.residue.toDouble());
      }
      payload[offset++] = step.coefficients.length;
      for (final coefficient in step.coefficients) {
        writeCoefficient(coefficient);
      }
    }
    return payload;
  }
}

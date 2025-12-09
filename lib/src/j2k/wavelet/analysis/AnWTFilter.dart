import 'dart:typed_data';

import '../WaveletFilter.dart';

/// Abstract contract for all JJ2000 analysis wavelet filters.
abstract class AnWTFilter implements WaveletFilter {
  static const String optionPrefix = 'F';

  static const List<List<String?>> parameterInfo = [
    [
      'Ffilters',
      '[<tile-component idx>] <id> [ [<tile-component idx>] <id> ...]',
      'Specifies the analysis filters per tile-component. The <id> token '
          'supports built-in choices such as w5x3 and w9x7.',
      null,
    ],
  ];

  /// Decomposes the input signal using the low-pass first convention.
  void analyzeLpf(
    Object inSig,
    int inOff,
    int inLen,
    int inStep,
    Object lowSig,
    int lowOff,
    int lowStep,
    Object highSig,
    int highOff,
    int highStep,
  );

  /// Decomposes the input signal using the high-pass first convention.
  void analyzeHpf(
    Object inSig,
    int inOff,
    int inLen,
    int inStep,
    Object lowSig,
    int lowOff,
    int lowStep,
    Object highSig,
    int highOff,
    int highStep,
  );

  /// Returns the filter selection flag used in codestream headers.
  int getFilterType();

  /// Returns the time-reversed low-pass synthesis filter of this analysis filter.
  Float32List getLPSynthesisFilter();

  /// Returns the time-reversed high-pass synthesis filter of this analysis filter.
  Float32List getHPSynthesisFilter();

  /// Derived helper: cascaded low-pass synthesis waveform for weighting.
  Float32List getLPSynWaveForm(Float32List? input, [Float32List? output]) {
    return _upsampleAndConvolve(input, getLPSynthesisFilter(), output);
  }

  /// Derived helper: cascaded high-pass synthesis waveform for weighting.
  Float32List getHPSynWaveForm(Float32List? input, [Float32List? output]) {
    return _upsampleAndConvolve(input, getHPSynthesisFilter(), output);
  }

  static Float32List _upsampleAndConvolve(
    Float32List? input,
    Float32List kernel,
    Float32List? reuse,
  ) {
    final Float32List signal;
    if (input == null) {
      signal = Float32List(1)..[0] = 1.0;
    } else {
      signal = input;
    }

    final resultLength = (signal.length * 2) + kernel.length - 2;
    final result = (reuse != null && reuse.length >= resultLength)
        ? reuse
        : Float32List(resultLength);

    for (var i = 0; i < resultLength; i++) {
      var acc = 0.0;
      var k = (i - kernel.length + 2) ~/ 2;
      if (k < 0) {
        k = 0;
      }
      var maxk = (i ~/ 2) + 1;
      if (maxk > signal.length) {
        maxk = signal.length;
      }
      var j = (2 * k) - i + kernel.length - 1;
      while (k < maxk) {
        acc += signal[k] * kernel[j];
        k++;
        j += 2;
      }
      result[i] = acc;
    }

    return result;
  }

  /// JJ2000 command-line parameter metadata for analysis filters.
  static List<List<String?>> getParameterInfo() => parameterInfo;
}


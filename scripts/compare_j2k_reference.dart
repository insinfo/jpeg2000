import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';

class PortableImage {
  final int width;
  final int height;
  final int maxVal;
  final int channels;
  final int bytesPerSample;
  final Uint8List data;

  const PortableImage(this.width, this.height, this.maxVal, this.channels, this.bytesPerSample, this.data);
}

Future<void> main(List<String> args) async {
  var instrumentation = false;
  final positional = <String>[];
  for (final arg in args) {
    if (arg == '--instrument') {
      instrumentation = true;
    } else {
      positional.add(arg);
    }
  }

  if (positional.length < 2) {
    stderr.writeln('Usage: dart run scripts/compare_j2k_reference.dart <codestream.jp2> <reference.pnm> [outputExtension] [--instrument]');
    exit(64);
  }

  final codestream = File(positional[0]);
  final reference = File(positional[1]);
  final outputExtension = positional.length >= 3
      ? positional[2]
      : (reference.path.toLowerCase().endsWith('.pgm') ? '.pgm' : '.ppm');

  if (!codestream.existsSync()) {
    stderr.writeln('Codestream not found: ${codestream.path}');
    exit(1);
  }
  if (!reference.existsSync()) {
    stderr.writeln('Reference not found: ${reference.path}');
    exit(1);
  }

  final decoded = await _decodeCodestream(
    codestream,
    outputExtension: outputExtension,
    instrumentation: instrumentation,
  );
  final referenceImage = await _loadPortableImage(reference);

  _compareImages(decoded, referenceImage, codestream.path, reference.path);
}

Future<PortableImage> _decodeCodestream(
  File codestream, {
  required String outputExtension,
  required bool instrumentation,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('jj2000_compare_');
  final normalizedExtension = outputExtension.startsWith('.') ? outputExtension : '.$outputExtension';
  final outputFile = File('${tempDir.path}/decoded$normalizedExtension');

  try {
    final params = ParameterList(Decoder.buildDefaultParameterList())
      ..put('i', codestream.path)
      ..put('o', outputFile.path)
      ..put('u', 'off')
      ..put('v', 'off')
      ..put('debug', 'off');
    if (instrumentation) {
      params.put('instrument', 'on');
    }

    final decoder = Decoder(params);
    decoder.run();
    if (decoder.exitCode != 0) {
      throw StateError('Decoder returned exit code ${decoder.exitCode} for ${codestream.path}');
    }

    if (!outputFile.existsSync()) {
      final component1 = File(outputFile.path.replaceFirst(normalizedExtension, '-1$normalizedExtension'));
      if (component1.existsSync()) {
         final image = await _loadPortableImage(component1);
         return image;
      }
    }

    final image = await _loadPortableImage(outputFile);
    return image;
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

Future<PortableImage> _loadPortableImage(File file) async {
  final bytes = await file.readAsBytes();
  var index = 0;

  String readToken() {
    void skipWhitespaceAndComments() {
      while (index < bytes.length) {
        final b = bytes[index];
        if (b == 35) {
          while (index < bytes.length && bytes[index] != 10 && bytes[index] != 13) {
            index++;
          }
        } else if (b == 9 || b == 10 || b == 13 || b == 32) {
          index++;
        } else {
          break;
        }
      }
    }

    skipWhitespaceAndComments();
    final start = index;
    while (index < bytes.length) {
      final b = bytes[index];
      if (b == 9 || b == 10 || b == 13 || b == 32) {
        break;
      }
      index++;
    }
    if (start == index) {
      throw FormatException('Invalid PNM header in ${file.path}');
    }
    return String.fromCharCodes(bytes.sublist(start, index));
  }

  final magic = readToken();
  if (magic != 'P5' && magic != 'P6' && magic != 'P7') {
    throw FormatException('Unsupported PNM magic $magic. Expected P5/P6/P7.');
  }

  if (magic == 'P7') {
    int? width;
    int? height;
    int? depth;
    int? maxVal;

    while (true) {
      final keyword = readToken();
      if (keyword == 'ENDHDR') {
        break;
      }
      final value = readToken();
      switch (keyword) {
        case 'WIDTH':
          width = int.parse(value);
          break;
        case 'HEIGHT':
          height = int.parse(value);
          break;
        case 'DEPTH':
          depth = int.parse(value);
          break;
        case 'MAXVAL':
          maxVal = int.parse(value);
          break;
        default:
          break;
      }
    }

    if (width == null || height == null || depth == null || maxVal == null) {
      throw FormatException('Incomplete P7 header in ${file.path}');
    }

    while (index < bytes.length && (bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13 || bytes[index] == 32)) {
      index++;
    }

    final bytesPerSample = maxVal > 255 ? 2 : 1;
    final expectedLength = width * height * depth * bytesPerSample;
    final data = bytes.sublist(index);
    if (data.length != expectedLength) {
      throw FormatException('Unexpected P7 data length. Expected $expectedLength, got ${data.length}.');
    }

    return PortableImage(width, height, maxVal, depth, bytesPerSample, Uint8List.fromList(data));
  }

  final width = int.parse(readToken());
  final height = int.parse(readToken());
  final maxVal = int.parse(readToken());

  while (index < bytes.length && (bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13 || bytes[index] == 32)) {
    index++;
  }

  final channels = magic == 'P6' ? 3 : 1;
  final bytesPerSample = maxVal > 255 ? 2 : 1;
  final expectedLength = width * height * channels * bytesPerSample;
  final data = bytes.sublist(index);
  if (data.length != expectedLength) {
    throw FormatException('Unexpected data length. Expected $expectedLength, got ${data.length}.');
  }

  return PortableImage(width, height, maxVal, channels, bytesPerSample, Uint8List.fromList(data));
}

int _readSample(Uint8List data, int sampleIndex, int bytesPerSample) {
  final byteIndex = sampleIndex * bytesPerSample;
  if (bytesPerSample == 1) {
    return data[byteIndex];
  }
  return (data[byteIndex] << 8) | data[byteIndex + 1];
}

void _compareImages(PortableImage decoded, PortableImage reference, String codestreamPath, String referencePath) {
  if (decoded.width != reference.width || decoded.height != reference.height) {
    throw StateError('Dimension mismatch: ${decoded.width}x${decoded.height} vs ${reference.width}x${reference.height}');
  }
  if (decoded.channels != reference.channels) {
    throw StateError('Channel count mismatch: ${decoded.channels} vs ${reference.channels}');
  }
  if (decoded.bytesPerSample != reference.bytesPerSample) {
    throw StateError('Bytes-per-sample mismatch: ${decoded.bytesPerSample} vs ${reference.bytesPerSample}');
  }
  if (decoded.maxVal != reference.maxVal) {
    stderr.writeln('Warning: maxVal differs (${decoded.maxVal} vs ${reference.maxVal}). Comparisons still performed.');
  }

  final totalSamples = decoded.width * decoded.height * decoded.channels;
  final channels = decoded.channels;
  final perChannelMax = List<int>.filled(channels, 0);
  final perChannelSum = List<int>.filled(channels, 0);
  final perChannelCount = List<int>.filled(channels, 0);
  final perChannelMin = List<int>.filled(channels, 1 << 30);
  final perChannelDiffs = List<List<String>>.generate(channels, (_) => <String>[]);

  for (var sampleIndex = 0; sampleIndex < totalSamples; sampleIndex++) {
    final channel = sampleIndex % channels;
    final a = _readSample(decoded.data, sampleIndex, decoded.bytesPerSample);
    final b = _readSample(reference.data, sampleIndex, reference.bytesPerSample);
    final diff = (a - b).abs();

    perChannelMax[channel] = max(perChannelMax[channel], diff);
    perChannelMin[channel] = min(perChannelMin[channel], diff);
    perChannelSum[channel] += diff;
    if (diff > 0) {
      perChannelCount[channel]++;
      if (perChannelDiffs[channel].length < 10) {
        final pixelIndex = sampleIndex ~/ channels;
        final x = pixelIndex % decoded.width;
        final y = pixelIndex ~/ decoded.width;
        perChannelDiffs[channel].add('($x,$y) decoded=$a reference=$b diff=$diff');
      }
    }
  }

  stdout.writeln('Comparison results for');
  stdout.writeln('  Codestream: $codestreamPath');
  stdout.writeln('  Reference : $referencePath');

  for (var c = 0; c < channels; c++) {
    final mismatches = perChannelCount[c];
    final samplesPerChannel = decoded.width * decoded.height;
    final avgDiff = samplesPerChannel == 0 ? 0 : perChannelSum[c] / samplesPerChannel;
    final minDiff = perChannelMin[c] == (1 << 30) ? 0 : perChannelMin[c];
    stdout.writeln('Channel $c -> max diff ${perChannelMax[c]}, min diff $minDiff, avg diff per pixel ${avgDiff.toStringAsFixed(4)}, mismatched samples $mismatches');
    if (perChannelDiffs[c].isNotEmpty) {
      stdout.writeln('  Examples:');
      for (final entry in perChannelDiffs[c]) {
        stdout.writeln('    $entry');
      }
    }
  }
}


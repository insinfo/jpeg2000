import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';

class PortableImage {
  final int width;
  final int height;
  final int maxVal;
  final int channels;
  final int bytesPerSample;
  final Uint8List data; // channel-interleaved, possibly >8 bits

  PortableImage(
    this.width,
    this.height,
    this.maxVal,
    this.channels,
    this.bytesPerSample,
    this.data,
  );
}

Future<PortableImage> loadPortableImage(File file) async {
  final bytes = await file.readAsBytes();
  var index = 0;

  String readToken() {
    // skip whitespace and comments
    while (index < bytes.length) {
      final b = bytes[index];
      if (b == 35) {
        // '#'
        while (index < bytes.length && bytes[index] != 10 && bytes[index] != 13) {
          index++;
        }
      } else if (b == 9 || b == 10 || b == 13 || b == 32) {
        index++;
      } else {
        break;
      }
    }

    final start = index;
    while (index < bytes.length) {
      final b = bytes[index];
      if (b == 9 || b == 10 || b == 13 || b == 32) {
        break;
      }
      index++;
    }

    if (start == index) {
      throw FormatException('Cabeçalho PNM inválido em ${file.path}');
    }

    return String.fromCharCodes(bytes.sublist(start, index));
  }

  final magic = readToken();
  if (magic != 'P6' && magic != 'P5' && magic != 'P7') {
    throw FormatException('Formato PNM não suportado ($magic). Apenas P5/P6/P7.');
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
          // ignore others (TUPLTYPE, etc)
          break;
      }
    }

    if (width == null || height == null || depth == null || maxVal == null) {
      throw FormatException('Cabeçalho P7 incompleto em ${file.path}');
    }

    while (index < bytes.length && (bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13 || bytes[index] == 32)) {
      index++;
    }

    final bytesPerSample = maxVal > 255 ? 2 : 1;
    final expectedLength = width * height * depth * bytesPerSample;
    final pixelData = bytes.sublist(index);
    if (pixelData.length != expectedLength) {
      throw FormatException('Tamanho de dados inconsistente: esperado $expectedLength bytes, obtido ${pixelData.length}.');
    }

    return PortableImage(width, height, maxVal, depth, bytesPerSample, Uint8List.fromList(pixelData));
  }

  final width = int.parse(readToken());
  final height = int.parse(readToken());
  final maxVal = int.parse(readToken());

  // Skip single whitespace char after header
  while (index < bytes.length && (bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13 || bytes[index] == 32)) {
    index++;
  }

  final channels = magic == 'P6' ? 3 : 1;
  final bytesPerSample = maxVal > 255 ? 2 : 1;
  final expectedLength = width * height * channels * bytesPerSample;
  final pixelData = bytes.sublist(index);
  if (pixelData.length != expectedLength) {
    throw FormatException('Tamanho de dados inconsistente: esperado $expectedLength bytes, obtido ${pixelData.length}.');
  }

  return PortableImage(width, height, maxVal, channels, bytesPerSample, Uint8List.fromList(pixelData));
}

Future<PortableImage> decodeCodestreamWithJj2000(
  File codestream, {
  String outputExtension = '.ppm',
}) async {
  if (!codestream.existsSync()) {
    throw ArgumentError('Codestream inexistente: ${codestream.path}');
  }

  final tempDir = await Directory.systemTemp.createTemp('jj2000_decode_');
  final normalizedExtension = outputExtension.startsWith('.') ? outputExtension : '.$outputExtension';
  final outputFile = File('${tempDir.path}/decoded$normalizedExtension');

  late final PortableImage decoded;
  try {
    final params = ParameterList(Decoder.buildDefaultParameterList());
    params.put('u', 'off');
    params.put('v', 'off');
    params.put('verbose', 'off');
    params.put('debug', 'off');
    params.put('i', codestream.path);
    params.put('o', outputFile.path);

    final decoder = Decoder(params);
    decoder.run();

    if (decoder.exitCode != 0) {
      throw StateError('Decoder retornou código ${decoder.exitCode} para ${codestream.path}');
    }

    decoded = await loadPortableImage(outputFile);
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }

  return decoded;
}

void expectImagesAlmostEqual(
  PortableImage a,
  PortableImage b, {
  int maxAbsError = 0,
}) {
  if (a.width != b.width || a.height != b.height) {
    throw StateError('Dimensões diferentes: ${a.width}x${a.height} vs ${b.width}x${b.height}');
  }
  if (a.channels != b.channels) {
    throw StateError('Quantidade de canais diferente: ${a.channels} vs ${b.channels}');
  }
  if (a.maxVal != b.maxVal) {
    throw StateError('maxVal diferente: ${a.maxVal} vs ${b.maxVal}');
  }
  if (a.bytesPerSample != b.bytesPerSample) {
    throw StateError('bytes por amostra diferente: ${a.bytesPerSample} vs ${b.bytesPerSample}');
  }

  if (a.data.length != b.data.length) {
    throw StateError('Buffers de dados com tamanhos diferentes.');
  }

  for (var i = 0; i < a.data.length; i++) {
    final diff = (a.data[i] - b.data[i]).abs();
    if (diff > maxAbsError) {
      throw StateError('Diferença de pixel $diff > $maxAbsError na posição $i');
    }
  }
}


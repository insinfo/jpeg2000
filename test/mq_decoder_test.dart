import 'dart:convert';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/entropy/decoder/ByteInputBuffer.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/MQDecoder.dart';
import 'package:test/test.dart';

void main() {
  final fixtures = _loadFixtures();
  final initStates = List<int>.from(fixtures['initStates'] as List<dynamic>);

  group('MQDecoder parity', () {
    test('decodes scenarioOne codestream gerado no Java', () {
      final scenario = fixtures['scenarioOne'] as Map<String, dynamic>;
      final contexts = List<int>.from(scenario['contexts'] as List<dynamic>);
      final expectedBits = List<int>.from(scenario['bits'] as List<dynamic>);
      final codestream = _bytesFromHex(scenario['codestreamHex'] as String);

      final decoder = MQDecoder(
        ByteInputBuffer(codestream),
        initStates.length,
        initStates,
      );
      final decoded = List<int>.filled(expectedBits.length, 0);
      decoder.decodeSymbols(decoded, contexts, decoded.length);

      expect(decoded, expectedBits);
    });

    test('fastDecodeSymbols replica resultado do Java', () {
      final run = fixtures['run'] as Map<String, dynamic>;
      final contexts = List<int>.from(run['contexts'] as List<dynamic>);
      final expectedBits = List<int>.from(run['bits'] as List<dynamic>);
      final codestream = _bytesFromHex(run['codestreamHex'] as String);

      final decoder = MQDecoder(
        ByteInputBuffer(codestream),
        initStates.length,
        initStates,
      );

      final buffer = List<int>.filled(expectedBits.length, 0);
      final usedFast =
          decoder.fastDecodeSymbols(buffer, 0, expectedBits.length);
      if (usedFast) {
        expect(buffer[0], expectedBits.first);
      } else {
        expect(buffer, expectedBits);
      }

      decoder.nextSegment(codestream, 0, codestream.length);
      decoder.resetCtxts();
      final decoded = List<int>.filled(expectedBits.length, 0);
      decoder.decodeSymbols(decoded, contexts, expectedBits.length);
      expect(decoded, expectedBits);
    });
  });
}

Map<String, dynamic> _loadFixtures() {
  return json.decode(_fixtureJson) as Map<String, dynamic>;
}

Uint8List _bytesFromHex(String hex) {
  final cleaned = hex.replaceAll(RegExp(r'\s+'), '');
  final bytes = <int>[];
  for (var i = 0; i < cleaned.length; i += 2) {
    bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

const _fixtureJson = '''
{
  "initStates": [0, 7, 3, 12],
  "scenarioOne": {
    "contexts": [0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 3, 3, 1, 2, 0],
    "bits": [0, 1, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 1],
    "codestreamHex": "2A 91 A4"
  },
  "run": {
    "contexts": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "bits": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "codestreamHex": "7D"
  }
}
''';

import 'dart:io';

import 'package:jpeg2000/src/j2k/util/CodestreamManipulator.dart';
import 'package:test/test.dart';

void main() {
  group('CodestreamManipulator', () {
    test('returns zero when no processing required', () {
      final manipulator = CodestreamManipulator(
        'nonexistent.j2k',
        1,
        0,
        false,
        false,
        false,
        false,
      );
      expect(manipulator.doCodestreamManipulation(), 0);
    });

    test('throws when codestream is incomplete', () async {
      final tempDir = await Directory.systemTemp.createTemp('jj2000_test_');
      try {
        final file = File('${tempDir.path}/incomplete.j2k')
          ..writeAsBytesSync(_minimalCodestream);
        final manipulator = CodestreamManipulator(
          file.path,
          1,
          1,
          false,
          false,
          false,
          false,
        );
        expect(() => manipulator.doCodestreamManipulation(), throwsA(isException));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('removes temporary SOP/EPH markers and rewrites headers', () async {
      final tempDir = await Directory.systemTemp.createTemp('jj2000_test_');
      try {
        final file = File('${tempDir.path}/temporary_markers.j2k')
          ..writeAsBytesSync(_codestreamWithTemporaryMarkers);
        final manipulator = CodestreamManipulator(
          file.path,
          1,
          1,
          false,
          false,
          true,
          true,
        );

        final delta = manipulator.doCodestreamManipulation();
        final bytes = file.readAsBytesSync();

        expect(delta, -8);
        expect(bytes.length, _codestreamWithTemporaryMarkers.length + delta);
        expect(_containsSequence(bytes, const [0xFF, 0x91]), isFalse);
        expect(_containsSequence(bytes, const [0xFF, 0x92]), isFalse);

        final codIndex = _indexOfSequence(bytes, const [0xFF, 0x52, 0x00, 0x0C]);
        expect(codIndex, isNonNegative);
        expect(bytes[codIndex + 4], 0);

        final sotIndex = _indexOfSequence(bytes, const [0xFF, 0x90]);
        expect(sotIndex, isNonNegative);
        final psot = (bytes[sotIndex + 6] << 24) |
            (bytes[sotIndex + 7] << 16) |
            (bytes[sotIndex + 8] << 8) |
            bytes[sotIndex + 9];
        expect(psot, 21);
        expect(bytes[sotIndex + 10], 0);
        expect(bytes[sotIndex + 11], 1);

        final sodIndex = _indexOfSequence(bytes, const [0xFF, 0x93]);
        expect(sodIndex, isNonNegative);
        expect(
          bytes.sublist(sodIndex + 2, sodIndex + 9),
          equals(const [0xDE, 0xAD, 0xC0, 0xBE, 0xEF, 0xFE, 0xED]),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('splits tile-part when packet budget exceeded', () async {
      final tempDir = await Directory.systemTemp.createTemp('jj2000_test_');
      try {
        final file = File('${tempDir.path}/two_packets.j2k')
          ..writeAsBytesSync(
            _buildCodestream([
              [
                _PacketDef(_firstPacketHeader, _firstPacketData),
                _PacketDef(_secondPacketHeader, _secondPacketData),
              ],
            ]),
          );
        expect(file.lengthSync(), 59);
        final manipulator = CodestreamManipulator(
          file.path,
          1,
          1,
          false,
          false,
          false,
          false,
        );

        final delta = manipulator.doCodestreamManipulation();
        final bytes = file.readAsBytesSync();
        expect(delta, greaterThan(0));

        final parts = _extractTileParts(bytes);
        expect(parts.length, 2);
        expect(parts.map((p) => p.tpIndex), orderedEquals(const [0, 1]));
        expect(parts.every((p) => p.totalParts == 2), isTrue);

        final packets = parts.map(_parseSinglePacket).toList(growable: false);
        expect(packets[0].header, equals(_firstPacketHeader));
        expect(packets[0].data, equals(_firstPacketData));
        expect(packets[1].header, equals(_secondPacketHeader));
        expect(packets[1].data, equals(_secondPacketData));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('interleaves tile-parts across multiple tiles', () async {
      final tempDir = await Directory.systemTemp.createTemp('jj2000_test_');
      try {
        final file = File('${tempDir.path}/multi_tile.j2k')
          ..writeAsBytesSync(
            _buildCodestream([
              [
                _PacketDef(_firstPacketHeader, _firstPacketData),
                _PacketDef(_secondPacketHeader, _secondPacketData),
              ],
              [
                _PacketDef(_tile1PacketHeader, _tile1PacketData),
              ],
            ]),
          );
        expect(file.lengthSync(), 88);
        final manipulator = CodestreamManipulator(
          file.path,
          2,
          1,
          false,
          false,
          false,
          false,
        );

        final delta = manipulator.doCodestreamManipulation();
        final bytes = file.readAsBytesSync();

        expect(delta, greaterThan(0));

        final parts = _extractTileParts(bytes);
        expect(parts.length, 3);
        expect(parts.map((p) => p.tileIndex), equals(const [0, 1, 0]));
        expect(parts.map((p) => p.tpIndex), equals(const [0, 0, 1]));
        expect(parts[0].totalParts, 2);
        expect(parts[2].totalParts, 2);
        expect(parts[1].totalParts, 1);

        final first = _parseSinglePacket(parts[0]);
        final second = _parseSinglePacket(parts[1]);
        final third = _parseSinglePacket(parts[2]);

        expect(first.header, equals(_firstPacketHeader));
        expect(first.data, equals(_firstPacketData));
        expect(second.header, equals(_tile1PacketHeader));
        expect(second.data, equals(_tile1PacketData));
        expect(third.header, equals(_secondPacketHeader));
        expect(third.data, equals(_secondPacketData));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}

final List<int> _minimalCodestream = List<int>.unmodifiable(<int>[
  0xFF,
  0x4F, // SOC with no subsequent data
]);

final List<int> _codestreamWithTemporaryMarkers = List<int>.unmodifiable(<int>[
  0xFF,
  0x4F,
  0xFF,
  0x51,
  0x00,
  0x28,
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0A,
  0x0B,
  0x0C,
  0x0D,
  0x0E,
  0x0F,
  0x10,
  0x11,
  0x12,
  0x13,
  0x14,
  0x15,
  0x16,
  0x17,
  0x18,
  0x19,
  0x1A,
  0x1B,
  0x1C,
  0x1D,
  0x1E,
  0x1F,
  0x20,
  0x21,
  0x22,
  0x23,
  0x24,
  0x25,
  0xFF,
  0x52,
  0x00,
  0x0C,
  0x06,
  0x11,
  0x22,
  0x33,
  0x44,
  0x55,
  0x66,
  0x77,
  0x88,
  0x99,
  0xFF,
  0x90,
  0x00,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x1D,
  0x00,
  0x01,
  0xFF,
  0x93,
  0xFF,
  0x91,
  0x00,
  0x04,
  0x00,
  0x01,
  0xDE,
  0xAD,
  0xC0,
  0xFF,
  0x92,
  0xBE,
  0xEF,
  0xFE,
  0xED,
  0xFF,
  0xD9,
]);

final List<int> _firstPacketHeader = List<int>.unmodifiable(<int>[0xC0, 0xC1, 0xC2]);
final List<int> _firstPacketData = List<int>.unmodifiable(<int>[0xA0, 0xA1, 0xA2, 0xA3]);
final List<int> _secondPacketHeader = List<int>.unmodifiable(<int>[0xC4, 0xC5, 0xC6]);
final List<int> _secondPacketData = List<int>.unmodifiable(<int>[0xA4, 0xA5, 0xA6, 0xA7]);
final List<int> _tile1PacketHeader = List<int>.unmodifiable(<int>[0xD0, 0xD1, 0xD2]);
final List<int> _tile1PacketData = List<int>.unmodifiable(<int>[0xB0, 0xB1, 0xB2, 0xB3]);

bool _containsSequence(List<int> data, List<int> pattern) =>
    _indexOfSequence(data, pattern) != -1;

int _indexOfSequence(List<int> data, List<int> pattern, [int start = 0]) {
  if (pattern.isEmpty || data.length < pattern.length || start < 0) {
    return -1;
  }
  final maxStart = data.length - pattern.length;
  for (var i = start; i <= maxStart; i++) {
    var j = 0;
    while (j < pattern.length && data[i + j] == pattern[j]) {
      j++;
    }
    if (j == pattern.length) {
      return i;
    }
  }
  return -1;
}

List<_TilePart> _extractTileParts(List<int> bytes) {
  final parts = <_TilePart>[];
  var index = 0;
  while (index + 1 < bytes.length) {
    if (bytes[index] == 0xFF && bytes[index + 1] == 0x90) {
      final psot = _readInt(bytes, index + 6);
      final tpIndex = bytes[index + 10];
      final totalParts = bytes[index + 11];
      if (index + psot > bytes.length) {
        throw StateError('Tile-part length exceeds codestream bounds');
      }
      parts.add(
        _TilePart(
          tileIndex: (bytes[index + 4] << 8) | bytes[index + 5],
          tpIndex: tpIndex,
          totalParts: totalParts,
          bytes: List<int>.unmodifiable(bytes.sublist(index, index + psot)),
        ),
      );
      index += psot;
    } else if (bytes[index] == 0xFF && bytes[index + 1] == 0xD9) {
      break;
    } else {
      index++;
    }
  }
  return parts;
}

_PacketSlices _parseSinglePacket(_TilePart part) {
  final bytes = part.bytes;
  final sodIndex = _indexOfSequence(bytes, const [0xFF, 0x93]);
  if (sodIndex == -1) {
    throw StateError('SOD marker missing in tile-part');
  }
  var cursor = sodIndex + 2;
  if (cursor + 5 >= bytes.length || bytes[cursor] != 0xFF || bytes[cursor + 1] != 0x91) {
    throw StateError('Expected SOP marker in tile-part payload');
  }
  cursor += 6; // Skip SOP marker, Lsop and Nsop.
  final headerEnd = _indexOfSequence(bytes, const [0xFF, 0x92], cursor);
  if (headerEnd == -1) {
    throw StateError('EPH marker missing in tile-part');
  }
  final header = List<int>.unmodifiable(bytes.sublist(cursor, headerEnd));
  cursor = headerEnd + 2;
  final data = List<int>.unmodifiable(bytes.sublist(cursor));
  return _PacketSlices(header, data);
}

int _readInt(List<int> data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

class _TilePart {
  const _TilePart({required this.tileIndex, required this.tpIndex, required this.totalParts, required this.bytes});

  final int tileIndex;
  final int tpIndex;
  final int totalParts;
  final List<int> bytes;
}

class _PacketSlices {
  const _PacketSlices(this.header, this.data);

  final List<int> header;
  final List<int> data;
}

List<int> _buildCodestream(List<List<_PacketDef>> tiles) {
  final bytes = <int>[];

  void writeMarker(int value) {
    bytes..add(0xFF)..add(value & 0xFF);
  }

  writeMarker(0x4F); // SOC
  writeMarker(0x51); // SIZ
  bytes..addAll(const [0x00, 0x04, 0x00, 0x00]);
  writeMarker(0x52); // COD
  bytes..addAll(const [0x00, 0x03, 0x00]);

  var nsop = 1;
  for (var tile = 0; tile < tiles.length; tile++) {
    final packets = tiles[tile];
    final tileBody = <int>[];
    tileBody..addAll(const [0xFF, 0x93]); // SOD

    for (final packet in packets) {
      tileBody
        ..addAll([0xFF, 0x91, 0x00, 0x04, (nsop >> 8) & 0xFF, nsop & 0xFF])
        ..addAll(packet.header)
        ..addAll(const [0xFF, 0x92])
        ..addAll(packet.data);
      nsop++;
    }

    final psot = 12 + tileBody.length;
    bytes
      ..addAll([0xFF, 0x90])
      ..addAll(const [0x00, 0x0A])
      ..addAll([(tile >> 8) & 0xFF, tile & 0xFF])
      ..addAll([
        (psot >> 24) & 0xFF,
        (psot >> 16) & 0xFF,
        (psot >> 8) & 0xFF,
        psot & 0xFF,
      ])
      ..add(0x00) // TPsot
      ..add(0x01) // TNsot
      ..addAll(tileBody);
  }

  writeMarker(0xD9); // EOC
  return List<int>.unmodifiable(bytes);
}

class _PacketDef {
  const _PacketDef(this.header, this.data);

  final List<int> header;
  final List<int> data;
}


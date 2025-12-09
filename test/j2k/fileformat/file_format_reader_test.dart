import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/util/ISRandomAccessIO.dart';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/fileformat/FileFormatBoxes.dart';
import 'package:jpeg2000/src/j2k/fileformat/FileFormatReader.dart';
import 'package:jpeg2000/src/j2k/fileformat/writer/FileFormatWriter.dart';


void main() {
  group('FileFormatReader', () {
    test('accepts raw codestreams', () {
      final data = Uint8List.fromList(<int>[
        0xff,
        0x4f,
        0xff,
        0x90,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff,
        0xd9,
        0x00,
        0x00,
      ]);
      final io = ISRandomAccessIO(data);

      final reader = FileFormatReader(io);
      expect(() => reader.readFileFormat(), returnsNormally);
      expect(reader.JP2FFUsed, isFalse);

      io.close();
    });

    test('locates contiguous codestream box', () {
      final data = _buildMinimalJp2();
      final io = ISRandomAccessIO(data);
      final reader = FileFormatReader(io);

      reader.readFileFormat();

      expect(reader.JP2FFUsed, isTrue);
      expect(reader.getFirstCodeStreamPos(), equals(48));
      expect(reader.getFirstCodeStreamLength(), equals(12));

      io.close();
    });
  });
  group('FileFormatWriter', () {
    test('wraps raw codestream into JP2 container', () {
      final tempDir = Directory.systemTemp.createTempSync('jj2000_writer_test');
      try {
        final file = File('${tempDir.path}/sample.j2k');
        final codestream = _buildRawCodestream();
        file.writeAsBytesSync(codestream);

        final writer = FileFormatWriter(
          file.path,
          1,
          1,
          1,
          <int>[8],
          codestream.length,
        );

        final addedBytes = writer.writeFileFormat();
        expect(addedBytes, equals(85));

        final bytes = file.readAsBytesSync();
        final io = ISRandomAccessIO(Uint8List.fromList(bytes));
        final reader = FileFormatReader(io);
        reader.readFileFormat();

        expect(reader.JP2FFUsed, isTrue);
        expect(reader.getFirstCodeStreamLength(), equals(codestream.length + 8));

        final restored = Uint8List(codestream.length);
        io.seek(reader.getFirstCodeStreamPos());
        io.readFully(restored, 0, restored.length);
        expect(restored, equals(codestream));

        io.close();
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}

Uint8List _buildMinimalJp2() {
  final builder = BytesBuilder();

  void writeInt(int value) {
    builder.add(<int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  // Signature box
  writeInt(12);
  writeInt(FileFormatBoxes.jp2SignatureBox);
  writeInt(0x0d0a870a);

  // File Type box with one compatibility entry
  writeInt(20);
  writeInt(FileFormatBoxes.fileTypeBox);
  writeInt(FileFormatBoxes.ftBr);
  writeInt(0);
  writeInt(FileFormatBoxes.ftBr);

  // Empty JP2 header box
  writeInt(8);
  writeInt(FileFormatBoxes.jp2HeaderBox);

  // Contiguous codestream box containing a minimal codestream (SOC + EOC)
  writeInt(12);
  writeInt(FileFormatBoxes.contiguousCodestreamBox);
  builder.add(<int>[0xff, 0x4f, 0xff, 0xd9]);

  return builder.takeBytes();
}

Uint8List _buildRawCodestream() => Uint8List.fromList(<int>[0xff, 0x4f, 0xff, 0xd9]);


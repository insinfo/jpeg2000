import 'dart:typed_data';


import 'package:jpeg2000/src/j2k/io/EndianType.dart';
import 'package:jpeg2000/src/j2k/io/exceptions.dart';
import 'package:jpeg2000/src/j2k/util/ISRandomAccessIO.dart';
import 'package:test/test.dart';

void main() {
  group('ISRandomAccessIO', () {
    test('reads primitives in big endian order', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final io = ISRandomAccessIO(data);

      expect(io.getByteOrdering(), EndianType.bigEndian);
      expect(io.readUnsignedShort(), 0x0102);
      expect(io.readUnsignedInt(), 0x03040506);
      expect(io.readUnsignedShort(), 0x0708);
    });

    test('seek and readFully', () {
      final data = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final io = ISRandomAccessIO(data);

      io.seek(4);
      expect(io.getPos(), 4);

      final buffer = Uint8List(4);
      io.readFully(buffer, 0, buffer.length);
      expect(buffer, [4, 5, 6, 7]);
      expect(io.getPos(), 8);

      io.seek(12);
      expect(io.readUnsignedByte(), 12);
    });

    test('read beyond end throws EOF', () {
      final data = Uint8List.fromList([0x01, 0x02]);
      final io = ISRandomAccessIO(data);

      expect(io.readUnsignedInt, throwsA(isA<EOFException>()));
    });

    test('skipBytes advances position', () {
      final data = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final io = ISRandomAccessIO(data);

      expect(io.skipBytes(2), 2);
      expect(io.getPos(), 2);
      expect(io.readUnsignedByte(), 0xCC);
    });
  });
}


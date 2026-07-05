@TestOn('vm')
import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/image/data_blk_int.dart';
import 'package:jpeg2000/src/j2k/image/input/img_reader_pgm.dart';
import 'package:jpeg2000/src/j2k/image/input/img_reader_ppm.dart';
import 'package:test/test.dart';

void main() {
  group('ImgReaderPPM', () {
    test('cached component blocks preserve scan width and row offset', () {
      final dir = Directory.systemTemp.createTempSync('img_reader_ppm_');
      final path = '${dir.path}${Platform.pathSeparator}sample.ppm';
      final bytes = <int>[...'P6\n4 3\n255\n'.codeUnits];

      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 4; x++) {
          final base = y * 10 + x;
          bytes.addAll([base, 50 + base, 100 + base]);
        }
      }

      File(path).writeAsBytesSync(Uint8List.fromList(bytes));
      final reader = ImgReaderPPM(path);
      try {
        reader.getInternCompData(DataBlkInt.withGeometry(0, 0, 4, 3), 0);

        final cachedGreen =
            reader.getInternCompData(DataBlkInt.withGeometry(0, 1, 2, 2), 1);
        final data = cachedGreen.getData() as Int32List;

        expect(cachedGreen.offset, 4);
        expect(cachedGreen.scanw, 4);
        expect(data[cachedGreen.offset], 60 - ImgReaderPPM.DC_OFFSET);
        expect(
          data[cachedGreen.offset + cachedGreen.scanw + 1],
          71 - ImgReaderPPM.DC_OFFSET,
        );
      } finally {
        reader.close();
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('ImgReaderPGM', () {
    test('returns compact blocks with zero offset and block scan width', () {
      final dir = Directory.systemTemp.createTempSync('img_reader_pgm_');
      final path = '${dir.path}${Platform.pathSeparator}sample.pgm';
      File(path).writeAsBytesSync(
        Uint8List.fromList(
            <int>[...'P5\n3 2\n255\n'.codeUnits, 1, 2, 3, 4, 5, 6]),
      );

      final reader = ImgReaderPGM(path);
      try {
        final blk =
            reader.getInternCompData(DataBlkInt.withGeometry(1, 0, 2, 2), 0);
        final data = blk.getData() as Int32List;

        expect(blk.offset, 0);
        expect(blk.scanw, 2);
        expect(data, <int>[
          2 - ImgReaderPGM.DC_OFFSET,
          3 - ImgReaderPGM.DC_OFFSET,
          5 - ImgReaderPGM.DC_OFFSET,
          6 - ImgReaderPGM.DC_OFFSET,
        ]);
      } finally {
        reader.close();
        dir.deleteSync(recursive: true);
      }
    });
  });
}

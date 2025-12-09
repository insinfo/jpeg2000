import 'dart:io';
import 'package:jpeg2000/src/j2k/io/BeBufferedRandomAccessFile.dart';
import 'package:test/test.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/HeaderDecoder.dart';
import 'package:jpeg2000/src/j2k/codestream/HeaderInfo.dart';

import 'package:jpeg2000/src/j2k/fileformat/FileFormatReader.dart';

void main() {
  group('Codestream Reading Tests', () {
    test('Read file1.jp2', () {
      dumpMarkers('test_images/file1.jp2');
    });

    test('Read barras_rgb.jp2', () {
      dumpMarkers('test_images/barras_rgb.jp2');
    });
  });
}

void dumpMarkers(String filename) {
  final file = File(filename);
  if (!file.existsSync()) {
    fail('File not found: $filename');
  }

  /*
  print('--- Dumping markers for $filename ---');
  */
  final input = BEBufferedRandomAccessFile.file(file, 'r');
  final headerInfo = HeaderInfo();

  try {
    final ff = FileFormatReader(input);
    ff.readFileFormat();
    if (ff.JP2FFUsed) {
      input.seek(ff.getFirstCodeStreamPos());
    }

    // In Dart port, we use the static method readMainHeader
    final hd = HeaderDecoder.readMainHeader(input: input, headerInfo: headerInfo);
    
    final siz = headerInfo.siz;
    expect(siz, isNotNull);
    if (siz != null) {
      // print('SIZ: w=${siz.xsiz} h=${siz.ysiz} tiles=${siz.xtsiz}x${siz.ytsiz} comps=${siz.csiz}');
      expect(siz.xsiz, greaterThan(0));
      expect(siz.ysiz, greaterThan(0));
      expect(siz.csiz, greaterThan(0));
    }

    final cod = headerInfo.cod['main'];
    expect(cod, isNotNull);
    if (cod != null) {
      // print('COD: len=${cod.lcod} order=${cod.sgcodPo} layers=${cod.sgcodNl} decomp=${cod.spcodNdl}');
      expect(cod.lcod, greaterThan(0));
    }

    final qcd = headerInfo.qcd['main'];
    expect(qcd, isNotNull);
    if (qcd != null) {
      // print('QCD: len=${qcd.lqcd} type=${qcd.sqcd & 0x1f} guard=${(qcd.sqcd >> 5) & 7}');
      expect(qcd.lqcd, greaterThan(0));
    }
    
    // Verify HeaderDecoder properties
    expect(hd.getNumComps(), siz!.csiz);
    expect(hd.getImgWidth(), siz.xsiz - siz.x0siz);
    expect(hd.getImgHeight(), siz.ysiz - siz.y0siz);

  } catch (e, stack) {
    print('Error reading header: $e');
    print(stack);
    rethrow;
  } finally {
    input.close();
  }
}


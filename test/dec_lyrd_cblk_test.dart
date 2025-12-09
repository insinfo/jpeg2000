import 'package:jpeg2000/src/j2k/entropy/decoder/DecLyrdCBlk.dart';
import 'package:test/test.dart';

void main() {
  group('DecLyrdCBlk parity', () {
    test('toString without terminated segments', () {
      final block = DecLyrdCBlk()
        ..m = 2
        ..n = 5
        ..skipMSBP = 1
        ..ulx = 10
        ..uly = 12
        ..w = 32
        ..h = 16
        ..dl = 6
        ..prog = true
        ..nl = 3
        ..ftpIdx = 1
        ..nTrunc = 4;

      expect(
        block.toString(),
        'Coded code-block (2,5): 1 MSB skipped, 6 bytes, 4 truncation points, 3 layers, '
        'progressive=true, ulx=10, uly=12, w=32, h=16, ftpIdx=1',
      );
    });

    test('toString includes terminated segment lengths', () {
      final block = DecLyrdCBlk()
        ..m = 7
        ..n = 3
        ..skipMSBP = 2
        ..ulx = 4
        ..uly = 8
        ..w = 24
        ..h = 28
        ..dl = 12
        ..prog = false
        ..nl = 5
        ..ftpIdx = 2
        ..nTrunc = 6
        ..tsLengths = [3, 5, 7];

      expect(
        block.toString(),
        'Coded code-block (7,3): 2 MSB skipped, 12 bytes, 6 truncation points, 5 layers, '
        'progressive=false, ulx=4, uly=8, w=24, h=28, ftpIdx=2 { 3 5 7 }',
      );
    });
  });
}


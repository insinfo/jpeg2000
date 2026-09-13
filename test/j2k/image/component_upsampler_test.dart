@TestOn('vm')
library;

import 'package:j2k/src/j2k/image/component_upsampler.dart';
import 'package:j2k/src/j2k/image/data_blk.dart';
import 'package:j2k/src/j2k/image/data_blk_float.dart';
import 'package:j2k/src/j2k/image/data_blk_int.dart';
import 'package:test/test.dart';

import '../../subsampled_support.dart';

/// Unit tests for the one resampling implementation of the package.
///
/// The expected values are computed in the test from the rule of ISO/IEC
/// 15444-1 B.2: the sample of component `c` that covers reference grid point
/// `(x, y)` is `(x ~/ XRsiz_c, y ~/ YRsiz_c)`.
void main() {
  PlanarSubsampledSource source({
    int width = 12,
    int height = 12,
    List<int> subsX = const <int>[1, 2, 3],
    List<int> subsY = const <int>[1, 3, 2],
  }) =>
      PlanarSubsampledSource.synthetic(
        width: width,
        height: height,
        subsX: subsX,
        subsY: subsY,
      );

  /// The level-shifted value the source hands out for grid point (x, y).
  int expected(PlanarSubsampledSource src, int c, int x, int y) =>
      src.sampleAt(c, x, y) - (1 << (src.bitsPerSample - 1));

  group('isNeeded', () {
    test('is false when every component is at full resolution', () {
      final plain = source(subsX: const <int>[1, 1], subsY: const <int>[1, 1]);
      expect(ComponentUpsampler.isNeeded(plain), isFalse);
    });

    test('is true as soon as one axis of one component is subsampled', () {
      expect(
        ComponentUpsampler.isNeeded(
          source(subsX: const <int>[1, 1], subsY: const <int>[1, 2]),
        ),
        isTrue,
      );
      expect(
        ComponentUpsampler.isNeeded(
          source(subsX: const <int>[1, 4], subsY: const <int>[1, 1]),
        ),
        isTrue,
      );
    });
  });

  group('geometry', () {
    test('reports every component at the size of the reference grid', () {
      final src = source(width: 13, height: 11);
      final upsampler = ComponentUpsampler(src);
      for (var c = 0; c < src.getNumComps(); c++) {
        expect(upsampler.getCompSubsX(c), 1, reason: 'component $c');
        expect(upsampler.getCompSubsY(c), 1, reason: 'component $c');
        expect(upsampler.getCompImgWidth(c), 13, reason: 'component $c');
        expect(upsampler.getCompImgHeight(c), 11, reason: 'component $c');
        expect(upsampler.getTileCompWidth(0, c), 13, reason: 'component $c');
        expect(upsampler.getTileCompHeight(0, c), 11, reason: 'component $c');
        expect(upsampler.getCompULX(c), 0, reason: 'component $c');
        expect(upsampler.getCompULY(c), 0, reason: 'component $c');
      }
    });

    test('does not round the image size up to a multiple of the factor', () {
      // The component plane is ceil(13 / 3) = 5 samples wide, and 5 * 3 = 15
      // is past the right edge of the 13-wide image area (T.800 B-2).
      final src = source(
        width: 13,
        height: 13,
        subsX: const <int>[3],
        subsY: const <int>[3],
      );
      expect(src.getCompImgWidth(0), 5);
      expect(ComponentUpsampler(src).getCompImgWidth(0), 13);
    });

    test('records the smallest and largest factors', () {
      final upsampler = ComponentUpsampler(
        source(subsX: const <int>[1, 2, 4], subsY: const <int>[1, 6, 2]),
      );
      expect(upsampler.minCompSubsX, 1);
      expect(upsampler.maxCompSubsX, 4);
      expect(upsampler.minCompSubsY, 1);
      expect(upsampler.maxCompSubsY, 6);
    });

    test('rejects a non-positive subsampling factor', () {
      final broken = _ZeroSubsamplingSource(
        width: 8,
        height: 8,
        planes: <List<int>>[List<int>.filled(64, 0)],
        subsX: const <int>[1],
        subsY: const <int>[1],
      );
      expect(() => ComponentUpsampler(broken), throwsArgumentError);
    });
  });

  group('integer blocks', () {
    test('replicates each sample over its own run of grid points', () {
      final src = source(width: 12, height: 12);
      final upsampler = ComponentUpsampler(src);
      for (var c = 0; c < src.getNumComps(); c++) {
        final block = upsampler.getInternCompData(
          DataBlkInt.withGeometry(0, 0, 12, 12),
          c,
        ) as DataBlkInt;
        final data = block.getDataInt()!;
        for (var y = 0; y < 12; y++) {
          for (var x = 0; x < 12; x++) {
            expect(
              data[block.offset + y * block.scanw + x],
              expected(src, c, x, y),
              reason: 'component $c at ($x, $y)',
            );
          }
        }
      }
    });

    test('gives the hand-computed values of a 3:1 run', () {
      // Component 0 of a 6-wide image subsampled 3:1 holds two samples; the
      // first covers grid points 0..2 and the second 3..5.
      final src = PlanarSubsampledSource(
        width: 6,
        height: 2,
        planes: <List<int>>[
          <int>[200, 40],
        ],
        subsX: const <int>[3],
        subsY: const <int>[2],
      );
      final block = ComponentUpsampler(src).getInternCompData(
        DataBlkInt.withGeometry(0, 0, 6, 2),
        0,
      ) as DataBlkInt;
      final row = block
          .getDataInt()!
          .sublist(block.offset, block.offset + 6)
          .map((v) => v + 128)
          .toList();
      expect(row, <int>[200, 200, 200, 40, 40, 40]);
      final second = block
          .getDataInt()!
          .sublist(block.offset + block.scanw, block.offset + block.scanw + 6)
          .map((v) => v + 128)
          .toList();
      expect(second, row, reason: 'the 2:1 vertical factor repeats the row');
    });

    test('honours a block that does not start at the tile origin', () {
      final src = source(width: 16, height: 16);
      final upsampler = ComponentUpsampler(src);
      // An origin that is not a multiple of any factor, so the first output
      // column sits in the middle of an input sample's run.
      const ulx = 5;
      const uly = 7;
      for (var c = 0; c < src.getNumComps(); c++) {
        final block = upsampler.getInternCompData(
          DataBlkInt.withGeometry(ulx, uly, 5, 4),
          c,
        ) as DataBlkInt;
        final data = block.getDataInt()!;
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 5; x++) {
            expect(
              data[block.offset + y * block.scanw + x],
              expected(src, c, ulx + x, uly + y),
              reason: 'component $c at (${ulx + x}, ${uly + y})',
            );
          }
        }
      }
    });

    test('passes a component that is not subsampled straight through', () {
      final src = source(subsX: const <int>[1, 2], subsY: const <int>[1, 2]);
      final upsampler = ComponentUpsampler(src);
      final block = upsampler.getInternCompData(
        DataBlkInt.withGeometry(0, 0, 12, 12),
        0,
      ) as DataBlkInt;
      final data = block.getDataInt()!;
      for (var y = 0; y < 12; y++) {
        for (var x = 0; x < 12; x++) {
          expect(
            data[block.offset + y * block.scanw + x],
            expected(src, 0, x, y),
            reason: 'at ($x, $y)',
          );
        }
      }
    });

    test('handles a factor far beyond 2:1', () {
      final src = source(
        width: 20,
        height: 20,
        subsX: const <int>[1, 10],
        subsY: const <int>[1, 20],
      );
      final block = ComponentUpsampler(src).getInternCompData(
        DataBlkInt.withGeometry(0, 0, 20, 20),
        1,
      ) as DataBlkInt;
      final data = block.getDataInt()!;
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          expect(
            data[block.offset + y * block.scanw + x],
            expected(src, 1, x, y),
            reason: 'at ($x, $y)',
          );
        }
      }
    });
  });

  group('float blocks', () {
    test('upsamples floating point data by the same rule', () {
      final src = source(width: 9, height: 9);
      final upsampler = ComponentUpsampler(src);
      for (var c = 0; c < src.getNumComps(); c++) {
        final block = upsampler.getInternCompData(
          DataBlkFloat.withGeometry(1, 2, 7, 6),
          c,
        ) as DataBlkFloat;
        final data = block.getDataFloat()!;
        for (var y = 0; y < 6; y++) {
          for (var x = 0; x < 7; x++) {
            expect(
              data[block.offset + y * block.scanw + x],
              expected(src, c, 1 + x, 2 + y).toDouble(),
              reason: 'component $c at (${1 + x}, ${2 + y})',
            );
          }
        }
      }
    });

    test('rejects a block type it cannot fill', () {
      final upsampler = ComponentUpsampler(source());
      expect(
        () => upsampler.getInternCompData(_UnknownBlk(), 1),
        throwsArgumentError,
      );
    });
  });
}

/// A source that claims a zero horizontal subsampling factor, which SIZ
/// forbids (T.800 A.5.1) but a corrupted file could still carry this far.
class _ZeroSubsamplingSource extends PlanarSubsampledSource {
  _ZeroSubsamplingSource({
    required super.width,
    required super.height,
    required super.planes,
    required super.subsX,
    required super.subsY,
  });

  @override
  int getCompSubsX(int c) => 0;
}

/// A block whose data type is neither int nor float.
class _UnknownBlk extends DataBlk {
  _UnknownBlk() {
    w = 4;
    h = 4;
  }

  @override
  int getDataType() => -1;

  @override
  Object? getData() => null;

  @override
  void setData(Object? data) {}
}

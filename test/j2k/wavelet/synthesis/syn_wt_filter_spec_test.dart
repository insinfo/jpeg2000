import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/module_spec.dart';
import 'package:jpeg2000/src/j2k/image/data_blk.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/syn_wt_filter_float_lift9x7.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/syn_wt_filter_int_lift5x3.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/syn_wt_filter_spec.dart';

void main() {
  group('SynWTFilterSpec', () {
    test('stores and retrieves per tile/component filters', () {
      final spec = SynWTFilterSpec(1, 1, ModuleSpec.SPEC_TYPE_TILE_COMP);
      final intFilters = [
        [SynWTFilterIntLift5x3()],
        [SynWTFilterIntLift5x3()],
      ];
      spec.setTileCompVal(0, 0, intFilters);

      expect(spec.getWTDataType(0, 0), DataBlk.typeInt);
      expect(spec.getHFilters(0, 0), same(intFilters[0]));
      expect(spec.getVFilters(0, 0), same(intFilters[1]));
      expect(spec.isReversible(0, 0), isTrue);
    });

    test('non-reversible configuration is detected', () {
      final spec = SynWTFilterSpec(1, 1, ModuleSpec.SPEC_TYPE_TILE_COMP);
      final floatFilters = [
        [SynWTFilterFloatLift9x7()],
        [SynWTFilterFloatLift9x7()],
      ];
      spec.setTileCompVal(0, 0, floatFilters);

      expect(spec.isReversible(0, 0), isFalse);
      expect(spec.getWTDataType(0, 0), DataBlk.typeFloat);
    });
  });
}

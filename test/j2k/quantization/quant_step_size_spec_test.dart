import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/module_spec.dart';
import 'package:jpeg2000/src/j2k/quantization/quant_step_size_spec.dart';
import 'package:jpeg2000/src/j2k/util/parameter_list.dart';

void main() {
  group('QuantStepSizeSpec', () {
    test('parses default value from parameters', () {
      final params = ParameterList(null)..put('Qstep', '0.5');
      final spec = QuantStepSizeSpec.fromParameters(
        1,
        1,
        ModuleSpec.SPEC_TYPE_TILE_COMP,
        params,
      );
      expect(spec.getDefault(), closeTo(0.5, 1e-6));
    });

    test('uses defaults when per tile/component unspecified', () {
      final defaults = ParameterList(null)..put('Qstep', '0.75');
      final params = ParameterList(defaults)..put('Qstep', 't0 0.5 c0 0.25');
      final spec = QuantStepSizeSpec.fromParameters(
        2,
        2,
        ModuleSpec.SPEC_TYPE_TILE_COMP,
        params,
      );
      expect(spec.getTileDef(0), closeTo(0.5, 1e-6));
      expect(spec.getCompDef(0), closeTo(0.25, 1e-6));
      expect(spec.getTileCompVal(0, 0), closeTo(0.5, 1e-6));
      expect(spec.getTileCompVal(1, 1), closeTo(0.75, 1e-6));
      expect(spec.getDefault(), closeTo(0.75, 1e-6));
    });
  });
}

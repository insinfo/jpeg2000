import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/ModuleSpec.dart';
import 'package:jpeg2000/src/j2k/quantization/QuantStepSizeSpec.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/StdDequantizerParams.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';

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
      final StdDequantizerParams? specParams = spec.getDefault();
      expect(specParams, isNotNull);
      expect(specParams!.nStep, isNotNull);
      expect(specParams.nStep![0][0], closeTo(0.5, 1e-6));
    });

    test('uses defaults when per tile/component unspecified', () {
      final defaults = ParameterList(null)..put('Qstep', '0.75');
      final params = ParameterList(defaults)
        ..put('Qstep', 't0 0.5 c0 0.25');
      final spec = QuantStepSizeSpec.fromParameters(
        2,
        2,
        ModuleSpec.SPEC_TYPE_TILE_COMP,
        params,
      );
      expect(spec.getTileDef(0)!.nStep![0][0], closeTo(0.5, 1e-6));
      expect(spec.getCompDef(0)!.nStep![0][0], closeTo(0.25, 1e-6));
      expect(spec.getTileCompVal(0, 0)!.nStep![0][0], closeTo(0.5, 1e-6));
      expect(spec.getTileCompVal(1, 1)!.nStep![0][0], closeTo(0.75, 1e-6));
      expect(spec.getDefault()!.nStep![0][0], closeTo(0.75, 1e-6));
    });
  });
}


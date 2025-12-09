import '../QuantizationType.dart';
import 'DequantizerParams.dart';

/// Parameters required by the standard dead-zone dequantizer.
class StdDequantizerParams extends DequantizerParams {
  StdDequantizerParams({
    List<List<int>>? exp,
    List<List<double>>? nStep,
  })  : exp = exp ?? <List<int>>[],
        nStep = nStep;

  /// Quantization exponent table per resolution/subband.
  final List<List<int>> exp;

  /// Normalized quantization step sizes per resolution/subband.
  final List<List<double>>? nStep;

  @override
  int getDequantizerType() => QuantizationType.qTypeScalarDz;
}


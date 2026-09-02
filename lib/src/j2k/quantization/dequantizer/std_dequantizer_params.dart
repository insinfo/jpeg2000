import '../quantization_type.dart';
import 'dequantizer_params.dart';

/// Parameters required by the standard dead-zone dequantizer.
class StdDequantizerParams extends DequantizerParams {
  StdDequantizerParams({
    List<List<int>>? exp,
    this.nStep,
  }) : exp = exp ?? <List<int>>[];

  /// Quantization exponent table per resolution/subband.
  final List<List<int>> exp;

  /// Normalized quantization step sizes per resolution/subband.
  final List<List<double>>? nStep;

  @override
  int getDequantizerType() => QuantizationType.qTypeScalarDz;
}

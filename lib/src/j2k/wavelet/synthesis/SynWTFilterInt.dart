import '../../image/DataBlk.dart';
import 'SynWTFilter.dart';

/// Synthesis filter entry-point specialized for integer sample buffers.
abstract class SynWTFilterInt extends SynWTFilter {
  /// Integer-aware implementation of [synthetize_lpf].
  void synthetizeLpfInt(
    List<int> lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    List<int> highSig,
    int highOff,
    int highLen,
    int highStep,
    List<int> outSig,
    int outOff,
    int outStep,
  );

  /// Integer-aware implementation of [synthetize_hpf].
  void synthetizeHpfInt(
    List<int> lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    List<int> highSig,
    int highOff,
    int highLen,
    int highStep,
    List<int> outSig,
    int outOff,
    int outStep,
  );

  @override
  void synthetize_lpf(
    Object lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Object highSig,
    int highOff,
    int highLen,
    int highStep,
    Object outSig,
    int outOff,
    int outStep,
  ) {
    synthetizeLpfInt(
      lowSig as List<int>,
      lowOff,
      lowLen,
      lowStep,
      highSig as List<int>,
      highOff,
      highLen,
      highStep,
      outSig as List<int>,
      outOff,
      outStep,
    );
  }

  @override
  void synthetize_hpf(
    Object lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Object highSig,
    int highOff,
    int highLen,
    int highStep,
    Object outSig,
    int outOff,
    int outStep,
  ) {
    synthetizeHpfInt(
      lowSig as List<int>,
      lowOff,
      lowLen,
      lowStep,
      highSig as List<int>,
      highOff,
      highLen,
      highStep,
      outSig as List<int>,
      outOff,
      outStep,
    );
  }

  @override
  int getDataType() => DataBlk.typeInt;
}


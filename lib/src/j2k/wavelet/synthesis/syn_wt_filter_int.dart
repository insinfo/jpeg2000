import '../../image/data_blk.dart';
import 'syn_wt_filter.dart';

/// Synthesis filter entry-point specialized for integer sample buffers.
abstract class SynWTFilterInt extends SynWTFilter {
  /// Integer-aware implementation of [synthetizeLpf].
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

  /// Integer-aware implementation of [synthetizeHpf].
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
  void synthetizeLpf(
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
  void synthetizeHpf(
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

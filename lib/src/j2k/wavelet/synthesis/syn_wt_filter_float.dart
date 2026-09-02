import 'dart:typed_data';

import '../../image/data_blk.dart';
import 'syn_wt_filter.dart';

/// Synthesis filter entry-point specialized for floating-point sample buffers.
abstract class SynWTFilterFloat extends SynWTFilter {
  /// Float-aware implementation of [synthetizeLpf].
  void synthetizeLpfFloat(
    Float32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Float32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Float32List outSig,
    int outOff,
    int outStep,
  );

  /// Float-aware implementation of [synthetizeHpf].
  void synthetizeHpfFloat(
    Float32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Float32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Float32List outSig,
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
    synthetizeLpfFloat(
      lowSig as Float32List,
      lowOff,
      lowLen,
      lowStep,
      highSig as Float32List,
      highOff,
      highLen,
      highStep,
      outSig as Float32List,
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
    synthetizeHpfFloat(
      lowSig as Float32List,
      lowOff,
      lowLen,
      lowStep,
      highSig as Float32List,
      highOff,
      highLen,
      highStep,
      outSig as Float32List,
      outOff,
      outStep,
    );
  }

  @override
  int getDataType() => DataBlk.typeFloat;
}

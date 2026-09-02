import 'dart:typed_data';

import '../../image/data_blk.dart';
import 'syn_wt_filter.dart';

/// Synthesis filter entry-point specialized for integer sample buffers.
abstract class SynWTFilterInt extends SynWTFilter {
  /// Integer-aware implementation of [synthetizeLpf].
  void synthetizeLpfInt(
    Int32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Int32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Int32List outSig,
    int outOff,
    int outStep,
  );

  /// Integer-aware implementation of [synthetizeHpf].
  void synthetizeHpfInt(
    Int32List lowSig,
    int lowOff,
    int lowLen,
    int lowStep,
    Int32List highSig,
    int highOff,
    int highLen,
    int highStep,
    Int32List outSig,
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
      lowSig as Int32List,
      lowOff,
      lowLen,
      lowStep,
      highSig as Int32List,
      highOff,
      highLen,
      highStep,
      outSig as Int32List,
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
      lowSig as Int32List,
      lowOff,
      lowLen,
      lowStep,
      highSig as Int32List,
      highOff,
      highLen,
      highStep,
      outSig as Int32List,
      outOff,
      outStep,
    );
  }

  @override
  int getDataType() => DataBlk.typeInt;
}

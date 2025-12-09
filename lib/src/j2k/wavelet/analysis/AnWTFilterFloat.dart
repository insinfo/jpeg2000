import 'dart:typed_data';

import '../../image/DataBlk.dart';
import 'AnWtFilter.dart';

/// Float-specialized analysis wavelet filter contract.
abstract class AnWTFilterFloat extends AnWTFilter {
  void analyzeLpfFloat(
    Float32List inSig,
    int inOff,
    int inLen,
    int inStep,
    Float32List lowSig,
    int lowOff,
    int lowStep,
    Float32List highSig,
    int highOff,
    int highStep,
  );

  void analyzeHpfFloat(
    Float32List inSig,
    int inOff,
    int inLen,
    int inStep,
    Float32List lowSig,
    int lowOff,
    int lowStep,
    Float32List highSig,
    int highOff,
    int highStep,
  );

  @override
  void analyzeLpf(
    Object inSig,
    int inOff,
    int inLen,
    int inStep,
    Object lowSig,
    int lowOff,
    int lowStep,
    Object highSig,
    int highOff,
    int highStep,
  ) {
    analyzeLpfFloat(
      inSig as Float32List,
      inOff,
      inLen,
      inStep,
      lowSig as Float32List,
      lowOff,
      lowStep,
      highSig as Float32List,
      highOff,
      highStep,
    );
  }

  @override
  void analyzeHpf(
    Object inSig,
    int inOff,
    int inLen,
    int inStep,
    Object lowSig,
    int lowOff,
    int lowStep,
    Object highSig,
    int highOff,
    int highStep,
  ) {
    analyzeHpfFloat(
      inSig as Float32List,
      inOff,
      inLen,
      inStep,
      lowSig as Float32List,
      lowOff,
      lowStep,
      highSig as Float32List,
      highOff,
      highStep,
    );
  }

  @override
  int getDataType() => DataBlk.typeFloat;
}


import '../../image/DataBlk.dart';
import 'AnWtFilter.dart';

/// Integer-specialized analysis wavelet filter contract.
abstract class AnWTFilterInt extends AnWTFilter {
  void analyzeLpfInt(
    List<int> inSig,
    int inOff,
    int inLen,
    int inStep,
    List<int> lowSig,
    int lowOff,
    int lowStep,
    List<int> highSig,
    int highOff,
    int highStep,
  );

  void analyzeHpfInt(
    List<int> inSig,
    int inOff,
    int inLen,
    int inStep,
    List<int> lowSig,
    int lowOff,
    int lowStep,
    List<int> highSig,
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
    analyzeLpfInt(
      inSig as List<int>,
      inOff,
      inLen,
      inStep,
      lowSig as List<int>,
      lowOff,
      lowStep,
      highSig as List<int>,
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
    analyzeHpfInt(
      inSig as List<int>,
      inOff,
      inLen,
      inStep,
      lowSig as List<int>,
      lowOff,
      lowStep,
      highSig as List<int>,
      highOff,
      highStep,
    );
  }

  @override
  int getDataType() => DataBlk.typeInt;
}


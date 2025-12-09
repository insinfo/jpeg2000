/// Utilidades para operar com inteiros assinados de 32 bits,
/// reproduzindo exatamente o comportamento do Java.
class Int32Utils {
  const Int32Utils._();

  static const int _mask = 0xFFFFFFFF;

  /// Aplica `toSigned(32)` garantindo intervalo [-2^31, 2^31).
  static int asInt32(int value) => value.toSigned(32);

  /// Mantém apenas 32 bits menos significativos do valor fornecido.
  static int mask32(int value) => value & _mask;

  /// Equivalente ao operador Java `>>>`.
  static int logicalShiftRight(int value, int shift) =>
      mask32(mask32(value) >>> shift);

  /// Inverte todos os bits e retorna o resultado mascarado para 32 bits.
  static int invert32(int value) => mask32(~value);

  /// Codifica o sinal com o bit mais significativo preservando 32 bits.
  static int encodeSignSample(int sign, int setmask) {
     int val = (sign << 31) | setmask;
     return asInt32(val);
  }

  /// Refina a magnitude de um coeficiente conforme implementado no JJ2000.
  static int refineMagnitude(
    int current,
    int resetmask,
    int symbol,
    int bitPlane,
    int setmask,
  ) {
    int step1 = current & resetmask;
    int step2 = symbol << bitPlane;
    int res = step1 | step2 | setmask;
    return asInt32(res);
  }
}

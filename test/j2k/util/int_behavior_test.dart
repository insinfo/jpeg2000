import 'package:test/test.dart';

int _asInt32(int value) => value.toSigned(32);

int _mask32(int value) => value & 0xFFFFFFFF;

int _logicalShift32(int value, int shift) => _mask32(_mask32(value) >>> shift);

int _refineMagnitude(int current, int bitPlane, int symbol) {
  final setmask = (1 << bitPlane) | ((1 << bitPlane) >> 1);
  final resetmask = -1 << (bitPlane + 1);
  return _asInt32((current & resetmask) | ((symbol << bitPlane) | setmask));
}

/// Exercita os comportamentos primitivos essenciais para portar o JJ2000.
/// Garante que o Dart continue reproduzindo o overflow e as operações
/// bitwise de um `int` Java de 32 bits.
void main() {
  group('int32 overflow e bitwise', () {
    test('literal hexadecimal com bit de sinal vira negativo', () {
      const literal = 0x85A20000;
      final signed = literal.toSigned(32);
      expect(signed, equals(-2052980736));
    });

    test('soma que estoura 31 bits faz wrap-around', () {
      const maxPositive = 0x7FFFFFFF;
      final wrapped = (maxPositive + 1).toSigned(32);
      expect(wrapped, equals(-2147483648));
    });

    test('máscara de 32 bits preserva parte unsigned', () {
      const signedValue = -2052980736;
      final unsigned = _mask32(signedValue);
      expect(unsigned, equals(0x85A20000));
    });

    test('shift aritmético conserva sinal como em Java >>', () {
      final signedValue = _asInt32(-0x12345678);
      final dartShift = signedValue >> 1;
      expect(dartShift, equals(_asInt32(0xF6E5D4C4)));
    });

    test('shift lógico reproduz Java >>>', () {
      const literal = 0x85A20000;
      final logicalShift = _logicalShift32(_asInt32(literal), 1);
      expect(logicalShift, equals(0x42D10000));
    });

    test('combinação de set/reset masks igual ao helper Java', () {
      const symbol = 1;
      const bitPlane = 5;
      final current = _asInt32(-123456789);
      final refined = _refineMagnitude(current, bitPlane, symbol);
      expect(refined, equals(_asInt32(-123456784)));
    });
  });
}

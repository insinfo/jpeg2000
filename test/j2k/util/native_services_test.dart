import 'package:jpeg2000/src/j2k/util/NativeServices.dart';
import 'package:test/test.dart';

void main() {
  group('NativeServices', () {
    test('loadLibrary returns false when unavailable', () {
      expect(NativeServices.loadLibrary(), isFalse);
      expect(NativeServices.loadLibrary(), isFalse);
    });

    test('setThreadConcurrency throws when library missing', () {
      expect(
        () => NativeServices.setThreadConcurrency(1),
        throwsA(isA<UnsatisfiedLinkError>()),
      );
    });

    test('getThreadConcurrency throws when library missing', () {
      expect(
        () => NativeServices.getThreadConcurrency(),
        throwsA(isA<UnsatisfiedLinkError>()),
      );
    });
  });
}


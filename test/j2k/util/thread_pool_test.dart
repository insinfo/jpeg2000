import 'dart:async';

import 'package:jpeg2000/src/j2k/util/ThreadPool.dart';
import 'package:test/test.dart';

void main() {
  group('ThreadPool', () {
    test('getSize reflects constructor argument', () {
      final pool = ThreadPool(2, 5, 'TestPool');
      expect(pool.getSize(), 2);
    });

    test('runTarget executes work and notifies lock', () async {
      final pool = ThreadPool(1, 5, 'TestPool');
      final lock = ThreadPoolLock();
      var runs = 0;

      pool.runTarget(() {
        runs += 1;
      }, lock);

      final Future<void> completion = lock.wait();
      await completion.timeout(const Duration(milliseconds: 200));
      pool.checkTargetErrors();
      expect(runs, 1);
    });

    test('async submission returns false when no idle worker', () async {
      final pool = ThreadPool(1, 5, 'TestPool');
      final firstLock = ThreadPoolLock();

      final accepted = pool.runTarget(() {}, firstLock, true);
      expect(accepted, isTrue);

      final Future<void> completion = firstLock.wait();

      final secondAccepted = pool.runTarget(() {}, ThreadPoolLock(), true);
      expect(secondAccepted, isFalse);

      await completion.timeout(const Duration(milliseconds: 200));
    });

    test('checkTargetErrors propagates runtime exceptions', () {
      final pool = ThreadPool(1, 5, 'TestPool');

      pool.runTarget(() {
        throw StateError('boom');
      });

      expect(() => pool.checkTargetErrors(), throwsA(isA<StateError>()));
      pool.clearTargetErrors();
      expect(pool.checkTargetErrors, returnsNormally);
    });
  });
}


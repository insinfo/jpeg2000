import 'dart:async';
import 'dart:collection';

import 'FacilityManager.dart';
import 'MsgLogger.dart';
import 'NativeServices.dart';

/// Function signature used for tasks submitted to [ThreadPool].
typedef Runnable = void Function();

/// Minimal thread-pool analogue for the single-threaded Dart runtime.
///
/// JJ2000 only relies on the orchestration semantics of the original Java
/// implementation (queueing work, recording asynchronous failures, and
/// notifying a latch upon completion). This port executes work sequentially
/// in the current isolate while preserving the observable behaviour around
/// error tracking and completion notifications.
class ThreadPool {
  ThreadPool(int size, int priority, String? name)
      : _poolSize = _validateSize(size),
        _poolName = name ?? 'Anonymous ThreadPool' {
    final desiredConcurrency = _readConcurrency();
    if (desiredConcurrency != null) {
      final loaded = NativeServices.loadLibrary();
      if (loaded) {
        NativeServices.setThreadConcurrency(desiredConcurrency);
      } else {
        FacilityManager.getMsgLogger().printmsg(
          MsgLogger.warning,
          'Native thread concurrency library was not found; '
          'continuing with Dart isolate scheduling.',
        );
      }
    }
  }

  static const String concurrencyPropertyName =
      'ucar.jpeg.jj2000.j2k.util.ThreadPool.concurrency';

  static int _validateSize(int size) {
    if (size <= 0) {
      throw ArgumentError.value(size, 'size', 'Pool must be of positive size');
    }
    return size;
  }

  static int? _readConcurrency() {
    final value = const String.fromEnvironment(concurrencyPropertyName);
    if (value.isEmpty) {
      return null;
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      throw ArgumentError.value(
        value,
        concurrencyPropertyName,
        'Invalid concurrency level',
      );
    }
    return parsed;
  }

  final int _poolSize;
  final String _poolName;

  Error? _targetError;
  StackTrace? _targetErrorStack;
  Object? _targetRuntimeException;
  StackTrace? _targetRuntimeStack;

  final Queue<_PendingTask> _queue = Queue<_PendingTask>();
  int _active = 0;

  int getSize() => _poolSize;

  /// Submits a unit of work to the pool.
  ///
  /// The optional [lock] parameter mirrors the Java behaviour: if it is a
  /// [ThreadPoolLock] or a [Completer], it is resolved after the task
  /// completes. Otherwise the value is ignored (but a warning is logged) to
  /// avoid crashing the runtime.
  bool runTarget(
    Runnable target, [
    Object? lock,
    bool async = false,
    bool notifyAll = false,
  ]) {
    final task = _PendingTask(target, lock, notifyAll);
    if (async) {
      if (_active >= _poolSize) {
        return false;
      }
      _queue.add(task);
      _drain();
      return true;
    }
    _execute(task);
    return true;
  }

  /// Records pending failures thrown by workers.
  void checkTargetErrors() {
    final error = _targetError;
    if (error != null) {
      final stack = _targetErrorStack ?? StackTrace.current;
      Error.throwWithStackTrace(error, stack);
    }

    final exception = _targetRuntimeException;
    if (exception != null) {
      final stack = _targetRuntimeStack ?? StackTrace.current;
      Error.throwWithStackTrace(exception, stack);
    }
  }

  /// Clears the stored error state.
  void clearTargetErrors() {
    _targetError = null;
    _targetErrorStack = null;
    _targetRuntimeException = null;
    _targetRuntimeStack = null;
  }

  void _drain() {
    if (_active >= _poolSize) {
      return;
    }
    if (_queue.isEmpty) {
      return;
    }
    _active++;
    final task = _queue.removeFirst();
    scheduleMicrotask(() {
      try {
        _execute(task);
      } finally {
        _active--;
        if (_queue.isNotEmpty) {
          _drain();
        }
      }
    });
  }

  void _execute(_PendingTask task) {
    try {
      task.runnable();
    } on Error catch (error, stackTrace) {
      _targetError = error;
      _targetErrorStack = stackTrace;
      _targetRuntimeStack = stackTrace;
    } on Object catch (exception, stackTrace) {
      _targetRuntimeException = exception;
      _targetRuntimeStack = stackTrace;
    } finally {
      _notify(task.lock, task.notifyAll);
    }
  }

  void _notify(Object? lock, bool notifyAll) {
    if (lock == null) {
      return;
    }
    if (lock is ThreadPoolLock) {
      lock._complete(notifyAll);
      return;
    }
    if (lock is Completer<void>) {
      if (!lock.isCompleted) {
        lock.complete();
      }
      return;
    }
    FacilityManager.getMsgLogger().printmsg(
      MsgLogger.warning,
      'ThreadPool(${
        _poolName
      }): ignoring completion lock of type ${lock.runtimeType}. '
      'Pass a ThreadPoolLock or Completer<void> for notifications.',
    );
  }
}

/// Helper that mirrors the wait/notify pattern expected by JJ2000 callers.
class ThreadPoolLock {
  Future<void> wait() => _completer.future;

  void _complete(bool notifyAll) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete();
  }

  final Completer<void> _completer = Completer<void>();
}

class _PendingTask {
  _PendingTask(this.runnable, this.lock, this.notifyAll);

  final Runnable runnable;
  final Object? lock;
  final bool notifyAll;
}


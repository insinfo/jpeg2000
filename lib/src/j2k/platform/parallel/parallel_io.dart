/// Worker-isolate execution for the Dart VM.
///
/// This file is only ever reached through the `dart.library.io` branch of
/// [parallel.dart]; nothing under `lib/` may import it directly, or the
/// package would lose its Web and Wasm support.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';

/// Upper bound on workers, however many cores the machine reports.
///
/// Beyond this the per-isolate setup cost and the memory held by each
/// in-flight tile grow faster than the decode time shrinks.
const int maxWorkerIsolates = 8;

/// Number of workers that could usefully run at the same time.
int get availableProcessors {
  final processors = Platform.numberOfProcessors;
  if (processors < 1) {
    return 1;
  }
  return processors > maxWorkerIsolates ? maxWorkerIsolates : processors;
}

/// Whether [runParallelTasks] can actually overlap work.
bool get supportsParallelExecution => true;

/// Runs every task in [tasks] on a worker isolate, at most [concurrency] at a
/// time, and returns the results in the order of [tasks].
///
/// Each task must be a closure whose captured state is sendable: the closure
/// itself is copied to the worker. If a task throws, the error is rethrown
/// here once the already-running tasks have settled, so no worker is left
/// running after this future completes.
Future<List<R>> runParallelTasks<R>(
  List<R Function()> tasks, {
  required int concurrency,
}) async {
  if (tasks.isEmpty) {
    return <R>[];
  }
  if (tasks.length == 1 || concurrency <= 1) {
    final results = <R>[];
    for (final task in tasks) {
      results.add(await Isolate.run(task));
    }
    return results;
  }

  final limit = concurrency < tasks.length ? concurrency : tasks.length;
  final results = List<R?>.filled(tasks.length, null);
  var next = 0;
  Object? failure;
  StackTrace? failureStack;

  Future<void> worker() async {
    while (true) {
      if (failure != null) {
        return;
      }
      final index = next;
      if (index >= tasks.length) {
        return;
      }
      next = index + 1;
      try {
        results[index] = await Isolate.run(tasks[index]);
      } catch (error, stackTrace) {
        // Keep the first failure: later ones are usually the same corrupt
        // input reported by another tile.
        failure ??= error;
        failureStack ??= stackTrace;
        return;
      }
    }
  }

  await Future.wait(<Future<void>>[
    for (var i = 0; i < limit; i++) worker(),
  ]);

  final error = failure;
  if (error != null) {
    Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
  }
  return List<R>.generate(tasks.length, (i) => results[i] as R,
      growable: false);
}

/// Sequential fallback used by every platform without worker isolates.
///
/// The contract is deliberately identical to [parallel_io.dart]: callers
/// always get a `Future`, and the only observable difference is that the
/// tasks run one after another on the current isolate.
library;

/// Number of workers that could run at the same time: one, here.
int get availableProcessors => 1;

/// Whether [runParallelTasks] can actually overlap work.
bool get supportsParallelExecution => false;

/// Runs every task in [tasks] and returns the results in the same order.
///
/// [concurrency] is accepted and ignored: without isolates the tasks run
/// sequentially on the calling isolate.
Future<List<R>> runParallelTasks<R>(
  List<R Function()> tasks, {
  required int concurrency,
}) async {
  final results = <R>[];
  for (final task in tasks) {
    results.add(task());
  }
  return results;
}

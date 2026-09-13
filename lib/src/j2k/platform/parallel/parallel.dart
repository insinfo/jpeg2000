/// Optional worker-isolate execution, resolved at compile time.
///
/// The default branch is the sequential stub, so `dart2js` and `dart2wasm`
/// builds — and `test/architecture/public_facade_imports_test.dart`, which
/// walks the graph the way those compilers do — never reach `dart:isolate`.
/// Only a `dart.library.io` build picks up the real isolate pool.
library;

export 'parallel_stub.dart' if (dart.library.io) 'parallel_io.dart';

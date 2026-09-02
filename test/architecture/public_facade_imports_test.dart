@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The public facade must stay importable from dart2js and dart2wasm builds.
///
/// pub.dev derives platform support from the static import graph: a single
/// reachable `dart:io` import removes the Web tag and fails the Wasm check,
/// even when the code is never executed there. This test walks the graph from
/// `lib/jpeg2000.dart` the way the browser compilers see it (default branch of
/// every conditional import, plus the `dart.library.js_interop` branch) and
/// fails if it reaches `dart:io` or any other VM-only library.
void main() {
  test('lib/jpeg2000.dart never reaches dart:io on the browser branch', () {
    final packageRoot = Directory.current.uri;
    final libRoot = packageRoot.resolve('lib/');
    final entry = libRoot.resolve('jpeg2000.dart');

    final visited = <Uri>{};
    final pending = <(Uri, List<Uri>)>[(entry, <Uri>[])];
    final violations = <String>[];

    while (pending.isNotEmpty) {
      final (file, chain) = pending.removeLast();
      if (!visited.add(file)) {
        continue;
      }
      final source = File.fromUri(file).readAsStringSync();
      final nextChain = <Uri>[...chain, file];
      for (final directive in _directives(source)) {
        for (final uri in _browserBranchUris(directive)) {
          if (uri.startsWith('dart:')) {
            if (_vmOnlyLibraries.contains(uri)) {
              violations.add(
                [
                  ...nextChain.map((u) => _relative(u, packageRoot)),
                  uri,
                ].join('\n    -> '),
              );
            }
            continue;
          }
          if (uri.startsWith('package:')) {
            if (!uri.startsWith('package:jpeg2000/')) {
              continue;
            }
            pending.add((
              libRoot.resolve(uri.substring('package:jpeg2000/'.length)),
              nextChain,
            ));
            continue;
          }
          pending.add((file.resolve(uri), nextChain));
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'VM-only libraries reachable from the public facade:\n'
          '${violations.join('\n\n')}',
    );
  });
}

const Set<String> _vmOnlyLibraries = <String>{
  'dart:io',
  'dart:ffi',
  'dart:isolate',
  'dart:mirrors',
};

final RegExp _directivePattern = RegExp(
  r'''^\s*(import|export)\s+([^;]+);''',
  multiLine: true,
);

final RegExp _uriPattern = RegExp(r'''['"]([^'"]+)['"]''');

final RegExp _conditionPattern = RegExp(
  r'''if\s*\(\s*([^)]+?)\s*\)\s*['"]([^'"]+)['"]''',
);

Iterable<String> _directives(String source) sync* {
  final withoutComments = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*'), '');
  for (final match in _directivePattern.allMatches(withoutComments)) {
    yield match.group(2)!;
  }
}

/// URIs a browser compiler follows for one import/export directive.
Iterable<String> _browserBranchUris(String directive) sync* {
  final first = _uriPattern.firstMatch(directive);
  if (first == null) {
    return;
  }
  final defaultUri = first.group(1)!;
  final conditions = _conditionPattern.allMatches(directive).toList();
  var defaultTaken = true;
  for (final condition in conditions) {
    final expression = condition.group(1)!.replaceAll(' ', '');
    final uri = condition.group(2)!;
    if (expression == 'dart.library.js_interop' ||
        expression == 'dart.library.html' ||
        expression == 'dart.library.js') {
      yield uri;
      defaultTaken = false;
    }
  }
  if (defaultTaken || conditions.isEmpty) {
    yield defaultUri;
  }
}

String _relative(Uri uri, Uri root) =>
    uri.toString().replaceFirst(root.toString(), '');

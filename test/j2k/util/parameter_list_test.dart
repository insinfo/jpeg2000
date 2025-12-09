import 'package:jpeg2000/src/j2k/util/ParameterList.dart';
import 'package:jpeg2000/src/j2k/util/StringFormatException.dart';
import 'package:test/test.dart';

void main() {
  group('ParameterList', () {
    test('parseArgs parses boolean and values', () {
      final params = ParameterList();
      params.parseArgs(['-Ffilters', 'w5x3', '-Wlev', '5', '+Ttile']);

      expect(params.getParameter('Ffilters'), 'w5x3');
      expect(params.getParameter('Wlev'), '5');
      expect(params.getParameter('Ttile'), 'off');
      expect(params.getBooleanParameter('Ttile'), isFalse);
    });

    test('parseArgs rejects duplicate options', () {
      final params = ParameterList();
      expect(
        () => params.parseArgs(['-Aalpha', '1', '-Aalpha', '2']),
        throwsA(isA<StringFormatException>()),
      );
    });

    test('parseArgs rejects value for boolean off', () {
      final params = ParameterList();
      expect(
        () => params.parseArgs(['+Flag', 'value']),
        throwsA(isA<StringFormatException>()),
      );
    });

    test('getBooleanParameter rejects invalid value', () {
      final params = ParameterList();
      params.put('Flag', 'maybe');
      expect(
        () => params.getBooleanParameter('Flag'),
        throwsA(isA<StringFormatException>()),
      );
    });

    test('getParameter falls back to defaults', () {
      final defaults = ParameterList()..put('Shared', 'value');
      final params = ParameterList(defaults);

      expect(params.getParameter('Shared'), 'value');
    });

    test('propertyNames merges defaults and local entries', () {
      final defaults = ParameterList()
        ..put('DefaultOnly', 'a')
        ..put('Shared', 'default');
      final params = ParameterList(defaults)
        ..put('Shared', 'local')
        ..put('LocalOnly', 'b');

      final names = params.propertyNames().toList();
      expect(names, containsAll(<String>['DefaultOnly', 'Shared', 'LocalOnly']));
      expect(params.getParameter('Shared'), equals('local'));
    });

    test('loadFromString handles comments and continuations', () {
      final params = ParameterList();
      params.loadFromString('''
# Comment line
alpha = 1 \\
  2
beta=value
''');

      expect(params.getParameter('alpha'), equals('1 2'));
      expect(params.getParameter('beta'), equals('value'));
    });

    test('checkListSingle accepts valid prefixed options', () {
      final params = ParameterList()
        ..put('Mfoo', '1')
        ..put('Rbar', '2');

      params.checkListSingle('M'.codeUnitAt(0), ['Mfoo']);
    });

    test('checkListSingle rejects invalid prefixed option', () {
      final params = ParameterList()..put('Mfoo', '1');

      expect(
        () => params.checkListSingle('M'.codeUnitAt(0), ['Mbar']),
        throwsArgumentError,
      );
    });

    test('checkList accepts valid options outside prefixes', () {
      final params = ParameterList()
        ..put('Xalpha', '1')
        ..put('Bbeta', '2');

      params.checkList(['Z'.codeUnitAt(0), 'Y'.codeUnitAt(0)], ['Xalpha', 'Bbeta']);
    });

    test('checkList rejects unexpected option outside prefixes', () {
      final params = ParameterList()
        ..put('Xalpha', '1')
        ..put('Bbeta', '2');

      expect(
        () => params.checkList(['Z'.codeUnitAt(0), 'Y'.codeUnitAt(0)], ['Bbeta']),
        throwsArgumentError,
      );
    });

    test('toNameArray returns first column', () {
      final info = [
        ['Aopt', 'usage', 'desc'],
        ['Bopt', 'usage', 'desc'],
      ];

      expect(ParameterList.toNameArray(info), ['Aopt', 'Bopt']);
    });
  });
}


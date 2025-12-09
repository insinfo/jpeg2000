import 'package:jpeg2000/src/j2k/util/MsgPrinter.dart';
import 'package:test/test.dart';

void main() {
  group('MsgPrinter', () {
    test('formats lines within width', () {
      final printer = MsgPrinter(10);
      final sink = _BufferSink();

      printer.print(sink, 0, 0, 'alpha beta gamma');

      final output = sink.toString();
      expect(output.contains('\n'), isTrue);
      expect(output.contains('gamma'), isTrue);
    });

    test('respects indentation hints', () {
      final printer = MsgPrinter(12);
      final sink = _BufferSink();

      printer.print(sink, 2, 4, 'alpha beta');

      final lines = sink.toString().split('\n');
      expect(lines.first.startsWith('  a'), isTrue);
    });

    test('rejects non positive line width', () {
      final printer = MsgPrinter(5);
      expect(() => printer.lineWidth = 0, throwsArgumentError);
    });
  });
}

class _BufferSink implements StringSink {
  final StringBuffer _buffer = StringBuffer();

  @override
  void write(Object? obj) => _buffer.write(obj);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void writeln([Object? obj = '']) => _buffer.writeln(obj);

  @override
  String toString() => _buffer.toString();
}


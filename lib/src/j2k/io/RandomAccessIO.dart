import 'BinaryDataInput.dart';
import 'BinaryDataOutput.dart';

/// Random access I/O abstraction matching JJ2000's expectations.
abstract class RandomAccessIO implements BinaryDataInput, BinaryDataOutput {
  void close();

  int getPos();

  int length();

  void seek(int offset);

  int read();

  void readFully(List<int> buffer, int offset, int length);

  void write(int value);
}


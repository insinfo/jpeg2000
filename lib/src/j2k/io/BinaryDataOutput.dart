/// Stream-like interface for writing binary data.
abstract class BinaryDataOutput {
  int getByteOrdering();

  void writeByte(int value);

  void writeShort(int value);

  void writeInt(int value);

  void writeLong(int value);

  void writeFloat(double value);

  void writeDouble(double value);

  void flush();
}

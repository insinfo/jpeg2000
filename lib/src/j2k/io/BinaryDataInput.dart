/// Stream-like interface for reading binary data.
///
/// The API mirrors JJ2000's `BinaryDataInput` but uses Dart's `int` for all
/// numeric return types. Callers should expect big-endian ordering unless
/// `getByteOrdering` reports otherwise.
abstract class BinaryDataInput {
  int getByteOrdering();

  int readByte();

  int readUnsignedByte();

  int readShort();

  int readUnsignedShort();

  int readInt();

  int readUnsignedInt();

  int readLong();

  double readFloat();

  double readDouble();

  int skipBytes(int count);
}

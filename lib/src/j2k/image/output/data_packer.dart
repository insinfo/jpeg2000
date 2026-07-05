/// Utility to pack signed or unsigned integers into big-endian byte buffers.
class DataPacker {
  /// Packs [value] using [bytesPerSample] bytes into [buffer] starting at [offset].
  /// Only the least-significant bits of [value] are written.
  static void packBigEndian(
    List<int> buffer,
    int offset,
    int bytesPerSample,
    int value,
  ) {
    for (var i = bytesPerSample - 1; i >= 0; i--) {
      buffer[offset + i] = value & 0xff;
      value >>= 8;
    }
  }
}

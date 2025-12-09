import 'dart:typed_data';

import '../../io/BEBufferedRandomAccessFile.dart';
import '../FileFormatBoxes.dart';

/// Minimal JP2 wrapper writer that mirrors JJ2000's implementation.
class FileFormatWriter implements FileFormatBoxes {
  FileFormatWriter(
    this.filename,
    this.height,
    this.width,
    this.numComponents,
    List<int> bitsPerComponent,
    this.codestreamLength,
  ) : bitsPerComponent = List<int>.unmodifiable(bitsPerComponent) {
    if (numComponents <= 0) {
      throw ArgumentError.value(numComponents, 'numComponents', 'Must be positive');
    }
    if (bitsPerComponent.length != numComponents) {
      throw ArgumentError(
        'bitsPerComponent must contain exactly $numComponents entries',
      );
    }
    if (codestreamLength < 0) {
      throw ArgumentError.value(codestreamLength, 'codestreamLength', 'Must be non-negative');
    }
    _bitsPerComponentVary = !_hasUniformBpc(bitsPerComponent);
  }

  final String filename;
  final int height;
  final int width;
  final int numComponents;
  final List<int> bitsPerComponent;
  final int codestreamLength;

  late final bool _bitsPerComponentVary;

  static const int _colourSpecificationBoxLength = 15;
  static const int _fileTypeBoxLength = 20;
  static const int _imageHeaderBoxLength = 22;
  static const int _bitsPerComponentBoxBaseLength = 8;

  /// Reads the existing codestream and writes the minimal JP2 wrapper.
  ///
  /// Returns the amount of bytes the wrapper adds on top of the raw codestream.
  int writeFileFormat() {
    BEBufferedRandomAccessFile? file;
    try {
      file = BEBufferedRandomAccessFile.path(filename, 'rw+');
      final codestream = Uint8List(codestreamLength);
      file.readFully(codestream, 0, codestreamLength);

      file.seek(0);
      _writeSignatureBox(file);
      _writeFileTypeBox(file);
      _writeJp2HeaderBox(file);
      _writeContiguousCodestreamBox(file, codestream);
    } catch (error, stackTrace) {
      file?.close();
      Error.throwWithStackTrace(
        StateError('Error while writing JP2 file format: $error'),
        stackTrace,
      );
    }

    file.close();
    return _bitsPerComponentVary
        ? 12 +
            _fileTypeBoxLength +
            8 +
            _imageHeaderBoxLength +
            _colourSpecificationBoxLength +
            _bitsPerComponentBoxBaseLength +
            numComponents +
            8
        : 12 + _fileTypeBoxLength + 8 + _imageHeaderBoxLength + _colourSpecificationBoxLength + 8;
  }

  static bool _hasUniformBpc(List<int> values) {
    if (values.isEmpty) {
      return true;
    }
    final first = values.first;
    for (var i = 1; i < values.length; i++) {
      if (values[i] != first) {
        return false;
      }
    }
    return true;
  }

  void _writeSignatureBox(BEBufferedRandomAccessFile file) {
    file
      ..writeInt(0x0000000c)
      ..writeInt(FileFormatBoxes.jp2SignatureBox)
      ..writeInt(0x0d0a870a);
  }

  void _writeFileTypeBox(BEBufferedRandomAccessFile file) {
    file
      ..writeInt(_fileTypeBoxLength)
      ..writeInt(FileFormatBoxes.fileTypeBox)
      ..writeInt(FileFormatBoxes.ftBr)
      ..writeInt(0)
      ..writeInt(FileFormatBoxes.ftBr);
  }

  void _writeJp2HeaderBox(BEBufferedRandomAccessFile file) {
    final length = 8 +
        _imageHeaderBoxLength +
        _colourSpecificationBoxLength +
        (_bitsPerComponentVary ? _bitsPerComponentBoxBaseLength + numComponents : 0);
    file
      ..writeInt(length)
      ..writeInt(FileFormatBoxes.jp2HeaderBox);
    _writeImageHeaderBox(file);
    _writeColourSpecificationBox(file);
    if (_bitsPerComponentVary) {
      _writeBitsPerComponentBox(file);
    }
  }

  void _writeImageHeaderBox(BEBufferedRandomAccessFile file) {
    file
      ..writeInt(_imageHeaderBoxLength)
      ..writeInt(FileFormatBoxes.imageHeaderBox)
      ..writeInt(height)
      ..writeInt(width)
      ..writeShort(numComponents)
      ..writeByte(_bitsPerComponentVary ? 0xff : (bitsPerComponent.first - 1))
      ..writeByte(FileFormatBoxes.imbC)
      ..writeByte(FileFormatBoxes.imbUnkC)
      ..writeByte(FileFormatBoxes.imbIpr);
  }

  void _writeColourSpecificationBox(BEBufferedRandomAccessFile file) {
    file
      ..writeInt(_colourSpecificationBoxLength)
      ..writeInt(FileFormatBoxes.colourSpecificationBox)
      ..writeByte(FileFormatBoxes.csbMeth)
      ..writeByte(FileFormatBoxes.csbPrec)
      ..writeByte(FileFormatBoxes.csbApprox)
      ..writeInt(numComponents > 1 ? FileFormatBoxes.csbEnumSrgb : FileFormatBoxes.csbEnumGrey);
  }

  void _writeBitsPerComponentBox(BEBufferedRandomAccessFile file) {
    file
      ..writeInt(_bitsPerComponentBoxBaseLength + numComponents)
      ..writeInt(FileFormatBoxes.bitsPerComponentBox);
    for (final value in bitsPerComponent) {
      file.writeByte(value - 1);
    }
  }

  void _writeContiguousCodestreamBox(
    BEBufferedRandomAccessFile file,
    Uint8List codestream,
  ) {
    file
      ..writeInt(codestreamLength + 8)
      ..writeInt(FileFormatBoxes.contiguousCodestreamBox)
      ..writeBytes(codestream, 0, codestream.length);
  }
}

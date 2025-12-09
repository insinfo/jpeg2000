import '../codestream/markers.dart';
import '../io/RandomAccessIO.dart';
import '../util/FacilityManager.dart';
import '../util/MsgLogger.dart';
import 'FileFormatBoxes.dart';

/// Lightweight JP2 wrapper parser that locates contiguous codestream boxes.
///
/// The decoder only needs the offset and length of the first codestream, so
/// the implementation stops parsing after it finds the mandatory sequence of
/// signature, file type and JP2 header boxes. Optional box payloads are
/// skipped but can be revisited later if metadata becomes necessary.
class FileFormatReader implements FileFormatBoxes {
  FileFormatReader(this._input);

  final RandomAccessIO _input;

  final List<int> _codestreamPositions = <int>[];
  final List<int> _codestreamLengths = <int>[];

  /// Whether the surrounding file follows the JP2 container syntax.
  bool JP2FFUsed = false;

  /// Parses the file format wrapper and records contiguous codestream boxes.
  ///
  /// If the input does not start with a JP2 signature the method rewinds to
  /// position zero and verifies that the stream begins with an SOC marker,
  /// signalling a raw codestream. Any structural inconsistencies raise a
  /// [StateError].
  void readFileFormat() {
    _codestreamPositions.clear();
    _codestreamLengths.clear();

    var foundCodeStreamBoxes = 0;
    var jp2HeaderBoxFound = false;
    var lastBoxFound = false;

    try {
      // Inspect the first 12 bytes: a valid JP2 file starts with the signature
      // box, otherwise treat the input as a bare codestream.
      final firstLength = _input.readInt();
      final firstType = _input.readInt();
      final signature = _input.readInt();
      final isJp2 = firstLength == 0x0000000c &&
          firstType == FileFormatBoxes.jp2SignatureBox &&
          signature == 0x0d0a870a;

      if (!isJp2) {
        _input.seek(0);
        final marker = _input.readUnsignedShort();
        if (marker != Markers.SOC) {
          throw StateError(
            'Stream is neither a JP2 file nor a raw JPEG 2000 codestream.',
          );
        }
        JP2FFUsed = false;
        _input.seek(0);
        return;
      }

      JP2FFUsed = true;

      // Validate the mandatory file type box immediately following the
      // signature box.
      _input.seek(12); // Move to the start of the second box after signature.
      if (!readFileTypeBox()) {
        throw StateError('Invalid JP2 file: missing or malformed File Type box');
      }

      // Iterate over the remaining boxes until the stream ends.
      while (!lastBoxFound) {
        final boxStart = _input.getPos();
        final length = _input.readInt();
        var lp = length;
        if (boxStart + length == _input.length()) {
          lastBoxFound = true;
        }

        final boxType = _input.readInt();
        if (length == 0) {
          lastBoxFound = true;
          lp = _input.length() - _input.getPos();
        } else if (length == 1) {
          // Extended length boxes are extremely rare and exceed 32-bit sizes,
          // which the current decoder does not support.
          _input.readLong();
          throw StateError('JP2 box length exceeds 2^32-1 bytes');
        }

        switch (boxType) {
          case FileFormatBoxes.contiguousCodestreamBox:
            if (!jp2HeaderBoxFound) {
              throw StateError(
                'Invalid JP2 file: JP2Header box must precede ContiguousCodestream box',
              );
            }
            readContiguousCodeStreamBox(boxStart, lp);
            foundCodeStreamBoxes++;
            break;
          case FileFormatBoxes.jp2HeaderBox:
            if (jp2HeaderBoxFound) {
              throw StateError('Invalid JP2 file: duplicate JP2Header box');
            }
            readJP2HeaderBox(boxStart, lp);
            jp2HeaderBoxFound = true;
            break;
          case FileFormatBoxes.intellectualPropertyBox:
            readIntPropertyBox(lp);
            break;
          case FileFormatBoxes.xmlBox:
            readXMLBox(lp);
            break;
          case FileFormatBoxes.uuidBox:
            readUUIDBox(lp);
            break;
          case FileFormatBoxes.uuidInfoBox:
            readUUIDInfoBox(lp);
            break;
          default:
            FacilityManager.getMsgLogger()
                .printmsg(MsgLogger.warning, 'Unknown JP2 box type: 0x${boxType.toRadixString(16)}');
        }

        if (!lastBoxFound) {
          _input.seek(boxStart + (length == 0 ? lp : length));
        }
      }
    } catch (e) {
      throw StateError('Error while reading JP2 file format: $e');
    }

    if (foundCodeStreamBoxes == 0) {
      throw StateError('Invalid JP2 file: missing ContiguousCodestream box');
    }
  }

  /// Reads and validates the File Type box (Ftyp).
  bool readFileTypeBox() {
    final start = _input.getPos();
    final length = _input.readInt();
    if (length == 0) {
      throw StateError('Invalid JP2 file: zero-length File Type box');
    }

    final type = _input.readInt();
    if (type != FileFormatBoxes.fileTypeBox) {
      _input.seek(start);
      return false;
    }

    if (length == 1) {
      _input.readLong();
      throw StateError('JP2 File Type box exceeds 2^32-1 bytes');
    }

    // Skip brand and minor version.
    _input.readInt();
    _input.readInt();

    final compatibilityEntries = (length - 16) ~/ 4;
    var foundBrand = false;
    for (var i = 0; i < compatibilityEntries; i++) {
      if (_input.readInt() == FileFormatBoxes.ftBr) {
        foundBrand = true;
      }
    }

    if (!foundBrand) {
      _input.seek(start);
      return false;
    }

    return true;
  }

  /// Registers the location of a contiguous codestream.
  void readContiguousCodeStreamBox(int position, int length) {
    final dataStart = _input.getPos();
    _codestreamPositions.add(dataStart);
    _codestreamLengths.add(length);
  }

  void readJP2HeaderBox(int position, int length) {
    if (length == 0) {
      throw StateError('Invalid JP2 file: zero-length JP2Header box');
    }
    // Payload is ignored for now; skip remains handled by caller.
  }

  void readIntPropertyBox(int length) {
    // Placeholder: skip contents.
  }

  void readXMLBox(int length) {
    // Placeholder: skip contents.
  }

  void readUUIDBox(int length) {
    // Placeholder: skip contents.
  }

  void readUUIDInfoBox(int length) {
    // Placeholder: skip contents.
  }

  /// Returns the recorded positions of all contiguous codestreams.
  List<int> getCodeStreamPos() => List<int>.unmodifiable(_codestreamPositions);

  /// Number of contiguous codestreams discovered in the container.
  int getCodestreamCount() => _codestreamPositions.length;

  /// Returns the offset of the first contiguous codestream.
  int getFirstCodeStreamPos() {
    if (_codestreamPositions.isEmpty) {
      throw StateError('No contiguous codestream recorded');
    }
    return _codestreamPositions.first;
  }

  /// Returns the length (in bytes) of the first contiguous codestream box.
  int getFirstCodeStreamLength() {
    if (_codestreamLengths.isEmpty) {
      throw StateError('No contiguous codestream recorded');
    }
    return _codestreamLengths.first;
  }
}


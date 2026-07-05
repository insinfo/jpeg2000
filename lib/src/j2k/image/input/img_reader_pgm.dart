import 'dart:io';
import 'dart:typed_data';

import '../data_blk.dart';
import '../data_blk_int.dart';
import 'img_reader.dart';

/// This class implements the ImgData interface for reading 8-bit unsigned
/// data from a binary PGM (raw, P5) file. Mirrors JJ2000's `ImgReaderPGM`.
///
/// After being read, the coefficients are level shifted by subtracting
/// 2^(number of bits per pixel - 1). The ROI encoder also relies on this
/// reader when an arbitrary-shape ROI mask is supplied.
class ImgReaderPGM extends ImgReader {
  /// DC offset value used when reading image
  static const int DC_OFFSET = 128;

  /// Where to read the data from
  RandomAccessFile? _in;

  /// Offset of the raw pixel data in the PGM file
  int _offset = 0;

  /// The number of bits that determine the nominal dynamic range
  int _rb = 0;

  /// Line buffer
  Uint8List? _buf;

  /// Temporary DataBlkInt object (needed when encoder uses floating-point
  /// filters). This avoids allocating new DataBlk at each time.
  DataBlkInt? _intBlk;

  /// Creates a new PGM file reader from the specified file name.
  ImgReaderPGM(String fname) {
    _in = File(fname).openSync();

    _confirmFileType();
    _skipCommentAndWhiteSpace();
    w = _readHeaderInt();
    _skipCommentAndWhiteSpace();
    h = _readHeaderInt();
    _skipCommentAndWhiteSpace();
    _readHeaderInt(); // Max number of values (discarded)
    nc = 1;
    _rb = 8;
  }

  /// Closes the underlying file from where the image data is being read.
  @override
  void close() {
    _in?.closeSync();
    _in = null;
  }

  /// Returns the number of bits corresponding to the nominal range of the
  /// data: 8 for PGM data.
  @override
  int getNomRangeBits(int c) {
    if (c != 0) {
      throw ArgumentError();
    }
    return _rb;
  }

  /// PGM data is not natively fixed-point: returns 0.
  @override
  int getFixedPoint(int c) {
    if (c != 0) {
      throw ArgumentError();
    }
    return 0;
  }

  @override
  DataBlk getInternCompData(DataBlk blk, int c) {
    // Check component index
    if (c != 0) {
      throw ArgumentError();
    }

    // Check type of block provided as an argument
    if (blk.getDataType() != DataBlk.typeInt) {
      if (_intBlk == null) {
        _intBlk = DataBlkInt.withGeometry(blk.ulx, blk.uly, blk.w, blk.h);
      } else {
        _intBlk!
          ..ulx = blk.ulx
          ..uly = blk.uly
          ..w = blk.w
          ..h = blk.h;
      }
      blk = _intBlk!;
    }

    // Get data array
    var barr = blk.getData() as List<int>?;
    if (barr == null || barr.length < blk.w * blk.h) {
      barr = Int32List(blk.w * blk.h);
      blk.setData(barr);
    }

    // Check line buffer
    if (_buf == null || _buf!.length < blk.w) {
      _buf = Uint8List(blk.w);
    }
    final buf = _buf!;
    final input = _in!;

    // Read line by line
    final mi = blk.uly + blk.h;
    for (var i = blk.uly; i < mi; i++) {
      // Reposition in input; offset takes care of the header size
      input.setPositionSync(_offset + i * w + blk.ulx);
      input.readIntoSync(buf, 0, blk.w);
      for (var k = (i - blk.uly) * blk.w + blk.w - 1, j = blk.w - 1;
          j >= 0;
          j--, k--) {
        barr[k] = (buf[j] & 0xFF) - DC_OFFSET;
      }
    }

    // Turn off the progressive attribute
    blk.progressive = false;
    // Set buffer attributes
    blk.offset = 0;
    blk.scanw = blk.w;
    return blk;
  }

  @override
  DataBlk getCompData(DataBlk blk, int c) {
    return getInternCompData(blk, c);
  }

  /// Returns a byte read from the file. The number of read bytes is counted
  /// to keep track of the offset of the pixel data in the PGM file.
  int _countedByteRead() {
    _offset++;
    final b = _in!.readByteSync();
    if (b < 0) {
      throw StateError('Unexpected end of PGM file');
    }
    return b;
  }

  /// Checks that the file begins with 'P5'.
  void _confirmFileType() {
    const type = <int>[80, 53]; // 'P5'
    for (var i = 0; i < 2; i++) {
      final b = _countedByteRead();
      if (b != type[i]) {
        if (i == 1 && b == 50) {
          // i.e 'P2'
          throw ArgumentError('JJ2000 does not support ascii-PGM files. '
              'Use raw-PGM file instead.');
        }
        throw ArgumentError('Not a raw-PGM file');
      }
    }
  }

  /// Skips any line in the header starting with '#' and any space, tab, line
  /// feed or carriage return.
  void _skipCommentAndWhiteSpace() {
    var done = false;
    while (!done) {
      final b = _countedByteRead();
      if (b == 35) {
        // Comment start
        var cb = b;
        while (cb != 10 && cb != 13) {
          cb = _countedByteRead();
        }
      } else if (!(b == 9 || b == 10 || b == 13 || b == 32)) {
        // not whitespace
        done = true;
      }
    }
    // Put back last valid byte
    _offset--;
    _in!.setPositionSync(_offset);
  }

  /// Returns an int read from the header of the PGM file.
  int _readHeaderInt() {
    var res = 0;
    var b = _countedByteRead();
    while (b != 32 && b != 10 && b != 9 && b != 13) {
      // While not whitespace
      res = res * 10 + b - 48;
      b = _countedByteRead();
    }
    if (b == 13) {
      final next = _countedByteRead();
      if (next != 10) {
        _offset--;
        _in!.setPositionSync(_offset);
      }
    }
    return res;
  }

  /// Returns true if the data read was originally signed in the specified
  /// component: false for this reader.
  @override
  bool isOrigSigned(int c) {
    if (c != 0) {
      throw ArgumentError();
    }
    return false;
  }

  @override
  String toString() => 'ImgReaderPGM: WxH = ${w}x$h, Component = 0';
}

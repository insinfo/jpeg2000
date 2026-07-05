import 'dart:io';
import 'dart:typed_data';

import '../DataBlk.dart';
import '../DataBlkInt.dart';
import 'ImgReader.dart';

/// This class implements the ImgData interface for reading 8-bit unsigned
/// data from a binary PPM (raw, P6) file. Mirrors JJ2000's `ImgReaderPPM`.
///
/// After being read, the coefficients are level shifted by subtracting
/// 2^(number of bits per pixel - 1).
class ImgReaderPPM extends ImgReader {
  /// DC offset value used when reading image
  static const int DC_OFFSET = 128;

  /// Where to read the data from
  RandomAccessFile? _in;

  /// Offset of the raw pixel data in the PPM file
  int _offset = 0;

  /// The number of bits that determine the nominal dynamic range
  int _rb = 0;

  /// Buffer for the 3 components of each pixel (in the current block)
  final List<List<int>?> _barr = List<List<int>?>.filled(3, null);

  /// Data block used only to store coordinates and dimensions of the buffered
  /// blocks
  final DataBlkInt _dbi = DataBlkInt();

  /// Temporary DataBlkInt object (needed when encoder uses floating-point
  /// filters). This avoids allocating new DataBlk at each time.
  DataBlkInt? _intBlk;

  /// Line buffer
  Uint8List? _buf;

  /// Creates a new PPM file reader from the specified file name.
  ImgReaderPPM(String fname) {
    _in = File(fname).openSync();
    _confirmFileType();
    _skipCommentAndWhiteSpace();
    w = _readHeaderInt();
    _skipCommentAndWhiteSpace();
    h = _readHeaderInt();
    _skipCommentAndWhiteSpace();
    _readHeaderInt(); // Max number of values (discarded)
    nc = 3;
    _rb = 8;
  }

  /// Closes the underlying file from where the image data is being read.
  @override
  void close() {
    _in?.closeSync();
    _in = null;
    _barr[0] = null;
    _barr[1] = null;
    _barr[2] = null;
    _buf = null;
  }

  /// Returns the number of bits corresponding to the nominal range of the
  /// data in the specified component: 8 for PPM data.
  @override
  int getNomRangeBits(int c) {
    if (c < 0 || c > 2) {
      throw ArgumentError();
    }
    return _rb;
  }

  /// PPM data is not natively fixed-point: returns 0.
  @override
  int getFixedPoint(int c) {
    if (c < 0 || c > 2) {
      throw ArgumentError();
    }
    return 0;
  }

  @override
  DataBlk getInternCompData(DataBlk blk, int c) {
    if (c < 0 || c > 2) {
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

    // If asking a component for the first time for this block, read the 3
    // components
    if ((_barr[c] == null) ||
        (_dbi.ulx > blk.ulx) ||
        (_dbi.uly > blk.uly) ||
        (_dbi.ulx + _dbi.w < blk.ulx + blk.w) ||
        (_dbi.uly + _dbi.h < blk.uly + blk.h)) {
      if (_barr[c] == null || _barr[c]!.length < blk.w * blk.h) {
        _barr[c] = Int32List(blk.w * blk.h);
      }
      blk.setData(_barr[c]);

      var i = (c + 1) % 3;
      if (_barr[i] == null || _barr[i]!.length < blk.w * blk.h) {
        _barr[i] = Int32List(blk.w * blk.h);
      }
      i = (c + 2) % 3;
      if (_barr[i] == null || _barr[i]!.length < blk.w * blk.h) {
        _barr[i] = Int32List(blk.w * blk.h);
      }

      // Save block's attributes. The cached arrays hold exactly this area
      // with a scan width of blk.w.
      _dbi
        ..ulx = blk.ulx
        ..uly = blk.uly
        ..w = blk.w
        ..h = blk.h
        ..scanw = blk.w;

      // Check line buffer
      if (_buf == null || _buf!.length < 3 * blk.w) {
        _buf = Uint8List(3 * blk.w);
      }
      final buf = _buf!;

      final red = _barr[0]!;
      final green = _barr[1]!;
      final blue = _barr[2]!;

      // Read line by line
      final mi = blk.uly + blk.h;
      final input = _in!;
      for (i = blk.uly; i < mi; i++) {
        // Reposition in input; offset takes care of the header size
        input.setPositionSync(_offset + i * 3 * w + 3 * blk.ulx);
        input.readIntoSync(buf, 0, 3 * blk.w);

        for (var k = (i - blk.uly) * blk.w + blk.w - 1, j = 3 * blk.w - 1;
            j >= 0;
            k--) {
          blue[k] = (buf[j--] & 0xFF) - DC_OFFSET;
          green[k] = (buf[j--] & 0xFF) - DC_OFFSET;
          red[k] = (buf[j--] & 0xFF) - DC_OFFSET;
        }
      }

      blk.setData(_barr[c]);
      blk.offset = 0;
      blk.scanw = blk.w;
    } else {
      // Asking for the 2nd or 3rd block component of the cached area.
      blk.setData(_barr[c]);
      blk.offset = (blk.uly - _dbi.uly) * _dbi.w + blk.ulx - _dbi.ulx;
      blk.scanw = _dbi.scanw;
    }

    // Turn off the progressive attribute
    blk.progressive = false;
    return blk;
  }

  @override
  DataBlk getCompData(DataBlk blk, int c) {
    // Check type of block provided as an argument
    if (blk.getDataType() != DataBlk.typeInt) {
      blk = DataBlkInt.withGeometry(blk.ulx, blk.uly, blk.w, blk.h);
    }

    var bakarr = blk.getData() as List<int>?;
    final w = blk.w;
    final h = blk.h;
    blk.setData(null);
    blk = getInternCompData(blk, c);
    bakarr ??= Int32List(w * h);
    final srcData = blk.getData() as List<int>;
    if (blk.offset == 0 && blk.scanw == w) {
      bakarr.setRange(0, w * h, srcData);
    } else {
      for (var i = h - 1; i >= 0; i--) {
        bakarr.setRange(i * w, i * w + w, srcData, blk.offset + i * blk.scanw);
      }
    }
    blk.setData(bakarr);
    blk.offset = 0;
    blk.scanw = blk.w;
    return blk;
  }

  /// Returns a byte read from the file. The number of read bytes is counted
  /// to keep track of the offset of the pixel data in the PPM file.
  int _countedByteRead() {
    _offset++;
    final b = _in!.readByteSync();
    if (b < 0) {
      throw StateError('Unexpected end of PPM file');
    }
    return b;
  }

  /// Checks that the file begins with 'P6'.
  void _confirmFileType() {
    const type = <int>[80, 54]; // 'P6'
    for (var i = 0; i < 2; i++) {
      final b = _countedByteRead();
      if (b != type[i]) {
        if (i == 1 && b == 51) {
          // i.e 'P3'
          throw ArgumentError('JJ2000 does not support ascii-PPM files. '
              'Use raw-PPM file instead.');
        }
        throw ArgumentError('Not a raw-PPM file');
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

  /// Returns an int read from the header of the PPM file.
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
    if (c < 0 || c > 2) {
      throw ArgumentError();
    }
    return false;
  }

  @override
  String toString() => 'ImgReaderPPM: WxH = ${w}x$h, Component = 0,1,2';
}

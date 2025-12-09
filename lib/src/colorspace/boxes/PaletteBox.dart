import 'dart:typed_data';
import '../../j2k/io/RandomAccessIO.dart';
import '../ColorSpaceException.dart';
import '../../icc/IccProfile.dart';
import 'JP2Box.dart';

class PaletteBox extends JP2Box {
  static const int boxType = 0x70636c72; // 'pclr'

  @override
  int get type => boxType;

  int nentries = 0;
  int ncolumns = 0;
  List<int>? bitdepth;
  List<List<int>>? entries;

  PaletteBox(RandomAccessIO in_io, int boxStart) : super(in_io, boxStart) {
    readBox();
  }

  void readBox() {
    Uint8List bfr = Uint8List(4);
    int i, j, b, m;

    // Read the number of palette entries and columns per entry.
    in_io.seek(dataStart);
    in_io.readFully(bfr, 0, 3);
    nentries = ICCProfile.getShort(bfr, 0) & 0x0000ffff;
    ncolumns = bfr[2] & 0x0000ffff;

    // Read the bitdepths for each column
    bitdepth = List.filled(ncolumns, 0);
    bfr = Uint8List(ncolumns);
    in_io.readFully(bfr, 0, ncolumns);
    for (i = 0; i < ncolumns; ++i) {
      bitdepth![i] = (bfr[i] & 0x00fff);
    }

    entries = List.generate(nentries, (_) => List.filled(ncolumns, 0));

    bfr = Uint8List(2);
    for (i = 0; i < nentries; ++i) {
      for (j = 0; j < ncolumns; ++j) {
        int bd = getBitDepth(j);
        bool signed = isSigned(j);

        switch (getEntrySize(j)) {
          case 1: // 8 bit entries
            in_io.readFully(bfr, 0, 1);
            b = bfr[0];
            break;

          case 2: // 16 bits
            in_io.readFully(bfr, 0, 2);
            b = ICCProfile.getShort(bfr, 0);
            break;

          default:
            throw ColorSpaceException(
                "palettes greater than 16 bits deep not supported");
        }

        if (signed) {
          // Do sign extension if high bit is set.
          if ((b & (1 << (bd - 1))) == 0) {
            // high bit not set.
            m = (1 << bd) - 1;
            entries![i][j] = m & b;
          } else {
            // high bit set.
            m = 0xffffffff << bd;
            entries![i][j] = m | b;
          }
        } else {
          // Clear all high bits.
          m = (1 << bd) - 1;
          entries![i][j] = m & b;
        }
      }
    }
  }

  int getNumEntries() {
    return nentries;
  }

  int getNumColumns() {
    return ncolumns;
  }

  bool isSigned(int column) {
    return (bitdepth![column] & 0x80) == 1;
  }

  bool isUnSigned(int column) {
    return !isSigned(column);
  }

  int getBitDepth(int column) {
    return ((bitdepth![column] & 0x7f) + 1);
  }

  int getEntry(int column, int entry) {
    return entries![entry][column];
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer("[PaletteBox ");
    rep.write("nentries= $nentries");
    rep.write(", ncolumns= $ncolumns");
    rep.write(", bitdepth per column= (");
    for (int i = 0; i < ncolumns; ++i) {
      rep.write(getBitDepth(i));
      rep.write(isSigned(i) ? "S" : "U");
      rep.write(i < ncolumns - 1 ? ", " : "");
    }
    rep.write(")]");
    return rep.toString();
  }

  int getEntrySize(int column) {
    int bd = getBitDepth(column);
    return (bd / 8).floor() + (bd % 8 == 0 ? 0 : 1);
  }
}


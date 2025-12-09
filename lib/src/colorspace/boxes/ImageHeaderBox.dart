import 'dart:typed_data';
import '../../j2k/io/RandomAccessIO.dart';
import '../../icc/IccProfile.dart';
import 'JP2Box.dart';

class ImageHeaderBox extends JP2Box {
  static const int boxType = 0x69686472; // 'ihdr'

  @override
  int get type => boxType;

  int height = 0;
  int width = 0;
  int nc = 0;
  int bpc = 0;
  int c = 0;
  bool unk = false;
  bool ipr = false;

  ImageHeaderBox(RandomAccessIO in_io, int boxStart) : super(in_io, boxStart) {
    readBox();
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ImageHeaderBox ");
    rep.write(JP2Box.eol);
    rep.write("  ");
    rep.write("height= $height, ");
    rep.write("width= $width");
    rep.write(JP2Box.eol);
    rep.write("  ");

    rep.write("nc= $nc, ");
    rep.write("bpc= $bpc, ");
    rep.write("c= $c");
    rep.write(JP2Box.eol);
    rep.write("  ");

    rep.write('image colorspace is ${unk ? "known" : "unknown"}');
    rep.write(", the image ${ipr ? "contains " : "does not contain "}");
    rep.write("intellectual property]");

    return rep.toString();
  }

  void readBox() {
    Uint8List bfr = Uint8List(14);
    in_io.seek(dataStart);
    in_io.readFully(bfr, 0, 14);

    height = ICCProfile.getInt(bfr, 0);
    width = ICCProfile.getInt(bfr, 4);
    nc = ICCProfile.getShort(bfr, 8);
    bpc = bfr[10] & 0x00ff;
    c = bfr[11] & 0x00ff;
    unk = bfr[12] == 0 ? true : false;
    ipr = bfr[13] == 1 ? true : false;
  }
}


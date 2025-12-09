import 'dart:typed_data';
import '../../j2k/io/RandomAccessIO.dart';
import '../../icc/IccProfile.dart';
import 'JP2Box.dart';

class ComponentMappingBox extends JP2Box {
  static const int boxType = 0x636d6170; // 'cmap'

  @override
  int get type => boxType;

  int nChannels = 0;
  final List<Uint8List> map = <Uint8List>[];

  ComponentMappingBox(RandomAccessIO in_io, int boxStart)
      : super(in_io, boxStart) {
    readBox();
  }

  void readBox() {
    nChannels = ((boxEnd - dataStart) / 4).floor();
    in_io.seek(dataStart);
    for (int offset = dataStart; offset < boxEnd; offset += 4) {
      Uint8List mapping = Uint8List(4);
      in_io.readFully(mapping, 0, 4);
      map.add(mapping);
    }
  }

  int getNChannels() {
    return nChannels;
  }

  int getCMP(int channel) {
    Uint8List mapping = map[channel];
    return ICCProfile.getShort(mapping, 0) & 0x0000ffff;
  }

  int getMTYP(int channel) {
    Uint8List mapping = map[channel];
    return mapping[2] & 0x00ff;
  }

  int getPCOL(int channel) {
    Uint8List mapping = map[channel];
    return mapping[3] & 0x000ff;
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ComponentMappingBox ");
    rep.write("  ");
    rep.write("nChannels= $nChannels");
    for (var mapping in map) {
      rep.write(JP2Box.eol);
      rep.write("  ");
      rep.write("CMP= ${_getCMP(mapping)}, ");
      rep.write("MTYP= ${_getMTYP(mapping)}, ");
      rep.write("PCOL= ${_getPCOL(mapping)}");
    }
    rep.write("]");
    return rep.toString();
  }

  int _getCMP(Uint8List mapping) {
    return ICCProfile.getShort(mapping, 0) & 0x0000ffff;
  }

  int _getMTYP(Uint8List mapping) {
    return mapping[2] & 0x00ff;
  }

  int _getPCOL(Uint8List mapping) {
    return mapping[3] & 0x000ff;
  }
}


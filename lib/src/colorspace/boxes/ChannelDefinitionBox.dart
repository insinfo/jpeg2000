import 'dart:typed_data';
import '../../j2k/io/RandomAccessIO.dart';
import '../../icc/IccProfile.dart';
import 'JP2Box.dart';

class ChannelDefinitionBox extends JP2Box {
  static const int boxType = 0x63646566; // 'cdef'

  @override
  int get type => boxType;

  int ndefs = 0;
  final Map<int, List<int>> definitions = <int, List<int>>{};

  ChannelDefinitionBox(RandomAccessIO in_io, int boxStart)
      : super(in_io, boxStart) {
    readBox();
  }

  void readBox() {
    Uint8List bfr = Uint8List(8);

    in_io.seek(dataStart);
    in_io.readFully(bfr, 0, 2);
    ndefs = ICCProfile.getShort(bfr, 0) & 0x0000ffff;

    int offset = dataStart + 2;
    in_io.seek(offset);
    for (int i = 0; i < ndefs; ++i) {
      in_io.readFully(bfr, 0, 6);
      // int channel = ICCProfile.getShort(bfr, 0); // Unused
      final channel_def = List<int>.filled(3, 0, growable: false);
      channel_def[0] = _getCn(bfr);
      channel_def[1] = _getTyp(bfr);
      channel_def[2] = _getAsoc(bfr);
      definitions[channel_def[0]] = channel_def;
    }
  }

  int getNDefs() {
    return ndefs;
  }

  int getCn(int asoc) {
    return tryGetCn(asoc) ?? asoc;
  }

  /// Finds the channel index associated with [asoc], or `null` if no mapping
  /// is present for that association entry.
  int? tryGetCn(int asoc) {
    for (final entry in definitions.values) {
      if (asoc == _getAsocFromIntArray(entry)) {
        return _getCnFromIntArray(entry);
      }
    }
    return null;
  }

  int getTyp(int channel) {
    final bfr = definitions[channel];
    if (bfr == null) {
      throw StateError('No channel definition for index $channel');
    }
    return _getTypFromIntArray(bfr);
  }

  int getAsoc(int channel) {
    final bfr = definitions[channel];
    if (bfr == null) {
      throw StateError('No channel definition for index $channel');
    }
    return _getAsocFromIntArray(bfr);
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ChannelDefinitionBox ");
    rep.write(JP2Box.eol);
    rep.write("  ");
    rep.write("ndefs= $ndefs");

    for (var key in definitions.keys) {
      List<int> bfr = definitions[key]!;
      rep.write(JP2Box.eol);
      rep.write("  ");
      rep.write("Cn= ${_getCnFromIntArray(bfr)}, ");
      rep.write("Typ= ${_getTypFromIntArray(bfr)}, ");
      rep.write("Asoc= ${_getAsocFromIntArray(bfr)}");
    }

    rep.write("]");
    return rep.toString();
  }

  int _getCn(Uint8List bfr) {
    return ICCProfile.getShort(bfr, 0);
  }

  int _getTyp(Uint8List bfr) {
    return ICCProfile.getShort(bfr, 2);
  }

  int _getAsoc(Uint8List bfr) {
    return ICCProfile.getShort(bfr, 4);
  }

  int _getCnFromIntArray(List<int> bfr) {
    return bfr[0];
  }

  int _getTypFromIntArray(List<int> bfr) {
    return bfr[1];
  }

  int _getAsocFromIntArray(List<int> bfr) {
    return bfr[2];
  }
}


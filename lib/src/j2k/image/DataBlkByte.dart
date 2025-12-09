import 'dart:typed_data';

import 'DataBlk.dart';

/// Unsigned byte implementation of [DataBlk].
class DataBlkByte extends DataBlk {
  DataBlkByte();

  DataBlkByte.withGeometry(int ulx, int uly, int width, int height) {
    this.ulx = ulx;
    this.uly = uly;
    w = width;
    h = height;
    offset = 0;
    scanw = width;
    data = Uint8List(width * height);
  }

  DataBlkByte.copy(DataBlkByte source) {
    ulx = source.ulx;
    uly = source.uly;
    w = source.w;
    h = source.h;
    offset = 0;
    scanw = w;
    final src = source.data;
    if (src != null) {
      data = Uint8List(w * h);
      for (var row = 0; row < h; row++) {
        final destBase = row * scanw;
        final srcBase = row * source.scanw;
        data!.setRange(destBase, destBase + w, src, srcBase);
      }
    }
  }

  Uint8List? data;

  @override
  int getDataType() => DataBlk.typeByte;

  @override
  Object? getData() => data;

  Uint8List? getDataByte() => data;

  @override
  void setData(Object? value) {
    data = value as Uint8List?;
  }

  void setDataByte(Uint8List? value) {
    data = value;
  }

  @override
  String toString() {
    final base = super.toString();
    final length = data?.length;
    return length == null ? base : '$base,data=$length bytes';
  }
}


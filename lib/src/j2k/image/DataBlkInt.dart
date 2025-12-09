import 'dart:typed_data';

import 'DataBlk.dart';

/// Integer implementation of [DataBlk].
class DataBlkInt extends DataBlk {
  Int32List? data;

  DataBlkInt();

  DataBlkInt.withGeometry(int ulx, int uly, int width, int height) {
    this.ulx = ulx;
    this.uly = uly;
    w = width;
    h = height;
    offset = 0;
    scanw = width;
    data = Int32List(width * height);
  }

  DataBlkInt.copy(DataBlkInt source) {
    ulx = source.ulx;
    uly = source.uly;
    w = source.w;
    h = source.h;
    offset = 0;
    scanw = w;
    final src = source.data;
    if (src != null) {
      data = Int32List(w * h);
      for (var row = 0; row < h; row++) {
        final destBase = row * scanw;
        final srcBase = row * source.scanw;
        for (var col = 0; col < w; col++) {
          data![destBase + col] = src[srcBase + col];
        }
      }
    }
  }

  @override
  int getDataType() => DataBlk.typeInt;

  @override
  Object? getData() => data;

  Int32List? getDataInt() => data;

  @override
  void setData(Object? value) {
    data = value as Int32List?;
  }

  void setDataInt(Int32List? value) {
    data = value;
  }

  @override
  String toString() {
    final base = super.toString();
    final length = data?.length;
    return length == null ? base : '$base,data=$length bytes';
  }
}


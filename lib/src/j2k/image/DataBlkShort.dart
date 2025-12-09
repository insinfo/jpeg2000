import 'dart:typed_data';

import 'DataBlk.dart';

/// Signed 16-bit implementation of [DataBlk].
class DataBlkShort extends DataBlk {
  DataBlkShort();

  DataBlkShort.withGeometry(int ulx, int uly, int width, int height) {
    this.ulx = ulx;
    this.uly = uly;
    w = width;
    h = height;
    offset = 0;
    scanw = width;
    data = Int16List(width * height);
  }

  DataBlkShort.copy(DataBlkShort source) {
    ulx = source.ulx;
    uly = source.uly;
    w = source.w;
    h = source.h;
    offset = 0;
    scanw = w;
    final src = source.data;
    if (src != null) {
      data = Int16List(w * h);
      for (var row = 0; row < h; row++) {
        final destBase = row * scanw;
        final srcBase = row * source.scanw;
        data!.setRange(destBase, destBase + w, src, srcBase);
      }
    }
  }

  Int16List? data;

  @override
  int getDataType() => DataBlk.typeShort;

  @override
  Object? getData() => data;

  Int16List? getDataShort() => data;

  @override
  void setData(Object? value) {
    data = value as Int16List?;
  }

  void setDataShort(Int16List? value) {
    data = value;
  }

  @override
  String toString() {
    final base = super.toString();
    final length = data?.length;
    return length == null ? base : '$base,data=$length shorts';
  }
}


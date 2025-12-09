import 'dart:typed_data';

import 'DataBlk.dart';

/// Floating-point implementation of [DataBlk].
class DataBlkFloat extends DataBlk {
  Float32List? data;

  DataBlkFloat();

  DataBlkFloat.withGeometry(int ulx, int uly, int width, int height) {
    this.ulx = ulx;
    this.uly = uly;
    w = width;
    h = height;
    offset = 0;
    scanw = width;
    data = Float32List(width * height);
  }

  DataBlkFloat.copy(DataBlkFloat source) {
    ulx = source.ulx;
    uly = source.uly;
    w = source.w;
    h = source.h;
    offset = 0;
    scanw = w;
    final src = source.data;
    if (src != null) {
      data = Float32List(w * h);
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
  int getDataType() => DataBlk.typeFloat;

  @override
  Object? getData() => data;

  Float32List? getDataFloat() => data;

  @override
  void setData(Object? value) {
    data = value as Float32List?;
  }

  void setDataFloat(Float32List? value) {
    data = value;
  }

  @override
  String toString() {
    final base = super.toString();
    final length = data?.length;
    return length == null ? base : '$base,data=$length bytes';
  }
}


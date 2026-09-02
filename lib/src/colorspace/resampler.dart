import 'dart:typed_data';

import '../j2k/image/blk_img_data_src.dart';
import '../j2k/image/data_blk.dart';
import '../j2k/image/data_blk_float.dart';
import '../j2k/image/data_blk_int.dart';
import 'color_space.dart';
import 'color_space_exception.dart';
import 'color_space_mapper.dart';

class Resampler extends ColorSpaceMapper {
  Resampler(super.src, super.csMap) {
    _initialize();
  }

  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return Resampler(src, csMap);
  }

  late final int minCompSubsX;
  late final int minCompSubsY;
  late final int maxCompSubsX;
  late final int maxCompSubsY;

  void _initialize() {
    var minX = src!.getCompSubsX(0);
    var minY = src!.getCompSubsY(0);
    var maxX = minX;
    var maxY = minY;
    for (var component = 1; component < ncomps; ++component) {
      final compSubsX = src!.getCompSubsX(component);
      final compSubsY = src!.getCompSubsY(component);
      if (compSubsX < minX) minX = compSubsX;
      if (compSubsY < minY) minY = compSubsY;
      if (compSubsX > maxX) maxX = compSubsX;
      if (compSubsY > maxY) maxY = compSubsY;
    }
    if ((maxX != 1 && maxX != 2) || (maxY != 1 && maxY != 2)) {
      throw ColorSpaceException('Upsampling by other than 2:1 not supported');
    }
    minCompSubsX = minX;
    minCompSubsY = minY;
    maxCompSubsX = maxX;
    maxCompSubsY = maxY;
  }

  @override
  DataBlk getInternCompData(DataBlk out, int component) {
    if (src!.getCompSubsX(component) == 1 &&
        src!.getCompSubsY(component) == 1) {
      return src!.getInternCompData(out, component);
    }
    final wfactor = src!.getCompSubsX(component);
    final hfactor = src!.getCompSubsY(component);
    if ((wfactor != 1 && wfactor != 2) || (hfactor != 1 && hfactor != 2)) {
      throw ArgumentError('Upsampling by other than 2:1 not supported');
    }

    final y0Out = out.uly;
    final y1Out = y0Out + out.h - 1;
    final x0Out = out.ulx;
    final x1Out = x0Out + out.w - 1;

    final y0In = y0Out ~/ hfactor;
    final y1In = y1Out ~/ hfactor;
    final x0In = x0Out ~/ wfactor;
    final x1In = x1Out ~/ wfactor;
    final reqW = x1In - x0In + 1;
    final reqH = y1In - y0In + 1;

    switch (out.getDataType()) {
      case DataBlk.typeInt:
        final inblk = DataBlkInt.withGeometry(x0In, y0In, reqW, reqH);
        final sourceBlock =
            src!.getInternCompData(inblk, component) as DataBlkInt;
        dataInt[component] = sourceBlock.getDataInt();
        _upsampleInt(out as DataBlkInt, sourceBlock, x0Out, x1Out, y0Out, y0In,
            hfactor, wfactor);
        out.progressive = sourceBlock.progressive;
        break;
      case DataBlk.typeFloat:
        final inblk = DataBlkFloat.withGeometry(x0In, y0In, reqW, reqH);
        final sourceBlock =
            src!.getInternCompData(inblk, component) as DataBlkFloat;
        dataFloat[component] = sourceBlock.getDataFloat();
        _upsampleFloat(out as DataBlkFloat, sourceBlock, x0Out, x1Out, y0Out,
            y0In, hfactor, wfactor);
        out.progressive = sourceBlock.progressive;
        break;
      default:
        throw ArgumentError('invalid source datablock type');
    }
    return out;
  }

  void _upsampleInt(DataBlkInt out, DataBlkInt inblk, int x0Out, int x1Out,
      int y0Out, int y0In, int hfactor, int wfactor) {
    final outData = out.getDataInt();
    if (outData == null || outData.length != out.w * out.h) {
      out.setData(Int32List(out.w * out.h));
    }
    final dst = out.getDataInt()!;
    final srcData = inblk.getDataInt()!;
    for (var yOut = y0Out; yOut <= y0Out + out.h - 1; ++yOut) {
      final yIn = yOut ~/ hfactor;
      var leftIn = inblk.offset + (yIn - y0In) * inblk.scanw;
      var leftOut = out.offset + (yOut - y0Out) * out.scanw;
      var rightOut = leftOut + out.w;
      if ((x0Out & 1) == 1) {
        dst[leftOut++] = srcData[leftIn++];
      }
      if ((x1Out & 1) == 0) {
        rightOut--;
      }
      while (leftOut < rightOut) {
        dst[leftOut++] = srcData[leftIn];
        dst[leftOut++] = srcData[leftIn++];
      }
      if ((x1Out & 1) == 0) {
        dst[leftOut++] = srcData[leftIn];
      }
    }
  }

  void _upsampleFloat(DataBlkFloat out, DataBlkFloat inblk, int x0Out,
      int x1Out, int y0Out, int y0In, int hfactor, int wfactor) {
    final outData = out.getDataFloat();
    if (outData == null || outData.length != out.w * out.h) {
      out.setData(Float32List(out.w * out.h));
    }
    final dst = out.getDataFloat()!;
    final srcData = inblk.getDataFloat()!;
    for (var yOut = y0Out; yOut <= y0Out + out.h - 1; ++yOut) {
      final yIn = yOut ~/ hfactor;
      var leftIn = inblk.offset + (yIn - y0In) * inblk.scanw;
      var leftOut = out.offset + (yOut - y0Out) * out.scanw;
      var rightOut = leftOut + out.w;
      if ((x0Out & 1) == 1) {
        dst[leftOut++] = srcData[leftIn++];
      }
      if ((x1Out & 1) == 0) {
        rightOut--;
      }
      while (leftOut < rightOut) {
        dst[leftOut++] = srcData[leftIn];
        dst[leftOut++] = srcData[leftIn++];
      }
      if ((x1Out & 1) == 0) {
        dst[leftOut++] = srcData[leftIn];
      }
    }
  }

  @override
  DataBlk getCompData(DataBlk out, int component) {
    return getInternCompData(out, component);
  }

  @override
  int getCompImgHeight(int component) {
    return src!.getCompImgHeight(component) * src!.getCompSubsY(component);
  }

  @override
  int getCompImgWidth(int component) {
    return src!.getCompImgWidth(component) * src!.getCompSubsX(component);
  }

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getTileCompHeight(int tile, int component) {
    return src!.getTileCompHeight(tile, component) *
        src!.getCompSubsY(component);
  }

  @override
  int getTileCompWidth(int tile, int component) {
    return src!.getTileCompWidth(tile, component) *
        src!.getCompSubsX(component);
  }

  @override
  String toString() {
    final rep = StringBuffer('[Resampler: ncomps=$ncomps');
    rep
      ..write(', minSubs=(')
      ..write(minCompSubsX)
      ..write(', ')
      ..write(minCompSubsY)
      ..write('), maxSubs=(')
      ..write(maxCompSubsX)
      ..write(', ')
      ..write(maxCompSubsY)
      ..write(')');
    final body = StringBuffer('  ');
    for (var i = 0; i < ncomps; ++i) {
      body
        ..write(ColorSpaceMapper.eol)
        ..write('comp[')
        ..write(i)
        ..write('] xscale= ')
        ..write(src!.getCompSubsX(i))
        ..write(', yscale= ')
        ..write(src!.getCompSubsY(i));
    }
    rep.write(ColorSpace.indent('  ', body.toString()));
    rep.write(']');
    return rep.toString();
  }
}

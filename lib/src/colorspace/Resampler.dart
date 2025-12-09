import 'dart:typed_data';

import '../j2k/image/BlkImgDataSrc.dart';
import '../j2k/image/DataBlk.dart';
import '../j2k/image/DataBlkFloat.dart';
import '../j2k/image/DataBlkInt.dart';
import 'ColorSpace.dart';
import 'ColorSpaceException.dart';
import 'ColorSpaceMapper.dart';

class Resampler extends ColorSpaceMapper {
  Resampler(BlkImgDataSrc src, ColorSpace csMap) : super(src, csMap) {
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
    for (var c = 1; c < ncomps; ++c) {
      final compSubsX = src!.getCompSubsX(c);
      final compSubsY = src!.getCompSubsY(c);
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
  DataBlk getInternCompData(DataBlk outblk, int c) {
    if (src!.getCompSubsX(c) == 1 && src!.getCompSubsY(c) == 1) {
      return src!.getInternCompData(outblk, c);
    }
    final wfactor = src!.getCompSubsX(c);
    final hfactor = src!.getCompSubsY(c);
    if ((wfactor != 1 && wfactor != 2) || (hfactor != 1 && hfactor != 2)) {
      throw ArgumentError('Upsampling by other than 2:1 not supported');
    }

    final y0Out = outblk.uly;
    final y1Out = y0Out + outblk.h - 1;
    final x0Out = outblk.ulx;
    final x1Out = x0Out + outblk.w - 1;

    final y0In = y0Out ~/ hfactor;
    final y1In = y1Out ~/ hfactor;
    final x0In = x0Out ~/ wfactor;
    final x1In = x1Out ~/ wfactor;
    final reqW = x1In - x0In + 1;
    final reqH = y1In - y0In + 1;

    switch (outblk.getDataType()) {
      case DataBlk.typeInt:
        final inblk = DataBlkInt.withGeometry(x0In, y0In, reqW, reqH);
        final sourceBlock =
            src!.getInternCompData(inblk, c) as DataBlkInt;
        dataInt[c] = sourceBlock.getDataInt();
        _upsampleInt(outblk as DataBlkInt, sourceBlock, x0Out, x1Out, y0Out,
            y0In, hfactor, wfactor);
        outblk.progressive = sourceBlock.progressive;
        break;
      case DataBlk.typeFloat:
        final inblk = DataBlkFloat.withGeometry(x0In, y0In, reqW, reqH);
        final sourceBlock =
            src!.getInternCompData(inblk, c) as DataBlkFloat;
        dataFloat[c] = sourceBlock.getDataFloat();
        _upsampleFloat(outblk as DataBlkFloat, sourceBlock, x0Out, x1Out,
            y0Out, y0In, hfactor, wfactor);
        outblk.progressive = sourceBlock.progressive;
        break;
      default:
        throw ArgumentError('invalid source datablock type');
    }
    return outblk;
  }

  void _upsampleInt(
      DataBlkInt outblk,
      DataBlkInt inblk,
      int x0Out,
      int x1Out,
      int y0Out,
      int y0In,
      int hfactor,
      int wfactor) {
    final outData = outblk.getDataInt();
    if (outData == null || outData.length != outblk.w * outblk.h) {
      outblk.setData(Int32List(outblk.w * outblk.h));
    }
    final dst = outblk.getDataInt()!;
    final srcData = inblk.getDataInt()!;
    for (var yOut = y0Out; yOut <= y0Out + outblk.h - 1; ++yOut) {
      final yIn = yOut ~/ hfactor;
      var leftIn = inblk.offset + (yIn - y0In) * inblk.scanw;
      var leftOut = outblk.offset + (yOut - y0Out) * outblk.scanw;
      var rightOut = leftOut + outblk.w;
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

  void _upsampleFloat(
      DataBlkFloat outblk,
      DataBlkFloat inblk,
      int x0Out,
      int x1Out,
      int y0Out,
      int y0In,
      int hfactor,
      int wfactor) {
    final outData = outblk.getDataFloat();
    if (outData == null || outData.length != outblk.w * outblk.h) {
      outblk.setData(Float32List(outblk.w * outblk.h));
    }
    final dst = outblk.getDataFloat()!;
    final srcData = inblk.getDataFloat()!;
    for (var yOut = y0Out; yOut <= y0Out + outblk.h - 1; ++yOut) {
      final yIn = yOut ~/ hfactor;
      var leftIn = inblk.offset + (yIn - y0In) * inblk.scanw;
      var leftOut = outblk.offset + (yOut - y0Out) * outblk.scanw;
      var rightOut = leftOut + outblk.w;
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
  DataBlk getCompData(DataBlk outblk, int c) {
    return getInternCompData(outblk, c);
  }

  @override
  int getCompImgHeight(int c) {
    return src!.getCompImgHeight(c) * src!.getCompSubsY(c);
  }

  @override
  int getCompImgWidth(int c) {
    return src!.getCompImgWidth(c) * src!.getCompSubsX(c);
  }

  @override
  int getCompSubsX(int c) => 1;

  @override
  int getCompSubsY(int c) => 1;

  @override
  int getTileCompHeight(int t, int c) {
    return src!.getTileCompHeight(t, c) * src!.getCompSubsY(c);
  }

  @override
  int getTileCompWidth(int t, int c) {
    return src!.getTileCompWidth(t, c) * src!.getCompSubsX(c);
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

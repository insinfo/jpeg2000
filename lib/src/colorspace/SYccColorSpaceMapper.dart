import 'dart:typed_data';

import '../j2k/image/BlkImgDataSrc.dart';
import '../j2k/image/DataBlk.dart';
import '../j2k/image/DataBlkFloat.dart';
import '../j2k/image/DataBlkInt.dart';
import '../j2k/util/FacilityManager.dart';
import '../j2k/util/MsgLogger.dart';
import 'ColorSpace.dart';
import 'ColorSpaceException.dart';
import 'ColorSpaceMapper.dart';

class SYccColorSpaceMapper extends ColorSpaceMapper {
  SYccColorSpaceMapper(BlkImgDataSrc src, ColorSpace csMap) : super(src, csMap) {
    _validateComponentCount();
  }

  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return SYccColorSpaceMapper(src, csMap);
  }

  static const double _m00 = 1.0;
  static const double _m01 = 0.0;
  static const double _m02 = 1.402;
  static const double _m10 = 1.0;
  static const double _m11 = -0.34413;
  static const double _m12 = -0.71414;
  static const double _m20 = 1.0;
  static const double _m21 = 1.772;
  static const double _m22 = 0.0;

  void _validateComponentCount() {
    if (ncomps != 1 && ncomps != 3) {
      final msg =
          'SYccColorSpaceMapper: ycc transformation not applied to $ncomps component image';
      FacilityManager.getMsgLogger().printmsg(MsgLogger.error, msg);
      throw ColorSpaceException(msg);
    }
  }

  @override
  DataBlk getCompData(DataBlk outblk, int c) {
    switch (outblk.getDataType()) {
      case DataBlk.typeInt:
        _prepareIntBlocks(outblk);
        if (ncomps == 1) {
          workInt[c] = inInt[c];
        } else {
          workInt = _multiplyInt();
        }
        outblk.setData(workInt[c]!.getData());
        outblk.progressive = inInt[c]!.progressive;
        break;
      case DataBlk.typeFloat:
        _prepareFloatBlocks(outblk);
        if (ncomps == 1) {
          workFloat[c] = inFloat[c];
        } else {
          workFloat = _multiplyFloat();
        }
        outblk.setData(workFloat[c]!.getData());
        outblk.progressive = inFloat[c]!.progressive;
        break;
      default:
        throw ArgumentError('Unsupported datablock type for SYcc mapper');
    }
    outblk.offset = 0;
    outblk.scanw = outblk.w;
    return outblk;
  }

  void _prepareIntBlocks(DataBlk template) {
    for (var i = 0; i < ncomps; ++i) {
      ColorSpaceMapper.copyGeometry(inInt[i]!, template);
      inInt[i] = src!.getInternCompData(inInt[i]!, i) as DataBlkInt;
    }
  }

  void _prepareFloatBlocks(DataBlk template) {
    for (var i = 0; i < ncomps; ++i) {
      ColorSpaceMapper.copyGeometry(inFloat[i]!, template);
      inFloat[i] = src!.getInternCompData(inFloat[i]!, i) as DataBlkFloat;
    }
  }

  List<DataBlkInt?> _multiplyInt() {
    if (ncomps != 3) {
      throw ArgumentError('bad input array size');
    }
    final length = inInt[0]!.h * inInt[0]!.w;
    final outputs = List<DataBlkInt?>.filled(3, null, growable: false);
    for (var i = 0; i < 3; ++i) {
      final outBlock = DataBlkInt();
      ColorSpaceMapper.copyGeometry(outBlock, inInt[i]!);
      outBlock.offset = inInt[i]!.offset;
      outBlock.setData(Int32List(length));
      outputs[i] = outBlock;
    }

    final yData = inInt[0]!.getDataInt()!;
    final cbData = inInt[1]!.getDataInt()!;
    final crData = inInt[2]!.getDataInt()!;
    final out0 = outputs[0]!.getDataInt()!;
    final out1 = outputs[1]!.getDataInt()!;
    final out2 = outputs[2]!.getDataInt()!;
    final yOffset = inInt[0]!.offset;
    final cbOffset = inInt[1]!.offset;
    final crOffset = inInt[2]!.offset;

    for (var j = 0; j < length; ++j) {
      final y = yData[yOffset + j];
      final cb = cbData[cbOffset + j];
      final cr = crData[crOffset + j];
      out0[j] = (_m00 * y + _m01 * cb + _m02 * cr).round();
      out1[j] = (_m10 * y + _m11 * cb + _m12 * cr).round();
      out2[j] = (_m20 * y + _m21 * cb + _m22 * cr).round();
    }

    return outputs;
  }

  List<DataBlkFloat?> _multiplyFloat() {
    if (ncomps != 3) {
      throw ArgumentError('bad input array size');
    }
    final length = inFloat[0]!.h * inFloat[0]!.w;
    final outputs = List<DataBlkFloat?>.filled(3, null, growable: false);
    for (var i = 0; i < 3; ++i) {
      final outBlock = DataBlkFloat();
      ColorSpaceMapper.copyGeometry(outBlock, inFloat[i]!);
      outBlock.offset = inFloat[i]!.offset;
      outBlock.setData(Float32List(length));
      outputs[i] = outBlock;
    }

    final yData = inFloat[0]!.getDataFloat()!;
    final cbData = inFloat[1]!.getDataFloat()!;
    final crData = inFloat[2]!.getDataFloat()!;
    final out0 = outputs[0]!.getDataFloat()!;
    final out1 = outputs[1]!.getDataFloat()!;
    final out2 = outputs[2]!.getDataFloat()!;
    final yOffset = inFloat[0]!.offset;
    final cbOffset = inFloat[1]!.offset;
    final crOffset = inFloat[2]!.offset;

    for (var j = 0; j < length; ++j) {
      final y = yData[yOffset + j];
      final cb = cbData[cbOffset + j];
      final cr = crData[crOffset + j];
      out0[j] = (_m00 * y + _m01 * cb + _m02 * cr).toDouble();
      out1[j] = (_m10 * y + _m11 * cb + _m12 * cr).toDouble();
      out2[j] = (_m20 * y + _m21 * cb + _m22 * cr).toDouble();
    }

    return outputs;
  }

  @override
  DataBlk getInternCompData(DataBlk out, int c) {
    return getCompData(out, c);
  }

  @override
  String toString() {
    final comps = StringBuffer();
    for (var i = 0; i < ncomps; ++i) {
      comps
        ..write('  component[$i] height, width = (')
        ..write(src!.getCompImgHeight(i))
        ..write(', ')
        ..write(src!.getCompImgWidth(i))
        ..write(')')
        ..write(ColorSpaceMapper.eol);
    }
    final rep = StringBuffer('[SYccColorSpaceMapper ');
    rep
      ..write('ncomps=$ncomps')
      ..write(ColorSpaceMapper.eol)
      ..write(ColorSpace.indent('  ', comps.toString()))
      ..write(']');
    return rep.toString();
  }
}

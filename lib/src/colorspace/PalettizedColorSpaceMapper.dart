import '../j2k/image/BlkImgDataSrc.dart';
import '../j2k/image/DataBlk.dart';
import '../j2k/image/DataBlkFloat.dart';
import '../j2k/image/DataBlkInt.dart';
import '../j2k/util/FacilityManager.dart';
import '../j2k/util/MsgLogger.dart';
import 'ColorSpace.dart';
import 'ColorSpaceException.dart';
import 'ColorSpaceMapper.dart';
import 'boxes/PaletteBox.dart';

class PalettizedColorSpaceMapper extends ColorSpaceMapper {
  PalettizedColorSpaceMapper(BlkImgDataSrc src, ColorSpace csMap)
      : super(src, csMap) {
    pbox = csMap.getPaletteBox();
    _initialize();
  }

  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return PalettizedColorSpaceMapper(src, csMap);
  }

  final int srcChannel = 0;
  PaletteBox? pbox;
  late final List<int> outShiftValueArray;

  void _initialize() {
    if (ncomps != 1 && ncomps != 3) {
      throw ColorSpaceException(
          'wrong number of components ($ncomps) for palettized image');
    }
    final outComps = getNumComps();
    outShiftValueArray = List<int>.generate(outComps, (i) => 1 << (getNomRangeBits(i) - 1));
  }

  @override
  DataBlk getCompData(DataBlk out, int c) {
    final palette = pbox;
    if (palette == null) {
      return src!.getCompData(out, c);
    }
    if (ncomps != 1) {
      final msg =
          'PalettizedColorSpaceMapper: color palette not applied, incorrect number ($ncomps) of components';
      FacilityManager.getMsgLogger().printmsg(MsgLogger.warning, msg);
      return src!.getCompData(out, c);
    }

    ColorSpaceMapper.setInternalBuffer(out);

    switch (out.getDataType()) {
      case DataBlk.typeInt:
        ColorSpaceMapper.copyGeometry(inInt[0]!, out);
        inInt[0] = src!.getInternCompData(inInt[0]!, 0) as DataBlkInt;
        dataInt[0] = inInt[0]!.getDataInt();
        final outData = (out as DataBlkInt).getDataInt()!;
        _mapPaletteInt(out, c, palette, outData);
        out.progressive = inInt[0]!.progressive;
        break;
      case DataBlk.typeFloat:
        ColorSpaceMapper.copyGeometry(inFloat[0]!, out);
        inFloat[0] = src!.getInternCompData(inFloat[0]!, 0) as DataBlkFloat;
        dataFloat[0] = inFloat[0]!.getDataFloat();
        final outData = (out as DataBlkFloat).getDataFloat()!;
        _mapPaletteFloat(out, c, palette, outData);
        out.progressive = inFloat[0]!.progressive;
        break;
      default:
        throw ArgumentError('invalid source datablock type');
    }

    out.offset = 0;
    out.scanw = out.w;
    return out;
  }

  void _mapPaletteInt(DataBlk out, int c, PaletteBox palette, List<int> outData) {
    final srcData = dataInt[0]!;
    for (var row = 0; row < out.h; ++row) {
      final leftIn = inInt[0]!.offset + row * inInt[0]!.scanw;
      final rightIn = leftIn + inInt[0]!.w;
      final leftOut = out.offset + row * out.scanw;
      var kOut = leftOut;
      for (var kIn = leftIn; kIn < rightIn; ++kIn, ++kOut) {
        outData[kOut] =
            palette.getEntry(c, srcData[kIn] + shiftValueArray![0]) - outShiftValueArray[c];
      }
    }
  }

  void _mapPaletteFloat(
      DataBlk out, int c, PaletteBox palette, List<double> outData) {
    final srcData = dataFloat[0]!;
    for (var row = 0; row < out.h; ++row) {
      final leftIn = inFloat[0]!.offset + row * inFloat[0]!.scanw;
      final rightIn = leftIn + inFloat[0]!.w;
      final leftOut = out.offset + row * out.scanw;
      var kOut = leftOut;
      for (var kIn = leftIn; kIn < rightIn; ++kIn, ++kOut) {
        outData[kOut] = (palette.getEntry(
                      c,
                      srcData[kIn].toInt() + shiftValueArray![0],
                    ) -
                    outShiftValueArray[c])
                .toDouble();
      }
    }
  }

  @override
  DataBlk getInternCompData(DataBlk out, int c) {
    return getCompData(out, c);
  }

  @override
  int getNomRangeBits(int c) {
    return pbox == null ? src!.getNomRangeBits(c) : pbox!.getBitDepth(c);
  }

  @override
  int getNumComps() {
    return pbox == null ? src!.getNumComps() : pbox!.getNumColumns();
  }

  @override
  int getCompSubsX(int c) {
    return src!.getCompSubsX(srcChannel);
  }

  @override
  int getCompSubsY(int c) {
    return src!.getCompSubsY(srcChannel);
  }

  @override
  int getTileCompWidth(int t, int c) {
    return src!.getTileCompWidth(t, srcChannel);
  }

  @override
  int getTileCompHeight(int t, int c) {
    return src!.getTileCompHeight(t, srcChannel);
  }

  @override
  int getCompImgWidth(int c) {
    return src!.getCompImgWidth(srcChannel);
  }

  @override
  int getCompImgHeight(int c) {
    return src!.getCompImgHeight(srcChannel);
  }

  @override
  int getCompULX(int c) {
    return src!.getCompULX(srcChannel);
  }

  @override
  int getCompULY(int c) {
    return src!.getCompULY(srcChannel);
  }

  @override
  String toString() {
    final builder = StringBuffer('[PalettizedColorSpaceMapper ');
    final body = StringBuffer('  ${ColorSpaceMapper.eol}');
    if (pbox != null) {
      body
        ..write('ncomps=${getNumComps()}, scomp=$srcChannel')
        ..write(ColorSpaceMapper.eol);
      for (var c = 0; c < getNumComps(); ++c) {
        body
          ..write('column=$c, ${pbox!.getBitDepth(c)} bit ')
          ..write(pbox!.isSigned(c) ? 'signed entry' : 'unsigned entry')
          ..write(ColorSpaceMapper.eol);
      }
    } else {
      body.write('image does not contain a palette box');
    }
    builder.write(ColorSpace.indent('  ', body.toString()));
    return '${builder}]';
  }
}

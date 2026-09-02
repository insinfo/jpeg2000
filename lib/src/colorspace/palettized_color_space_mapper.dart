import '../j2k/image/blk_img_data_src.dart';
import '../j2k/image/data_blk.dart';
import '../j2k/image/data_blk_float.dart';
import '../j2k/image/data_blk_int.dart';
import '../j2k/util/facility_manager.dart';
import '../j2k/util/msg_logger.dart';
import 'color_space.dart';
import 'color_space_exception.dart';
import 'color_space_mapper.dart';
import 'boxes/palette_box.dart';

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
    outShiftValueArray =
        List<int>.generate(outComps, (i) => 1 << (getNomRangeBits(i) - 1));
  }

  @override
  DataBlk getCompData(DataBlk out, int component) {
    final palette = pbox;
    if (palette == null) {
      return src!.getCompData(out, component);
    }
    if (ncomps != 1) {
      final msg =
          'PalettizedColorSpaceMapper: color palette not applied, incorrect number ($ncomps) of components';
      FacilityManager.getMsgLogger().printmsg(MsgLogger.warning, msg);
      return src!.getCompData(out, component);
    }

    ColorSpaceMapper.setInternalBuffer(out);

    switch (out.getDataType()) {
      case DataBlk.typeInt:
        ColorSpaceMapper.copyGeometry(inInt[0]!, out);
        inInt[0] = src!.getInternCompData(inInt[0]!, 0) as DataBlkInt;
        dataInt[0] = inInt[0]!.getDataInt();
        final outData = (out as DataBlkInt).getDataInt()!;
        _mapPaletteInt(out, component, palette, outData);
        out.progressive = inInt[0]!.progressive;
        break;
      case DataBlk.typeFloat:
        ColorSpaceMapper.copyGeometry(inFloat[0]!, out);
        inFloat[0] = src!.getInternCompData(inFloat[0]!, 0) as DataBlkFloat;
        dataFloat[0] = inFloat[0]!.getDataFloat();
        final outData = (out as DataBlkFloat).getDataFloat()!;
        _mapPaletteFloat(out, component, palette, outData);
        out.progressive = inFloat[0]!.progressive;
        break;
      default:
        throw ArgumentError('invalid source datablock type');
    }

    out.offset = 0;
    out.scanw = out.w;
    return out;
  }

  void _mapPaletteInt(
      DataBlk out, int component, PaletteBox palette, List<int> outData) {
    final srcData = dataInt[0]!;
    for (var row = 0; row < out.h; ++row) {
      final leftIn = inInt[0]!.offset + row * inInt[0]!.scanw;
      final rightIn = leftIn + inInt[0]!.w;
      final leftOut = out.offset + row * out.scanw;
      var kOut = leftOut;
      for (var kIn = leftIn; kIn < rightIn; ++kIn, ++kOut) {
        outData[kOut] =
            palette.getEntry(component, srcData[kIn] + shiftValueArray![0]) -
                outShiftValueArray[component];
      }
    }
  }

  void _mapPaletteFloat(
      DataBlk out, int component, PaletteBox palette, List<double> outData) {
    final srcData = dataFloat[0]!;
    for (var row = 0; row < out.h; ++row) {
      final leftIn = inFloat[0]!.offset + row * inFloat[0]!.scanw;
      final rightIn = leftIn + inFloat[0]!.w;
      final leftOut = out.offset + row * out.scanw;
      var kOut = leftOut;
      for (var kIn = leftIn; kIn < rightIn; ++kIn, ++kOut) {
        outData[kOut] = (palette.getEntry(
                  component,
                  srcData[kIn].toInt() + shiftValueArray![0],
                ) -
                outShiftValueArray[component])
            .toDouble();
      }
    }
  }

  @override
  DataBlk getInternCompData(DataBlk out, int component) {
    return getCompData(out, component);
  }

  @override
  int getNomRangeBits(int component) {
    return pbox == null
        ? src!.getNomRangeBits(component)
        : pbox!.getBitDepth(component);
  }

  @override
  int getNumComps() {
    return pbox == null ? src!.getNumComps() : pbox!.getNumColumns();
  }

  @override
  int getCompSubsX(int component) {
    return src!.getCompSubsX(srcChannel);
  }

  @override
  int getCompSubsY(int component) {
    return src!.getCompSubsY(srcChannel);
  }

  @override
  int getTileCompWidth(int tile, int component) {
    return src!.getTileCompWidth(tile, srcChannel);
  }

  @override
  int getTileCompHeight(int tile, int component) {
    return src!.getTileCompHeight(tile, srcChannel);
  }

  @override
  int getCompImgWidth(int component) {
    return src!.getCompImgWidth(srcChannel);
  }

  @override
  int getCompImgHeight(int component) {
    return src!.getCompImgHeight(srcChannel);
  }

  @override
  int getCompULX(int component) {
    return src!.getCompULX(srcChannel);
  }

  @override
  int getCompULY(int component) {
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
      for (var component = 0; component < getNumComps(); ++component) {
        body
          ..write('column=$component, ${pbox!.getBitDepth(component)} bit ')
          ..write(pbox!.isSigned(component) ? 'signed entry' : 'unsigned entry')
          ..write(ColorSpaceMapper.eol);
      }
    } else {
      body.write('image does not contain a palette box');
    }
    builder.write(ColorSpace.indent('  ', body.toString()));
    return '$builder]';
  }
}

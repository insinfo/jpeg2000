import '../j2k/image/blk_img_data_src.dart';
import '../j2k/image/data_blk.dart';
import 'color_space.dart';
import 'color_space_mapper.dart';

/// Maps logical JP2 components onto actual image channels based on the
/// channel definition box.
class ChannelDefinitionMapper extends ColorSpaceMapper {
  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return ChannelDefinitionMapper(src, csMap);
  }

  ChannelDefinitionMapper(super.src, super.csMap);

  @override
  DataBlk getCompData(DataBlk out, int component) {
    return src!.getCompData(out, csMap!.getChannelDefinition(component));
  }

  @override
  DataBlk getInternCompData(DataBlk out, int component) {
    return src!.getInternCompData(out, csMap!.getChannelDefinition(component));
  }

  @override
  int getFixedPoint(int component) {
    return src!.getFixedPoint(csMap!.getChannelDefinition(component));
  }

  @override
  int getNomRangeBits(int component) {
    return src!.getNomRangeBits(csMap!.getChannelDefinition(component));
  }

  @override
  int getCompImgHeight(int component) {
    return src!.getCompImgHeight(csMap!.getChannelDefinition(component));
  }

  @override
  int getCompImgWidth(int component) {
    return src!.getCompImgWidth(csMap!.getChannelDefinition(component));
  }

  @override
  int getCompSubsX(int component) {
    return src!.getCompSubsX(csMap!.getChannelDefinition(component));
  }

  @override
  int getCompSubsY(int component) {
    return src!.getCompSubsY(csMap!.getChannelDefinition(component));
  }

  @override
  int getCompULX(int component) {
    return src!.getCompULX(csMap!.getChannelDefinition(component));
  }

  @override
  int getCompULY(int component) {
    return src!.getCompULY(csMap!.getChannelDefinition(component));
  }

  @override
  int getTileCompHeight(int tile, int component) {
    return src!.getTileCompHeight(tile, csMap!.getChannelDefinition(component));
  }

  @override
  int getTileCompWidth(int tile, int component) {
    return src!.getTileCompWidth(tile, csMap!.getChannelDefinition(component));
  }

  @override
  String toString() {
    StringBuffer rep =
        StringBuffer('[ChannelDefinitionMapper nchannels= $ncomps');
    for (int i = 0; i < ncomps; ++i) {
      rep
        ..write(ColorSpaceMapper.eol)
        ..write('  component[')
        ..write(i)
        ..write('] mapped to channel[')
        ..write(csMap!.getChannelDefinition(i))
        ..write(']');
    }
    return (rep..write(']')).toString();
  }
}

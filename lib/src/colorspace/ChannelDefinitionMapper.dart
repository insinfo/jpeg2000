import '../j2k/image/BlkImgDataSrc.dart';
import '../j2k/image/DataBlk.dart';
import 'ColorSpace.dart';
import 'ColorSpaceMapper.dart';

/// Maps logical JP2 components onto actual image channels based on the
/// channel definition box.
class ChannelDefinitionMapper extends ColorSpaceMapper {
  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return ChannelDefinitionMapper(src, csMap);
  }

  ChannelDefinitionMapper(BlkImgDataSrc src, ColorSpace csMap)
      : super(src, csMap);

  @override
  DataBlk getCompData(DataBlk outblk, int c) {
    return src!.getCompData(outblk, csMap!.getChannelDefinition(c));
  }

  @override
  DataBlk getInternCompData(DataBlk outblk, int c) {
    return src!.getInternCompData(outblk, csMap!.getChannelDefinition(c));
  }

  @override
  int getFixedPoint(int c) {
    return src!.getFixedPoint(csMap!.getChannelDefinition(c));
  }

  @override
  int getNomRangeBits(int c) {
    return src!.getNomRangeBits(csMap!.getChannelDefinition(c));
  }

  @override
  int getCompImgHeight(int c) {
    return src!.getCompImgHeight(csMap!.getChannelDefinition(c));
  }

  @override
  int getCompImgWidth(int c) {
    return src!.getCompImgWidth(csMap!.getChannelDefinition(c));
  }

  @override
  int getCompSubsX(int c) {
    return src!.getCompSubsX(csMap!.getChannelDefinition(c));
  }

  @override
  int getCompSubsY(int c) {
    return src!.getCompSubsY(csMap!.getChannelDefinition(c));
  }

  @override
  int getCompULX(int c) {
    return src!.getCompULX(csMap!.getChannelDefinition(c));
  }

  @override
  int getCompULY(int c) {
    return src!.getCompULY(csMap!.getChannelDefinition(c));
  }

  @override
  int getTileCompHeight(int t, int c) {
    return src!.getTileCompHeight(t, csMap!.getChannelDefinition(c));
  }

  @override
  int getTileCompWidth(int t, int c) {
    return src!.getTileCompWidth(t, csMap!.getChannelDefinition(c));
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer('[ChannelDefinitionMapper nchannels= $ncomps');
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

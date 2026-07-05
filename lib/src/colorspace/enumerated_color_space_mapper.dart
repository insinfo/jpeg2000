import '../j2k/image/blk_img_data_src.dart';
import '../j2k/image/data_blk.dart';
import 'color_space.dart';
import 'color_space_mapper.dart';

class EnumeratedColorSpaceMapper extends ColorSpaceMapper {
  EnumeratedColorSpaceMapper(super.src, super.csMap);

  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return EnumeratedColorSpaceMapper(src, csMap);
  }

  @override
  DataBlk getCompData(DataBlk out, int c) {
    return src!.getCompData(out, c);
  }

  @override
  DataBlk getInternCompData(DataBlk out, int c) {
    return src!.getInternCompData(out, c);
  }

  @override
  String toString() {
    final repShift = StringBuffer('shiftValue=(');
    final repMax = StringBuffer('maxValue=(');
    final repFixed = StringBuffer('fixedPointBits=(');
    for (var i = 0; i < ncomps; ++i) {
      if (i != 0) {
        repShift.write(', ');
        repMax.write(', ');
        repFixed.write(', ');
      }
      repShift.write(shiftValueArray![i]);
      repMax.write(maxValueArray![i]);
      repFixed.write(fixedPtBitsArray![i]);
    }
    repShift.write(')');
    repMax.write(')');
    repFixed.write(')');
    final rep = StringBuffer('[EnumeratedColorSpaceMapper ');
    const newline = ColorSpaceMapper.eol;
    rep
      ..write('ncomps=$ncomps$newline  ')
      ..write(repShift)
      ..write('$newline  ')
      ..write(repMax)
      ..write('$newline  ')
      ..write(repFixed)
      ..write(']');
    return rep.toString();
  }
}

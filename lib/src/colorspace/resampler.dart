import '../j2k/image/blk_img_data_src.dart';
import '../j2k/image/component_upsampler.dart';
import '../j2k/image/data_blk.dart';
import 'color_space.dart';
import 'color_space_mapper.dart';

/// Colour-pipeline face of [ComponentUpsampler].
///
/// JP2 files reach the resampling stage through the colour pipeline, which
/// requires a [ColorSpace]; raw codestreams have no JP2 boxes and therefore no
/// [ColorSpace] at all. So that both get the same arithmetic, all the work
/// lives in [ComponentUpsampler] and this class is only the adapter that lets
/// the colour pipeline use it.
class Resampler extends ColorSpaceMapper {
  Resampler(super.src, super.csMap) {
    _initialize();
  }

  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return Resampler(src, csMap);
  }

  late final ComponentUpsampler _upsampler;

  int get minCompSubsX => _upsampler.minCompSubsX;
  int get minCompSubsY => _upsampler.minCompSubsY;
  int get maxCompSubsX => _upsampler.maxCompSubsX;
  int get maxCompSubsY => _upsampler.maxCompSubsY;

  void _initialize() {
    _upsampler = ComponentUpsampler(src!);
  }

  @override
  DataBlk getInternCompData(DataBlk out, int component) {
    return _upsampler.getInternCompData(out, component);
  }

  @override
  DataBlk getCompData(DataBlk out, int component) {
    return getInternCompData(out, component);
  }

  @override
  int getCompImgHeight(int component) => _upsampler.getCompImgHeight(component);

  @override
  int getCompImgWidth(int component) => _upsampler.getCompImgWidth(component);

  @override
  int getCompSubsX(int component) => 1;

  @override
  int getCompSubsY(int component) => 1;

  @override
  int getTileCompHeight(int tile, int component) =>
      _upsampler.getTileCompHeight(tile, component);

  @override
  int getTileCompWidth(int tile, int component) =>
      _upsampler.getTileCompWidth(tile, component);

  @override
  int getCompULX(int component) => _upsampler.getCompULX(component);

  @override
  int getCompULY(int component) => _upsampler.getCompULY(component);

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

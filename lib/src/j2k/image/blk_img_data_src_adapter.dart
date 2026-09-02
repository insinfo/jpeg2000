import 'blk_img_data_src.dart';
import 'data_blk.dart';
import 'img_data_adapter.dart';

/// Convenience base class that forwards [BlkImgDataSrc] methods to a delegate.
class BlkImgDataSrcAdapter extends ImgDataAdapter implements BlkImgDataSrc {
  BlkImgDataSrcAdapter(BlkImgDataSrc super.source) : _source = source;

  final BlkImgDataSrc _source;

  @override
  BlkImgDataSrc get source => _source;

  @override
  int getFixedPoint(int component) => source.getFixedPoint(component);

  @override
  DataBlk getInternCompData(DataBlk block, int component) =>
      source.getInternCompData(block, component);

  @override
  DataBlk getCompData(DataBlk block, int component) =>
      source.getCompData(block, component);
}

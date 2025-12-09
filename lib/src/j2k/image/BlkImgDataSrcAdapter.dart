import 'BlkImgDataSrc.dart';
import 'DataBlk.dart';
import 'ImgDataAdapter.dart';

/// Convenience base class that forwards [BlkImgDataSrc] methods to a delegate.
class BlkImgDataSrcAdapter extends ImgDataAdapter implements BlkImgDataSrc {
  BlkImgDataSrcAdapter(this.source) : super(source);

  final BlkImgDataSrc source;

  @override
  int getFixedPoint(int component) => source.getFixedPoint(component);

  @override
  DataBlk getInternCompData(DataBlk block, int component) =>
      source.getInternCompData(block, component);

  @override
  DataBlk getCompData(DataBlk block, int component) =>
      source.getCompData(block, component);
}


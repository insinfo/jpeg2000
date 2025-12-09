import 'DataBlk.dart';
import 'ImgData.dart';

/// Supplies component image data in tile-relative blocks.
abstract class BlkImgDataSrc extends ImgData {
  int getFixedPoint(int component);

  DataBlk getInternCompData(DataBlk block, int component);

  DataBlk getCompData(DataBlk block, int component);
}


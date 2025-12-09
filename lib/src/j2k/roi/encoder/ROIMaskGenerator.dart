import '../../image/DataBlkInt.dart';
import '../../wavelet/subband.dart';
import 'roi.dart';

/// Abstract contract for ROI mask generators used by the encoder.
abstract class ROIMaskGenerator {
  ROIMaskGenerator(this.rois, this.numComponents)
      : tileMaskComputed = List<bool>.filled(numComponents, false);

  /// ROI definitions used by the encoder.
  final List<ROI> rois;

  /// Total number of image components.
  final int numComponents;

  /// Tracks which tile/components already have a mask cached.
  final List<bool> tileMaskComputed;

  /// Indicates whether the current tile contains any ROI samples.
  bool roiInTile = false;

  List<ROI> getRegions() => rois;

  /// Populates [block] with ROI scaling factors for the provided subband.
  bool getRoiMask(DataBlkInt block, Subband subband, int magnitudeBits, int componentIndex);

  /// Rebuilds the cached mask for the current tile-component.
  void buildMask(Subband subband, int magnitudeBits, int componentIndex);

  /// Invalidate cached masks when the processing moves to another tile.
  void tileChanged() {
    for (var i = 0; i < tileMaskComputed.length; i++) {
      tileMaskComputed[i] = false;
    }
  }
}


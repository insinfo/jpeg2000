import '../BlkImgDataSrc.dart';
import '../Coord.dart';

/// Base class for image writers that emit decoded samples to files or streams.
abstract class ImgWriter {
  /// Default strip height used when writers process a tile incrementally.
  static const int defStripHeight = 64;

  /// Source of image data that this writer serialises.
  late BlkImgDataSrc src;

  /// Width of the output image in pixels.
  late int width;

  /// Height of the output image in pixels.
  late int height;

  /// Releases the underlying resource. Implementations should flush pending
  /// data before closing and should not allow further use afterwards.
  void close();

  /// Forces any buffered data to be written to the destination.
  void flush();

  /// Writes the currently selected tile from [src] to the destination.
  void writeTile();

  /// Writes a rectangular region from the current tile.
  void writeRegion(int ulx, int uly, int regionWidth, int regionHeight);

  /// Convenience alias matching the Java API.
  void write() => writeTile();

  /// Writes the full image by iterating over all tiles.
  void writeAll() {
    final Coord tileCount = src.getNumTilesCoord(null);
    for (var ty = 0; ty < tileCount.y; ty++) {
      for (var tx = 0; tx < tileCount.x; tx++) {
        src.setTile(tx, ty);
        writeTile();
      }
    }
  }
}


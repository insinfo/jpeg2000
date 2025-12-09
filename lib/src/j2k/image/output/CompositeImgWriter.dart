import '../BlkImgDataSrc.dart';
import 'ImgWriter.dart';

/// Dispatches write operations to multiple [ImgWriter] instances.
class CompositeImgWriter extends ImgWriter {
  CompositeImgWriter(this.writers) {
    if (writers.isEmpty) {
      throw ArgumentError('Composite writer requires at least one delegate.');
    }
    src = writers.first.src;
    width = writers.first.width;
    height = writers.first.height;
  }

  final List<ImgWriter> writers;

  ImgWriter get _primary => writers.first;

  @override
  void close() {
    Object? firstError;
    for (final writer in writers) {
      try {
        writer.close();
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw firstError;
    }
  }

  @override
  void flush() {
    for (final writer in writers) {
      writer.flush();
    }
  }

  @override
  void writeTile() {
    for (final writer in writers) {
      writer.writeTile();
    }
  }

  @override
  void writeRegion(int ulx, int uly, int regionWidth, int regionHeight) {
    for (final writer in writers) {
      writer.writeRegion(ulx, uly, regionWidth, regionHeight);
    }
  }

  @override
  void writeAll() {
    for (final writer in writers) {
      writer.writeAll();
    }
  }

  @override
  @override
  @override
  BlkImgDataSrc get src => _primary.src;

  @override
  int get width => _primary.width;

  @override
  int get height => _primary.height;
}


import 'dart:math' as math;
import 'dart:typed_data';

import 'BlkImgDataSrc.dart';
import 'DataBlk.dart';
import 'DataBlkFloat.dart';
import 'DataBlkInt.dart';
import 'ImgDataAdapter.dart';
import '../util/DecoderInstrumentation.dart';

class ImgDataConverter extends ImgDataAdapter implements BlkImgDataSrc {
  ImgDataConverter(BlkImgDataSrc source, [int fixedPoint = 0, String? debugLabel])
      : _source = source,
        _fixedPoint = fixedPoint,
        _debugLabel = debugLabel ?? 'ImgDataConverter',
        _requestBlock = DataBlkInt(),
        super(source);

  static const int _maxLogsPerDirection = 4;

  final BlkImgDataSrc _source;
  final String _debugLabel;
  DataBlk _requestBlock;
  int _fixedPoint;
  int _intToFloatLogs = 0;
  int _floatToIntLogs = 0;

  @override
  int getFixedPoint(int component) => _fixedPoint;

  @override
  DataBlk getCompData(DataBlk block, int component) =>
      _getData(block, component, false);

  @override
  DataBlk getInternCompData(DataBlk block, int component) =>
      _getData(block, component, true);

  DataBlk _getData(DataBlk block, int component, bool intern) {
    final desiredType = block.getDataType();
    DataBlk request;

    if (desiredType == _requestBlock.getDataType()) {
      request = block;
    } else {
      request = _requestBlock
        ..ulx = block.ulx
        ..uly = block.uly
        ..w = block.w
        ..h = block.h;
    }

    final DataBlk acquired = intern
        ? _source.getInternCompData(request, component)
        : _source.getCompData(request, component);

    _requestBlock = acquired;

    if (acquired.getDataType() == desiredType) {
      return acquired;
    }

    if (desiredType == DataBlk.typeFloat && acquired is DataBlkInt) {
      return _convertIntToFloat(block, acquired, component);
    }

    if (desiredType == DataBlk.typeInt && acquired is DataBlkFloat) {
      return _convertFloatToInt(block, acquired, component);
    }

    throw ArgumentError(
      'Unsupported conversion: source=${acquired.getDataType()} target=$desiredType',
    );
  }

  DataBlk _convertIntToFloat(
    DataBlk target,
    DataBlkInt source,
    int component,
  ) {
    final intData = source.getDataInt();
    if (intData == null) {
      throw StateError('Integer block payload missing');
    }

    final floatBlock = target is DataBlkFloat ? target : DataBlkFloat();
    final width = source.w;
    final height = source.h;

    floatBlock
      ..ulx = source.ulx
      ..uly = source.uly
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = source.progressive;

    final required = width * height;
    var floatData = floatBlock.getDataFloat();
    if (floatData == null || floatData.length < required) {
      floatData = Float32List(required);
      floatBlock.setDataFloat(floatData);
    }

    final shift = _source.getFixedPoint(component);
    _fixedPoint = shift;
    final scale = shift == 0 ? 1.0 : 1.0 / (1 << shift);

    var srcIndex = source.offset;
    var dstIndex = 0;
    for (var row = 0; row < height; row++) {
      final rowEnd = dstIndex + width;
      while (dstIndex < rowEnd) {
        floatData[dstIndex++] = intData[srcIndex++] * scale;
      }
      srcIndex += source.scanw - width;
    }

    if (DecoderInstrumentation.isEnabled() && _intToFloatLogs < _maxLogsPerDirection) {
      _intToFloatLogs++;
      _logIntToFloatStats(
        component: component,
        width: width,
        height: height,
        shift: shift,
        scale: scale,
        intData: intData,
        intOffset: source.offset,
        intScanw: source.scanw,
        floatData: floatData,
      );
    }

    return floatBlock;
  }

  DataBlk _convertFloatToInt(
    DataBlk target,
    DataBlkFloat source,
    int component,
  ) {
    final floatData = source.getDataFloat();
    if (floatData == null) {
      throw StateError('Float block payload missing');
    }

    final intBlock = target is DataBlkInt ? target : DataBlkInt();
    final width = source.w;
    final height = source.h;

    intBlock
      ..ulx = source.ulx
      ..uly = source.uly
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = source.progressive;

    final required = width * height;
    var intData = intBlock.getDataInt();
    if (intData == null || intData.length < required) {
      intData = Int32List(required);
      intBlock.setDataInt(intData);
    }

    final shift = _fixedPoint;
    final scale = shift == 0 ? 1.0 : (1 << shift).toDouble();

    var srcIndex = source.offset;
    var dstIndex = 0;
    for (var row = 0; row < height; row++) {
      final rowEnd = dstIndex + width;
      while (dstIndex < rowEnd) {
        final value = floatData[srcIndex++] * scale;
        if (value > 0.0) {
          intData[dstIndex++] = (value + 0.5).toInt();
        } else {
          intData[dstIndex++] = (value - 0.5).toInt();
        }
      }
      srcIndex += source.scanw - width;
    }

    if (DecoderInstrumentation.isEnabled() && _floatToIntLogs < _maxLogsPerDirection) {
      _floatToIntLogs++;
      _logFloatToIntStats(
        component: component,
        width: width,
        height: height,
        shift: shift,
        floatData: floatData,
        floatOffset: source.offset,
        floatScanw: source.scanw,
        intData: intData,
      );
    }

    return intBlock;
  }

  void _logIntToFloatStats({
    required int component,
    required int width,
    required int height,
    required int shift,
    required double scale,
    required Int32List intData,
    required int intOffset,
    required int intScanw,
    required Float32List floatData,
  }) {
    if (width == 0 || height == 0) {
      DecoderInstrumentation.log(
        'ImgDataConverter',
        '$_debugLabel int->float comp=$component empty block',
      );
      return;
    }
    final intSummary = _summarizeIntBlock(intData, intOffset, intScanw, width, height);
    final floatSummary = _summarizeFloatBlock(floatData, width, height);
    DecoderInstrumentation.log(
      'ImgDataConverter',
      '$_debugLabel int->float comp=$component shift=$shift scale=${scale.toStringAsFixed(6)} '
      'block=${width}x$height int[min=${intSummary.min}, max=${intSummary.max}, preview=${intSummary.preview}] '
      'float[min=${floatSummary.min.toStringAsFixed(4)}, max=${floatSummary.max.toStringAsFixed(4)}, '
      'preview=${floatSummary.preview}]',
    );
  }

  void _logFloatToIntStats({
    required int component,
    required int width,
    required int height,
    required int shift,
    required Float32List floatData,
    required int floatOffset,
    required int floatScanw,
    required Int32List intData,
  }) {
    if (width == 0 || height == 0) {
      DecoderInstrumentation.log(
        'ImgDataConverter',
        '$_debugLabel float->int comp=$component empty block',
      );
      return;
    }
    final floatSummary = _summarizeFloatBlock(floatData, width, height, offset: floatOffset, scanw: floatScanw);
    final intSummary = _summarizeIntBlock(intData, 0, width, width, height);
    DecoderInstrumentation.log(
      'ImgDataConverter',
      '$_debugLabel float->int comp=$component shift=$shift block=${width}x$height '
      'float[min=${floatSummary.min.toStringAsFixed(4)}, max=${floatSummary.max.toStringAsFixed(4)}, preview=${floatSummary.preview}] '
      'int[min=${intSummary.min}, max=${intSummary.max}, preview=${intSummary.preview}]',
    );
  }

  _BlockSummary<int> _summarizeIntBlock(
    Int32List data,
    int offset,
    int scanw,
    int width,
    int height,
  ) {
    var minVal = data[offset];
    var maxVal = data[offset];
    var idx = offset;
    final previewCount = math.min(width, 8);
    final preview = <String>[];
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final sample = data[idx + col];
        if (sample < minVal) {
          minVal = sample;
        }
        if (sample > maxVal) {
          maxVal = sample;
        }
        if (row == 0 && col < previewCount) {
          preview.add(sample.toString());
        }
      }
      idx += scanw;
    }
    return _BlockSummary<int>(minVal, maxVal, preview);
  }

  _BlockSummary<double> _summarizeFloatBlock(
    Float32List data,
    int width,
    int height, {
    int offset = 0,
    int? scanw,
  }) {
    final effectiveScanw = scanw ?? width;
    var idx = offset;
    var minVal = data[idx].toDouble();
    var maxVal = minVal;
    final previewCount = math.min(width, 8);
    final preview = <String>[];
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final sample = data[idx + col].toDouble();
        if (sample < minVal) {
          minVal = sample;
        }
        if (sample > maxVal) {
          maxVal = sample;
        }
        if (row == 0 && col < previewCount) {
          preview.add(sample.toStringAsFixed(4));
        }
      }
      idx += effectiveScanw;
    }
    return _BlockSummary<double>(minVal, maxVal, preview);
  }
}

class _BlockSummary<T extends num> {
  const _BlockSummary(this.min, this.max, this.preview);

  final T min;
  final T max;
  final List<String> preview;
}


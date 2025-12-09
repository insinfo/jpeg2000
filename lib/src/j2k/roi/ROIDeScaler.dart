import '../decoder/DecoderSpecs.dart';
import '../image/BlkImgDataSrc.dart';
import '../image/DataBlk.dart';
import '../image/DataBlkFloat.dart';
import '../image/DataBlkInt.dart';
import '../quantization/dequantizer/CBlkQuantDataSrcDec.dart';
import '../util/Int32Utils.dart';
import '../util/ParameterList.dart';
import '../wavelet/synthesis/MultiResImgDataAdapter.dart';
import '../wavelet/synthesis/SubbandSyn.dart';
import 'MaxShiftSpec.dart';
import 'RectRoiSpec.dart';
import 'RectangularRoi.dart';

/// Restores background coefficient magnitudes when ROI max-shift coding was used.
class ROIDeScaler extends MultiResImgDataAdapter
    implements CBlkQuantDataSrcDec {
  ROIDeScaler(
    this._source,
    this._roiSpec, {
    RectROISpec? rectSpec,
    BlkImgDataSrc? sampleSource,
  })  : _rectSpec = rectSpec,
        _sampleSource = sampleSource,
        super(_source);

  /// JJ2000 option prefix used to scope ROI-specific parameters.
  static const String optionPrefix = 'R';

  /// CLI parameter metadata for ROI handling.
  static const List<List<String>> parameterInfo = <List<String>>[
    <String>[
      'Rno_roi',
      '',
      'Disables ROI de-scaling regardless of codestream metadata.',
      '',
    ],
  ];

  final CBlkQuantDataSrcDec _source;
  final MaxShiftSpec? _roiSpec;
  final RectROISpec? _rectSpec;
  final BlkImgDataSrc? _sampleSource;

  BlkImgDataSrc? get _imgSource =>
      _sampleSource ??
      (_source is BlkImgDataSrc ? _source as BlkImgDataSrc : null);

  @override
  int getCbULX() => _source.getCbULX();

  @override
  int getCbULY() => _source.getCbULY();

  @override
  DataBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) {
    return getInternCodeBlock(
      component,
      verticalCodeBlockIndex,
      horizontalCodeBlockIndex,
      subband,
      block,
    );
  }

  @override
  DataBlk getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) {
    final result = _source.getInternCodeBlock(
      component,
      verticalCodeBlockIndex,
      horizontalCodeBlockIndex,
      subband,
      block,
    );

    final spec = _roiSpec;
    if (spec == null) {
      return result;
    }

    final shift = spec.shiftFor(getTileIdx(), component);
    if (shift <= 0) {
      return result;
    }

    final roi =
        _rectSpec?.roiFor(getTileIdx(), component) ?? _rectSpec?.defaultROI;

    if (result is DataBlkInt) {
      _applyDescaleInt(result, subband, shift, roi);
    } else if (result is DataBlkFloat) {
      _applyDescaleFloat(result, shift, roi);
    }
    return result;
  }

  int getFixedPoint(int component) {
    final src = _imgSource;
    if (src == null) {
      throw StateError('Underlying source does not expose sample data access');
    }
    return src.getFixedPoint(component);
  }

  DataBlk getCompData(DataBlk block, int component) {
    final src = _imgSource;
    if (src == null) {
      throw StateError('Underlying source does not expose sample data access');
    }
    final result = src.getCompData(block, component);
    _applyComponentScaling(result, component);
    return result;
  }

  DataBlk getInternCompData(DataBlk block, int component) {
    final src = _imgSource;
    if (src == null) {
      throw StateError('Underlying source does not expose sample data access');
    }
    final result = src.getInternCompData(block, component);
    _applyComponentScaling(result, component);
    return result;
  }

  void _applyDescaleInt(
    DataBlkInt block,
    SubbandSyn subband,
    int shift,
    RectangularROI? roi,
  ) {
    final data = block.getDataInt();
    if (data == null) {
      throw StateError('ROI de-scaler received a block without payload');
    }

    final magBits = subband.magBits;
    if (magBits <= 0 || magBits > 31) {
      return;
    }

    final roiMask = Int32Utils.mask32(((1 << magBits) - 1) << (31 - magBits));
    final overflowMask =
      Int32Utils.mask32(Int32Utils.invert32(roiMask) & 0x7fffffff);
    final baseX = block.ulx;
    final baseY = block.uly;
    final divisor = 1 << shift;

    final stride = block.scanw;
    var index = block.offset;

    for (var row = 0; row < block.h; row++) {
      var rowIndex = index;
      final y = baseY + row;
      for (var col = 0; col < block.w; col++, rowIndex++) {
        final value = data[rowIndex];
        final isSpatialRoi = roi != null && roi.contains(baseX + col, y);
        if (!isSpatialRoi && (value & roiMask) == 0) {
          final sign = value & 0x80000000;
          final magnitude = (value & 0x7fffffff) ~/ divisor;
          final scaled = sign | (magnitude & 0x7fffffff);
          data[rowIndex] = Int32Utils.asInt32(scaled);
        } else if (overflowMask != 0 && (value & overflowMask) != 0) {
          final cleared = value & Int32Utils.invert32(overflowMask);
          final midpoint = 1 << (30 - magBits);
          final adjusted = Int32Utils.mask32(cleared | midpoint);
          data[rowIndex] = Int32Utils.asInt32(adjusted);
        }
      }
      index += stride;
    }
  }

  void _applyDescaleFloat(
    DataBlkFloat block,
    int shift,
    RectangularROI? roi,
  ) {
    final data = block.getDataFloat();
    if (data == null) {
      throw StateError('ROI de-scaler received a float block without payload');
    }

    final divisor = 1 << shift;
    if (divisor <= 1) {
      return;
    }

    final baseX = block.ulx;
    final baseY = block.uly;
    final stride = block.scanw;
    var index = block.offset;

    for (var row = 0; row < block.h; row++) {
      var rowIndex = index;
      final y = baseY + row;
      for (var col = 0; col < block.w; col++, rowIndex++) {
        final isSpatialRoi = roi != null && roi.contains(baseX + col, y);
        if (!isSpatialRoi) {
          data[rowIndex] = data[rowIndex] / divisor;
        }
      }
      index += stride;
    }
  }

  void _applyComponentScaling(DataBlk block, int component) {
    final spec = _roiSpec;
    if (spec == null) {
      return;
    }

    final shift = spec.shiftFor(getTileIdx(), component);
    if (shift <= 0) {
      return;
    }

    final roi =
        _rectSpec?.roiFor(getTileIdx(), component) ?? _rectSpec?.defaultROI;
    if (roi == null) {
      return;
    }

    if (block is DataBlkInt) {
      _applyComponentInt(block, shift, roi);
    } else if (block is DataBlkFloat) {
      _applyComponentFloat(block, shift, roi);
    }
  }

  void _applyComponentInt(DataBlkInt block, int shift, RectangularROI roi) {
    final data = block.getDataInt();
    if (data == null) {
      throw StateError('ROI de-scaler received a block without payload');
    }

    final divisor = 1 << shift;
    if (divisor <= 1) {
      return;
    }

    final baseX = block.ulx;
    final baseY = block.uly;
    final stride = block.scanw;
    var index = block.offset;

    for (var row = 0; row < block.h; row++) {
      var rowIndex = index;
      final y = baseY + row;
      for (var col = 0; col < block.w; col++, rowIndex++) {
        if (!roi.contains(baseX + col, y)) {
          data[rowIndex] = data[rowIndex] ~/ divisor;
        }
      }
      index += stride;
    }
  }

  void _applyComponentFloat(DataBlkFloat block, int shift, RectangularROI roi) {
    final data = block.getDataFloat();
    if (data == null) {
      throw StateError('ROI de-scaler received a float block without payload');
    }

    final divisor = 1 << shift;
    if (divisor <= 1) {
      return;
    }

    final baseX = block.ulx;
    final baseY = block.uly;
    final stride = block.scanw;
    var index = block.offset;

    for (var row = 0; row < block.h; row++) {
      var rowIndex = index;
      final y = baseY + row;
      for (var col = 0; col < block.w; col++, rowIndex++) {
        if (!roi.contains(baseX + col, y)) {
          data[rowIndex] = data[rowIndex] / divisor;
        }
      }
      index += stride;
    }
  }

  static ROIDeScaler createInstance(
    CBlkQuantDataSrcDec source,
    ParameterList parameters,
    DecoderSpecs specs,
  ) {
    parameters.checkListSingle(
      optionPrefix.codeUnitAt(0),
      ParameterList.toNameArray(parameterInfo),
    );

    final disable = parameters.getParameter('Rno_roi') != null;
    final spec = disable ? null : specs.rois;
    final rectSpec = disable ? null : specs.rectRois;
    return ROIDeScaler(source, spec, rectSpec: rectSpec);
  }
}



import 'dart:typed_data';

import '../../util/DecoderInstrumentation.dart';
import '../BlkImgDataSrc.dart';
import '../CompTransfSpec.dart';
import '../DataBlk.dart';
import '../DataBlkFloat.dart';
import '../DataBlkInt.dart';
import '../ImgDataAdapter.dart';
import 'InvCompTransf.dart';

/// Applies inverse component transforms (ICT/RCT) to reconstructed samples.
class InvCompTransfImgDataSrc extends ImgDataAdapter implements BlkImgDataSrc {
  static const String _logSource = 'InvCompTransf';
  InvCompTransfImgDataSrc(
    BlkImgDataSrc source,
    this.compTransfSpec, {
    bool enableComponentTransforms = true,
  })  : _source = source,
        _componentTransformEnabled = enableComponentTransforms,
        super(source);

  static final List<int> _componentDebugCountdown = <int>[5, 5, 5];

  final BlkImgDataSrc _source;
  final CompTransfSpec compTransfSpec;
  final bool _componentTransformEnabled;

  final List<DataBlkInt?> _intScratch = List<DataBlkInt?>.filled(3, null);
  final List<DataBlkFloat?> _floatScratch = List<DataBlkFloat?>.filled(3, null);

  static const double _ictRedCrFactor = 1.402;
  static const double _ictGreenCbFactor = 0.344136;
  static const double _ictGreenCrFactor = 0.714136;
  static const double _ictBlueCbFactor = 1.7720907830451322;
  static const double _ictBlueCrFactor = 0.00006723594218332702;

  int get _numComponents => _source.getNumComps();

  @override
  int getFixedPoint(int component) => _source.getFixedPoint(component);

  @override
  DataBlk getInternCompData(DataBlk block, int component) {
    final result = _maybeTransform(block, component, true);
    return result;
  }

  @override
  DataBlk getCompData(DataBlk block, int component) {
    final result = _maybeTransform(block, component, false);
    if (!identical(result, block)) {
      block
        ..ulx = result.ulx
        ..uly = result.uly
        ..w = result.w
        ..h = result.h
        ..offset = result.offset
        ..scanw = result.scanw
        ..progressive = result.progressive
        ..setData(result.getData());
      return block;
    }
    return result;
  }

  DataBlk _maybeTransform(DataBlk block, int component, bool intern) {
    if (!_componentTransformEnabled) {
      return intern
          ? _source.getInternCompData(block, component)
          : _source.getCompData(block, component);
    }
    final tileIdx = getTileIdx();
    final transform = compTransfSpec.getSpec(tileIdx, component) ?? InvCompTransf.none;
    if (_componentDebugCountdown[component] > 0) {
      _componentDebugCountdown[component]--;
      _log('InvCompTransf: tile=$tileIdx component=$component transform=$transform');
    }
    if (transform == InvCompTransf.none ||
        _numComponents < 3 ||
        component >= 3) {
      return intern
          ? _source.getInternCompData(block, component)
          : _source.getCompData(block, component);
    }

    switch (transform) {
      case InvCompTransf.invRct:
        return _applyRCT(block, component, intern);
      case InvCompTransf.invIct:
        return _applyICT(block, component, intern);
      default:
        throw StateError('Unsupported inverse component transform: $transform');
    }
  }

  DataBlk _applyRCT(DataBlk block, int component, bool intern) {
    final DataBlkInt target = block is DataBlkInt ? block : DataBlkInt();
    if (!identical(target, block)) {
      target
        ..ulx = block.ulx
        ..uly = block.uly
        ..w = block.w
        ..h = block.h
        ..progressive = block.progressive;
    }
    final DataBlkInt y =
        _fetchIntBlock(component: 0, template: target, intern: intern);
    final DataBlkInt cb =
        _fetchIntBlock(component: 1, template: target, intern: intern);
    final DataBlkInt cr =
        _fetchIntBlock(component: 2, template: target, intern: intern);

    final int width = y.w;
    final int height = y.h;
    target
      ..ulx = y.ulx
      ..uly = y.uly
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = y.progressive;

    final required = width * height;
    final existing = target.getDataInt();
    late final List<int> buffer;
    if (existing == null || existing.length < required) {
      final newData = Int32List(required);
      target.setDataInt(newData);
      buffer = newData;
    } else {
      buffer = existing;
    }

    final yData = y.getDataInt();
    final cbData = cb.getDataInt();
    final crData = cr.getDataInt();
    if (yData == null || cbData == null || crData == null) {
      throw StateError('RCT requires integer data in all coefficient blocks');
    }

    final bool isR = component == 0;
    final bool isG = component == 1;

    var yIndex = y.offset;
    var cbIndex = cb.offset;
    var crIndex = cr.offset;
    var destIndex = 0;

    for (var row = 0; row < height; row++) {
      final yRowEnd = yIndex + width;
      var yPos = yIndex;
      var cbPos = cbIndex;
      var crPos = crIndex;
      while (yPos < yRowEnd) {
        final int yVal = yData[yPos];
        final int cbVal = cbData[cbPos];
        final int crVal = crData[crPos];

        final int g = yVal - ((cbVal + crVal) >> 2);
        // For the reversible transform the chroma components are defined
        // relative to green, so rebuild red/blue from the recovered green.
        final int r = g + crVal;
        final int b = g + cbVal;

        if (_componentDebugCountdown[component] > 0) {
          if (_componentDebugCountdown[component] == 5) {
            _log(
              'RCT geometry c=$component y.off=${y.offset} y.scan=${y.scanw} '
              'cb.off=${cb.offset} cb.scan=${cb.scanw} cr.off=${cr.offset} cr.scan=${cr.scanw}',
            );
          }
          _componentDebugCountdown[component]--;
          _log('RCT debug c=$component y=$yVal cb=$cbVal cr=$crVal -> r=$r g=$g b=$b');
        }

        buffer[destIndex++] = isR ? r : (isG ? g : b);

        yPos++;
        cbPos++;
        crPos++;
      }
      yIndex += y.scanw;
      cbIndex += cb.scanw;
      crIndex += cr.scanw;
    }

    return target;
  }

  DataBlk _applyICT(DataBlk block, int component, bool intern) {
    final DataBlkFloat target = block is DataBlkFloat ? block : DataBlkFloat();
    if (!identical(target, block)) {
      target
        ..ulx = block.ulx
        ..uly = block.uly
        ..w = block.w
        ..h = block.h
        ..progressive = block.progressive;
    }
    final DataBlkFloat y =
        _fetchFloatBlock(component: 0, template: target, intern: intern);
    final DataBlkFloat cb =
        _fetchFloatBlock(component: 1, template: target, intern: intern);
    final DataBlkFloat cr =
        _fetchFloatBlock(component: 2, template: target, intern: intern);

    final int width = y.w;
    final int height = y.h;
    target
      ..ulx = y.ulx
      ..uly = y.uly
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = y.progressive;

    final required = width * height;
    final existing = target.getDataFloat();
    late final Float32List buffer;
    if (existing == null || existing.length < required) {
      final newData = Float32List(required);
      target.setDataFloat(newData);
      buffer = newData;
    } else {
      buffer = existing;
    }

    final yData = y.getDataFloat();
    final cbData = cb.getDataFloat();
    final crData = cr.getDataFloat();
    if (yData == null || cbData == null || crData == null) {
      throw StateError(
          'ICT requires floating-point data in all coefficient blocks');
    }

    final bool isR = component == 0;
    final bool isG = component == 1;

    var yIndex = y.offset;
    var cbIndex = cb.offset;
    var crIndex = cr.offset;
    var destIndex = 0;

    for (var row = 0; row < height; row++) {
      final yRowEnd = yIndex + width;
      var yPos = yIndex;
      var cbPos = cbIndex;
      var crPos = crIndex;
      while (yPos < yRowEnd) {
        final double yVal = yData[yPos];
        final double cbVal = cbData[cbPos];
        final double crVal = crData[crPos];

        final double r = yVal + _ictRedCrFactor * crVal;
        final double g =
          yVal - _ictGreenCbFactor * cbVal - _ictGreenCrFactor * crVal;
        final double b =
          yVal + _ictBlueCbFactor * cbVal + _ictBlueCrFactor * crVal;

        if (_componentDebugCountdown[component] > 0) {
          if (_componentDebugCountdown[component] == 5) {
            _log(
              'ICT geometry c=$component y.off=${y.offset} y.scan=${y.scanw} '
              'cb.off=${cb.offset} cb.scan=${cb.scanw} cr.off=${cr.offset} cr.scan=${cr.scanw}',
            );
          }
          _componentDebugCountdown[component]--;
          _log(
            'ICT debug c=$component y=${yVal.toStringAsFixed(3)} '
            'cb=${cbVal.toStringAsFixed(3)} cr=${crVal.toStringAsFixed(3)} '
            '-> r=${r.toStringAsFixed(3)} g=${g.toStringAsFixed(3)} b=${b.toStringAsFixed(3)}',
          );
        }

        buffer[destIndex++] = isR ? r : (isG ? g : b);

        yPos++;
        cbPos++;
        crPos++;
      }
      yIndex += y.scanw;
      cbIndex += cb.scanw;
      crIndex += cr.scanw;
    }

    return target;
  }

  DataBlkInt _fetchIntBlock({
    required int component,
    required DataBlkInt template,
    required bool intern,
  }) {
    final cache = _intScratch[component] ?? DataBlkInt();
    cache
      ..ulx = template.ulx
      ..uly = template.uly
      ..w = template.w
      ..h = template.h
      ..progressive = template.progressive;

    final DataBlk result = intern
        ? _source.getInternCompData(cache, component)
        : _source.getCompData(cache, component);
    if (result is! DataBlkInt) {
      throw StateError('Expected integer block for RCT component $component');
    }
    _intScratch[component] = result;
    return result;
  }

  DataBlkFloat _fetchFloatBlock({
    required int component,
    required DataBlkFloat template,
    required bool intern,
  }) {
    final cache = _floatScratch[component] ?? DataBlkFloat();
    cache
      ..ulx = template.ulx
      ..uly = template.uly
      ..w = template.w
      ..h = template.h
      ..progressive = template.progressive;

    final DataBlk result = intern
        ? _source.getInternCompData(cache, component)
        : _source.getCompData(cache, component);
    if (result is! DataBlkFloat) {
      throw StateError('Expected float block for ICT component $component');
    }
    _floatScratch[component] = result;
    return result;
  }

  static bool _isInstrumentationEnabled() => DecoderInstrumentation.isEnabled();

  void _log(String message) {
    if (_isInstrumentationEnabled()) {
      DecoderInstrumentation.log(_logSource, message);
    }
  }
}


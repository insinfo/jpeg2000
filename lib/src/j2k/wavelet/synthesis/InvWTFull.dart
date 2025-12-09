import 'dart:math' as math;
import 'dart:typed_data';

import '../../decoder/DecoderSpecs.dart';
import '../../image/DataBlk.dart';
import '../../image/DataBlkFloat.dart';
import '../../image/DataBlkInt.dart';
import '../../util/DecoderInstrumentation.dart';
import '../../util/FacilityManager.dart';
import '../../util/ProgressWatch.dart';
import '../WaveletTransform.dart';
import 'CBlkWTDataSrcDec.dart';
import 'InverseWT.dart';
import 'SubbandSyn.dart';

/// Full-frame inverse wavelet transform mirroring JJ2000's `InvWTFull`.
class InvWTFull extends InverseWT {
  InvWTFull(this.src, DecoderSpecs decSpec)
      : reconstructedComps = List<DataBlk?>.filled(src.getNumComps(), null),
        ndl = List<int>.filled(src.getNumComps(), 0),
        reversible =
            List<List<bool>?>.filled(src.getNumTilesTotal(), null, growable: false),
        super(src, decSpec) {
    pw = FacilityManager.getProgressWatch();
  }

  final CBlkWTDataSrcDec src;
  final List<DataBlk?> reconstructedComps;
  final List<int> ndl;
  final List<List<bool>?> reversible;
  ProgressWatch? pw;
  int cblkToDecode = 0;
  int nDecCblk = 0;
  int dtype = DataBlk.typeInt;
  static const int _maxReconstructionLogs = 4;
  int _reconstructionLogCount = 0;
  static const int _subbandLogLimit = 2;
  final Map<String, int> _subbandLogCounts = <String, int>{};

  bool _isSubbandReversible(SubbandSyn subband) {
    if (subband.isNode) {
      final ll = subband.getLL() as SubbandSyn;
      final hl = subband.getHL() as SubbandSyn;
      final lh = subband.getLH() as SubbandSyn;
      final hh = subband.getHH() as SubbandSyn;
      final hFilter = subband.hFilter;
      final vFilter = subband.vFilter;
      if (hFilter == null || vFilter == null) {
        return false;
      }
      return _isSubbandReversible(ll) &&
          _isSubbandReversible(hl) &&
          _isSubbandReversible(lh) &&
          _isSubbandReversible(hh) &&
          hFilter.isReversible() &&
          vFilter.isReversible();
    }
    return true;
  }

  @override
  bool isReversible(int tile, int component) {
    final cached = reversible[tile];
    if (cached != null) {
      return cached[component];
    }
    final compStates = List<bool>.filled(getNumComps(), false);
    for (var i = compStates.length - 1; i >= 0; i--) {
        compStates[i] = _isSubbandReversible(src.getSynSubbandTree(tile, i));
    }
    reversible[tile] = compStates;
    return compStates[component];
  }

  @override
  int getNomRangeBits(int component) => src.getNomRangeBits(component);

  @override
  int getFixedPoint(int component) => src.getFixedPoint(component);

  @override
  DataBlk getInternCompData(DataBlk block, int component) {
    final tileIdx = getTileIdx();
    final root = src.getSynSubbandTree(tileIdx, component);
    final hFilter = root.hFilter;
    dtype = hFilter?.getDataType() ?? DataBlk.typeInt;

    if (reconstructedComps[component] == null) {
      final width = getTileCompWidth(tileIdx, component);
      final height = getTileCompHeight(tileIdx, component);
      switch (dtype) {
        case DataBlk.typeFloat:
            reconstructedComps[component] =
              DataBlkFloat.withGeometry(0, 0, width, height);
          break;
        default:
            reconstructedComps[component] =
              DataBlkInt.withGeometry(0, 0, width, height);
          break;
      }
      _waveletTreeReconstruction(
        reconstructedComps[component]!,
        root,
        component,
      );
      _logReconstructionPreview(tileIdx, component, reconstructedComps[component]!);
      if (pw != null && component == src.getNumComps() - 1) {
        pw!.terminateProgressWatch();
      }
    }

    DataBlk blk = block;
    if (blk.getDataType() != dtype) {
      blk = dtype == DataBlk.typeInt
          ? DataBlkInt.withGeometry(block.ulx, block.uly, block.w, block.h)
          : DataBlkFloat.withGeometry(block.ulx, block.uly, block.w, block.h);
    }

    final reconstructed = reconstructedComps[component]!;
    blk.setData(reconstructed.getData());
    blk.ulx = block.ulx;
    blk.uly = block.uly;
    blk.w = block.w;
    blk.h = block.h;
    blk.offset = reconstructed.w * blk.uly + blk.ulx;
    blk.scanw = reconstructed.w;
    blk.progressive = false;
    return blk;
  }

  @override
  DataBlk getCompData(DataBlk block, int component) {
    Object? dstData;
    switch (block.getDataType()) {
      case DataBlk.typeInt:
        var buffer = block.getData() as List<int>?;
        if (buffer == null || buffer.length < block.w * block.h) {
          buffer = Int32List(block.w * block.h);
        }
        dstData = buffer;
        break;
      case DataBlk.typeFloat:
        var buffer = block.getData() as Float32List?;
        if (buffer == null || buffer.length < block.w * block.h) {
          buffer = Float32List(block.w * block.h);
        }
        dstData = buffer;
        break;
      default:
        throw StateError('Unsupported data type ${block.getDataType()}');
    }

    final blk = getInternCompData(block, component);
    final srcData = blk.getData();
    if (srcData == null) {
      throw StateError('Wavelet reconstruction produced no data');
    }

    if (dstData is List<int> && srcData is List<int>) {
      for (var row = 0; row < blk.h; row++) {
        final dstPos = row * blk.w;
        final srcPos = blk.offset + row * blk.scanw;
        dstData.setRange(dstPos, dstPos + blk.w, srcData, srcPos);
      }
    } else if (dstData is Float32List && srcData is Float32List) {
      for (var row = 0; row < blk.h; row++) {
        final dstPos = row * blk.w;
        final srcPos = blk.offset + row * blk.scanw;
        dstData.setRange(dstPos, dstPos + blk.w, srcData, srcPos);
      }
    } else {
      for (var row = 0; row < blk.h; row++) {
        final dstPos = row * blk.w;
        final srcPos = blk.offset + row * blk.scanw;
        for (var col = 0; col < blk.w; col++) {
          final value = (srcData as List)[srcPos + col];
          (dstData as List)[dstPos + col] = value;
        }
      }
    }

    block
      ..ulx = blk.ulx
      ..uly = blk.uly
      ..w = blk.w
      ..h = blk.h
      ..offset = 0
      ..scanw = blk.w
      ..progressive = false
      ..setData(dstData);
    return block;
  }

  void _wavelet2DReconstruction(DataBlk buffer, SubbandSyn sb, int component) {
    final data = buffer.getData();
    if (data == null) {
      throw StateError('Missing destination buffer for reconstruction');
    }

    final ulx = sb.ulx;
    final uly = sb.uly;
    final width = sb.w;
    final height = sb.h;

    if (width == 0 || height == 0) {
      return;
    }

    final bufLength = math.max(width, height);
    Object? tmp;
    switch ((sb.hFilter ?? sb.vFilter)?.getDataType() ?? dtype) {
      case DataBlk.typeFloat:
        tmp = Float32List(bufLength);
        break;
      default:
        tmp = List<int>.filled(bufLength, 0, growable: false);
        break;
    }

    final rowStride = buffer.w;
    var offset = (uly - buffer.uly) * rowStride + (ulx - buffer.ulx);

    final hFilter = sb.hFilter;
    if (hFilter == null) {
      throw StateError('Horizontal synthesis filter not set');
    }
    final vFilter = sb.vFilter;
    if (vFilter == null) {
      throw StateError('Vertical synthesis filter not set');
    }

    // Horizontal reconstruction
    for (var row = 0; row < height; row++, offset += rowStride) {
      if (tmp is List<int> && data is List<int>) {
        tmp.setRange(0, width, data, offset);
      } else if (tmp is Float32List && data is Float32List) {
        tmp.setRange(0, width, data, offset);
      } else {
        for (var col = 0; col < width; col++) {
          (tmp as List)[col] = (data as List)[offset + col];
        }
      }

      if (sb.ulcx.isEven) {
        hFilter.synthetize_lpf(
          tmp,
          0,
          (width + 1) >> 1,
          1,
          tmp,
          (width + 1) >> 1,
          width >> 1,
          1,
          data,
          offset,
          1,
        );
      } else {
        hFilter.synthetize_hpf(
          tmp,
          0,
          width >> 1,
          1,
          tmp,
          width >> 1,
          (width + 1) >> 1,
          1,
          data,
          offset,
          1,
        );
      }
    }

    // Vertical reconstruction
    offset = (uly - buffer.uly) * rowStride + (ulx - buffer.ulx);
    if (data is List<int> && tmp is List<int>) {
      for (var col = 0; col < width; col++, offset++) {
        for (var row = height - 1, k = offset + row * rowStride;
            row >= 0;
            row--, k -= rowStride) {
          tmp[row] = data[k];
        }
        if (sb.ulcy.isEven) {
          vFilter.synthetize_lpf(
            tmp,
            0,
            (height + 1) >> 1,
            1,
            tmp,
            (height + 1) >> 1,
            height >> 1,
            1,
            data,
            offset,
            rowStride,
          );
        } else {
          vFilter.synthetize_hpf(
            tmp,
            0,
            height >> 1,
            1,
            tmp,
            height >> 1,
            (height + 1) >> 1,
            1,
            data,
            offset,
            rowStride,
          );
        }
      }
    } else if (data is Float32List && tmp is Float32List) {
      for (var col = 0; col < width; col++, offset++) {
        for (var row = height - 1, k = offset + row * rowStride;
            row >= 0;
            row--, k -= rowStride) {
          tmp[row] = data[k];
        }
        if (sb.ulcy.isEven) {
          vFilter.synthetize_lpf(
            tmp,
            0,
            (height + 1) >> 1,
            1,
            tmp,
            (height + 1) >> 1,
            height >> 1,
            1,
            data,
            offset,
            rowStride,
          );
        } else {
          vFilter.synthetize_hpf(
            tmp,
            0,
            height >> 1,
            1,
            tmp,
            height >> 1,
            (height + 1) >> 1,
            1,
            data,
            offset,
            rowStride,
          );
        }
      }
    } else {
      for (var col = 0; col < width; col++, offset++) {
        for (var row = height - 1, k = offset + row * rowStride;
            row >= 0;
            row--, k -= rowStride) {
          (tmp as List)[row] = (data as List)[k];
        }
        if (sb.ulcy.isEven) {
          vFilter.synthetize_lpf(
            tmp,
            0,
            (height + 1) >> 1,
            1,
            tmp,
            (height + 1) >> 1,
            height >> 1,
            1,
            data,
            offset,
            rowStride,
          );
        } else {
          vFilter.synthetize_hpf(
            tmp,
            0,
            height >> 1,
            1,
            tmp,
            height >> 1,
            (height + 1) >> 1,
            1,
            data,
            offset,
            rowStride,
          );
        }
      }
    }
  }

  void _waveletTreeReconstruction(DataBlk img, SubbandSyn sb, int component) {
    final tileIdx = src.getTileIdx();
    if (!sb.isNode) {
      if (sb.w == 0 || sb.h == 0) {
        return;
      }

      final subbData = dtype == DataBlk.typeInt ? DataBlkInt() : DataBlkFloat();
      final numBlocks = sb.numCb;
      if (numBlocks == null) {
        throw StateError('Subband code-block layout unavailable');
      }
      final dstData = img.getData();
      if (dstData == null) {
        throw StateError('Destination buffer not allocated');
      }

      for (var m = 0; m < numBlocks.y; m++) {
        for (var n = 0; n < numBlocks.x; n++) {
          final block =
              src.getInternCodeBlock(component, m, n, sb, subbData) ?? subbData;
          final srcData = block.getData();
          if (srcData == null) {
            continue;
          }
          if (pw != null) {
            nDecCblk++;
            pw!.updateProgressWatch(nDecCblk, '');
          }
          _logSubbandBlock(tileIdx, component, sb, block);
          for (var row = block.h - 1; row >= 0; row--) {
            final dstPos = (block.uly + row) * img.w + block.ulx;
            final srcPos = block.offset + row * block.scanw;
            if (dstData is List<int> && srcData is List<int>) {
              dstData.setRange(dstPos, dstPos + block.w, srcData, srcPos);
            } else if (dstData is Float32List && srcData is Float32List) {
              dstData.setRange(dstPos, dstPos + block.w, srcData, srcPos);
            } else {
              for (var col = 0; col < block.w; col++) {
                (dstData as List)[dstPos + col] =
                    (srcData as List)[srcPos + col];
              }
            }
          }
        }
      }
      return;
    }

    final ll = sb.getLL() as SubbandSyn;
    _waveletTreeReconstruction(img, ll, component);

    final threshold = resLevel - maxImgRes + ndl[component];
    if (sb.resLvl <= threshold) {
      _waveletTreeReconstruction(img, sb.getHL() as SubbandSyn, component);
      _waveletTreeReconstruction(img, sb.getLH() as SubbandSyn, component);
      _waveletTreeReconstruction(img, sb.getHH() as SubbandSyn, component);
      _wavelet2DReconstruction(img, sb, component);
    }
  }

  @override
  int getImplementationType(int component) => WaveletTransform.wtImplFull;

  @override
  void setTile(int x, int y) {
    super.setTile(x, y);
    final nc = src.getNumComps();
    final tileIdx = src.getTileIdx();
    for (var c = 0; c < nc; c++) {
      ndl[c] = src.getSynSubbandTree(tileIdx, c).resLvl;
    }
    for (var i = 0; i < reconstructedComps.length; i++) {
      reconstructedComps[i] = null;
    }

    cblkToDecode = 0;
    final thresholdBase = resLevel - maxImgRes;
    for (var c = 0; c < nc; c++) {
      final root = src.getSynSubbandTree(tileIdx, c);
      for (var r = 0; r <= thresholdBase + root.resLvl; r++) {
        if (r == 0) {
          final sb = root.getSubbandByIdx(0, 0) as SubbandSyn?;
          if (sb != null && sb.numCb != null) {
            cblkToDecode += sb.numCb!.x * sb.numCb!.y;
          }
        } else {
          for (var sib = 1; sib <= 3; sib++) {
            final sb = root.getSubbandByIdx(r, sib) as SubbandSyn?;
            if (sb != null && sb.numCb != null) {
              cblkToDecode += sb.numCb!.x * sb.numCb!.y;
            }
          }
        }
      }
    }
    nDecCblk = 0;
    pw?.initProgressWatch(0, cblkToDecode, 'Decoding tile $tileIdx...');
  }

  @override
  void setImgResLevel(int resLevel) {
    if (resLevel == this.resLevel) {
      return;
    }
    super.setImgResLevel(resLevel);
    for (var i = 0; i < reconstructedComps.length; i++) {
      reconstructedComps[i] = null;
    }
  }

  @override
  void nextTile() {
    super.nextTile();
    final nc = src.getNumComps();
    final tileIdx = src.getTileIdx();
    for (var c = 0; c < nc; c++) {
      ndl[c] = src.getSynSubbandTree(tileIdx, c).resLvl;
    }
    for (var i = 0; i < reconstructedComps.length; i++) {
      reconstructedComps[i] = null;
    }
  }

  void _logReconstructionPreview(int tileIdx, int component, DataBlk block) {
    if (!DecoderInstrumentation.isEnabled() || _reconstructionLogCount >= _maxReconstructionLogs) {
      return;
    }
    _reconstructionLogCount++;
    final width = block.w;
    final height = block.h;
    if (width == 0 || height == 0) {
      DecoderInstrumentation.log(
        'InvWTFull',
        'tile=$tileIdx comp=$component reconstruction empty block',
      );
      return;
    }

    final data = block.getData();
    if (data == null) {
      DecoderInstrumentation.log(
        'InvWTFull',
        'tile=$tileIdx comp=$component reconstruction missing buffer',
      );
      return;
    }

    final summary = data is Float32List
        ? _summarizeFloatBlock(data, width, height, block.offset, block.scanw)
        : _summarizeIntBlock(data as List<int>, width, height, block.offset, block.scanw);

    DecoderInstrumentation.log(
      'InvWTFull',
      'tile=$tileIdx comp=$component reconstruction dtype=${block.getDataType()} '
      'block=${width}x$height min=${summary.minLabel} max=${summary.maxLabel} preview=${summary.preview}',
    );
  }

  _ReconstructionSummary _summarizeIntBlock(
    List<int> data,
    int width,
    int height,
    int offset,
    int scanw,
  ) {
    var minVal = data[offset];
    var maxVal = data[offset];
    final previewCount = math.min(width, 8);
    final preview = <String>[];
    var rowOffset = offset;
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final sample = data[rowOffset + col];
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
      rowOffset += scanw;
    }
    return _ReconstructionSummary(
      minVal.toString(),
      maxVal.toString(),
      '[${preview.join(', ')}]',
    );
  }

  _ReconstructionSummary _summarizeFloatBlock(
    Float32List data,
    int width,
    int height,
    int offset,
    int scanw,
  ) {
    var minVal = data[offset];
    var maxVal = data[offset];
    final previewCount = math.min(width, 8);
    final preview = <String>[];
    var rowOffset = offset;
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final sample = data[rowOffset + col];
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
      rowOffset += scanw;
    }
    return _ReconstructionSummary(
      minVal.toStringAsFixed(6),
      maxVal.toStringAsFixed(6),
      '[${preview.join(', ')}]',
    );
  }

  void _logSubbandBlock(
    int tileIdx,
    int component,
    SubbandSyn subband,
    DataBlk block,
  ) {
    if (!DecoderInstrumentation.isEnabled()) {
      return;
    }
    final key = 't${tileIdx}c${component}r${subband.resLvl}b${subband.sbandIdx}';
    final count = _subbandLogCounts[key] ?? 0;
    if (count >= _subbandLogLimit) {
      return;
    }
    final data = block.getData();
    if (data == null || block.w == 0 || block.h == 0) {
      return;
    }
    _subbandLogCounts[key] = count + 1;
    final summary = data is Float32List
        ? _summarizeFloatBlock(data, block.w, block.h, block.offset, block.scanw)
        : _summarizeIntBlock(data as List<int>, block.w, block.h, block.offset, block.scanw);
    DecoderInstrumentation.log(
      'InvWTFull',
      'subband tile=$tileIdx comp=$component res=${subband.resLvl} band=${subband.sbandIdx} '
      'dtype=${block.getDataType()} block=${block.w}x${block.h} min=${summary.minLabel} '
      'max=${summary.maxLabel} preview=${summary.preview}',
    );
  }
}

class _ReconstructionSummary {
  const _ReconstructionSummary(this.minLabel, this.maxLabel, this.preview);

  final String minLabel;
  final String maxLabel;
  final String preview;
}



import 'dart:math' as math;
import 'dart:typed_data';

import '../../decoder/decoder_specs.dart';
import '../../image/data_blk.dart';
import '../../image/data_blk_float.dart';
import '../../image/data_blk_int.dart';
import '../../util/decoder_instrumentation.dart';
import '../../util/facility_manager.dart';
import '../../util/progress_watch.dart';
import '../wavelet_transform.dart';
import 'c_blk_wt_data_src_dec.dart';
import 'inverse_wt.dart';
import 'syn_wt_filter_float_lift9x7.dart';
import 'subband_syn.dart';
import 'syn_wt_filter.dart';

/// Full-frame inverse wavelet transform mirroring JJ2000's `InvWTFull`.
class InvWTFull extends InverseWT {
  InvWTFull(this.src, DecoderSpecs decSpec)
      : reconstructedComps = List<DataBlk?>.filled(src.getNumComps(), null),
        ndl = List<int>.filled(src.getNumComps(), 0),
        reversible = List<List<bool>?>.filled(src.getNumTilesTotal(), null,
            growable: false),
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
          // The row stride is rounded up to four samples so that the SIMD
          // passes of the wavelet and of the component transform read
          // whole aligned vectors on every row. The block's `w` is the
          // stride; callers read `scanw` and their own width.
          reconstructedComps[component] =
              DataBlkFloat.withGeometry(0, 0, (width + 3) & ~3, height);
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
      _logReconstructionPreview(
          tileIdx, component, reconstructedComps[component]!);
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
        var buffer = block.getData() as Int32List?;
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
    // Two column buffers: the vertical pass reads a column into [tmp],
    // filters it into [tmpOut] with unit stride, and copies the result back.
    // Writing the filter output straight into the image with a stride of one
    // row (tens of kilobytes on a large image) touched a new cache line and
    // often a new page per sample; the copy is the same strided traffic the
    // read already pays, and the arithmetic runs on contiguous memory.
    Object? tmp;
    Object? tmpOut;
    switch ((sb.hFilter ?? sb.vFilter)?.getDataType() ?? dtype) {
      case DataBlk.typeFloat:
        tmp = Float32List(bufLength);
        tmpOut = Float32List(bufLength);
        break;
      default:
        tmp = Int32List(bufLength);
        tmpOut = Int32List(bufLength);
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
    var simdRowsDone = false;
    if (hFilter is SynWTFilterFloatLift9x7 &&
        data is Float32List &&
        width >= 8) {
      // Whole rows on SIMD lanes; see synthetizeLpfRow4.
      final scratch = SynRow97Scratch(width);
      final lowFirstRow = sb.ulcx.isEven;
      final lowLen = lowFirstRow ? (width + 1) >> 1 : width >> 1;
      final highLen = width - lowLen;
      for (var row = 0; row < height; row++, offset += rowStride) {
        scratch.low.setRange(0, lowLen, data, offset);
        scratch.high.setRange(0, highLen, data, offset + lowLen);
        if (lowFirstRow) {
          hFilter.synthetizeLpfRow4(scratch, lowLen, highLen);
        } else {
          hFilter.synthetizeHpfRow4(scratch, lowLen, highLen);
        }
        data.setRange(offset, offset + width, scratch.out);
      }
      offset -= height * rowStride;
      simdRowsDone = true;
    }
    for (var row = 0; row < height; row++, offset += rowStride) {
      if (simdRowsDone) {
        break;
      }
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
        hFilter.synthetizeLpf(
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
        hFilter.synthetizeHpf(
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
    final bool lowFirst = sb.ulcy.isEven;
    if (data is Int32List && tmp is Int32List && tmpOut is Int32List) {
      for (var col = 0; col < width; col++, offset++) {
        for (var row = height - 1, k = offset + row * rowStride;
            row >= 0;
            row--, k -= rowStride) {
          tmp[row] = data[k];
        }
        if (lowFirst) {
          vFilter.synthetizeLpf(
            tmp,
            0,
            (height + 1) >> 1,
            1,
            tmp,
            (height + 1) >> 1,
            height >> 1,
            1,
            tmpOut,
            0,
            1,
          );
        } else {
          vFilter.synthetizeHpf(
            tmp,
            0,
            height >> 1,
            1,
            tmp,
            height >> 1,
            (height + 1) >> 1,
            1,
            tmpOut,
            0,
            1,
          );
        }
        for (var row = height - 1, k = offset + row * rowStride;
            row >= 0;
            row--, k -= rowStride) {
          data[k] = tmpOut[row];
        }
      }
    } else if (data is Float32List &&
        tmp is Float32List &&
        tmpOut is Float32List) {
      var col = 0;
      if (vFilter is SynWTFilterFloatLift9x7 && width >= 4 && height > 1) {
        // Four columns per pass on SIMD lanes; see synthetizeLpfFloat4.
        // Four column groups (sixteen columns, one cache line per row)
        // per pass, laid out group-major in the scratch buffers; each row
        // of the image is then touched once instead of four times.
        final Float32x4List tmp4 = Float32x4List(4 * height);
        final Float32x4List tmpOut4 = Float32x4List(4 * height);
        final int lowLen = (height + 1) >> 1;
        final int highLen = height >> 1;
        // With a row stride that is a multiple of four, the column groups
        // starting at an aligned offset can be read as whole vectors, which
        // is much cheaper than packing four scalar loads.
        final bool aligned = rowStride & 3 == 0 && data.offsetInBytes & 15 == 0;
        final Float32x4List data4 = aligned
            ? data.buffer.asFloat32x4List(data.offsetInBytes, data.length >> 2)
            : Float32x4List(0);
        if (aligned) {
          // Scalar columns up to the first aligned one.
          for (; col < width && offset & 3 != 0; col++, offset++) {
            _verticalColumn(data, tmp, tmpOut, offset, height, rowStride,
                vFilter, lowFirst);
          }
        }
        if (aligned) {
          for (; col + 16 <= width; col += 16, offset += 16) {
            for (var row = 0, k = offset >> 2, s4 = rowStride >> 2;
                row < height;
                row++, k += s4) {
              tmp4[row] = data4[k];
              tmp4[height + row] = data4[k + 1];
              tmp4[2 * height + row] = data4[k + 2];
              tmp4[3 * height + row] = data4[k + 3];
            }
            for (var g = 0, base = 0; g < 4; g++, base += height) {
              if (lowFirst) {
                vFilter.synthetizeLpfFloat4(tmp4, base, lowLen, tmp4,
                    base + lowLen, highLen, tmpOut4, base);
              } else {
                vFilter.synthetizeHpfFloat4(tmp4, base, highLen, tmp4,
                    base + highLen, lowLen, tmpOut4, base);
              }
            }
            for (var row = 0, k = offset >> 2, s4 = rowStride >> 2;
                row < height;
                row++, k += s4) {
              data4[k] = tmpOut4[row];
              data4[k + 1] = tmpOut4[height + row];
              data4[k + 2] = tmpOut4[2 * height + row];
              data4[k + 3] = tmpOut4[3 * height + row];
            }
          }
        }
        for (; col + 4 <= width; col += 4, offset += 4) {
          if (aligned) {
            for (var row = 0, k = offset >> 2, s4 = rowStride >> 2;
                row < height;
                row++, k += s4) {
              tmp4[row] = data4[k];
            }
          } else {
            for (var row = 0, k = offset; row < height; row++, k += rowStride) {
              tmp4[row] =
                  Float32x4(data[k], data[k + 1], data[k + 2], data[k + 3]);
            }
          }
          if (lowFirst) {
            vFilter.synthetizeLpfFloat4(
                tmp4, 0, lowLen, tmp4, lowLen, highLen, tmpOut4, 0);
          } else {
            vFilter.synthetizeHpfFloat4(
                tmp4, 0, highLen, tmp4, highLen, lowLen, tmpOut4, 0);
          }
          if (aligned) {
            for (var row = 0, k = offset >> 2, s4 = rowStride >> 2;
                row < height;
                row++, k += s4) {
              data4[k] = tmpOut4[row];
            }
          } else {
            for (var row = 0, k = offset; row < height; row++, k += rowStride) {
              final Float32x4 v = tmpOut4[row];
              data[k] = v.x;
              data[k + 1] = v.y;
              data[k + 2] = v.z;
              data[k + 3] = v.w;
            }
          }
        }
      }
      for (; col < width; col++, offset++) {
        for (var row = height - 1, k = offset + row * rowStride;
            row >= 0;
            row--, k -= rowStride) {
          tmp[row] = data[k];
        }
        if (lowFirst) {
          vFilter.synthetizeLpf(
            tmp,
            0,
            (height + 1) >> 1,
            1,
            tmp,
            (height + 1) >> 1,
            height >> 1,
            1,
            tmpOut,
            0,
            1,
          );
        } else {
          vFilter.synthetizeHpf(
            tmp,
            0,
            height >> 1,
            1,
            tmp,
            height >> 1,
            (height + 1) >> 1,
            1,
            tmpOut,
            0,
            1,
          );
        }
        for (var row = height - 1, k = offset + row * rowStride;
            row >= 0;
            row--, k -= rowStride) {
          data[k] = tmpOut[row];
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
          vFilter.synthetizeLpf(
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
          vFilter.synthetizeHpf(
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

  /// One column of the float vertical pass through [tmp]/[tmpOut].
  static void _verticalColumn(
      Float32List data,
      Float32List tmp,
      Float32List tmpOut,
      int offset,
      int height,
      int rowStride,
      SynWTFilter vFilter,
      bool lowFirst) {
    for (var row = height - 1, k = offset + row * rowStride;
        row >= 0;
        row--, k -= rowStride) {
      tmp[row] = data[k];
    }
    if (lowFirst) {
      vFilter.synthetizeLpf(tmp, 0, (height + 1) >> 1, 1, tmp,
          (height + 1) >> 1, height >> 1, 1, tmpOut, 0, 1);
    } else {
      vFilter.synthetizeHpf(tmp, 0, height >> 1, 1, tmp, height >> 1,
          (height + 1) >> 1, 1, tmpOut, 0, 1);
    }
    for (var row = height - 1, k = offset + row * rowStride;
        row >= 0;
        row--, k -= rowStride) {
      data[k] = tmpOut[row];
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
    if (!DecoderInstrumentation.isEnabled() ||
        _reconstructionLogCount >= _maxReconstructionLogs) {
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
        : _summarizeIntBlock(
            data as List<int>, width, height, block.offset, block.scanw);

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
    final key =
        't${tileIdx}c${component}r${subband.resLvl}b${subband.sbandIdx}';
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
        ? _summarizeFloatBlock(
            data, block.w, block.h, block.offset, block.scanw)
        : _summarizeIntBlock(
            data as List<int>, block.w, block.h, block.offset, block.scanw);
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

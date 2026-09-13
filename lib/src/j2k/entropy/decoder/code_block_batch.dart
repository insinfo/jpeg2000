/// Self-contained EBCOT work units.
///
/// Entropy decoding is where most of a JPEG 2000 decode goes — measured at 88%
/// of a 768x512 photograph and 93% of a noisy 256x256 image — and every
/// code-block is independent: it carries its own MQ-coder state, its own
/// context set and its own bit planes. That makes the code-block the natural
/// unit of parallel work for the single-tile images that dominate scanned PDF.
///
/// A unit has to be closed to cross an isolate: compressed bytes and
/// parameters in, coefficients out, with nothing shared. The types here are
/// exactly that, and [decodeCodeBlockBatch] runs a batch of them through the
/// ordinary [StdEntropyDecoder] rather than a second implementation, so the
/// coefficients are the ones the sequential decoder would have produced.
library;

import 'dart:typed_data';

import '../../decoder/decoder_specs.dart';
import '../../image/coord.dart';
import '../../image/data_blk.dart';
import '../../image/data_blk_int.dart';
import '../../wavelet/synthesis/subband_syn.dart';
import 'coded_c_blk_data_src_dec.dart';
import 'dec_lyrd_c_blk.dart';
import 'std_entropy_decoder.dart';

/// One code-block to decode, with everything the decoder reads about it.
///
/// The subband is reduced to the three fields [StdEntropyDecoder] actually
/// consults — orientation picks the zero-coding context table, the other two
/// only label diagnostics — because the real subband is a node of a tree whose
/// parents and children would all be copied along with it.
class CodeBlockTask {
  const CodeBlockTask({
    required this.tileIndex,
    required this.component,
    required this.resolutionLevel,
    required this.subbandIndex,
    required this.orientation,
    required this.verticalIndex,
    required this.horizontalIndex,
    required this.block,
  });

  final int tileIndex;
  final int component;
  final int resolutionLevel;
  final int subbandIndex;
  final int orientation;

  /// Row of the code-block inside its subband.
  final int verticalIndex;

  /// Column of the code-block inside its subband.
  final int horizontalIndex;

  /// The coded code-block as the bitstream reader produced it.
  final DecLyrdCBlk block;
}

/// A batch of [CodeBlockTask]s plus the decoder configuration they share.
///
/// [specs] travels with the batch instead of being rebuilt from the
/// codestream: [StdEntropyDecoder] reads only the maximum code-block size and
/// the per-tile-component coding options from it, and copying the object is
/// far cheaper than parsing the main header again on every worker.
class CodeBlockBatch {
  const CodeBlockBatch({
    required this.specs,
    required this.doErrorDetection,
    required this.verboseErrors,
    required this.mQuit,
    required this.tasks,
  });

  final DecoderSpecs specs;
  final bool doErrorDetection;
  final bool verboseErrors;
  final int mQuit;
  final List<CodeBlockTask> tasks;
}

/// The coefficients of one decoded code-block, ready to be sent back.
class CodeBlockResult {
  const CodeBlockResult({
    required this.ulx,
    required this.uly,
    required this.width,
    required this.height,
    required this.progressive,
    required this.data,
  });

  final int ulx;
  final int uly;
  final int width;
  final int height;
  final bool progressive;

  /// `width * height` coefficients, row-major, no padding.
  final Int32List data;

  /// Copies these coefficients into [block], or into a fresh block.
  ///
  /// The consumer of a code-block reads it through `offset` and `scanw`, so a
  /// tight buffer is described by `offset == 0` and `scanw == width`.
  DataBlkInt toDataBlk(DataBlk? block) {
    final target = block is DataBlkInt ? block : DataBlkInt();
    target
      ..ulx = ulx
      ..uly = uly
      ..w = width
      ..h = height
      ..offset = 0
      ..scanw = width
      ..progressive = progressive;
    final required = width * height;
    var buffer = target.data;
    if (buffer == null || buffer.length < required) {
      buffer = Int32List(required);
      target.data = buffer;
    }
    buffer.setRange(0, required, data);
    return target;
  }
}

/// Decodes every task in [batch], in order, and returns their coefficients.
///
/// Runs on a worker isolate. One [StdEntropyDecoder] serves the whole batch,
/// exactly as one serves a whole tile in the sequential decode: it resets its
/// context state, its MQ decoder and its significance-state array at the start
/// of every code-block, so decoding a subset of the blocks — or the same
/// blocks in a different grouping — cannot change the result.
List<CodeBlockResult> decodeCodeBlockBatch(CodeBlockBatch batch) {
  final source = _BatchCodedSource(batch.tasks.length);
  final decoder = StdEntropyDecoder(
    source,
    batch.specs,
    batch.doErrorDetection,
    batch.verboseErrors,
    batch.mQuit,
  );

  final subband = SubbandSyn();
  final results = <CodeBlockResult>[];
  for (final task in batch.tasks) {
    source.current = task.block;
    source.tileIndex = task.tileIndex;
    subband
      ..resLvl = task.resolutionLevel
      ..sbandIdx = task.subbandIndex
      ..orientation = task.orientation;

    // A null destination makes the decoder allocate a buffer of exactly
    // `w * h`, so the result needs no compaction before it is sent back.
    final decoded = decoder.getCodeBlock(
      task.component,
      task.verticalIndex,
      task.horizontalIndex,
      subband,
      null,
    ) as DataBlkInt;
    final data = decoded.getDataInt();
    if (data == null) {
      throw StateError('Entropy decoder returned a code-block with no data');
    }
    results.add(
      CodeBlockResult(
        ulx: decoded.ulx,
        uly: decoded.uly,
        width: decoded.w,
        height: decoded.h,
        progressive: decoded.progressive,
        data: data,
      ),
    );
  }
  return results;
}

/// Feeds one already-extracted code-block to [StdEntropyDecoder].
///
/// The entropy decoder pulls its input through [CodedCBlkDataSrcDec], which
/// on the normal path is the bitstream reader. A worker has no bitstream: the
/// coded blocks were extracted on the calling isolate and travelled with the
/// batch, so this source simply hands back the block currently being decoded.
/// Everything else on the interface belongs to the pipeline stages that do not
/// exist here, and asking for it is a bug rather than a case to handle.
class _BatchCodedSource implements CodedCBlkDataSrcDec {
  _BatchCodedSource(this.numComps);

  final int numComps;

  /// The block the decoder is about to ask for.
  DecLyrdCBlk? current;

  /// Reported through [getTileIdx], which the decoder uses to look up the
  /// coding options of the tile the block belongs to.
  int tileIndex = 0;

  @override
  DecLyrdCBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    int firstLayer,
    int numLayers,
    DecLyrdCBlk? block,
  ) {
    final coded = current;
    if (coded == null) {
      throw StateError('No coded code-block was staged for this task');
    }
    return coded;
  }

  @override
  int getTileIdx() => tileIndex;

  @override
  int getNumComps() => numComps;

  Never _unsupported(String member) => throw UnsupportedError(
        'A code-block worker has no pipeline: $member is not available.',
      );

  @override
  SubbandSyn getSynSubbandTree(int tile, int component) =>
      _unsupported('getSynSubbandTree');

  @override
  int getCbULX() => _unsupported('getCbULX');

  @override
  int getCbULY() => _unsupported('getCbULY');

  @override
  int getResULX(int component, int resolution) => _unsupported('getResULX');

  @override
  int getResULY(int component, int resolution) => _unsupported('getResULY');

  @override
  int getTileCompWidth(int tile, int component, int resolution) =>
      _unsupported('getTileCompWidth');

  @override
  int getTileCompHeight(int tile, int component, int resolution) =>
      _unsupported('getTileCompHeight');

  @override
  int getCompImgWidth(int component, int resolution) =>
      _unsupported('getCompImgWidth');

  @override
  int getCompImgHeight(int component, int resolution) =>
      _unsupported('getCompImgHeight');

  @override
  int getImgWidth(int resolution) => _unsupported('getImgWidth');

  @override
  int getImgHeight(int resolution) => _unsupported('getImgHeight');

  @override
  int getImgULX(int resolution) => _unsupported('getImgULX');

  @override
  int getImgULY(int resolution) => _unsupported('getImgULY');

  @override
  int getNomTileWidth() => _unsupported('getNomTileWidth');

  @override
  int getNomTileHeight() => _unsupported('getNomTileHeight');

  @override
  int getCompSubsX(int component) => _unsupported('getCompSubsX');

  @override
  int getCompSubsY(int component) => _unsupported('getCompSubsY');

  @override
  int getTilePartULX() => _unsupported('getTilePartULX');

  @override
  int getTilePartULY() => _unsupported('getTilePartULY');

  @override
  int getNomRangeBits(int component) => _unsupported('getNomRangeBits');

  @override
  int getTileWidth(int resolution) => _unsupported('getTileWidth');

  @override
  int getTileHeight(int resolution) => _unsupported('getTileHeight');

  @override
  void setTile(int x, int y) => _unsupported('setTile');

  @override
  void nextTile() => _unsupported('nextTile');

  @override
  Coord getTile(Coord? reuse) => _unsupported('getTile');

  @override
  Coord getNumTiles(Coord? reuse) => _unsupported('getNumTiles');

  @override
  int getNumTilesTotal() => _unsupported('getNumTilesTotal');
}

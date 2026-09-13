/// An entropy decoder that is filled in advance instead of on demand.
///
/// The pipeline pulls code-blocks lazily: the inverse wavelet asks the
/// dequantizer, which asks the entropy decoder, one code-block at a time and
/// strictly in order. That is fine for a single thread and useless for
/// several, because nothing can be started before it is asked for.
///
/// This decoder inverts the order. [harvestTile] walks the subband trees of a
/// tile and pulls every coded code-block out of the bitstream up front — that
/// is packet parsing only, no arithmetic decoding — and hands back a list of
/// independent work units. Once those units have been decoded, wherever that
/// happened, [installResults] files the coefficients and the pipeline pulls
/// them out of the cache at the usual moment, unaware that anything changed.
library;

import '../../decoder/decoder_specs.dart';
import '../../platform/parallel/parallel.dart';
import '../../image/data_blk.dart';
import '../../image/data_blk_int.dart';
import '../../wavelet/synthesis/subband_syn.dart';
import 'code_block_batch.dart';

// The orchestration below hands these types to its caller, so the caller
// needs only this one import to drive a parallel prefetch.
export 'code_block_batch.dart'
    show CodeBlockBatch, CodeBlockResult, CodeBlockTask;
import 'entropy_decoder.dart';

/// Identifies one subband of one component of one tile.
///
/// The subband index alone is not enough. `Subband.split` gives a child the
/// index `(parent << 2) + k`, and the root index is zero, so the leaves of
/// every resolution level of a dyadic decomposition are numbered 1, 2 and 3
/// all over again. The bitstream reader keys its own code-block table by
/// component, resolution and subband for exactly this reason.
typedef _SubbandKey = (int tile, int component, int resolution, int subband);

/// Decoded code-blocks of one subband, addressed by their grid position.
class _SubbandCache {
  _SubbandCache(this.codeBlocksAcross, int count)
      : blocks = List<CodeBlockResult?>.filled(count, null);

  final int codeBlocksAcross;
  final List<CodeBlockResult?> blocks;
}

/// Serves code-blocks that were decoded ahead of time.
class PrefetchedEntropyDecoder extends EntropyDecoder {
  /// Wraps the bitstream reader that yields coded code-blocks.
  ///
  /// [specs], [doErrorDetection], [verboseErrors] and [mQuit] are the same
  /// values the ordinary entropy decoder would have been built with; they are
  /// carried along so the workers can build a decoder that behaves identically.
  PrefetchedEntropyDecoder(
    super.src, {
    required this.specs,
    required this.doErrorDetection,
    required this.verboseErrors,
    required this.mQuit,
  });

  final DecoderSpecs specs;
  final bool doErrorDetection;
  final bool verboseErrors;
  final int mQuit;

  final Map<_SubbandKey, _SubbandCache> _cache = <_SubbandKey, _SubbandCache>{};

  int get _numComps => src.getNumComps();

  /// Pulls every coded code-block of the current tile out of the bitstream.
  ///
  /// The caller must have set the tile on this decoder first; [tileIndex] is
  /// the index that tile reports. Only packet headers and payload bytes are
  /// touched here, so this pass costs a small fraction of a decode — the
  /// arithmetic decoding, which is the expensive part, happens on whoever
  /// processes the returned units.
  List<CodeBlockTask> harvestTile(int tileIndex) {
    final tasks = <CodeBlockTask>[];
    final components = _numComps;
    for (var component = 0; component < components; component++) {
      final root = src.getSynSubbandTree(tileIndex, component);
      _harvestSubband(root, tileIndex, component, tasks);
    }
    return tasks;
  }

  void _harvestSubband(
    SubbandSyn subband,
    int tileIndex,
    int component,
    List<CodeBlockTask> tasks,
  ) {
    if (subband.isNode) {
      final ll = subband.subbLL;
      final hl = subband.subbHL;
      final lh = subband.subbLH;
      final hh = subband.subbHH;
      if (ll != null) {
        _harvestSubband(ll, tileIndex, component, tasks);
      }
      if (hl != null) {
        _harvestSubband(hl, tileIndex, component, tasks);
      }
      if (lh != null) {
        _harvestSubband(lh, tileIndex, component, tasks);
      }
      if (hh != null) {
        _harvestSubband(hh, tileIndex, component, tasks);
      }
      return;
    }

    // An empty subband is never asked for by the inverse wavelet, and asking
    // the bitstream reader for a code-block it has no entry for would fail.
    if (subband.w == 0 || subband.h == 0) {
      return;
    }
    final grid = subband.numCb;
    if (grid == null) {
      throw StateError(
        'Subband ${subband.sbandIdx} of component $component has no '
        'code-block layout.',
      );
    }

    final cache = _SubbandCache(grid.x, grid.x * grid.y);
    _cache[(tileIndex, component, subband.resLvl, subband.sbandIdx)] = cache;
    for (var m = 0; m < grid.y; m++) {
      for (var n = 0; n < grid.x; n++) {
        // A fresh destination every time: the units are independent, and a
        // reused block would leave them all sharing one payload buffer.
        final coded = src.getCodeBlock(component, m, n, subband, 1, -1, null);
        tasks.add(
          CodeBlockTask(
            tileIndex: tileIndex,
            component: component,
            resolutionLevel: subband.resLvl,
            subbandIndex: subband.sbandIdx,
            orientation: subband.orientation,
            verticalIndex: m,
            horizontalIndex: n,
            block: coded,
          ),
        );
      }
    }
  }

  /// Files the coefficients of [tasks], which must be in the same order.
  void installResults(
    List<CodeBlockTask> tasks,
    List<CodeBlockResult> results,
  ) {
    if (tasks.length != results.length) {
      throw StateError(
        'Got ${results.length} decoded code-blocks for ${tasks.length} '
        'work units.',
      );
    }
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final cache = _cache[(
        task.tileIndex,
        task.component,
        task.resolutionLevel,
        task.subbandIndex,
      )];
      if (cache == null) {
        throw StateError(
          'No cache slot for code-block (${task.verticalIndex}, '
          '${task.horizontalIndex}) of subband ${task.subbandIndex} at '
          'resolution ${task.resolutionLevel}.',
        );
      }
      cache.blocks[task.verticalIndex * cache.codeBlocksAcross +
          task.horizontalIndex] = results[i];
    }
  }

  /// Number of code-blocks currently held. Used by tests and by the decision
  /// of whether the prefetch was worth its cost.
  int get cachedCodeBlockCount {
    var total = 0;
    for (final cache in _cache.values) {
      total += cache.blocks.length;
    }
    return total;
  }

  @override
  DataBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) =>
      getInternCodeBlock(
        component,
        verticalCodeBlockIndex,
        horizontalCodeBlockIndex,
        subband,
        block,
      );

  @override
  DataBlkInt getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) {
    final tileIndex = getTileIdx();
    final cache = _cache[(
      tileIndex,
      component,
      subband.resLvl,
      subband.sbandIdx,
    )];
    final result = cache?.blocks[
        verticalCodeBlockIndex * cache.codeBlocksAcross +
            horizontalCodeBlockIndex];
    if (result == null) {
      throw StateError(
        'Code-block ($verticalCodeBlockIndex, $horizontalCodeBlockIndex) of '
        'subband ${subband.sbandIdx} at resolution ${subband.resLvl}, '
        'component $component, tile $tileIndex was not prefetched.',
      );
    }
    return result.toDataBlk(block);
  }
}

/// Harvests every code-block of the tiles [tileXs] x [tileYs] and splits them
/// into one batch per worker.
///
/// The harvest — walking the subband trees and pulling the coded blocks out of
/// the packets — stays on the calling isolate, because it is a single ordered
/// pass over the bitstream and cannot be split. Only the arithmetic decoding
/// moves, and that is where measurement puts nearly nine tenths of the time.
///
/// The units go to the batches round-robin over the enumeration order, so each
/// worker gets a mix of the large low-frequency blocks and the small
/// high-frequency ones instead of one worker getting every expensive block.
List<List<CodeBlockTask>> planCodeBlockBatches(
  PrefetchedEntropyDecoder decoder, {
  required List<int> tileXs,
  required List<int> tileYs,
  required int workers,
}) {
  final tasks = <CodeBlockTask>[];
  for (var i = 0; i < tileXs.length; i++) {
    decoder.setTile(tileXs[i], tileYs[i]);
    tasks.addAll(decoder.harvestTile(decoder.getTileIdx()));
  }
  if (tasks.isEmpty) {
    return const <List<CodeBlockTask>>[];
  }

  var count = workers < tasks.length ? workers : tasks.length;
  if (count < 1) {
    count = 1;
  }
  final batches = List<List<CodeBlockTask>>.generate(
    count,
    (_) => <CodeBlockTask>[],
    growable: false,
  );
  for (var i = 0; i < tasks.length; i++) {
    batches[i % count].add(tasks[i]);
  }
  return batches;
}

/// Runs [batches] through the workers and returns their coefficients.
Future<List<List<CodeBlockResult>>> decodeCodeBlockBatches(
  PrefetchedEntropyDecoder decoder,
  List<List<CodeBlockTask>> batches, {
  required int concurrency,
}) {
  if (batches.isEmpty) {
    return Future<List<List<CodeBlockResult>>>.value(
      const <List<CodeBlockResult>>[],
    );
  }
  final jobs = <List<CodeBlockResult> Function()>[
    for (final batch in batches)
      _codeBlockJob(
        CodeBlockBatch(
          specs: decoder.specs,
          doErrorDetection: decoder.doErrorDetection,
          verboseErrors: decoder.verboseErrors,
          mQuit: decoder.mQuit,
          tasks: batch,
        ),
      ),
  ];
  return runParallelTasks(jobs, concurrency: concurrency);
}

/// Files the decoded coefficients so the pipeline can pull them.
void installCodeBlockBatches(
  PrefetchedEntropyDecoder decoder,
  List<List<CodeBlockTask>> batches,
  List<List<CodeBlockResult>> results,
) {
  if (batches.length != results.length) {
    throw StateError(
      'Got ${results.length} decoded batches for ${batches.length} planned.',
    );
  }
  for (var i = 0; i < batches.length; i++) {
    decoder.installResults(batches[i], results[i]);
  }
}

/// Builds the closure a worker runs.
///
/// Created by a top-level function taking only the sendable batch, so the
/// context the closure captures holds nothing that cannot cross to an isolate.
List<CodeBlockResult> Function() _codeBlockJob(CodeBlockBatch batch) =>
    () => decodeCodeBlockBatch(batch);

// Parallel decoding, split by tile.
//
// This is a `part` of `jpeg2000_codec.dart` on purpose: the sequential decode
// pipeline it drives (`_open`, `_buildDecodePipeline`, `_writePlane`, ...) is
// library-private, and the parallel path must reuse exactly that code so its
// output stays bit-identical to [decodeJpeg2000]. Duplicating the pipeline
// here would be a second implementation free to drift from the first.
//
// JPEG 2000 tiles are independent by construction: every tile carries its own
// packets, its own wavelet decomposition and its own EBCOT state, so a tile
// can be decoded on a worker that has never seen the other tiles. Each worker
// re-parses the (cheap) main header from its own copy of the codestream and
// then decodes only the tiles it was given.

part of 'jpeg2000_codec.dart';

/// How [decodeJpeg2000Parallel] spreads a decode over worker isolates.
///
/// The defaults are tuned so that a decode which cannot profit from workers
/// silently stays on the sequential path: sending a tile to an isolate costs a
/// copy of the codestream in and a copy of the decoded samples out, which is
/// more than a small tile costs to decode in the first place.
class Jpeg2000ParallelOptions {
  /// Creates parallel-decode options; every field has a safe default.
  const Jpeg2000ParallelOptions({
    this.concurrency,
    this.minParallelPixels = defaultMinParallelPixels,
    this.minTilesPerWorker = 1,
  });

  /// Options that never leave the sequential path, for A/B testing.
  static const Jpeg2000ParallelOptions sequential =
      Jpeg2000ParallelOptions(concurrency: 1);

  /// Smallest image, in samples, that is worth handing to workers.
  ///
  /// Starting the workers costs about a millisecond and a half that the
  /// sequential path does not pay, and below a certain size the decode does
  /// not last long enough to earn it back. Measured on eight cores over
  /// greyscale of two kinds, one that compresses well and one that barely
  /// does, sequential against parallel: 32x32 loses at 0.49x-0.53x, 64x64
  /// loses at 0.71x-0.97x, 128x128 breaks even at 0.98x-1.03x, 192x192 wins
  /// at 1.20x-1.64x and 256x256 wins at 1.16x-2.01x. This default is the
  /// first size that won in both kinds.
  ///
  /// The gain keeps growing with size, which is what matters for the scanned
  /// pages this exists for: a 768x512 photograph decodes 3.5x faster.
  static const int defaultMinParallelPixels = 36864;

  /// Maximum number of worker isolates. Null means the platform default,
  /// which is the processor count capped at eight.
  ///
  /// One disables parallelism: the decode runs on the calling isolate.
  final int? concurrency;

  /// Images smaller than this many samples are decoded sequentially.
  final int minParallelPixels;

  /// Fewest tiles a worker must receive for a whole-tile split to be worth it.
  final int minTilesPerWorker;

  /// Number of workers a [pixels]-sample image should use, or one to stay on
  /// the calling isolate.
  ///
  /// The tile count plays no part here: an image with a single tile is still
  /// split, by code-block, which is the case that matters for PDF.
  int workersFor({required int pixels}) {
    final requested = concurrency ?? availableProcessors;
    if (requested <= 1 || !supportsParallelExecution) {
      return 1;
    }
    if (pixels < minParallelPixels) {
      return 1;
    }
    return requested;
  }

  /// Number of workers for splitting [tileCount] tiles whole, or one when
  /// there are too few tiles for that split to keep [workers] of them busy.
  ///
  /// Returning less than [workers] is the signal to split by code-block
  /// instead: a whole-tile split that leaves workers idle is worse than a
  /// finer one that does not.
  int tileWorkersFor({required int tileCount, required int workers}) {
    if (tileCount < 2 || workers <= 1) {
      return 1;
    }
    final perWorker = minTilesPerWorker < 1 ? 1 : minTilesPerWorker;
    var count = workers < tileCount ? workers : tileCount;
    final byTiles = tileCount ~/ perWorker;
    if (byTiles < count) {
      count = byTiles;
    }
    return count < 1 ? 1 : count;
  }
}

/// Decodes JP2 or raw J2K [bytes] using worker isolates when that helps.
///
/// The result is bit-identical to [decodeJpeg2000] with the same [options]:
/// the workers run the very same pipeline, one tile at a time, and the
/// interleaving of the decoded samples into the output buffer still happens
/// here, in order. Only the tile decoding moves off this isolate.
///
/// Falls back to the synchronous path — with no isolate involved — when the
/// image has a single tile, when it is smaller than
/// [Jpeg2000ParallelOptions.minParallelPixels], or when the platform has no
/// isolates at all (`dart2js`, `dart2wasm`). Most JPEG 2000 images embedded in
/// PDF are single-tile, so that fallback is the common case rather than the
/// exception.
///
/// [decodeJpeg2000] stays synchronous and unchanged; this is a separate entry
/// point precisely so that no existing caller has to become asynchronous.
///
/// Warnings reported through [Jpeg2000DecodeOptions.onWarning] are collected
/// from every worker and replayed here, with exact duplicates removed: each
/// worker parses the same main header, so a header warning would otherwise be
/// reported once per worker.
Future<Jpeg2000Image> decodeJpeg2000Parallel(
  Uint8List bytes, {
  Jpeg2000DecodeOptions options = const Jpeg2000DecodeOptions(),
  Jpeg2000ParallelOptions parallel = const Jpeg2000ParallelOptions(),
}) async {
  _validateDecodeOptions(options);

  // The tile grid comes from the SIZ marker, so the decision to split costs
  // one short header read and never touches a packet.
  final grid = _guardDecode(options.onWarning, () {
    final input = ISRandomAccessIO(bytes);
    try {
      final opened = _open(input);
      _checkBudget(opened.siz, options);
      return opened.siz;
    } finally {
      input.close();
    }
  });

  final tileCount = grid.tileColumns * grid.tileRows;
  final workers = parallel.workersFor(pixels: grid.width * grid.height);
  if (workers <= 1) {
    return decodeJpeg2000(bytes, options: options);
  }

  // Two ways to split, and the tile count decides between them. With enough
  // tiles to keep every worker busy, sending whole tiles is better: a worker
  // then runs the entire pipeline for its tiles and only the finished samples
  // come back. With fewer — and a single tile is the usual case for the JPEG 2000 images
  // embedded in PDF — whole tiles would leave most workers idle, so the split
  // moves down to the code-block, the smallest independent unit EBCOT has.
  final tileWorkers =
      parallel.tileWorkersFor(tileCount: tileCount, workers: workers);
  if (tileWorkers < workers) {
    return _decodeByCodeBlocks(
      bytes,
      options: options,
      grid: grid,
      workers: workers,
    );
  }

  // Tiles go round-robin rather than in contiguous runs: a scanned page is
  // usually busy in the middle and empty at the edges, so contiguous runs
  // would leave one worker with every expensive tile.
  final batches = List<List<int>>.generate(
    tileWorkers,
    (_) => <int>[],
    growable: false,
  );
  for (var tile = 0; tile < tileCount; tile++) {
    batches[tile % tileWorkers].add(tile);
  }

  final request = _ParallelDecodeRequest.from(bytes, options);
  final tasks = <_TileBatchResult Function()>[
    for (final batch in batches) _tileBatchTask(request, batch),
  ];
  final batchResults = await runParallelTasks(tasks, concurrency: tileWorkers);

  final warnings = options.onWarning;
  if (warnings != null) {
    final seen = <String>{};
    for (final result in batchResults) {
      for (final message in result.warnings) {
        if (seen.add(message)) {
          warnings(message);
        }
      }
    }
  }

  final tiles = List<_DecodedTile?>.filled(tileCount, null);
  for (final result in batchResults) {
    for (final tile in result.tiles) {
      tiles[tile.tileIndex] = tile;
    }
  }

  return _guardDecode(options.onWarning, () {
    final input = ISRandomAccessIO(bytes);
    try {
      final metadata = _readOutputMetadata(input, options);
      return _assembleParallelImage(
        metadata,
        tiles,
        options.outputBitDepth,
      );
    } finally {
      input.close();
    }
  });
}

/// Builds the closure a worker runs.
///
/// It is created by a top-level function with sendable parameters only, so the
/// context the closure captures holds nothing that cannot cross to an isolate.
_TileBatchResult Function() _tileBatchTask(
  _ParallelDecodeRequest request,
  List<int> tiles,
) =>
    () => _decodeTileBatch(request, tiles);

/// Everything a worker needs to rebuild the decode pipeline.
///
/// [Jpeg2000DecodeOptions] itself cannot cross an isolate boundary: its
/// `onWarning` field is a closure over caller state. The primitive fields are
/// copied here and the options are rebuilt on the other side.
class _ParallelDecodeRequest {
  const _ParallelDecodeRequest({
    required this.bytes,
    required this.applyColorSpace,
    required this.applyComponentTransform,
    required this.rate,
    required this.decodeBytes,
    required this.resolution,
    required this.parsing,
    required this.outputBitDepth,
  });

  factory _ParallelDecodeRequest.from(
    Uint8List bytes,
    Jpeg2000DecodeOptions options,
  ) =>
      _ParallelDecodeRequest(
        bytes: bytes,
        applyColorSpace: options.applyColorSpace,
        applyComponentTransform: options.applyComponentTransform,
        rate: options.rate,
        decodeBytes: options.bytes,
        resolution: options.resolution,
        parsing: options.parsing,
        outputBitDepth: options.outputBitDepth,
      );

  final Uint8List bytes;
  final bool applyColorSpace;
  final bool applyComponentTransform;
  final double? rate;
  final int? decodeBytes;
  final int? resolution;
  final bool parsing;
  final int outputBitDepth;

  Jpeg2000DecodeOptions toOptions(void Function(String) onWarning) =>
      Jpeg2000DecodeOptions(
        applyColorSpace: applyColorSpace,
        applyComponentTransform: applyComponentTransform,
        rate: rate,
        bytes: decodeBytes,
        resolution: resolution,
        parsing: parsing,
        outputBitDepth: outputBitDepth,
        onWarning: onWarning,
      );
}

/// One tile's decoded samples, one plane per output channel.
///
/// The planes are compacted to `offset == 0` and `scanw == width` before they
/// are sent back, so the isolate copies exactly the samples the caller needs
/// and the receiving side can address them without extra bookkeeping.
class _DecodedTile {
  const _DecodedTile({
    required this.tileIndex,
    required this.width,
    required this.height,
    required this.planes,
    required this.offsetX,
    required this.offsetY,
    required this.fixedPoint,
  });

  final int tileIndex;
  final int width;
  final int height;
  final List<Int32List> planes;
  final List<int> offsetX;
  final List<int> offsetY;
  final List<int> fixedPoint;
}

/// What one worker sends back: its tiles plus anything it warned about.
class _TileBatchResult {
  const _TileBatchResult(this.tiles, this.warnings);

  final List<_DecodedTile> tiles;
  final List<String> warnings;
}

/// Output-buffer geometry, read once on the calling isolate.
class _OutputMetadata {
  const _OutputMetadata({
    required this.width,
    required this.height,
    required this.channels,
    required this.layout,
    required this.bitDepths,
    required this.signed,
  });

  final int width;
  final int height;
  final List<int> channels;
  final _ChannelLayout layout;
  final List<int> bitDepths;
  final List<bool> signed;
}

/// Decodes the tiles of one batch. Runs on a worker isolate.
_TileBatchResult _decodeTileBatch(
  _ParallelDecodeRequest request,
  List<int> tileIndices,
) {
  final warnings = <String>[];
  final options = request.toOptions(warnings.add);
  final params = _buildDecodeParameters(options);

  final tiles = _guardDecode(warnings.add, () {
    final input = ISRandomAccessIO(request.bytes);
    try {
      final source = _openDecodePipeline(input, options, params);
      return _decodeTiles(source.pipeline, source.colorSpace, tileIndices);
    } finally {
      input.close();
    }
  });

  return _TileBatchResult(tiles, warnings);
}

/// Parses the headers and builds the decode pipeline over [input].
///
/// This is the prologue [decodeJpeg2000] runs before it collects pixels; it
/// only reads the main header and the JP2 boxes, so it is cheap enough for
/// every worker to repeat.
({BlkImgDataSrc pipeline, ColorSpace? colorSpace}) _openDecodePipeline(
  ISRandomAccessIO input,
  Jpeg2000DecodeOptions options,
  ParameterList params,
) {
  final opened = _open(input);
  final headerInfo = HeaderInfo();
  input.seek(opened.codestreamStart);
  final headerDecoder = HeaderDecoder.readMainHeader(
    input: input,
    headerInfo: headerInfo,
  );
  final decoderSpecs = headerDecoder.decSpec;
  _scanTileParts(input, headerDecoder);

  ColorSpace? colorSpace;
  if (opened.isJp2) {
    colorSpace = _loadColorSpace(
      input,
      headerDecoder,
      params,
      required: options.applyColorSpace,
    );
  }

  final pipeline = _buildDecodePipeline(
    input: input,
    params: params,
    headerInfo: headerInfo,
    headerDecoder: headerDecoder,
    decoderSpecs: decoderSpecs,
    colorSpace: options.applyColorSpace ? colorSpace : null,
    applyComponentTransform: options.applyComponentTransform,
  );
  return (
    pipeline: pipeline,
    colorSpace: options.applyColorSpace ? colorSpace : null,
  );
}

/// Reads the output geometry without decoding a single packet.
///
/// Building the pipeline allocates the decoder chain but pulls no data: the
/// entropy decoding only starts at the first `getInternCompData` call.
_OutputMetadata _readOutputMetadata(
  ISRandomAccessIO input,
  Jpeg2000DecodeOptions options,
) {
  final params = _buildDecodeParameters(options);
  final opened = _open(input);
  final headerInfo = HeaderInfo();
  input.seek(opened.codestreamStart);
  final headerDecoder = HeaderDecoder.readMainHeader(
    input: input,
    headerInfo: headerInfo,
  );
  final decoderSpecs = headerDecoder.decSpec;
  _scanTileParts(input, headerDecoder);

  ColorSpace? colorSpace;
  if (opened.isJp2) {
    colorSpace = _loadColorSpace(
      input,
      headerDecoder,
      params,
      // The worker already reported a missing profile; asking again here
      // would only duplicate the warning.
      required: false,
    );
  }

  final pipeline = _buildDecodePipeline(
    input: input,
    params: params,
    headerInfo: headerInfo,
    headerDecoder: headerDecoder,
    decoderSpecs: decoderSpecs,
    colorSpace: options.applyColorSpace ? colorSpace : null,
    applyComponentTransform: options.applyComponentTransform,
  );

  final sourceComponents = pipeline.getNumComps();
  if (sourceComponents <= 0) {
    throw const Jpeg2000CorruptedException('Decoded image has no components.');
  }
  final layout = _channelLayout(
    sourceComponents,
    options.applyColorSpace ? colorSpace : null,
  );
  final channels = layout.channels;
  final width = pipeline.getImgWidth();
  final height = pipeline.getImgHeight();
  for (final component in channels) {
    if (pipeline.getCompImgWidth(component) != width ||
        pipeline.getCompImgHeight(component) != height) {
      throw Jpeg2000CorruptedException(
        'Component $component reports '
        '${pipeline.getCompImgWidth(component)}x'
        '${pipeline.getCompImgHeight(component)} samples after resampling but '
        'the image is ${width}x$height.',
      );
    }
  }

  return _OutputMetadata(
    width: width,
    height: height,
    channels: channels,
    layout: layout,
    bitDepths: List<int>.generate(
      channels.length,
      (i) => pipeline.getNomRangeBits(channels[i]),
      growable: false,
    ),
    signed: List<bool>.generate(
      channels.length,
      (i) => headerDecoder.isOriginalSigned(channels[i]),
      growable: false,
    ),
  );
}

/// Decodes the tiles named by [tileIndices] and compacts their samples.
///
/// Mirrors the per-tile body of [_collectImage], stopping one step earlier:
/// the samples are returned as planes instead of being interleaved, because
/// the interleaving happens once, on the calling isolate, for every tile.
List<_DecodedTile> _decodeTiles(
  BlkImgDataSrc source,
  ColorSpace? colorSpace,
  List<int> tileIndices,
) {
  final sourceComponents = source.getNumComps();
  if (sourceComponents <= 0) {
    throw const Jpeg2000CorruptedException('Decoded image has no components.');
  }
  final layout = _channelLayout(sourceComponents, colorSpace);
  final channels = layout.channels;
  final outputComponents = channels.length;
  final tilesAcross = source.getNumTilesCoord(null).x;

  // One reusable block per slot, as in [_collectImage]: sharing a single
  // block between slots would let one component overwrite the next.
  final blocks = List<DataBlkInt>.generate(
    outputComponents,
    (_) => DataBlkInt(),
    growable: false,
  );

  final decoded = <_DecodedTile>[];
  for (final tileIndex in tileIndices) {
    source.setTile(tileIndex % tilesAcross, tileIndex ~/ tilesAcross);
    final actualIndex = source.getTileIdx();
    final tileWidth = source.getTileCompWidth(actualIndex, channels[0]);
    final tileHeight = source.getTileCompHeight(actualIndex, channels[0]);

    final planes = List<Int32List>.filled(
      outputComponents,
      _emptyPlane,
      growable: false,
    );
    final offsetX = List<int>.filled(outputComponents, 0);
    final offsetY = List<int>.filled(outputComponents, 0);
    final fixedPoint = List<int>.filled(outputComponents, 0);

    for (var slot = 0; slot < outputComponents; slot++) {
      final component = channels[slot];
      final block = blocks[slot]
        ..ulx = 0
        ..uly = 0
        ..w = tileWidth
        ..h = tileHeight;
      DataBlkInt dataBlock;
      do {
        dataBlock = source.getInternCompData(block, component) as DataBlkInt;
      } while (dataBlock.progressive);
      final data = dataBlock.getDataInt();
      if (data == null) {
        throw const Jpeg2000CorruptedException(
          'Decoded component block has no data.',
        );
      }
      planes[slot] = _compactPlane(
        data,
        dataBlock.offset,
        dataBlock.scanw,
        tileWidth,
        tileHeight,
      );
      offsetX[slot] = source.getCompULX(component) -
          (source.getImgULX() / source.getCompSubsX(component)).ceil();
      offsetY[slot] = source.getCompULY(component) -
          (source.getImgULY() / source.getCompSubsY(component)).ceil();
      fixedPoint[slot] = source.getFixedPoint(component);
    }

    decoded.add(
      _DecodedTile(
        tileIndex: actualIndex,
        width: tileWidth,
        height: tileHeight,
        planes: planes,
        offsetX: offsetX,
        offsetY: offsetY,
        fixedPoint: fixedPoint,
      ),
    );
  }
  return decoded;
}

final Int32List _emptyPlane = Int32List(0);

/// Copies the [width] x [height] window of [data] into a tight plane.
///
/// The decoder hands back a buffer that may be wider than the tile and start
/// at an offset; only the window is worth copying across an isolate boundary,
/// and every value the consumer reads is preserved exactly.
///
/// The copy is unconditional, with no fast path for a buffer that already has
/// the right shape: the pipeline reuses one [DataBlkInt] per slot for every
/// tile, so handing that buffer back would give all the tiles of a worker the
/// samples of whichever tile it decoded last.
Int32List _compactPlane(
  Int32List data,
  int offset,
  int scanw,
  int width,
  int height,
) {
  final compact = Int32List(width * height);
  for (var row = 0; row < height; row++) {
    final sourceStart = offset + row * scanw;
    compact.setRange(
      row * width,
      row * width + width,
      data,
      sourceStart,
    );
  }
  return compact;
}

/// Interleaves the decoded tiles into the final image buffer.
///
/// Uses the very same writers as [_collectImage], so a sample that reached
/// this point through a worker lands on exactly the byte, and with exactly the
/// value, the sequential decode would have produced.
Jpeg2000Image _assembleParallelImage(
  _OutputMetadata metadata,
  List<_DecodedTile?> tiles,
  int outputBitDepth,
) {
  final width = metadata.width;
  final height = metadata.height;
  final outputComponents = metadata.channels.length;
  final bitDepths = metadata.bitDepths;
  final signed = metadata.signed;

  final sampleCount = width * height * outputComponents;
  final wide = outputBitDepth == 16;
  final Uint8List bytes;
  final Uint8List? pixels8;
  final Uint16List? pixels16;
  if (wide) {
    pixels16 = Uint16List(sampleCount);
    pixels8 = null;
    bytes = Uint8List.view(pixels16.buffer);
  } else {
    pixels8 = Uint8List(sampleCount);
    pixels16 = null;
    bytes = pixels8;
  }

  for (final tile in tiles) {
    if (tile == null) {
      throw const Jpeg2000CorruptedException(
        'A tile was not returned by any worker.',
      );
    }
    final offsetX = tile.offsetX;
    final offsetY = tile.offsetY;
    if (pixels8 != null &&
        outputComponents == 3 &&
        bitDepths.every((depth) => depth == outputBitDepth) &&
        offsetX.every((v) => v == offsetX[0]) &&
        offsetY.every((v) => v == offsetY[0])) {
      _writeRgb8Tile(
        pixels8,
        width,
        tile.width,
        tile.height,
        offsetX[0],
        offsetY[0],
        tile.planes[0],
        tile.planes[1],
        tile.planes[2],
        const <int>[0, 0, 0],
        <int>[tile.width, tile.width, tile.width],
        tile.fixedPoint,
        signed,
        outputBitDepth,
      );
      continue;
    }

    for (var slot = 0; slot < outputComponents; slot++) {
      _writePlane(
        pixels8,
        pixels16,
        tile.planes[slot],
        0,
        tile.width,
        tile.fixedPoint[slot],
        bitDepths[slot],
        signed[slot],
        outputBitDepth,
        width,
        tile.width,
        tile.height,
        offsetX[slot],
        offsetY[slot],
        outputComponents,
        slot,
      );
    }
  }

  final layout = metadata.layout;
  return Jpeg2000Image(
    width: width,
    height: height,
    components: outputComponents,
    colorComponents: layout.colorComponents,
    hasAlpha: layout.alpha != null,
    alphaIsPremultiplied: layout.alphaIsPremultiplied,
    sourceBitsPerComponent: List<int>.unmodifiable(bitDepths),
    bitsPerSample: outputBitDepth,
    pixels: bytes,
    format: layout.format,
  );
}

/// Decodes one image by spreading its code-blocks over the workers.
///
/// The pipeline is built here, on the calling isolate, with its entropy
/// decoder replaced by one that is filled in advance. Packet parsing, the
/// inverse wavelet, the component transform and the interleaving all stay
/// here and stay sequential; what moves to the workers is the arithmetic
/// decoding of the code-blocks, measured at 88% of a photograph decode and
/// 93% of a noisy one.
///
/// Because the pipeline and the assembly are the untouched sequential code,
/// and because each code-block is decoded by an ordinary [StdEntropyDecoder]
/// that resets its whole state at the start of every block, the samples are
/// the ones [decodeJpeg2000] would have produced.
Future<Jpeg2000Image> _decodeByCodeBlocks(
  Uint8List bytes, {
  required Jpeg2000DecodeOptions options,
  required _SizSummary grid,
  required int workers,
}) async {
  final params = _buildDecodeParameters(options);
  final input = ISRandomAccessIO(bytes);
  try {
    late PrefetchedEntropyDecoder prefetcher;
    final built = _guardDecode(options.onWarning, () {
      final opened = _open(input);
      final headerInfo = HeaderInfo();
      input.seek(opened.codestreamStart);
      final headerDecoder = HeaderDecoder.readMainHeader(
        input: input,
        headerInfo: headerInfo,
      );
      final decoderSpecs = headerDecoder.decSpec;
      _scanTileParts(input, headerDecoder);

      ColorSpace? colorSpace;
      if (opened.isJp2) {
        colorSpace = _loadColorSpace(
          input,
          headerDecoder,
          params,
          required: options.applyColorSpace,
        );
      }

      final pipeline = _buildDecodePipeline(
        input: input,
        params: params,
        headerInfo: headerInfo,
        headerDecoder: headerDecoder,
        decoderSpecs: decoderSpecs,
        colorSpace: options.applyColorSpace ? colorSpace : null,
        applyComponentTransform: options.applyComponentTransform,
        entropyDecoderFactory: (reader) {
          // The reference decoder is built and thrown away for its parsed
          // configuration: reading it back is how the workers are guaranteed
          // the same error-detection and truncation settings without parsing
          // the codestream options a second time.
          final reference = headerDecoder.createEntropyDecoder(
            reader,
            _subsetParametersByPrefix(params, EntropyDecoder.optionPrefix),
          );
          return prefetcher = PrefetchedEntropyDecoder(
            reader,
            specs: decoderSpecs,
            doErrorDetection: reference.errorDetectionEnabled,
            verboseErrors: reference.verboseErrorsEnabled,
            mQuit: reference.mqQuitPasses,
          );
        },
      );
      return (
        pipeline: pipeline,
        headerDecoder: headerDecoder,
        colorSpace: options.applyColorSpace ? colorSpace : null,
      );
    });

    final tileXs = <int>[];
    final tileYs = <int>[];
    for (var y = 0; y < grid.tileRows; y++) {
      for (var x = 0; x < grid.tileColumns; x++) {
        tileXs.add(x);
        tileYs.add(y);
      }
    }

    final batches = _guardDecode(
      options.onWarning,
      () => planCodeBlockBatches(
        prefetcher,
        tileXs: tileXs,
        tileYs: tileYs,
        workers: workers,
      ),
    );

    List<List<CodeBlockResult>> decoded;
    try {
      decoded = await decodeCodeBlockBatches(
        prefetcher,
        batches,
        concurrency: workers,
      );
    } catch (error, stackTrace) {
      // A failure inside a worker arrives here untranslated; send it back
      // through the same table the synchronous decoder uses so callers see
      // one exception hierarchy whichever path ran.
      _translateDecodeFailure(options.onWarning, error, stackTrace);
    }

    return _guardDecode(options.onWarning, () {
      installCodeBlockBatches(prefetcher, batches, decoded);
      return _collectImage(
        built.pipeline,
        built.headerDecoder,
        built.colorSpace,
        options.outputBitDepth,
      );
    });
  } finally {
    input.close();
  }
}

/// Rethrows [error] as the public exception it would have been on the
/// synchronous path.
Never _translateDecodeFailure(
  void Function(String)? onWarning,
  Object error,
  StackTrace stackTrace,
) {
  _guardDecode<Never>(
    onWarning,
    () => Error.throwWithStackTrace(error, stackTrace),
  );
}

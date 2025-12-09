part of 'BitstreamReaderAgent.dart';


typedef _CodeBlockGrid =
    List<List<List<List<List<CBlkInfo?>?>?>?>?>;

class _ProgressionSegment {
  const _ProgressionSegment({
    required this.progression,
    required this.layerEnd,
    required this.resStart,
    required this.resEnd,
    required this.compStart,
    required this.compEnd,
  });

  final int progression;
  final int layerEnd;
  final int resStart;
  final int resEnd;
  final int compStart;
  final int compEnd;
}

/// Stub port of JJ2000's [FileBitstreamReaderAgent].
///
/// The original implementation is responsible for parsing tile-part headers
/// from a JPEG 2000 codestream and exposing coded code-block data on demand.
/// Porting that logic is non-trivial; for now this class only wires the
/// constructor parameters and marks the pending work.
class FileBitstreamReaderAgent extends BitstreamReaderAgent {
  static final Map<int, int> _debugCblkPreviewCounts = <int, int>{};
  static const int _maxBudget = 0x7fffffff;

  late final bool _isParsingMode;
  late final bool _usePocQuit;
  late final bool _limitToSingleTilePart;
  late final int _ncbQuitTarget;

  FileBitstreamReaderAgent(
    HeaderDecoder header,
    RandomAccessIO input,
    DecoderSpecs decoderSpecs,
    ParameterList parameters,
    bool codestreamInfo,
    HeaderInfo headerInfo,
    {PktDecoder Function(FileBitstreamReaderAgent agent)? pktDecoderFactory}
  )   : _input = input,
        _parameters = parameters,
        _codestreamInfo = codestreamInfo,
        _headerInfo = headerInfo,
        super(header, decoderSpecs) {
    _initializeOptionState();
      _isTruncationMode = !_isParsingMode;
    _pktDecoder = pktDecoderFactory?.call(this) ??
        PktDecoder(decoderSpecs, header, input, this, _isTruncationMode, _ncbQuitTarget);
    
    // Parse all tile parts to populate offsets
    try {
      while (true) {
        header.parseNextTilePart(input);
      }
    } catch (e) {
      // Ignore errors indicating end of stream/EOC, rethrow others if critical
      // For now, assume loop terminates when EOC is hit or EOF
      if (e is StateError && e.message.contains('Reached end of codestream')) {
        // Normal termination
      } else if (e is EOFException) {
        // Normal termination
      } else {
        // print('FileBitstreamReaderAgent: Stopped parsing tile parts: $e');
      }
    }

    _prepareTileBudgets();
    _initialiseTargetResolution();
  }

  final RandomAccessIO _input;
  final ParameterList _parameters;
  final bool _codestreamInfo;
  final HeaderInfo _headerInfo;

  late final PktDecoder _pktDecoder;

  _CodeBlockGrid? cbI;
  int lQuit = -1;
  late final bool _isTruncationMode;
  late final List<int> _tileBudgets;
  late final List<int> _tileBudgetRemaining;
  late final List<int> _tileBytesConsumed;
  late final List<int> _tileBodyLengths;
  late final List<int> _tileHeaderLengths;
  late final List<int> _tileTotalLengths;
  late final List<List<int>> _tilePartBodyLengths;
  late final List<List<int>> _tilePartHeaderLengths;
  int _totalTileHeaderBytes = 0;

  void _initializeOptionState() {
    _isParsingMode = _readBooleanOption('parsing', defaultValue: true);

    var targetRate = _readDoubleOption('rate', defaultValue: -1.0);
    if (targetRate == -1) {
      targetRate = double.maxFinite;
    }
    var targetBytes = _readIntOption('nbytes', defaultValue: -1);
    final defaults = _parameters.getDefaultParameterList();
    final defaultNbytes = defaults?.getParameter('nbytes');
    final hasLocalNbytes = _parameters.containsKey('nbytes');
    final resolvedNbytes = _parameters.getParameter('nbytes') ?? defaultNbytes;
    final usesNbytes = hasLocalNbytes ||
        (resolvedNbytes != null && defaultNbytes != null && resolvedNbytes != defaultNbytes);

    if (usesNbytes && resolvedNbytes != null) {
      tnbytes = targetBytes <= 0 ? _maxBudget : targetBytes;
      trate = tnbytes * 8.0 / hd.getMaxCompImgWidth() / hd.getMaxCompImgHeight();
    } else {
      trate = targetRate;
      if (targetRate >= double.maxFinite / 2) {
        tnbytes = _maxBudget;
      } else {
        final computedBytes =
            targetRate * hd.getMaxCompImgWidth() * hd.getMaxCompImgHeight() / 8.0;
        tnbytes = computedBytes.isFinite
            ? math.max(0, computedBytes.floor())
            : _maxBudget;
      }
    }
    if (tnbytes <= 0) {
      tnbytes = _maxBudget;
    }

    DecoderInstrumentation.log(
      'FileBitstreamReaderAgent',
      'Resolved target rate=${trate.toStringAsFixed(4)} bpp, bytes=$tnbytes, parsing=${_isParsingMode ? 'on' : 'off'}',
    );

    _ncbQuitTarget = _readIntOption('ncb_quit', defaultValue: -1);
    if (_ncbQuitTarget != -1 && _isParsingMode) {
      throw StringFormatException(
          "Cannot enable 'ncb_quit' when parsing mode is active (set parsing=off)");
    }

    lQuit = _readIntOption('l_quit', defaultValue: -1);
    _usePocQuit = _readBooleanOption('poc_quit', defaultValue: false);
    _limitToSingleTilePart = _readBooleanOption('one_tp', defaultValue: false);
  }

  bool _readBooleanOption(String name, {required bool defaultValue}) {
    final raw = _parameters.getParameter(name);
    if (raw == null) {
      return defaultValue;
    }
    if (raw == 'on') {
      return true;
    }
    if (raw == 'off') {
      return false;
    }
    throw StringFormatException("Invalid value for '$name': $raw");
  }

  int _readIntOption(String name, {required int defaultValue}) {
    final raw = _parameters.getParameter(name);
    if (raw == null) {
      return defaultValue;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw StringFormatException("Invalid integer for '$name': $raw");
    }
    return parsed;
  }

  double _readDoubleOption(String name, {required double defaultValue}) {
    final raw = _parameters.getParameter(name);
    if (raw == null) {
      return defaultValue;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      throw StringFormatException("Invalid floating-point value for '$name': $raw");
    }
    return parsed;
  }

  void _initialiseTargetResolution() {
    final minAvailable = decSpec.dls.getMin();
    final resParam = _parameters.getParameter('res');
    if (resParam == null) {
      targetRes = minAvailable;
      return;
    }

    final parsed = int.tryParse(resParam);
    if (parsed == null) {
      throw ArgumentError(
        "Invalid resolution level index ('-res' option) $resParam",
      );
    }
    if (parsed < 0) {
      throw ArgumentError('Resolution level index cannot be negative: $parsed');
    }
    if (parsed > minAvailable) {
      FacilityManager.getMsgLogger().printmsg(
        MsgLogger.warning,
        'Specified resolution level ($parsed) exceeds the available maximum ($minAvailable); clamping to $minAvailable.',
      );
      targetRes = minAvailable;
      return;
    }

    targetRes = parsed;
  }

  void _prepareTileBudgets() {
    if (nt <= 0) {
      _tileBudgets = const <int>[];
      _tileBudgetRemaining = const <int>[];
      _tileBytesConsumed = const <int>[];
      _tilePartBodyLengths = const <List<int>>[];
      _tilePartHeaderLengths = const <List<int>>[];
      _tileBodyLengths = const <int>[];
      _tileHeaderLengths = const <int>[];
      _tileTotalLengths = const <int>[];
      _totalTileHeaderBytes = 0;
      return;
    }

    _buildTilePartCaches();
    _tileBytesConsumed = List<int>.filled(nt, 0, growable: false);

    if (_isTruncationMode) {
      _allocateTruncationBudgets();
    } else {
      _allocateParsingBudgets();
    }
  }

  void _buildTilePartCaches() {
    _tilePartBodyLengths =
        List<List<int>>.generate(nt, (_) => <int>[], growable: false);
    _tilePartHeaderLengths =
        List<List<int>>.generate(nt, (_) => <int>[], growable: false);
    _tileBodyLengths = List<int>.filled(nt, 0, growable: false);
    _tileHeaderLengths = List<int>.filled(nt, 0, growable: false);
    _tileTotalLengths = List<int>.filled(nt, 0, growable: false);
    _totalTileHeaderBytes = 0;

    for (var tile = 0; tile < nt; tile++) {
      final rawBodies = hd.getTilePartBodyLengths(tile) ?? const <int>[];
      final rawHeaders = hd.getTilePartHeaderLengths(tile) ?? const <int>[];
      final rawLengths = hd.getTilePartLengths(tile) ?? const <int>[];
      var partCount = rawBodies.length;
      if (rawHeaders.length > partCount) {
        partCount = rawHeaders.length;
      }
      if (rawLengths.length > partCount) {
        partCount = rawLengths.length;
      }
      if (_limitToSingleTilePart && partCount > 1) {
        partCount = 1;
      }

      if (partCount == 0) {
        _tilePartBodyLengths[tile] = <int>[_maxBudget];
        _tilePartHeaderLengths[tile] = <int>[0];
        _tileBodyLengths[tile] = _maxBudget;
        _tileHeaderLengths[tile] = 0;
        _tileTotalLengths[tile] = _maxBudget;
        continue;
      }

      final bodies = <int>[];
      final headers = <int>[];
      for (var part = 0; part < partCount; part++) {
        final headerLen = part < rawHeaders.length
            ? rawHeaders[part]
            : part < rawLengths.length && part < rawBodies.length
                ? math.max(0, rawLengths[part] - rawBodies[part])
                : 0;
        final bodyLen = part < rawBodies.length
            ? rawBodies[part]
            : part < rawLengths.length
                ? math.max(0, rawLengths[part] - headerLen)
                : _maxBudget;
        bodies.add(bodyLen);
        headers.add(headerLen);
      }

      _tilePartBodyLengths[tile] = bodies;
      _tilePartHeaderLengths[tile] = headers;

      var bodyTotal = 0;
      var bodyUnlimited = false;
      for (final length in bodies) {
        if (length >= _maxBudget) {
          bodyUnlimited = true;
          break;
        }
        bodyTotal += length;
      }
      _tileBodyLengths[tile] = bodyUnlimited ? _maxBudget : bodyTotal;

      final headerTotal = headers.fold<int>(0, (sum, value) => sum + value);
      _tileHeaderLengths[tile] = headerTotal;
      _totalTileHeaderBytes += headerTotal;

      if (bodyUnlimited) {
        _tileTotalLengths[tile] = _maxBudget;
      } else {
        final combined = bodyTotal + headerTotal;
        _tileTotalLengths[tile] = combined >= _maxBudget ? _maxBudget : combined;
      }
    }
  }

  void _allocateParsingBudgets() {
    final stopOff = tnbytes <= 0 ? _maxBudget : tnbytes;
    final baseHeaders = _ncbQuitTarget == -1
        ? hd.mainHeaderLength + _totalTileHeaderBytes
        : 0;
    anbytes = baseHeaders;

    if (stopOff == _maxBudget) {
      _tileBudgets = List<int>.filled(nt, _maxBudget, growable: false);
      _tileBudgetRemaining = List<int>.filled(nt, _maxBudget, growable: false);
      return;
    }

    const eocBytes = 2;
    if (baseHeaders + eocBytes > stopOff) {
      throw StateError('Requested bitrate is too small for parsing mode');
    }

    final totalTileLength = _tileTotalLengths.fold<int>(0, (sum, value) {
      if (sum >= _maxBudget || value >= _maxBudget) {
        return _maxBudget;
      }
      return sum + value;
    });

    if (totalTileLength == 0 || totalTileLength >= _maxBudget) {
      _tileBudgets = List<int>.filled(nt, _maxBudget, growable: false);
      _tileBudgetRemaining = List<int>.filled(nt, _maxBudget, growable: false);
      anbytes += eocBytes;
      return;
    }

    _tileBudgets = List<int>.filled(nt, 0, growable: false);
    var rem = stopOff - (baseHeaders + eocBytes);
    final totnByte = rem;
    for (var tile = nt - 1; tile > 0; tile--) {
      final weight = _tileTotalLengths[tile];
      final allocation = weight == 0
          ? 0
          : (totnByte * weight / totalTileLength).floor();
      _tileBudgets[tile] = math.max(0, allocation);
      rem -= _tileBudgets[tile];
      if (rem < 0) {
        rem = 0;
      }
    }
    _tileBudgets[0] = math.max(0, rem);
    _tileBudgetRemaining = List<int>.from(_tileBudgets, growable: false);
    anbytes += eocBytes;
  }

  void _allocateTruncationBudgets() {
    final target = tnbytes <= 0 ? _maxBudget : tnbytes;
    final unlimited = target >= _maxBudget;
    final headerBase = _ncbQuitTarget == -1 ? hd.mainHeaderLength : 0;

    if (nt <= 0) {
      _tileBudgets = const <int>[];
      _tileBudgetRemaining = const <int>[];
      anbytes = math.min(headerBase, target);
      return;
    }

    if (unlimited) {
      _tileBudgets = List<int>.filled(nt, _maxBudget, growable: false);
      _tileBudgetRemaining =
          List<int>.filled(nt, _maxBudget, growable: false);
      anbytes = headerBase;
      return;
    }

    if (headerBase > target) {
      throw StateError('Requested bitrate is too small for codestream headers');
    }

    _tileBudgets = List<int>.filled(nt, 0, growable: false);
    _tileBudgetRemaining = List<int>.filled(nt, 0, growable: false);

    final traversal = _buildTilePartTraversal();
    final cursors = List<int>.filled(nt, 0, growable: false);
    var headerConsumed = headerBase;

    for (final tile in traversal) {
      if (tile < 0 || tile >= nt) {
        continue;
      }
      final partIdx = cursors[tile];
      if (_limitToSingleTilePart && partIdx > 0) {
        continue;
      }

      final headerLen = _getTilePartHeaderLength(tile, partIdx);
      final bodyLen = _getTilePartBodyLength(tile, partIdx);

      final tilePartFitsCompletely = () {
        if (bodyLen >= _maxBudget) {
          return false;
        }
        final projected = headerConsumed + headerLen + bodyLen;
        return projected <= target;
      }();

      if (!tilePartFitsCompletely) {
        final headerCap = headerConsumed + headerLen;
        if (headerCap > target) {
          throw StateError(
              'Requested bitrate exhausted while reading tile-part headers');
        }
        final remainingAfterHeader = target - headerCap;
        if (remainingAfterHeader > 0) {
          final allocation = bodyLen >= _maxBudget
              ? remainingAfterHeader
              : math.min(bodyLen, remainingAfterHeader);
          _tileBudgets[tile] += allocation;
        }
        headerConsumed = headerCap;
        break;
      }

      headerConsumed += headerLen;
      if (bodyLen >= _maxBudget) {
        _tileBudgets[tile] = _maxBudget;
        break;
      }
      _tileBudgets[tile] += bodyLen;
      cursors[tile] = partIdx + 1;
    }

    for (var tile = 0; tile < nt; tile++) {
      _tileBudgetRemaining[tile] = _tileBudgets[tile];
    }
    anbytes = math.min(headerConsumed, target);
  }

  List<int> _buildTilePartTraversal() {
    final order = hd.getTilePartTileOrder();
    if (order.isNotEmpty) {
      return order;
    }
    final traversal = <int>[];
    for (var tile = 0; tile < nt; tile++) {
      final partCount = _tilePartBodyLengths[tile].isEmpty
          ? 1
          : _tilePartBodyLengths[tile].length;
      final limit = _limitToSingleTilePart
          ? math.min(1, partCount)
          : partCount;
      for (var part = 0; part < limit; part++) {
        traversal.add(tile);
      }
    }
    return traversal;
  }

  int _getTilePartBodyLength(int tileIdx, int tilePartIdx) {
    if (tileIdx < 0 || tileIdx >= _tilePartBodyLengths.length) {
      return _maxBudget;
    }
    final parts = _tilePartBodyLengths[tileIdx];
    if (parts.isEmpty) {
      return _maxBudget;
    }
    if (tilePartIdx < 0 || tilePartIdx >= parts.length) {
      return _maxBudget;
    }
    return parts[tilePartIdx];
  }

  int _getTilePartHeaderLength(int tileIdx, int tilePartIdx) {
    if (tileIdx < 0 || tileIdx >= _tilePartHeaderLengths.length) {
      return 0;
    }
    final parts = _tilePartHeaderLengths[tileIdx];
    if (parts.isEmpty) {
      return 0;
    }
    if (tilePartIdx < 0 || tilePartIdx >= parts.length) {
      return 0;
    }
    return parts[tilePartIdx];
  }

  bool Function(
    int layer,
    int resolution,
    int component,
    int precinct,
    List<int> remainingBytes,
  )? _packetOverride;
  int _packetOverrideCount = 0;
  int _packetOverrideInvocations = 0;

  ParameterList get parameters => _parameters;
  RandomAccessIO get input => _input;
  bool get codestreamInfo => _codestreamInfo;
  HeaderInfo get headerInfo => _headerInfo;

  @override
  void setTile(int x, int y) {
    if (x < 0 || y < 0 || x >= ntX || y >= ntY) {
      throw ArgumentError('Invalid tile coordinates: ($x,$y)');
    }

    ctX = x;
    ctY = y;

    final ctox = x == 0 ? ax : px + x * ntW;
    final ctoy = y == 0 ? ay : py + y * ntH;

    for (var comp = nc - 1; comp >= 0; comp--) {
      final subX = hd.getCompSubsX(comp);
      final subY = hd.getCompSubsY(comp);
      culx[comp] = (ctox + subX - 1) ~/ subX;
      culy[comp] = (ctoy + subY - 1) ~/ subY;
      offX[comp] = (px + x * ntW + subX - 1) ~/ subX;
      offY[comp] = (py + y * ntH + subY - 1) ~/ subY;
    }

    final tileIdx = getTileIdx();
    for (var comp = 0; comp < nc; comp++) {
      derived[comp] = decSpec.qts.isDerived(tileIdx, comp);

      final quantParams = decSpec.qsss.getTileCompVal(tileIdx, comp);
      if (quantParams == null) {
        throw StateError('Missing quantization step sizes for tile=$tileIdx component=$comp');
      }
      params[comp] = quantParams;

      final guardBitsValue = decSpec.gbs.getTileCompVal(tileIdx, comp);
      if (guardBitsValue == null) {
        throw StateError('Missing guard bits for tile=$tileIdx component=$comp');
      }
      guardBits[comp] = guardBitsValue;

      final maxDecompLevels = decSpec.dls.getTileCompVal(tileIdx, comp);
      if (maxDecompLevels == null) {
        throw StateError('Missing decomposition levels for tile=$tileIdx component=$comp');
      }
      mdl[comp] = maxDecompLevels;

      final hFilters = decSpec.wfs.getHFilters(tileIdx, comp).cast<WaveletFilter>();
      final vFilters = decSpec.wfs.getVFilters(tileIdx, comp).cast<WaveletFilter>();

      subbTrees[comp] = SubbandSyn.tree(
        getTileCompWidth(tileIdx, comp, maxDecompLevels),
        getTileCompHeight(tileIdx, comp, maxDecompLevels),
        getResULX(comp, maxDecompLevels),
        getResULY(comp, maxDecompLevels),
        maxDecompLevels,
        hFilters,
        vFilters,
      );

      final tree = subbTrees[comp];
      if (tree == null) {
        throw StateError('Failed to initialise subband tree for tile=$tileIdx component=$comp');
      }
      initSubbandsFields(comp, tree);
    }

    _decodeTilePackets(tileIdx);
  }

  @override
  void nextTile() {
    if (ctX == ntX - 1 && ctY == ntY - 1) {
      throw StateError('Already at the last tile');
    }
    if (ctX < ntX - 1) {
      setTile(ctX + 1, ctY);
    } else {
      setTile(0, ctY + 1);
    }
  }

  @override
  int getNomRangeBits(int component) {
    if (component < 0 || component >= nc) {
      throw ArgumentError('Component index out of range: $component');
    }
    final tree = subbTrees[component];
    if (tree == null) {
      throw StateError('Subband tree not initialized for component $component');
    }
    return tree.magBits;
  }

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
    final tileIndex = getTileIdx();
    final blockGrid = cbI;
    if (blockGrid == null) {
      throw StateError('Code-block metadata not initialised for tile $tileIndex');
    }

    final totalLayers = decSpec.nls.getTileDef(tileIndex);
    if (totalLayers == null) {
      throw StateError('Number of layers undefined for tile $tileIndex');
    }

    var layersRequested = numLayers;
    if (layersRequested < 0) {
      layersRequested = totalLayers - firstLayer + 1;
    }

    if (lQuit != -1 && firstLayer + layersRequested > lQuit) {
      layersRequested = lQuit - firstLayer;
    }

    if (firstLayer < 1 || firstLayer > totalLayers || firstLayer + layersRequested - 1 > totalLayers) {
      throw ArgumentError(
        'Invalid layer range request (tile=$tileIndex component=$component fl=$firstLayer nl=$layersRequested)',
      );
    }

    final resolution = subband.resLvl;
    final subbandIdx = subband.sbandIdx;

    CBlkInfo? requested;
    try {
      final compLevels = blockGrid[component];
      if (compLevels == null) {
        throw ArgumentError();
      }
      final resBands = compLevels[resolution];
      if (resBands == null) {
        throw ArgumentError();
      }
      final bandBlocks = resBands[subbandIdx];
      if (bandBlocks == null) {
        throw ArgumentError();
      }
      final rowBlocks = bandBlocks[verticalCodeBlockIndex];
      if (rowBlocks == null) {
        throw ArgumentError();
      }
      requested = rowBlocks[horizontalCodeBlockIndex];
    } on RangeError catch (_) {
      throw ArgumentError(
        'Code-block (t:$tileIndex, c:$component, r:$resolution, s:$subbandIdx, '
        '${verticalCodeBlockIndex}x$horizontalCodeBlockIndex) not found in codestream',
      );
    } on ArgumentError catch (_) {
      throw ArgumentError(
        'Code-block (t:$tileIndex, c:$component, r:$resolution, s:$subbandIdx, '
        '${verticalCodeBlockIndex}x$horizontalCodeBlockIndex) not found in bit stream',
      );
    }

    final result = block ?? DecLyrdCBlk();
    result
      ..m = verticalCodeBlockIndex
      ..n = horizontalCodeBlockIndex
      ..nl = 0
      ..dl = 0
      ..nTrunc = 0
      ..prog = false
      ..ftpIdx = 0;

    if (requested == null) {
      result
        ..skipMSBP = 0
        ..w = 0
        ..h = 0
        ..ulx = 0
        ..uly = 0;
      return result;
    }

    if (component > 0 && layersRequested > 0) {
      final previewCount = _debugCblkPreviewCounts.putIfAbsent(component, () => 0);
      if (previewCount < 6) {
        _debugCblkPreviewCounts[component] = previewCount + 1;
        // final displayCount = math.min(layersRequested, requested.ntp.length);
        // final ntpSummary = requested.ntp.take(displayCount).join(',');
        // final lenSummary = requested.len.take(displayCount).join(',');
        /*
        print(
          'FileBitstreamReaderAgent cblk meta: tile=$tileIndex comp=$component res=$resolution '
          'band=$subbandIdx m=$verticalCodeBlockIndex n=$horizontalCodeBlockIndex '
          'len=[$lenSummary] ntp=[$ntpSummary] msbSkipped=${requested.msbSkipped}',
        );
        */
      }
    }

    result
      ..skipMSBP = requested.msbSkipped
      ..ulx = requested.ulx
      ..uly = requested.uly
      ..w = requested.w
      ..h = requested.h;

    var layerCursor = 0;
    while (layerCursor < requested.len.length && requested.len[layerCursor] == 0) {
      result.ftpIdx += requested.ntp[layerCursor];
      layerCursor++;
    }

    if (layersRequested > 0) {
      for (var layer = firstLayer - 1; layer < firstLayer + layersRequested - 1; layer++) {
        result.nl++;
        result.dl += requested.len[layer];
        result.nTrunc += requested.ntp[layer];
      }
    }

    if (DecoderInstrumentation.isEnabled()) {
      final metaSummary = StringBuffer()
        ..write('tile=$tileIndex comp=$component res=$resolution band=$subbandIdx ')
        ..write('m=$verticalCodeBlockIndex n=$horizontalCodeBlockIndex ')
        ..write('firstLayer=$firstLayer layersRequested=$layersRequested ')
        ..write('dl=${result.dl} nl=${result.nl} ftpIdx=${result.ftpIdx} ')
        ..write('nTrunc=${result.nTrunc} ntp=${requested.ntp} len=${requested.len}');
      DecoderInstrumentation.log('FileBitstreamReaderAgent', metaSummary.toString());
    }

    final options = decSpec.ecopts.getTileCompVal(tileIndex, component) ?? 0;
    var terminatedSegments = 1;
    if ((options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
      terminatedSegments = result.nTrunc - result.ftpIdx;
    } else if ((options & StdEntropyCoderOptions.OPT_BYPASS) != 0) {
      if (result.nTrunc <= StdEntropyCoderOptions.FIRST_BYPASS_PASS_IDX) {
        terminatedSegments = 1;
      } else {
        terminatedSegments = 1;
        for (var tpIdx = result.ftpIdx; tpIdx < result.nTrunc; tpIdx++) {
          if (tpIdx >= StdEntropyCoderOptions.FIRST_BYPASS_PASS_IDX - 1) {
            final passType =
                (tpIdx + StdEntropyCoderOptions.NUM_EMPTY_PASSES_IN_MS_BP) % StdEntropyCoderOptions.NUM_PASSES;
            if (passType == 1 || passType == 2) {
              terminatedSegments++;
            }
          }
        }
      }
    }

    if (terminatedSegments <= 0) {
      terminatedSegments = 1;
    }

    if (result.dl > 0) {
      var data = result.data;
      if (data == null || data.length < result.dl) {
        data = Uint8List(result.dl);
        result.data = data;
      }
    } else {
      result.data = result.dl == 0 ? Uint8List(0) : result.data;
    }

    if (terminatedSegments > 1) {
      final current = result.tsLengths;
      if (current == null || current.length < terminatedSegments) {
        result.tsLengths = List<int>.filled(terminatedSegments, 0, growable: false);
      } else if ((options & (StdEntropyCoderOptions.OPT_BYPASS | StdEntropyCoderOptions.OPT_TERM_PASS)) ==
          StdEntropyCoderOptions.OPT_BYPASS) {
        ArrayUtil.intArraySet(current, 0);
      }
    } else if (result.tsLengths != null && result.tsLengths!.isNotEmpty) {
      result.tsLengths![0] = 0;
    }

    if (result.dl == 0) {
      if (terminatedSegments == 1 && result.tsLengths != null && result.tsLengths!.isNotEmpty) {
        result.tsLengths![0] = 0;
      }
      return result;
    }

    var dataIndex = -1;
    var truncationIndex = result.ftpIdx;
    var cumulativeTruncation = result.ftpIdx;
    var terminatedIndex = 0;

    final tsLengths = result.tsLengths;

    for (var layer = firstLayer - 1; layer < firstLayer + layersRequested - 1; layer++) {
      cumulativeTruncation += requested.ntp[layer];
      final layerLength = requested.len[layer];
      if (layerLength == 0) {
        continue;
      }

      final data = result.data;
      if (data == null) {
        throw StateError('Allocated code-block buffer missing for tile $tileIndex');
      }
      final payload = requested.body[layer];
      if (payload != null) {
        if (payload.length != layerLength) {
          throw StateError(
            'Stored packet body length mismatch for tile $tileIndex layer ${layer + 1}: '
            'expected $layerLength, found ${payload.length}',
          );
        }
        if (payload.isNotEmpty) {
          data.setRange(dataIndex + 1, dataIndex + 1 + payload.length, payload);
        }
      } else {
        _input.seek(requested.off[layer]);
        _input.readFully(data, dataIndex + 1, layerLength);
      }
      dataIndex += layerLength;

      if (terminatedSegments == 1 || tsLengths == null) {
        continue;
      }

      if ((options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
        final segLengths = requested.segLen[layer];
        for (var j = 0; truncationIndex < cumulativeTruncation; j++, truncationIndex++) {
          tsLengths[terminatedIndex++] =
              segLengths != null && j < segLengths.length ? segLengths[j] : requested.len[layer];
        }
      } else {
        final segLengths = requested.segLen[layer];
        var segCursor = 0;
        for (; truncationIndex < cumulativeTruncation; truncationIndex++) {
          if (truncationIndex >= StdEntropyCoderOptions.FIRST_BYPASS_PASS_IDX - 1) {
            final passType =
                (truncationIndex + StdEntropyCoderOptions.NUM_EMPTY_PASSES_IN_MS_BP) % StdEntropyCoderOptions.NUM_PASSES;
            if (passType != 0) {
              if (segLengths != null && segCursor < segLengths.length) {
                tsLengths[terminatedIndex] += segLengths[segCursor];
                requested.len[layer] -= segLengths[segCursor];
                terminatedIndex++;
                segCursor++;
              } else {
                tsLengths[terminatedIndex] += requested.len[layer];
                requested.len[layer] = 0;
                terminatedIndex++;
              }
            }
          }
        }

        if (segLengths != null && segCursor < segLengths.length) {
          tsLengths[terminatedIndex] += segLengths[segCursor];
          requested.len[layer] -= segLengths[segCursor];
        } else if (terminatedIndex < terminatedSegments) {
          tsLengths[terminatedIndex] += requested.len[layer];
          requested.len[layer] = 0;
        }
      }
    }

    if (terminatedSegments == 1 && tsLengths != null && tsLengths.isNotEmpty) {
      tsLengths[0] = result.dl;
    }

    final lastLayer = firstLayer + layersRequested - 1;
    if (lastLayer < totalLayers - 1) {
      for (var layer = lastLayer + 1; layer < totalLayers; layer++) {
        if (requested.len[layer] != 0) {
          result.prog = true;
          break;
        }
      }
    }

    return result;
  }

  void _decodeTilePackets(int tileIdx) {
    if (_tileBudgets.isEmpty) {
      _prepareTileBudgets();
    }

    final tileBudget = tileIdx < _tileBudgets.length ? _tileBudgets[tileIdx] : _maxBudget;
    if (tileBudget <= 0) {
      DecoderInstrumentation.log(
        'FileBitstreamReaderAgent',
        'Tile $tileIdx budget exhausted before decoding; skipping packets.',
      );
      return;
    }

    final numLayersValue = decSpec.nls.getTileDef(tileIdx) ?? decSpec.nls.getDefault();
    if (numLayersValue == null) {
      throw StateError('Number of layers undefined for tile $tileIdx');
    }

    final maxLevels = List<int>.generate(
      nc,
      (component) {
        final value = decSpec.dls.getTileCompVal(tileIdx, component);
        if (value == null) {
          throw StateError('Missing decomposition levels for tile=$tileIdx component=$component');
        }
        return value;
      },
      growable: false,
    );

    var packedHeaders = decSpec.pphs.getTileDef(tileIdx) ?? false;
    Uint8List? packedHeaderData;
    if (packedHeaders) {
      packedHeaderData = hd.getPackedPacketHeaders(tileIdx);
      if (packedHeaderData == null || packedHeaderData.isEmpty) {
        packedHeaders = false;
      }
    } else {
      final candidate = hd.getPackedPacketHeaders(tileIdx);
      if (candidate != null && candidate.isNotEmpty) {
        packedHeaders = true;
        packedHeaderData = candidate;
      }
    }

    if (numLayersValue <= 0) {
      cbI = _pktDecoder.restart(nc, maxLevels, 0, cbI, packedHeaders, null);
      return;
    }

    final tilePartOffsets = hd.getTilePartDataOffsets(tileIdx);
    if (tilePartOffsets != null && tilePartOffsets.isNotEmpty) {
      _input.seek(tilePartOffsets.first);
    }

    final partBudgets = tileIdx < _tilePartBodyLengths.length
        ? _tilePartBodyLengths[tileIdx]
        : const <int>[];
    final budgets = partBudgets.isNotEmpty
        ? List<int>.from(partBudgets, growable: true)
        : <int>[_maxBudget];
    if (_limitToSingleTilePart && budgets.length > 1) {
      budgets.removeRange(1, budgets.length);
    }

    final remainingBytes = List<int>.filled(nt > 0 ? nt : 1, 0, growable: false);
    remainingBytes[tileIdx] = budgets.first;

    final grid = _pktDecoder.restart(
      nc,
      maxLevels,
      numLayersValue,
      cbI,
      packedHeaders,
      packedHeaders ? packedHeaderData : null,
    );

    cbI = grid;
    _pktDecoder.syncHeaderReader();

    if (_pktDecoder.hasReachedNcbQuit) {
      DecoderInstrumentation.log(
        'FileBitstreamReaderAgent',
        'ncb_quit satisfied before processing tile $tileIdx; skipping remaining tiles.',
      );
      return;
    }

    _tileBudgetRemaining[tileIdx] = tileBudget >= _maxBudget ? _maxBudget : tileBudget;
    _tileBytesConsumed[tileIdx] = 0;

    final maxResolutionsInTile = maxLevels.isEmpty ? 0 : maxLevels.reduce(math.max) + 1;
    final precinctGrid = _buildPrecinctGridCache(maxLevels, maxResolutionsInTile);

    final segments = _buildProgressionSegments(tileIdx, numLayersValue, maxLevels, maxResolutionsInTile);
    final layerStarts = List<List<int>>.generate(
      nc,
      (component) => List<int>.filled(maxLevels[component] + 1, 0, growable: false),
      growable: false,
    );

    var tilePartIdx = 0;
    var segmentIdx = 0;
    while (segmentIdx < segments.length) {
      final segment = segments[segmentIdx];
      final truncated = _decodeSegment(
        segment,
        layerStarts,
        maxLevels,
        maxResolutionsInTile,
        numLayersValue,
        remainingBytes,
        grid,
        precinctGrid,
      );
      if (truncated) {
        final partExhausted = remainingBytes[tileIdx] <= 0;
        final budgetDepleted = _tileBudgetRemaining[tileIdx] <= 0;
        if (partExhausted && tilePartIdx + 1 < budgets.length && !budgetDepleted) {
          tilePartIdx++;
          remainingBytes[tileIdx] = budgets[tilePartIdx];
          if (tilePartOffsets != null && tilePartIdx < tilePartOffsets.length) {
            _input.seek(tilePartOffsets[tilePartIdx]);
          }
          _pktDecoder.syncHeaderReader();
          continue;
        }
        break;
      }
      _updateLayerStarts(layerStarts, segment, numLayersValue, maxLevels);
      segmentIdx++;
    }

    if (tileIdx < _tileBytesConsumed.length) {
      final consumedData = _tileBytesConsumed[tileIdx];
      if (consumedData > 0) {
        anbytes += consumedData;
        _tileBytesConsumed[tileIdx] = 0;
      }
    }
  }

  List<List<Coord?>> _buildPrecinctGridCache(List<int> maxLevels, int maxResolutions) {
    return List<List<Coord?>>.generate(
      nc,
      (component) => List<Coord?>.generate(
        maxResolutions,
        (resolution) {
          if (resolution > maxLevels[component]) {
            return null;
          }
          final numPrecincts = _pktDecoder.getNumPrecinct(component, resolution);
          if (numPrecincts == 0) {
            return null;
          }
          final size = _pktDecoder.getPrecinctGridSize(component, resolution);
          if (size.x == 0 || size.y == 0) {
            return null;
          }
          return size;
        },
        growable: false,
      ),
      growable: false,
    );
  }

  bool _decodeLrcp(
    _ProgressionSegment segment,
    List<List<int>> layerStarts,
    List<int> maxLevels,
    int maxResolutions,
    int numLayers,
    List<int> remainingBytes,
    _CodeBlockGrid grid,
    List<List<Coord?>> precinctGrid,
  ) {
    final layerEnd = math.min(segment.layerEnd, numLayers);
    final resStart = math.max(segment.resStart, 0);
    final resEnd = math.min(segment.resEnd, maxResolutions);
    final compStart = math.max(segment.compStart, 0);
    final compEnd = math.min(segment.compEnd, nc);
    final minLayer = _computeMinLayerStart(layerStarts, segment, maxLevels, numLayers);

    for (var layer = minLayer; layer < layerEnd; layer++) {
      for (var resolution = resStart; resolution < resEnd; resolution++) {
        for (var component = compStart; component < compEnd; component++) {
          if (component >= nc) {
            break;
          }
          if (resolution > maxLevels[component]) {
            continue;
          }
          final startLayer = layerStarts[component][resolution];
          if (layer < startLayer) {
            continue;
          }
          final coord = precinctGrid[component][resolution];
          if (coord == null) {
            continue;
          }
          final precinctCount = coord.x * coord.y;
          for (var precinct = 0; precinct < precinctCount; precinct++) {
            if (_processPacket(layer, resolution, component, precinct, remainingBytes, grid)) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  bool _decodeRlcp(
    _ProgressionSegment segment,
    List<List<int>> layerStarts,
    List<int> maxLevels,
    int maxResolutions,
    int numLayers,
    List<int> remainingBytes,
    _CodeBlockGrid grid,
    List<List<Coord?>> precinctGrid,
  ) {
    final layerEnd = math.min(segment.layerEnd, numLayers);
    final resStart = math.max(segment.resStart, 0);
    final resEnd = math.min(segment.resEnd, maxResolutions);
    final compStart = math.max(segment.compStart, 0);
    final compEnd = math.min(segment.compEnd, nc);
    final minLayer = _computeMinLayerStart(layerStarts, segment, maxLevels, numLayers);

    for (var resolution = resStart; resolution < resEnd; resolution++) {
      for (var layer = minLayer; layer < layerEnd; layer++) {
        for (var component = compStart; component < compEnd; component++) {
          if (component >= nc) {
            break;
          }
          if (resolution > maxLevels[component]) {
            continue;
          }
          final startLayer = layerStarts[component][resolution];
          if (layer < startLayer) {
            continue;
          }
          final coord = precinctGrid[component][resolution];
          if (coord == null) {
            continue;
          }
          final precinctCount = coord.x * coord.y;
          if (precinctCount == 0) {
            if (layerStarts[component][resolution] <= layer) {
              layerStarts[component][resolution] = layer + 1;
            }
            continue;
          }
          for (var precinct = 0; precinct < precinctCount; precinct++) {
            if (_processPacket(layer, resolution, component, precinct, remainingBytes, grid)) {
              return true;
            }
          }
          if (layerStarts[component][resolution] <= layer) {
            layerStarts[component][resolution] = layer + 1;
          }
        }
      }
    }

    return false;
  }

  bool _decodeRpcl(
    _ProgressionSegment segment,
    List<List<int>> layerStarts,
    List<int> maxLevels,
    int maxResolutions,
    int numLayers,
    List<int> remainingBytes,
    _CodeBlockGrid grid,
    List<List<Coord?>> precinctGrid,
  ) {
    final layerEnd = math.min(segment.layerEnd, numLayers);
    final resStart = math.max(segment.resStart, 0);
    final resEnd = math.min(segment.resEnd, maxResolutions);
    final compStart = math.max(segment.compStart, 0);
    final compEnd = math.min(segment.compEnd, nc);
    final minLayer = _computeMinLayerStart(layerStarts, segment, maxLevels, numLayers);

    for (var resolution = resStart; resolution < resEnd; resolution++) {
      var maxPrecX = 0;
      var maxPrecY = 0;
      final coords = List<Coord?>.filled(nc, null, growable: false);

      for (var component = compStart; component < compEnd; component++) {
        if (component >= nc) {
          break;
        }
        if (resolution > maxLevels[component]) {
          continue;
        }
        final coord = precinctGrid[component][resolution];
        if (coord == null || coord.x == 0 || coord.y == 0) {
          coords[component] = null;
          continue;
        }
        coords[component] = coord;
        if (coord.x > maxPrecX) {
          maxPrecX = coord.x;
        }
        if (coord.y > maxPrecY) {
          maxPrecY = coord.y;
        }
      }

      if (maxPrecX == 0 || maxPrecY == 0) {
        continue;
      }

      for (var y = 0; y < maxPrecY; y++) {
        for (var x = 0; x < maxPrecX; x++) {
          for (var component = compStart; component < compEnd; component++) {
            if (component >= nc) {
              break;
            }
            final coord = coords[component];
            if (coord == null || x >= coord.x || y >= coord.y) {
              continue;
            }
            final precinct = y * coord.x + x;
            final startLayer = layerStarts[component][resolution];
            final effectiveStart = math.max(minLayer, startLayer);
            for (var layer = effectiveStart; layer < layerEnd; layer++) {
              if (_processPacket(layer, resolution, component, precinct, remainingBytes, grid)) {
                return true;
              }
            }
          }
        }
      }
    }

    return false;
  }

  bool _decodePcrl(
    _ProgressionSegment segment,
    List<List<int>> layerStarts,
    List<int> maxLevels,
    int maxResolutions,
    int numLayers,
    List<int> remainingBytes,
    _CodeBlockGrid grid,
    List<List<Coord?>> precinctGrid,
  ) {
    final layerEnd = math.min(segment.layerEnd, numLayers);
    final resStart = math.max(segment.resStart, 0);
    final resEnd = math.min(segment.resEnd, maxResolutions);
    final compStart = math.max(segment.compStart, 0);
    final compEnd = math.min(segment.compEnd, nc);
    final minLayer = _computeMinLayerStart(layerStarts, segment, maxLevels, numLayers);

    var maxPrecX = 0;
    var maxPrecY = 0;
    for (var component = compStart; component < compEnd; component++) {
      if (component >= nc) {
        break;
      }
      final levels = precinctGrid[component];
      final compMaxRes = math.min(resEnd, maxLevels[component] + 1);
      for (var resolution = resStart; resolution < compMaxRes; resolution++) {
        final coord = levels[resolution];
        if (coord == null) {
          continue;
        }
        if (coord.x > maxPrecX) {
          maxPrecX = coord.x;
        }
        if (coord.y > maxPrecY) {
          maxPrecY = coord.y;
        }
      }
    }

    if (maxPrecX == 0 || maxPrecY == 0) {
      return false;
    }

    for (var y = 0; y < maxPrecY; y++) {
      for (var x = 0; x < maxPrecX; x++) {
        for (var component = compStart; component < compEnd; component++) {
          if (component >= nc) {
            break;
          }
          final levels = precinctGrid[component];
          final compMaxRes = math.min(resEnd, maxLevels[component] + 1);
          for (var resolution = resStart; resolution < compMaxRes; resolution++) {
            final coord = levels[resolution];
            if (coord == null || x >= coord.x || y >= coord.y) {
              continue;
            }
            final precinct = y * coord.x + x;
            final startLayer = layerStarts[component][resolution];
            final effectiveStart = math.max(minLayer, startLayer);
            for (var layer = effectiveStart; layer < layerEnd; layer++) {
              if (_processPacket(layer, resolution, component, precinct, remainingBytes, grid)) {
                return true;
              }
            }
          }
        }
      }
    }

    return false;
  }

  bool _decodeCprl(
    _ProgressionSegment segment,
    List<List<int>> layerStarts,
    List<int> maxLevels,
    int maxResolutions,
    int numLayers,
    List<int> remainingBytes,
    _CodeBlockGrid grid,
    List<List<Coord?>> precinctGrid,
  ) {
    final layerEnd = math.min(segment.layerEnd, numLayers);
    final resStart = math.max(segment.resStart, 0);
    final resEnd = math.min(segment.resEnd, maxResolutions);
    final compStart = math.max(segment.compStart, 0);
    final compEnd = math.min(segment.compEnd, nc);
    final minLayer = _computeMinLayerStart(layerStarts, segment, maxLevels, numLayers);

    for (var component = compStart; component < compEnd; component++) {
      if (component >= nc) {
        break;
      }
      var maxPrecX = 0;
      var maxPrecY = 0;
      final levels = precinctGrid[component];
      final compMaxRes = math.min(resEnd, maxLevels[component] + 1);
      for (var resolution = resStart; resolution < compMaxRes; resolution++) {
        final coord = levels[resolution];
        if (coord == null) {
          continue;
        }
        if (coord.x > maxPrecX) {
          maxPrecX = coord.x;
        }
        if (coord.y > maxPrecY) {
          maxPrecY = coord.y;
        }
      }

      if (maxPrecX == 0 || maxPrecY == 0) {
        continue;
      }

      for (var y = 0; y < maxPrecY; y++) {
        for (var x = 0; x < maxPrecX; x++) {
          for (var resolution = resStart; resolution < compMaxRes; resolution++) {
            final coord = levels[resolution];
            if (coord == null || x >= coord.x || y >= coord.y) {
              continue;
            }
            final precinct = y * coord.x + x;
            final startLayer = layerStarts[component][resolution];
            final effectiveStart = math.max(minLayer, startLayer);
            for (var layer = effectiveStart; layer < layerEnd; layer++) {
              if (_processPacket(layer, resolution, component, precinct, remainingBytes, grid)) {
                return true;
              }
            }
          }
        }
      }
    }

    return false;
  }

  List<_ProgressionSegment> _buildProgressionSegments(
    int tileIdx,
    int numLayers,
    List<int> maxLevels,
    int maxResolutions,
  ) {
    final pocSpec = decSpec.pcs.getTileDef(tileIdx);
    if (pocSpec == null || pocSpec.isEmpty) {
      final progression =
          decSpec.pos.getTileDef(tileIdx) ?? decSpec.pos.getDefault() ?? ProgressionType.LY_RES_COMP_POS_PROG;
      return <_ProgressionSegment>[
        _ProgressionSegment(
          progression: progression,
          layerEnd: numLayers,
          resStart: 0,
          resEnd: maxResolutions,
          compStart: 0,
          compEnd: nc,
        ),
      ];
    }

    final segments = <_ProgressionSegment>[];
    for (final entry in pocSpec) {
      if (entry.length < 6) {
        throw StateError('Invalid POC specification entry: expected 6 values, got ${entry.length}');
      }
      segments.add(
        _ProgressionSegment(
          progression: entry[5],
          layerEnd: entry[2],
          resStart: entry[0],
          resEnd: entry[3],
          compStart: entry[1],
          compEnd: entry[4],
        ),
      );
    }
    if (_usePocQuit && segments.isNotEmpty) {
      return <_ProgressionSegment>[segments.first];
    }
    return segments;
  }

  bool _decodeSegment(
    _ProgressionSegment segment,
    List<List<int>> layerStarts,
    List<int> maxLevels,
    int maxResolutions,
    int numLayers,
    List<int> remainingBytes,
    _CodeBlockGrid grid,
    List<List<Coord?>> precinctGrid,
  ) {
    if (segment.layerEnd <= 0) {
      return false;
    }
    switch (segment.progression) {
      case ProgressionType.LY_RES_COMP_POS_PROG:
        return _decodeLrcp(segment, layerStarts, maxLevels, maxResolutions, numLayers, remainingBytes, grid, precinctGrid);
      case ProgressionType.RES_LY_COMP_POS_PROG:
        return _decodeRlcp(segment, layerStarts, maxLevels, maxResolutions, numLayers, remainingBytes, grid, precinctGrid);
      case ProgressionType.RES_POS_COMP_LY_PROG:
        return _decodeRpcl(segment, layerStarts, maxLevels, maxResolutions, numLayers, remainingBytes, grid, precinctGrid);
      case ProgressionType.POS_COMP_RES_LY_PROG:
        return _decodePcrl(segment, layerStarts, maxLevels, maxResolutions, numLayers, remainingBytes, grid, precinctGrid);
      case ProgressionType.COMP_POS_RES_LY_PROG:
        return _decodeCprl(segment, layerStarts, maxLevels, maxResolutions, numLayers, remainingBytes, grid, precinctGrid);
      default:
        throw UnsupportedError('Progression order ${segment.progression} is not supported yet');
    }
  }

  int _computeMinLayerStart(
    List<List<int>> layerStarts,
    _ProgressionSegment segment,
    List<int> maxLevels,
    int numLayers,
  ) {
    final compStart = math.max(segment.compStart, 0);
    final compEnd = math.min(segment.compEnd, nc);
    if (compStart >= compEnd) {
      return math.min(segment.layerEnd, numLayers);
    }
    var minStart = numLayers;
    for (var component = compStart; component < compEnd; component++) {
      if (component >= nc) {
        break;
      }
      final compMaxRes = maxLevels[component];
      final resStart = math.max(segment.resStart, 0);
      final resEnd = math.min(segment.resEnd, compMaxRes + 1);
      if (resStart >= resEnd) {
        continue;
      }
      final compLayers = layerStarts[component];
      for (var resolution = resStart; resolution < resEnd; resolution++) {
        final start = compLayers[resolution];
        if (start < minStart) {
          minStart = start;
        }
      }
    }
    if (minStart == numLayers) {
      return math.min(segment.layerEnd, numLayers);
    }
    return minStart;
  }

  void _updateLayerStarts(
    List<List<int>> layerStarts,
    _ProgressionSegment segment,
    int numLayers,
    List<int> maxLevels,
  ) {
    final stopLayer = math.min(segment.layerEnd, numLayers);
    final compStart = math.max(segment.compStart, 0);
    final compEnd = math.min(segment.compEnd, nc);
    if (compStart >= compEnd) {
      return;
    }
    for (var component = compStart; component < compEnd; component++) {
      if (component >= nc) {
        break;
      }
      final compMaxRes = maxLevels[component];
      final resStart = math.max(segment.resStart, 0);
      final resEnd = math.min(segment.resEnd, compMaxRes + 1);
      if (resStart >= resEnd) {
        continue;
      }
      final compLayers = layerStarts[component];
      for (var resolution = resStart; resolution < resEnd; resolution++) {
        if (compLayers[resolution] < stopLayer) {
          compLayers[resolution] = stopLayer;
        }
      }
    }
  }

  bool _processPacket(
    int layer,
    int resolution,
    int component,
    int precinct,
    List<int> remainingBytes,
    _CodeBlockGrid grid,
  ) {
    final tileIdx = getTileIdx();
    final before = remainingBytes[tileIdx];

    if (_packetOverride != null) {
      if (_packetOverrideCount > 0 && _packetOverrideInvocations >= _packetOverrideCount) {
        return _finalizePacket(tileIdx, before, remainingBytes, true);
      }
      _packetOverrideInvocations++;
      final forced =
          _packetOverride!(layer, resolution, component, precinct, remainingBytes);
      return _finalizePacket(tileIdx, before, remainingBytes, forced);
    }

    if (_pktDecoder.readSOPMarker(remainingBytes, precinct, component, resolution)) {
      return _finalizePacket(tileIdx, before, remainingBytes, true);
    }

    List<List<List<CBlkInfo?>?>?>? subbandBlocks;
    if (component < grid.length) {
      final compEntry = grid[component];
      if (compEntry != null && resolution < compEntry.length) {
        subbandBlocks = compEntry[resolution];
      }
    }

    if (_pktDecoder.readPktHead(
        layer, resolution, component, precinct, subbandBlocks, remainingBytes)) {
      return _finalizePacket(tileIdx, before, remainingBytes, true);
    }
    if (_pktDecoder.readPktBody(
        layer, resolution, component, precinct, subbandBlocks, remainingBytes)) {
      return _finalizePacket(tileIdx, before, remainingBytes, true);
    }
    return _finalizePacket(tileIdx, before, remainingBytes, false);
  }

  bool _finalizePacket(
    int tileIdx,
    int before,
    List<int> tilePartBudgets,
    bool truncated,
  ) {
    if (tileIdx < 0 || tileIdx >= tilePartBudgets.length) {
      return truncated;
    }
    final after = tilePartBudgets[tileIdx];
    final consumed = before - after;
    if (consumed > 0 && tileIdx < _tileBytesConsumed.length) {
      _tileBytesConsumed[tileIdx] += consumed;
      if (tileIdx < _tileBudgetRemaining.length) {
        final updated = _tileBudgetRemaining[tileIdx] - consumed;
        _tileBudgetRemaining[tileIdx] = updated <= 0 ? 0 : updated;
      }
    }
    if (tileIdx < _tileBudgetRemaining.length && _tileBudgetRemaining[tileIdx] <= 0) {
      tilePartBudgets[tileIdx] = 0;
      return true;
    }
    return truncated;
  }

  @visibleForTesting
  List<int> debugGetTileBudgets() => List<int>.from(_tileBudgets);

  @visibleForTesting
  List<List<int>> debugGetCachedTilePartBodyLengths() =>
      _tilePartBodyLengths.map((parts) => List<int>.from(parts)).toList(growable: false);

  @visibleForTesting
  int debugGetPktDecoderMaxCodeBlocks() => _pktDecoder.maxCB;

  @visibleForTesting
  int debugGetNcbQuitTarget() => _ncbQuitTarget;

  @visibleForTesting
  List<Map<String, int>> debugDescribeProgressionSegments() {
    if (nc == 0) {
      return const <Map<String, int>>[];
    }
    final tileIdx = getTileIdx();
    final numLayers =
        decSpec.nls.getTileDef(tileIdx) ?? decSpec.nls.getDefault() ?? 0;
    final maxLevels = List<int>.generate(
      nc,
      (component) =>
          decSpec.dls.getTileCompVal(tileIdx, component) ??
          decSpec.dls.getCompDef(component) ??
          decSpec.dls.getDefault() ??
          0,
      growable: false,
    );
    final maxResolutions =
        maxLevels.isEmpty ? 0 : maxLevels.reduce(math.max) + 1;
    final segments =
        _buildProgressionSegments(tileIdx, numLayers, maxLevels, maxResolutions);
    return segments
        .map((segment) => <String, int>{
              'progression': segment.progression,
              'layerEnd': segment.layerEnd,
              'resStart': segment.resStart,
              'resEnd': segment.resEnd,
              'compStart': segment.compStart,
              'compEnd': segment.compEnd,
            })
        .toList(growable: false);
  }

  void debugSetPacketSimulation(
    int packetCount,
    bool Function(
      int layer,
      int resolution,
      int component,
      int precinct,
      List<int> remainingBytes,
    ) override,
  ) {
    _packetOverrideCount = packetCount;
    _packetOverrideInvocations = 0;
    _packetOverride = override;
  }

  void debugClearPacketSimulation() {
    _packetOverrideCount = 0;
    _packetOverride = null;
    _packetOverrideInvocations = 0;
  }
}


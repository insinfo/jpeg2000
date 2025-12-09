part of 'BitstreamReaderAgent.dart';

/// Minimal packet decoder used in unit tests to simulate code-block limits
/// without requiring a full JPEG 2000 bitstream.
@visibleForTesting
class PktDecoderHarness extends PktDecoder {
  PktDecoderHarness(
    DecoderSpecs decSpec,
    HeaderDecoder hd,
    RandomAccessIO input,
    BitstreamReaderAgent agent,
    bool truncationMode,
    int maxCodeBlocks, {
    this.codeBlocksPerPacket = 1,
  }) : super(decSpec, hd, input, agent, truncationMode, maxCodeBlocks);

  final int codeBlocksPerPacket;

  int _packetsDecoded = 0;
  bool _quitTriggered = false;
  List<int> _maxLevels = const <int>[];

  bool get quitTriggered => _quitTriggered;
  int get packetsDecoded => _packetsDecoded;

  @override
  _CodeBlockGrid restart(
    int numComponents,
    List<int> maxDecompositionLevels,
    int numLayers,
    _CodeBlockGrid? existing,
    bool packedHeaders,
    Uint8List? packedHeaderData,
  ) {
    _maxLevels = List<int>.from(maxDecompositionLevels, growable: false);
    return List<List<List<List<List<CBlkInfo?>?>?>?>?>.generate(
      numComponents,
      (component) => List<List<List<List<CBlkInfo?>?>?>?>.filled(
        maxDecompositionLevels[component] + 1,
        null,
        growable: false,
      ),
      growable: false,
    );
  }

  @override
  void syncHeaderReader() {
    // No-op for the harness.
  }

  @override
  int getNumPrecinct(int component, int resolution) {
    if (component < _maxLevels.length && resolution <= _maxLevels[component]) {
      return 1;
    }
    return 0;
  }

  @override
  Coord getPrecinctGridSize(int component, int resolution) {
    if (component < _maxLevels.length && resolution <= _maxLevels[component]) {
      return Coord(1, 1);
    }
    return Coord(0, 0);
  }

  @override
  bool readSOPMarker(
    List<int> remainingBytesPerTile,
    int precinct,
    int component,
    int resolution,
  ) {
    return false;
  }

  @override
  bool readPktHead(
    int layer,
    int resolution,
    int component,
    int precinct,
    List<List<List<CBlkInfo?>?>?>? subbandBlocks,
    List<int> remainingBytesPerTile,
  ) {
    return _quitTriggered;
  }

  @override
  bool readPktBody(
    int layer,
    int resolution,
    int component,
    int precinct,
    List<List<List<CBlkInfo?>?>?>? subbandBlocks,
    List<int> remainingBytesPerTile,
  ) {
    if (_quitTriggered) {
      return true;
    }
    final tileIdx = src.getTileIdx();
    if (remainingBytesPerTile.isNotEmpty) {
      remainingBytesPerTile[tileIdx] =
          math.max(0, remainingBytesPerTile[tileIdx] - codeBlocksPerPacket);
    }
    _packetsDecoded++;
    if (maxCB != -1 && _packetsDecoded * codeBlocksPerPacket >= maxCB) {
      _quitTriggered = true;
      return true;
    }
    return false;
  }
}

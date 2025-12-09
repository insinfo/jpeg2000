import 'dart:math' as math;
import 'dart:typed_data';

import '../../../colorspace/ChannelDefinitionMapper.dart';
import '../../../colorspace/ColorSpace.dart';
import '../../../colorspace/ColorSpaceMapper.dart';
import '../../../colorspace/PalettizedColorSpaceMapper.dart';
import '../../../colorspace/Resampler.dart';
import '../../decoder/DecoderSpecs.dart';
import '../../entropy/StdEntropyCoderOptions.dart';
import '../../entropy/decoder/CodedCBlkDataSrcDec.dart';
import '../../entropy/decoder/EntropyDecoder.dart';
import '../../entropy/decoder/StdEntropyDecoder.dart';
import '../../image/BlkImgDataSrc.dart';
import '../../image/Coord.dart';
import '../../image/invcomptransf/InvCompTransf.dart';
import '../../io/RandomAccessIO.dart';
import '../../quantization/dequantizer/StdDequantizer.dart';
import '../../quantization/dequantizer/StdDequantizerParams.dart';
import '../../quantization/dequantizer/CBlkQuantDataSrcDec.dart';
import '../../roi/RoiDeScaler.dart';
import '../../util/DecoderInstrumentation.dart';
import '../../util/FacilityManager.dart';
import '../../util/MsgLogger.dart';
import '../../util/ParameterList.dart';
import '../../util/StringFormatException.dart';
import '../HeaderInfo.dart';
import '../markers.dart';
import '../../wavelet/FilterTypes.dart';
import '../../wavelet/synthesis/SynWTFilter.dart';
import '../../wavelet/synthesis/SynWTFilterFloatLift9x7.dart';
import '../../wavelet/synthesis/SynWTFilterIntLift5x3.dart';

class _TilePartInfo {
  int? length;
  int? dataOffset;
  int? bodyLength;
  int? headerLength;
  Uint8List? packedHeaders;
  final Map<int, Uint8List> pptSegments = <int, Uint8List>{};
}

class _QuantizationParseResult {
  _QuantizationParseResult({
    required this.params,
    required this.segmentValues,
    required this.offset,
  });

  final StdDequantizerParams params;
  final List<List<int>> segmentValues;
  final int offset;
}

/// Partial port of JJ2000's `HeaderDecoder`.
///
/// The real implementation parses JPEG 2000 main and tile-part headers to
/// populate [HeaderInfo] and [DecoderSpecs]. For now we model the data the
/// rest of the pipeline expects while leaving TODO markers where parsing
/// logic must be restored.
class HeaderDecoder {
  static const String _logSource = 'HeaderDecoder';
  static const int _maxSizLogs = 2;
  static const int _maxCodLogs = 4;
  static const int _maxQuantLogs = 6;
  static int _sizLogCount = 0;
  /// JJ2000 option prefix reserved for header decoder parameters.
  static const String optionPrefix = 'H';
  static int _codLogCount = 0;
  static int _quantLogCount = 0;
  static const int _allowedCodingStyleFlags =
      Markers.SCOX_PRECINCT_PARTITION |
      Markers.SCOX_USE_SOP |
      Markers.SCOX_USE_EPH |
      Markers.SCOX_HOR_CB_PART |
      Markers.SCOX_VER_CB_PART;

  static bool _isInstrumentationEnabled() => DecoderInstrumentation.isEnabled();

  static void _log(String message) {
    if (_isInstrumentationEnabled()) {
      DecoderInstrumentation.log(_logSource, message);
    }
  }

  /// Parses the main header of a JPEG 2000 codestream.
  ///
  /// The method assumes [input] is positioned at the beginning of a codestream
  /// (i.e. the next word corresponds to the SOC marker) and stops right before
  /// the first SOT marker. Only a subset of marker segments is handled for now
  /// (SIZ for geometry, POC/PPM when present); the remaining segments are
  /// skipped while preserving positional integrity so that downstream readers
  /// can revisit them once their ports are completed.
  static HeaderDecoder readMainHeader({
    required RandomAccessIO input,
    required HeaderInfo headerInfo,
  }) {
    final codestreamStart = input.getPos();
    final logger = FacilityManager.getMsgLogger();
    final soc = input.readUnsignedShort();
    if (soc != Markers.SOC) {
      throw StateError('Codestream does not start with SOC marker');
    }

    HeaderDecoder? decoder;
    var mainHeaderDone = false;

    while (!mainHeaderDone) {
      final positionBeforeMarker = input.getPos();
      final marker = input.readUnsignedShort();

      switch (marker) {
        case Markers.SIZ:
          final payload = _readMarkerPayload(input);
          final siz = _parseSizMarker(payload, headerInfo);
          final numTiles = siz.getNumTiles();
          final numComps = siz.csiz;
          final specs = DecoderSpecs.basic(numTiles, numComps);
          decoder = HeaderDecoder(
            decSpec: specs,
            headerInfo: headerInfo,
            numComps: numComps,
            imgWidth: siz.xsiz - siz.x0siz,
            imgHeight: siz.ysiz - siz.y0siz,
            imgULX: siz.x0siz,
            imgULY: siz.y0siz,
            nomTileWidth: siz.xtsiz,
            nomTileHeight: siz.ytsiz,
            cbULX: 0,
            cbULY: 0,
            compSubsX: siz.xrsiz,
            compSubsY: siz.yrsiz,
            maxCompImgWidth: siz.getMaxCompWidth(),
            maxCompImgHeight: siz.getMaxCompHeight(),
            tilingOrigin: Coord(siz.xt0siz, siz.yt0siz),
          );
          break;
        case Markers.POC:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('POC marker encountered before SIZ');
          }
          target.parsePocMarker(
            payload,
            isMainHeader: true,
            tileIdx: 0,
          );
          break;
        case Markers.COD:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('COD marker encountered before SIZ');
          }
          target.parseCodMarker(
            payload,
            isMainHeader: true,
            tileIdx: 0,
          );
          break;
        case Markers.COC:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('COC marker encountered before SIZ');
          }
          target.parseCocMarker(
            payload,
            isMainHeader: true,
            tileIdx: 0,
          );
          break;
        case Markers.QCD:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('QCD marker encountered before SIZ');
          }
          target.parseQcdMarker(
            payload,
            isMainHeader: true,
            tileIdx: 0,
          );
          break;
        case Markers.QCC:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('QCC marker encountered before SIZ');
          }
          target.parseQccMarker(
            payload,
            isMainHeader: true,
            tileIdx: 0,
          );
          break;
        case Markers.PPM:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('PPM marker encountered before SIZ');
          }
          target.parsePpmMarker(payload);
          break;
        case Markers.TLM:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('TLM marker encountered before SIZ');
          }
          target.parseTlmMarker(payload);
          break;
        case Markers.RGN:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('RGN marker encountered before SIZ');
          }
          target.parseRgnMarker(
            payload,
            isMainHeader: true,
            tileIdx: 0,
          );
          break;
        case Markers.COM:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('COM marker encountered before SIZ');
          }
          target.parseComMarker(payload);
          break;
        case Markers.CRG:
          final payload = _readMarkerPayload(input);
          final target = decoder;
          if (target == null) {
            throw StateError('CRG marker encountered before SIZ');
          }
          target.parseCrgMarker(payload);
          break;
        case Markers.SOT:
          final target = decoder;
          if (target == null) {
            throw StateError('SOT marker encountered before SIZ');
          }
          input.seek(positionBeforeMarker);
          mainHeaderDone = true;
          break;
        default:
          _skipUnknownMarker(input, marker, logger);
          break;
      }
    }

    final result = decoder;
    if (result == null) {
      throw StateError('Main header parsing did not produce a HeaderDecoder');
    }
    result._codestreamStart = codestreamStart;
    result._mainHeaderLength = input.getPos() - codestreamStart;
    return result;
  }

  HeaderDecoder({
    required this.decSpec,
    required this.headerInfo,
    required this.numComps,
    required this.imgWidth,
    required this.imgHeight,
    required this.imgULX,
    required this.imgULY,
    required this.nomTileWidth,
    required this.nomTileHeight,
    required this.cbULX,
    required this.cbULY,
    required List<int> compSubsX,
    required List<int> compSubsY,
    required this.maxCompImgWidth,
    required this.maxCompImgHeight,
    required Coord tilingOrigin,
    bool precinctPartitionUsed = false,
  })  : compSubsX = List<int>.unmodifiable(compSubsX),
        compSubsY = List<int>.unmodifiable(compSubsY),
        tilingOrigin = Coord.copy(tilingOrigin),
        precinctPartitionFlag = precinctPartitionUsed;

  /// Convenience constructor for tests or provisional call sites.
  ///
  /// All geometry fields default to zero while preserving the provided
  /// component count and sub-sampling factors. Real parsing code should avoid
  /// this path.
  HeaderDecoder.placeholder({
    required this.decSpec,
    required this.headerInfo,
    required this.numComps,
    List<int>? compSubsX,
    List<int>? compSubsY,
  })  : imgWidth = 0,
        imgHeight = 0,
        imgULX = 0,
        imgULY = 0,
        nomTileWidth = 0,
        nomTileHeight = 0,
        cbULX = 0,
        cbULY = 0,
        maxCompImgWidth = 0,
        maxCompImgHeight = 0,
        tilingOrigin = Coord(0, 0),
        precinctPartitionFlag = false,
        compSubsX =
            List<int>.unmodifiable(compSubsX ?? List<int>.filled(numComps, 1)),
        compSubsY =
            List<int>.unmodifiable(compSubsY ?? List<int>.filled(numComps, 1));

  final HeaderInfo headerInfo;
  final int numComps;
  final int imgWidth;
  final int imgHeight;
  final int imgULX;
  final int imgULY;
  final int nomTileWidth;
  final int nomTileHeight;
  int cbULX;
  int cbULY;
  final List<int> compSubsX;
  final List<int> compSubsY;
  final int maxCompImgWidth;
  final int maxCompImgHeight;
  final Coord tilingOrigin;
  bool precinctPartitionFlag;
  final DecoderSpecs decSpec;
  int _codestreamStart = 0;
  int _mainHeaderLength = 0;
  bool _cbULXDefined = false;
  bool _cbULYDefined = false;

  /// Number of tile-parts per tile. Populated by the codestream reader.
  List<int> nTileParts = <int>[];

  final Map<int, Map<int, _TilePartInfo>> _tilePartInfo =
      <int, Map<int, _TilePartInfo>>{};
  final Map<int, Uint8List> _packedHeaders = <int, Uint8List>{};
  final List<Uint8List?> _ppmMarkerData = <Uint8List?>[];
  final List<int> _tilePartTiles = <int>[];
  bool _packedHeadersDirty = false;
  bool _ppmSeen = false;

  int get codestreamStart => _codestreamStart;
  int get mainHeaderLength => _mainHeaderLength;

  int getNumComps() => numComps;
  int getImgWidth() => imgWidth;
  int getImgHeight() => imgHeight;
  int getImgULX() => imgULX;
  int getImgULY() => imgULY;
  int getNomTileWidth() => nomTileWidth;
  int getNomTileHeight() => nomTileHeight;
  int getCbULX() => cbULX;
  int getCbULY() => cbULY;

  int getCompSubsX(int comp) => comp < compSubsX.length ? compSubsX[comp] : 1;
  int getCompSubsY(int comp) => comp < compSubsY.length ? compSubsY[comp] : 1;

  int getMaxCompImgWidth() => maxCompImgWidth;
  int getMaxCompImgHeight() => maxCompImgHeight;

  Coord getTilingOrigin(Coord? reuse) {
    if (reuse != null) {
      reuse
        ..x = tilingOrigin.x
        ..y = tilingOrigin.y;
      return reuse;
    }
    return Coord(tilingOrigin.x, tilingOrigin.y);
  }

  bool precinctPartitionUsed() => precinctPartitionFlag;

  int _currentTile = -1;

  int get currentTile => _currentTile;

  void _applyCodeBlockPartitionOrigin({
    required int scod,
    required bool isMainHeader,
    required int tileIdx,
  }) {
    if ((scod & (Markers.SCOX_HOR_CB_PART | Markers.SCOX_VER_CB_PART)) != 0) {
      FacilityManager.getMsgLogger().printmsg(
        MsgLogger.warning,
        'Code-block partition origin different from (0,0). This requires JPEG 2000 Part 2 support and may not be supported by all decoders.',
      );
    }

    final contextLabel = isMainHeader ? 'main header' : 'tile $tileIdx';
    final newCbULX = (scod & Markers.SCOX_HOR_CB_PART) != 0 ? 1 : 0;
    if (_cbULXDefined && cbULX != newCbULX) {
      throw StateError(
        'Code-block partition origin redefined in $contextLabel COD marker (expected $cbULX, got $newCbULX).',
      );
    }
    cbULX = newCbULX;
    _cbULXDefined = true;

    final newCbULY = (scod & Markers.SCOX_VER_CB_PART) != 0 ? 1 : 0;
    if (_cbULYDefined && cbULY != newCbULY) {
      throw StateError(
        'Code-block partition origin redefined in $contextLabel COD marker (expected $cbULY, got $newCbULY).',
      );
    }
    cbULY = newCbULY;
    _cbULYDefined = true;
  }

  List<List<SynWTFilter>> _buildWaveletFilterSpec(int filterId) {
    final filter = _instantiateWaveletFilter(filterId);
    final filters = List<SynWTFilter>.unmodifiable(<SynWTFilter>[filter]);
    return List<List<SynWTFilter>>.unmodifiable(<List<SynWTFilter>>[
      filters,
      filters,
    ]);
  }

  SynWTFilter _instantiateWaveletFilter(int filterId) {
    if (filterId >= (1 << 7)) {
      throw UnsupportedError(
        'Custom wavelet filters (id=$filterId) are not supported yet',
      );
    }
    switch (filterId) {
      case FilterTypes.W9X7:
        return SynWTFilterFloatLift9x7();
      case FilterTypes.W5X3:
        return SynWTFilterIntLift5x3();
      default:
        throw StateError(
          'Wavelet filter id=$filterId is not JPEG 2000 Part 1 compliant',
        );
    }
  }

  void beginTile(int tileIdx) {
    _currentTile = tileIdx;
  }

  void parseCodMarker(
    Uint8List markerPayload, {
    required bool isMainHeader,
    required int tileIdx,
  }) {
    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final length = view.getUint16(0);
    if (length < 12) {
      throw StateError('COD marker too short: $length bytes');
    }

    var offset = 2;
    final scod = view.getUint8(offset++);
    _validateCodingStyleFlags(scod, 'COD marker');
    final sgcodPo = view.getUint8(offset++);
    _validateProgressionOrder(sgcodPo, 'COD marker');
    final sgcodNl = view.getUint16(offset);
    offset += 2;
    _validateLayerCount(sgcodNl);
    final sgcodMct = view.getUint8(offset++);
    _validateMctUsage(sgcodMct, 'COD marker');
    final spcodNdl = view.getUint8(offset++);
    _validateDecompositionLevels(spcodNdl);
    final spcodCw = view.getUint8(offset++);
    final spcodCh = view.getUint8(offset++);
    final spcodCs = view.getUint8(offset++);
    _validateEntropyOptions(spcodCs, 'COD marker');
    final spcodT = view.getUint8(offset++);

    final usesPrecinctPartition =
        (scod & Markers.SCOX_PRECINCT_PARTITION) != 0;
    List<int>? precinctSpec;
    if (usesPrecinctPartition) {
      precinctSpec = <int>[];
      final expected = spcodNdl + 1;
      for (var i = 0; i < expected; i++) {
        if (offset >= markerPayload.length) {
          throw StateError('COD marker precinct data truncated');
        }
        precinctSpec.add(view.getUint8(offset++));
      }
    }

    final key = isMainHeader ? 'main' : 't$tileIdx';
    final cod = headerInfo.getNewCOD()
      ..lcod = length
      ..scod = scod
      ..sgcodPo = sgcodPo
      ..sgcodNl = sgcodNl
      ..sgcodMct = sgcodMct
      ..spcodNdl = spcodNdl
      ..spcodCw = spcodCw
      ..spcodCh = spcodCh
      ..spcodCs = spcodCs
      ..spcodT = <int>[spcodT]
      ..spcodPs = precinctSpec;
    headerInfo.cod[key] = cod;

    final cblkWidth = 1 << (spcodCw + 2);
    final cblkHeight = 1 << (spcodCh + 2);
    _validateCodeBlockDimensions(
      width: cblkWidth,
      height: cblkHeight,
      markerLabel: 'COD marker',
    );
    final cblkSize = List<int>.unmodifiable(<int>[cblkWidth, cblkHeight]);

    _applyCodeBlockPartitionOrigin(
      scod: scod,
      isMainHeader: isMainHeader,
      tileIdx: tileIdx,
    );

    final waveletFilters = _buildWaveletFilterSpec(spcodT);
    if (isMainHeader) {
      decSpec.wfs.setDefault(waveletFilters);
    } else {
      decSpec.wfs.setTileDef(tileIdx, waveletFilters);
    }

    if (isMainHeader) {
      decSpec.nls.setDefault(sgcodNl);
      decSpec.pos.setDefault(sgcodPo);
      decSpec.dls.setDefault(spcodNdl);
      decSpec.cblks.setDefault(cblkSize);
      decSpec.ecopts.setDefault(spcodCs);
      decSpec.sops.setDefault((scod & Markers.SCOX_USE_SOP) != 0);
      decSpec.ephs.setDefault((scod & Markers.SCOX_USE_EPH) != 0);
    } else {
      decSpec.nls.setTileDef(tileIdx, sgcodNl);
      decSpec.pos.setTileDef(tileIdx, sgcodPo);
      decSpec.dls.setTileDef(tileIdx, spcodNdl);
      decSpec.cblks.setTileDef(tileIdx, cblkSize);
      decSpec.ecopts.setTileDef(tileIdx, spcodCs);
      decSpec.sops.setTileDef(tileIdx, (scod & Markers.SCOX_USE_SOP) != 0);
      decSpec.ephs.setTileDef(tileIdx, (scod & Markers.SCOX_USE_EPH) != 0);
    }

    _logCodSummary(
      contextLabel: isMainHeader ? 'main' : 'tile=$tileIdx',
      scod: scod,
      progression: sgcodPo,
      layers: sgcodNl,
      decompLevels: spcodNdl,
      cblkWidthExp: spcodCw,
      cblkHeightExp: spcodCh,
      filterId: spcodT,
      precincts: precinctSpec,
    );

    final precinctValue = _buildPrecinctValue(precinctSpec);
    if (isMainHeader) {
      decSpec.pss.setDefault(precinctValue);
    } else {
      decSpec.pss.setTileDef(tileIdx, precinctValue);
    }
    if (usesPrecinctPartition) {
      precinctPartitionFlag = true;
    }

    final componentTransform = _selectComponentTransform(sgcodMct, spcodT);
    if (isMainHeader) {
      decSpec.cts.setDefault(componentTransform);
    } else {
      decSpec.cts.setTileDef(tileIdx, componentTransform);
    }
  }

  void parseTilePartHeader(
    RandomAccessIO input, {
    required HeaderInfoSOT sot,
  }) {
    beginTile(sot.isot);

    var headerDone = false;
    while (!headerDone) {
      final marker = input.readUnsignedShort();
      switch (marker) {
        case Markers.COD:
          parseCodMarker(
            _readMarkerPayload(input),
            isMainHeader: false,
            tileIdx: sot.isot,
          );
          break;
        case Markers.COC:
          parseCocMarker(
            _readMarkerPayload(input),
            isMainHeader: false,
            tileIdx: sot.isot,
          );
          break;
        case Markers.QCD:
          parseQcdMarker(
            _readMarkerPayload(input),
            isMainHeader: false,
            tileIdx: sot.isot,
          );
          break;
        case Markers.QCC:
          parseQccMarker(
            _readMarkerPayload(input),
            isMainHeader: false,
            tileIdx: sot.isot,
          );
          break;
        case Markers.POC:
          parsePocMarker(
            _readMarkerPayload(input),
            isMainHeader: false,
            tileIdx: sot.isot,
            tilePartIdx: sot.tpsot,
          );
          break;
        case Markers.PPT:
          FacilityManager.getMsgLogger().printmsg(
            MsgLogger.info,
            'Parsed PPT marker for tile=${sot.isot} part=${sot.tpsot}',
          );
          parsePptMarker(
            _readMarkerPayload(input),
            tileIdx: sot.isot,
            tilePartIdx: sot.tpsot,
          );
          break;
        case Markers.RGN:
          parseRgnMarker(
            _readMarkerPayload(input),
            isMainHeader: false,
            tileIdx: sot.isot,
          );
          break;
        case Markers.COM:
          parseComMarker(_readMarkerPayload(input));
          break;
        case Markers.SOD:
          headerDone = true;
          input.seek(input.getPos() - 2);
          break;
        case Markers.EOC:
          headerDone = true;
          input.seek(input.getPos() - 2);
          break;
        default:
          _skipUnknownMarker(input, marker, FacilityManager.getMsgLogger());
          break;
      }
    }
  }

  HeaderInfoSOT parseNextTilePart(
    RandomAccessIO input, {
    bool registerTileOrder = true,
  }) {
    while (true) {
      if (input.getPos() + 2 > input.length()) {
        throw StateError(
            'Unexpected end of codestream while searching for tile-part header');
      }
      final marker = input.readUnsignedShort();
      switch (marker) {
        case Markers.SOT:
          final sotStart = input.getPos() - 2;
          final payload = _readMarkerPayload(input);
          final view = ByteData.view(
            payload.buffer,
            payload.offsetInBytes,
            payload.lengthInBytes,
          );
          final tileIdx = view.getUint16(2);
          final tilePartIdx = view.getUint8(8);

          parseSotMarker(payload);
          if (registerTileOrder) {
            setTileOfTileParts(tileIdx);
          }

          final sotKey = 't${tileIdx}_tp$tilePartIdx';
          final sot = headerInfo.sot[sotKey];
          if (sot == null) {
            throw StateError(
                'Parsed SOT for tile=$tileIdx part=$tilePartIdx but metadata missing');
          }

          parseTilePartHeader(input, sot: sot);

          if (input.getPos() + 2 > input.length()) {
            throw StateError(
                'Unexpected end of codestream while expecting SOD marker');
          }
          final sodMarker = input.readUnsignedShort();
          if (sodMarker != Markers.SOD) {
            throw StateError(
              'Expected SOD marker after tile-part header, found 0x${sodMarker.toRadixString(16)}',
            );
          }

          final dataOffset = input.getPos();
          registerTilePartDataOffset(sot.isot, sot.tpsot, dataOffset);
          final headerBytes = dataOffset - sotStart;
          registerTilePartHeaderLength(sot.isot, sot.tpsot, headerBytes);
          if (sot.psot != 0) {
            final bodyLength = sot.psot - headerBytes;
            registerTilePartBodyLength(sot.isot, sot.tpsot, bodyLength);
          }

          return sot;
        case Markers.EOC:
          throw StateError(
              'Reached end of codestream before encountering tile-part header');
        default:
          _skipUnknownMarker(input, marker, FacilityManager.getMsgLogger());
          break;
      }
    }
  }

  void parseCocMarker(
    Uint8List markerPayload, {
    required bool isMainHeader,
    required int tileIdx,
  }) {
    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final length = view.getUint16(0);
    if (length < 6) {
      throw StateError('COC marker too short: $length bytes');
    }
    if (length > markerPayload.length) {
      throw StateError('COC marker length exceeds payload size');
    }

    var offset = 2;
    final component =
        numComps < 257 ? view.getUint8(offset++) : view.getUint16(offset);
    if (numComps >= 257) {
      offset += 2;
    }
    if (component < 0 || component >= numComps) {
      throw StateError('COC marker references invalid component $component');
    }

    final scoc = view.getUint8(offset++);
    _validateCodingStyleFlags(scoc, 'COC marker');
    final usesPrecinctPartition = (scoc & Markers.SCOX_PRECINCT_PARTITION) != 0;
    final spcocNdl = view.getUint8(offset++);
    _validateDecompositionLevels(spcocNdl);
    final spcocCw = view.getUint8(offset++);
    final spcocCh = view.getUint8(offset++);
    final spcocCs = view.getUint8(offset++);
    _validateEntropyOptions(spcocCs, 'COC marker');
    if (offset >= length) {
      throw StateError('COC marker missing transform specification');
    }
    final spcocT = view.getUint8(offset++);

    List<int>? precinctSpec;
    if (usesPrecinctPartition) {
      precinctSpec = <int>[];
      final expected = spcocNdl + 1;
      for (var i = 0; i < expected; i++) {
        if (offset >= markerPayload.length) {
          throw StateError('COC marker precinct data truncated');
        }
        precinctSpec.add(view.getUint8(offset++));
      }
    }

    if (offset != length) {
      throw StateError('Unexpected padding bytes at end of COC marker');
    }

    final key = isMainHeader ? 'main_c$component' : 't${tileIdx}_c$component';
    final coc = headerInfo.getNewCOC()
      ..lcoc = length
      ..ccoc = component
      ..scoc = scoc
      ..spcocNdl = spcocNdl
      ..spcocCw = spcocCw
      ..spcocCh = spcocCh
      ..spcocCs = spcocCs
      ..spcocT = <int>[spcocT]
      ..spcocPs = precinctSpec;
    headerInfo.coc[key] = coc;

    final cblkWidth = 1 << (spcocCw + 2);
    final cblkHeight = 1 << (spcocCh + 2);
    _validateCodeBlockDimensions(
      width: cblkWidth,
      height: cblkHeight,
      markerLabel: 'COC marker',
    );
    final cblkSizes = List<int>.unmodifiable(<int>[cblkWidth, cblkHeight]);
    if (isMainHeader) {
      decSpec.cblks.setCompDef(component, cblkSizes);
      decSpec.dls.setCompDef(component, spcocNdl);
      decSpec.ecopts.setCompDef(component, spcocCs);
      decSpec.wfs.setCompDef(component, _buildWaveletFilterSpec(spcocT));
    } else {
      decSpec.cblks.setTileCompVal(tileIdx, component, cblkSizes);
      decSpec.dls.setTileCompVal(tileIdx, component, spcocNdl);
      decSpec.ecopts.setTileCompVal(tileIdx, component, spcocCs);
      decSpec.wfs
          .setTileCompVal(tileIdx, component, _buildWaveletFilterSpec(spcocT));
    }

    final precinctValue = _buildPrecinctValue(precinctSpec);
    if (isMainHeader) {
      decSpec.pss.setCompDef(component, precinctValue);
    } else {
      decSpec.pss.setTileCompVal(tileIdx, component, precinctValue);
    }
    if (usesPrecinctPartition) {
      precinctPartitionFlag = true;
    }
  }

  void parseQcdMarker(
    Uint8List markerPayload, {
    required bool isMainHeader,
    required int tileIdx,
  }) {
    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final length = view.getUint16(0);
    if (length < 3) {
      throw StateError('QCD marker too short: $length bytes');
    }
    if (length > markerPayload.length) {
      throw StateError('QCD marker length exceeds payload size');
    }

    var offset = 2;
    final sqcd = view.getUint8(offset++);
    final guardBits = (sqcd >> Markers.SQCX_GB_SHIFT) & Markers.SQCX_GB_MSK;
    final qType = sqcd & ~(Markers.SQCX_GB_MSK << Markers.SQCX_GB_SHIFT);

    final result = _parseQuantizationTables(
      view: view,
      offset: offset,
      limit: length,
      qType: qType,
    );
    offset = result.offset;
    if (offset != length) {
      throw StateError('Unexpected padding bytes at end of QCD marker');
    }

    final qcd = headerInfo.getNewQCD()
      ..lqcd = length
      ..sqcd = sqcd
      ..spqcd = result.segmentValues;

    final key = isMainHeader ? 'main' : 't$tileIdx';
    headerInfo.qcd[key] = qcd;

    final label = _quantizationTypeLabel(qType);
    if (isMainHeader) {
      decSpec.qts.setDefault(label);
      decSpec.qsss.setDefault(result.params);
      decSpec.gbs.setDefault(guardBits);
    } else {
      decSpec.qts.setTileDef(tileIdx, label);
      decSpec.qsss.setTileDef(tileIdx, result.params);
      decSpec.gbs.setTileDef(tileIdx, guardBits);
    }

    _logQuantSummary(
      contextLabel: isMainHeader ? 'main' : 'tile=$tileIdx',
      guardBits: guardBits,
      qType: qType,
      params: result.params,
    );
  }

  void parseQccMarker(
    Uint8List markerPayload, {
    required bool isMainHeader,
    required int tileIdx,
  }) {
    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final length = view.getUint16(0);
    if (length < 4) {
      throw StateError('QCC marker too short: $length bytes');
    }
    if (length > markerPayload.length) {
      throw StateError('QCC marker length exceeds payload size');
    }

    var offset = 2;
    final component =
        numComps < 257 ? view.getUint8(offset++) : view.getUint16(offset);
    if (numComps >= 257) {
      offset += 2;
    }
    if (component < 0 || component >= numComps) {
      throw StateError('QCC marker references invalid component $component');
    }

    final sqcc = view.getUint8(offset++);
    final guardBits = (sqcc >> Markers.SQCX_GB_SHIFT) & Markers.SQCX_GB_MSK;
    final qType = sqcc & ~(Markers.SQCX_GB_MSK << Markers.SQCX_GB_SHIFT);

    final result = _parseQuantizationTables(
      view: view,
      offset: offset,
      limit: length,
      qType: qType,
    );
    offset = result.offset;
    if (offset != length) {
      throw StateError('Unexpected padding bytes at end of QCC marker');
    }

    final qcc = headerInfo.getNewQCC()
      ..lqcc = length
      ..cqcc = component
      ..sqcc = sqcc
      ..spqcc = result.segmentValues;

    final key = isMainHeader ? 'main_c$component' : 't${tileIdx}_c$component';
    headerInfo.qcc[key] = qcc;

    final label = _quantizationTypeLabel(qType);
    if (isMainHeader) {
      decSpec.qts.setCompDef(component, label);
      decSpec.qsss.setCompDef(component, result.params);
      decSpec.gbs.setCompDef(component, guardBits);
    } else {
      decSpec.qts.setTileCompVal(tileIdx, component, label);
      decSpec.qsss.setTileCompVal(tileIdx, component, result.params);
      decSpec.gbs.setTileCompVal(tileIdx, component, guardBits);
    }

    final contextLabel =
        isMainHeader ? 'main:c$component' : 'tile=$tileIdx:c$component';
    _logQuantSummary(
      contextLabel: contextLabel,
      guardBits: guardBits,
      qType: qType,
      params: result.params,
    );
  }

  int _selectComponentTransform(int sgcodMct, int spcodT) {
    if (sgcodMct == 0) {
      return InvCompTransf.none;
    }
    return spcodT == FilterTypes.W5X3
        ? InvCompTransf.invRct
        : InvCompTransf.invIct;
  }

  static void _validateLayerCount(int layers) {
    if (layers <= 0 || layers > 65535) {
      throw StateError('Number of layers out of range (1..65535): $layers');
    }
  }

  static void _validateProgressionOrder(int order, String markerLabel) {
    if (order < 0 || order > 4) {
      throw StateError('Unsupported progression order in $markerLabel: $order');
    }
  }

  static void _validateMctUsage(int mct, String markerLabel) {
    if (mct != 0 && mct != 1) {
      throw StateError('Unsupported multi-component transform flag in '
          '$markerLabel: $mct');
    }
  }

  static void _validateDecompositionLevels(int levels) {
    if (levels > 32) {
      throw StateError('Number of decomposition levels out of range (max 32): $levels');
    }
  }

  static void _validateCodingStyleFlags(int flags, String markerLabel) {
    if ((flags & ~_allowedCodingStyleFlags) != 0) {
      throw StateError(
        'Unsupported coding style flags in $markerLabel: 0x'
        '${flags.toRadixString(16)}',
      );
    }
  }

  static void _validateCodeBlockDimensions({
    required int width,
    required int height,
    required String markerLabel,
  }) {
    if (width < StdEntropyCoderOptions.MIN_CB_DIM ||
        width > StdEntropyCoderOptions.MAX_CB_DIM) {
      throw StateError(
        'Non-valid code-block width in $markerLabel: $width (expected '
        '${StdEntropyCoderOptions.MIN_CB_DIM}..${StdEntropyCoderOptions.MAX_CB_DIM}).',
      );
    }
    if (height < StdEntropyCoderOptions.MIN_CB_DIM ||
        height > StdEntropyCoderOptions.MAX_CB_DIM) {
      throw StateError(
        'Non-valid code-block height in $markerLabel: $height (expected '
        '${StdEntropyCoderOptions.MIN_CB_DIM}..${StdEntropyCoderOptions.MAX_CB_DIM}).',
      );
    }
  }

  static void _validateEntropyOptions(int options, String markerLabel) {
    const allowedOptions =
        StdEntropyCoderOptions.OPT_BYPASS |
        StdEntropyCoderOptions.OPT_RESET_MQ |
        StdEntropyCoderOptions.OPT_TERM_PASS |
        StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL |
        StdEntropyCoderOptions.OPT_PRED_TERM |
        StdEntropyCoderOptions.OPT_SEG_SYMBOLS;
    if ((options & ~allowedOptions) != 0) {
      throw StateError(
        'Unknown code-block style flags in $markerLabel: 0x'
        '${options.toRadixString(16)}',
      );
    }
  }

  static List<List<int>> _buildPrecinctValue(List<int>? packedPrecincts) {
    if (packedPrecincts == null || packedPrecincts.isEmpty) {
      final defaultSize = Markers.PRECINCT_PARTITION_DEF_SIZE;
      return _wrapPrecinctLists(<int>[defaultSize], <int>[defaultSize]);
    }
    final widths = <int>[];
    final heights = <int>[];
    for (final packed in packedPrecincts) {
      widths.add(1 << (packed & 0x0f));
      heights.add(1 << ((packed >> 4) & 0x0f));
    }
    return _wrapPrecinctLists(widths, heights);
  }

  static List<List<int>> _wrapPrecinctLists(
    List<int> widths,
    List<int> heights,
  ) {
    return List<List<int>>.unmodifiable(
      <List<int>>[
        List<int>.unmodifiable(widths),
        List<int>.unmodifiable(heights),
      ],
    );
  }

  _QuantizationParseResult _parseQuantizationTables({
    required ByteData view,
    required int offset,
    required int limit,
    required int qType,
  }) {
    if (offset > limit) {
      throw StateError('Invalid offset while parsing quantization tables');
    }

    final bytesPerEntry = qType == Markers.SQCX_NO_QUANTIZATION ? 1 : 2;
    final available = limit - offset;
    if (available < bytesPerEntry) {
      throw StateError('Quantization marker missing step size entries');
    }
    if (available % bytesPerEntry != 0) {
      throw StateError('Quantization marker has misaligned step size data');
    }

    final totalEntries = available ~/ bytesPerEntry;
    if (totalEntries == 0) {
      throw StateError('Quantization marker must contain at least one entry');
    }
    if (qType == Markers.SQCX_SCALAR_DERIVED && totalEntries != 1) {
      throw StateError('Derived quantization expects a single step size entry');
    }

    final maxrl = totalEntries == 1 ? 0 : (totalEntries - 1) ~/ 3;
    if (qType != Markers.SQCX_SCALAR_DERIVED) {
      final expected = 1 + maxrl * 3;
      if (expected != totalEntries) {
        throw StateError(
          'Quantization marker encodes $totalEntries entries but expected $expected',
        );
      }
    }

    final expTable = List<List<int>>.generate(
      maxrl + 1,
      (_) => List<int>.filled(4, 0, growable: false),
      growable: false,
    );
    final segmentValues = List<List<int>>.generate(
      maxrl + 1,
      (_) => List<int>.filled(4, 0, growable: false),
      growable: false,
    );
    List<List<double>>? steps;
    if (qType != Markers.SQCX_NO_QUANTIZATION) {
      steps = List<List<double>>.generate(
        maxrl + 1,
        (_) => List<double>.filled(4, 0.0, growable: false),
        growable: false,
      );
    }

    var current = offset;
    for (var rl = 0; rl <= maxrl; rl++) {
      final startBand = rl == 0 ? 0 : 1;
      final endBand = rl == 0 ? 0 : 3;
      for (var band = startBand; band <= endBand; band++) {
        if (qType == Markers.SQCX_NO_QUANTIZATION) {
          if (current >= limit) {
            throw StateError('Unexpected end of data while parsing QCD/QCC');
          }
          final raw = view.getUint8(current++);
          segmentValues[rl][band] = raw;
          expTable[rl][band] =
              (raw >> Markers.SQCX_EXP_SHIFT) & Markers.SQCX_EXP_MASK;
        } else {
          if (current + 2 > limit) {
            throw StateError('Unexpected end of data while parsing QCD/QCC');
          }
          final raw = view.getUint16(current);
          current += 2;
          segmentValues[rl][band] = raw;
          final exponent = (raw >> 11) & 0x1f;
          expTable[rl][band] = exponent;
          final mantissa = raw & 0x07ff;
          final denominator = 1 << exponent;
          final step = (1.0 + mantissa / 2048.0) / denominator;
          steps![rl][band] = step;
        }
      }
    }

    return _QuantizationParseResult(
      params: StdDequantizerParams(
        exp: expTable,
        nStep: steps,
      ),
      segmentValues: segmentValues,
      offset: current,
    );
  }

  String _quantizationTypeLabel(int qType) {
    switch (qType) {
      case Markers.SQCX_NO_QUANTIZATION:
        return 'reversible';
      case Markers.SQCX_SCALAR_DERIVED:
        return 'derived';
      case Markers.SQCX_SCALAR_EXPOUNDED:
        return 'expounded';
      default:
        throw StateError('Unsupported quantization type: $qType');
    }
  }

  // TODO(jj2000): Port the full header parsing logic, populating DecoderSpecs
  // and HeaderInfo from a RandomAccessIO source.

  void parsePocMarker(
    Uint8List markerPayload, {
    required bool isMainHeader,
    required int tileIdx,
    int tilePartIdx = 0,
  }) {
    if (markerPayload.length < 2) {
      throw ArgumentError('POC marker payload too short');
    }

    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    var offset = 0;
    final lpoc = view.getUint16(offset);
    offset += 2;

    if (lpoc > markerPayload.length) {
      throw ArgumentError(
          'POC marker length $lpoc exceeds payload size ${markerPayload.length}');
    }

    final useShort = numComps >= 256;
    final changeStride = 5 + (useShort ? 4 : 2);
    if (changeStride <= 0 || lpoc < 2 || (lpoc - 2) % changeStride != 0) {
      throw ArgumentError(
          'Invalid POC marker length $lpoc for component count $numComps');
    }

    final newChanges = (lpoc - 2) ~/ changeStride;
    if (newChanges <= 0) {
      return;
    }

    final key = isMainHeader ? 'main' : 't$tileIdx';
    final existing = headerInfo.poc[key];
    var existingChanges = 0;
    List<int> prevRspoc = const <int>[];
    List<int> prevCspoc = const <int>[];
    List<int> prevLyepoc = const <int>[];
    List<int> prevRepoc = const <int>[];
    List<int> prevCepoc = const <int>[];
    List<int> prevPpoc = const <int>[];

    late final HeaderInfoPOC poc;
    if (existing != null && existing.rspoc.isNotEmpty) {
      existingChanges = existing.rspoc.length;
      prevRspoc = List<int>.from(existing.rspoc);
      prevCspoc = List<int>.from(existing.cspoc);
      prevLyepoc = List<int>.from(existing.lyepoc);
      prevRepoc = List<int>.from(existing.repoc);
      prevCepoc = List<int>.from(existing.cepoc);
      prevPpoc = List<int>.from(existing.ppoc);
      poc = existing;
    } else {
      poc = headerInfo.getNewPOC();
    }

    final totalChanges = existingChanges + newChanges;
    poc
      ..lpoc = lpoc
      ..rspoc = List<int>.filled(totalChanges, 0, growable: false)
      ..cspoc = List<int>.filled(totalChanges, 0, growable: false)
      ..lyepoc = List<int>.filled(totalChanges, 0, growable: false)
      ..repoc = List<int>.filled(totalChanges, 0, growable: false)
      ..cepoc = List<int>.filled(totalChanges, 0, growable: false)
      ..ppoc = List<int>.filled(totalChanges, 0, growable: false);

    final segments = List<List<int>>.generate(
      totalChanges,
      (_) => List<int>.filled(6, 0, growable: false),
      growable: false,
    );

    for (var i = 0; i < existingChanges; i++) {
      segments[i][0] = prevRspoc[i];
      segments[i][1] = prevCspoc[i];
      segments[i][2] = prevLyepoc[i];
      segments[i][3] = prevRepoc[i];
      segments[i][4] = prevCepoc[i];
      segments[i][5] = prevPpoc[i];

      poc
        ..rspoc[i] = prevRspoc[i]
        ..cspoc[i] = prevCspoc[i]
        ..lyepoc[i] = prevLyepoc[i]
        ..repoc[i] = prevRepoc[i]
        ..cepoc[i] = prevCepoc[i]
        ..ppoc[i] = prevPpoc[i];
    }

    for (var idx = existingChanges; idx < totalChanges; idx++) {
      final rspoc = view.getUint8(offset);
      offset += 1;

      final cspoc = useShort ? view.getUint16(offset) : view.getUint8(offset);
      offset += useShort ? 2 : 1;

      final lyepoc = view.getUint16(offset);
      offset += 2;
      if (lyepoc < 1) {
        throw ArgumentError(
          'LYEpoc must be >= 1 in POC marker (tile=$tileIdx tile-part=$tilePartIdx change=${idx - existingChanges})',
        );
      }

      final repoc = view.getUint8(offset);
      offset += 1;
      if (repoc <= rspoc) {
        throw ArgumentError(
          'REpoc must be greater than RSpoc in POC marker (tile=$tileIdx tile-part=$tilePartIdx change=${idx - existingChanges})',
        );
      }

      final rawCepoc =
          useShort ? view.getUint16(offset) : view.getUint8(offset);
      offset += useShort ? 2 : 1;
      final cepoc = rawCepoc == 0 ? 0 : rawCepoc;
      if (cepoc <= cspoc) {
        throw ArgumentError(
          'CEpoc must be greater than CSpoc in POC marker (tile=$tileIdx tile-part=$tilePartIdx change=${idx - existingChanges})',
        );
      }

      final ppoc = view.getUint8(offset);
      offset += 1;

      segments[idx][0] = rspoc;
      segments[idx][1] = cspoc;
      segments[idx][2] = lyepoc;
      segments[idx][3] = repoc;
      segments[idx][4] = cepoc;
      segments[idx][5] = ppoc;

      poc
        ..rspoc[idx] = rspoc
        ..cspoc[idx] = cspoc
        ..lyepoc[idx] = lyepoc
        ..repoc[idx] = repoc
        ..cepoc[idx] = cepoc
        ..ppoc[idx] = ppoc;
    }

    if (isMainHeader) {
      headerInfo.poc['main'] = poc;
      decSpec.pcs.setDefault(segments);
    } else {
      headerInfo.poc['t$tileIdx'] = poc;
      decSpec.pcs.setTileDef(tileIdx, segments);
    }
  }

  void parseRgnMarker(
    Uint8List markerPayload, {
    required bool isMainHeader,
    required int tileIdx,
  }) {
    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final length = view.getUint16(0);
    if (length < 5) {
      throw StateError('RGN marker too short: $length bytes');
    }
    if (length > markerPayload.length) {
      throw StateError('RGN marker length exceeds payload size');
    }

    var offset = 2;
    final component =
        numComps < 257 ? view.getUint8(offset++) : view.getUint16(offset);
    if (numComps >= 257) {
      offset += 2;
    }
    if (component < 0 || component >= numComps) {
      throw StateError('RGN marker references invalid component $component');
    }

    final srgn = view.getUint8(offset++);
    final sprgn = view.getUint8(offset++);

    if (offset != length) {
      throw StateError('Unexpected padding bytes at end of RGN marker');
    }

    final rgn = headerInfo.getNewRGN()
      ..lrgn = length
      ..crgn = component
      ..srgn = srgn
      ..sprgn = sprgn;

    final key = isMainHeader ? 'main_c$component' : 't${tileIdx}_c$component';
    headerInfo.rgn[key] = rgn;

    if (srgn == Markers.SRGN_IMPLICIT) {
      _applyRoiShift(
        isMainHeader: isMainHeader,
        tileIdx: tileIdx,
        component: component,
        shift: sprgn,
      );
    } else {
      FacilityManager.getMsgLogger().printmsg(
        MsgLogger.warning,
        'Unsupported ROI style $srgn encountered for tile=$tileIdx component=$component',
      );
    }

    _log('Parsed RGN marker: comp=$component style=$srgn shift=$sprgn');
  }

  void _applyRoiShift({
    required bool isMainHeader,
    required int tileIdx,
    required int component,
    required int shift,
  }) {
    final rectSpec = decSpec.rectRois;
    if (isMainHeader) {
      decSpec.rois.setCompDef(component, shift);
      rectSpec?.setCompDef(component, null);
      return;
    }
    decSpec.rois.setTileCompVal(tileIdx, component, shift);
    rectSpec?.setTileCompVal(tileIdx, component, null);
  }

  void parseComMarker(Uint8List markerPayload) {
    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final length = view.getUint16(0);
    if (length < 4) {
      throw StateError('COM marker too short: $length bytes');
    }

    final rcom = view.getUint16(2);
    final dataLength = length - 4;
    final ccom = markerPayload.sublist(4, 4 + dataLength);

    final com = headerInfo.getNewCOM()
      ..lcom = length
      ..rcom = rcom
      ..ccom = Uint8List.fromList(ccom);

    final key = 'main_${headerInfo.numCOM - 1}';
    headerInfo.com[key] = com;

    _log('Parsed COM marker: reg=$rcom len=$dataLength');
  }

  void parseCrgMarker(Uint8List markerPayload) {
    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final length = view.getUint16(0);
    if (length < 6) {
      throw StateError('CRG marker too short: $length bytes');
    }

    final xcrg = <int>[];
    final ycrg = <int>[];
    var offset = 2;
    // CRG contains Xcrg, Ycrg for all components
    // But we should check if payload has enough data
    for (var i = 0; i < numComps; i++) {
      if (offset + 4 > length) {
        throw StateError('CRG marker truncated');
      }
      xcrg.add(view.getUint16(offset));
      offset += 2;
      ycrg.add(view.getUint16(offset));
      offset += 2;
    }

    final crg = headerInfo.getNewCRG()
      ..lcrg = length
      ..xcrg = xcrg
      ..ycrg = ycrg;

    headerInfo.crg = crg;
    _log('Parsed CRG marker');
  }

  void registerTilePartLength(int tileIdx, int tilePartIdx, int length) {
    if (tileIdx < 0 || tilePartIdx < 0) {
      throw ArgumentError(
          'Tile index and tile-part index must be non-negative');
    }
    final tileMap =
        _tilePartInfo.putIfAbsent(tileIdx, () => <int, _TilePartInfo>{});
    final info = tileMap.putIfAbsent(tilePartIdx, () => _TilePartInfo());
    info.length = length;

    while (nTileParts.length <= tileIdx) {
      nTileParts.add(0);
    }
    nTileParts[tileIdx] = math.max(nTileParts[tileIdx], tileMap.length);
    _packedHeadersDirty = true;
  }

  void registerTilePartDataOffset(int tileIdx, int tilePartIdx, int offset) {
    if (tileIdx < 0 || tilePartIdx < 0) {
      throw ArgumentError(
          'Tile index and tile-part index must be non-negative');
    }
    final tileMap =
        _tilePartInfo.putIfAbsent(tileIdx, () => <int, _TilePartInfo>{});
    final info = tileMap.putIfAbsent(tilePartIdx, () => _TilePartInfo());
    info.dataOffset = offset;
  }

  void registerTilePartBodyLength(
      int tileIdx, int tilePartIdx, int bodyLength) {
    if (tileIdx < 0 || tilePartIdx < 0) {
      throw ArgumentError(
          'Tile index and tile-part index must be non-negative');
    }
    final tileMap =
        _tilePartInfo.putIfAbsent(tileIdx, () => <int, _TilePartInfo>{});
    final info = tileMap.putIfAbsent(tilePartIdx, () => _TilePartInfo());
    info.bodyLength = math.max(0, bodyLength);
  }

  void registerTilePartHeaderLength(
      int tileIdx, int tilePartIdx, int headerLength) {
    if (tileIdx < 0 || tilePartIdx < 0) {
      throw ArgumentError(
          'Tile index and tile-part index must be non-negative');
    }
    final tileMap =
        _tilePartInfo.putIfAbsent(tileIdx, () => <int, _TilePartInfo>{});
    final info = tileMap.putIfAbsent(tilePartIdx, () => _TilePartInfo());
    info.headerLength = math.max(0, headerLength);
  }

  int? getTileTotalLength(int tileIdx) {
    final tileMap = _tilePartInfo[tileIdx];
    if (tileMap == null || tileMap.isEmpty) {
      return null;
    }
    var total = 0;
    for (final entry in tileMap.values) {
      final length = entry.length;
      if (length == null || length == 0) {
        return null;
      }
      total += length;
    }
    return total;
  }

  List<int>? getTilePartLengths(int tileIdx) {
    final tileMap = _tilePartInfo[tileIdx];
    if (tileMap == null || tileMap.isEmpty) {
      return null;
    }
    final ordered = tileMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final lengths = <int>[];
    for (final entry in ordered) {
      final length = entry.value.length;
      if (length == null) {
        return null;
      }
      lengths.add(length);
    }
    return lengths;
  }

  int? getTilePartDataOffset(int tileIdx, int tilePartIdx) {
    final tileMap = _tilePartInfo[tileIdx];
    if (tileMap == null) {
      return null;
    }
    return tileMap[tilePartIdx]?.dataOffset;
  }

  List<int>? getTilePartDataOffsets(int tileIdx) {
    final tileMap = _tilePartInfo[tileIdx];
    if (tileMap == null || tileMap.isEmpty) {
      return null;
    }
    final ordered = tileMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final offsets = <int>[];
    for (final entry in ordered) {
      final offset = entry.value.dataOffset;
      if (offset == null) {
        return null;
      }
      offsets.add(offset);
    }
    return offsets;
  }

  int? getTilePartBodyLength(int tileIdx, int tilePartIdx) {
    final tileMap = _tilePartInfo[tileIdx];
    if (tileMap == null) {
      return null;
    }
    final info = tileMap[tilePartIdx];
    if (info == null) {
      return null;
    }
    return info.bodyLength ?? info.length;
  }

  List<int>? getTilePartBodyLengths(int tileIdx) {
    final tileMap = _tilePartInfo[tileIdx];
    if (tileMap == null || tileMap.isEmpty) {
      return null;
    }
    final ordered = tileMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final lengths = <int>[];
    for (final entry in ordered) {
      final info = entry.value;
      final length = info.bodyLength ?? info.length;
      if (length == null) {
        return null;
      }
      lengths.add(length);
    }
    return lengths;
  }

  List<int>? getTilePartHeaderLengths(int tileIdx) {
    final tileMap = _tilePartInfo[tileIdx];
    if (tileMap == null || tileMap.isEmpty) {
      return null;
    }
    final ordered = tileMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final lengths = <int>[];
    for (final entry in ordered) {
      final headerLen = entry.value.headerLength;
      if (headerLen == null) {
        return null;
      }
      lengths.add(headerLen);
    }
    return lengths;
  }

  void registerPackedPacketHeaders(int tileIdx, Uint8List data) {
    if (tileIdx < 0) {
      throw ArgumentError('Tile index must be non-negative');
    }
    _packedHeaders[tileIdx] = Uint8List.fromList(data);
    decSpec.pphs.setTileDef(tileIdx, true);
  }

  Uint8List? getPackedPacketHeaders(int tileIdx) {
    _ensurePackedPacketHeadersResolved();
    final data = _packedHeaders[tileIdx];
    if (data == null) {
      return null;
    }
    return Uint8List.fromList(data);
  }

  void parseSotMarker(Uint8List markerPayload) {
    if (markerPayload.length < 10) {
      throw ArgumentError('SOT marker payload must be at least 10 bytes');
    }

    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final lsot = view.getUint16(0);
    if (lsot != 10) {
      throw ArgumentError('Invalid SOT marker length: $lsot');
    }

    final tileIdx = view.getUint16(2);
    final tilePartLength = view.getUint32(4);
    final tilePartIdx = view.getUint8(8);
    final declaredTileParts = view.getUint8(9);

    final sot = headerInfo.getNewSOT()
      ..lsot = lsot
      ..isot = tileIdx
      ..psot = tilePartLength
      ..tpsot = tilePartIdx
      ..tnsot = declaredTileParts;
    headerInfo.sot['t${tileIdx}_tp$tilePartIdx'] = sot;

    registerTilePartLength(tileIdx, tilePartIdx, tilePartLength);

    while (nTileParts.length <= tileIdx) {
      nTileParts.add(0);
    }
    if (declaredTileParts != 0) {
      nTileParts[tileIdx] = math.max(nTileParts[tileIdx], declaredTileParts);
    }

    _packedHeadersDirty = true;
  }

  void parseTlmMarker(Uint8List markerPayload) {
    if (markerPayload.length < 4) {
      throw ArgumentError('TLM marker payload must be at least 4 bytes');
    }

    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final ltlm = view.getUint16(0);
    if (ltlm < 4 || ltlm > markerPayload.length) {
      throw ArgumentError('Invalid TLM marker length: $ltlm');
    }

    final ztlm = view.getUint8(2);
    final stlm = view.getUint8(3);
    final tileIndexBytes = (stlm >> 4) & 0x3;
    if (tileIndexBytes == 3) {
      throw StateError('TLM marker uses unsupported tile index field width');
    }

    final tilePartLengthBytes = (((stlm >> 6) & 0x1) + 1) * 2;
    final entrySize = tileIndexBytes + tilePartLengthBytes;
    if (entrySize == 0) {
      throw StateError('Derived TLM entry size is zero');
    }

    final payloadBytes = ltlm - 4;
    if (payloadBytes <= 0 || payloadBytes % entrySize != 0) {
      throw StateError(
        'TLM marker length $ltlm is incompatible with entry size $entrySize',
      );
    }

    final entryCount = payloadBytes ~/ entrySize;
    if (entryCount == 0) {
      return;
    }

    final record =
        headerInfo.tlm.putIfAbsent(ztlm, () => headerInfo.getNewTLM());
    final startingIndex = record.entries.length;
    record
      ..ltlm = ltlm
      ..ztlm = ztlm
      ..stlm = stlm;

    var offset = 4;
    for (var i = 0; i < entryCount; i++) {
      final implicitIndex = startingIndex + i;
      final tileIndex = () {
        switch (tileIndexBytes) {
          case 0:
            return implicitIndex;
          case 1:
            if (offset + 1 > markerPayload.length) {
              throw StateError('TLM marker truncated while reading tile index');
            }
            final value = view.getUint8(offset);
            offset += 1;
            return value;
          case 2:
            if (offset + 2 > markerPayload.length) {
              throw StateError('TLM marker truncated while reading tile index');
            }
            final value = view.getUint16(offset);
            offset += 2;
            return value;
          default:
            throw StateError(
                'Unsupported tile index field length: $tileIndexBytes');
        }
      }();

      final tilePartLength = () {
        if (tilePartLengthBytes == 2) {
          if (offset + 2 > markerPayload.length) {
            throw StateError('TLM marker truncated while reading tile length');
          }
          final value = view.getUint16(offset);
          offset += 2;
          return value;
        }
        if (offset + 4 > markerPayload.length) {
          throw StateError('TLM marker truncated while reading tile length');
        }
        final value = view.getUint32(offset);
        offset += 4;
        return value;
      }();

      record.entries.add(
        HeaderInfoTLMEntry(
          tileIndex: tileIndex,
          length: tilePartLength,
        ),
      );
    }
  }

  void parsePpmMarker(Uint8List markerPayload) {
    FacilityManager.getMsgLogger().printmsg(
      MsgLogger.info,
      'Parsed PPM marker segment (length=${markerPayload.length})',
    );
    if (markerPayload.length < 3) {
      throw ArgumentError('PPM marker payload must be at least 3 bytes');
    }

    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final lppm = view.getUint16(0);
    if (lppm < 3 || lppm > markerPayload.length) {
      throw ArgumentError('Invalid PPM marker length: $lppm');
    }

    final zppm = view.getUint8(2);
    final dataLength = lppm - 3;
    if (markerPayload.length < 3 + dataLength) {
      throw ArgumentError(
          'PPM marker truncated: expected ${3 + dataLength} bytes');
    }

    final data = markerPayload.sublist(3, 3 + dataLength);

    while (_ppmMarkerData.length <= zppm) {
      _ppmMarkerData.add(null);
    }
    _ppmMarkerData[zppm] = Uint8List.fromList(data);
    decSpec.pphs.setDefault(true);
    _ppmSeen = true;
    _packedHeadersDirty = true;
  }

  void parsePptMarker(
    Uint8List markerPayload, {
    required int tileIdx,
    required int tilePartIdx,
  }) {
    if (markerPayload.length < 3) {
      throw ArgumentError('PPT marker payload must be at least 3 bytes');
    }

    final view = ByteData.view(
      markerPayload.buffer,
      markerPayload.offsetInBytes,
      markerPayload.lengthInBytes,
    );

    final lppt = view.getUint16(0);
    if (lppt < 3 || lppt > markerPayload.length) {
      throw ArgumentError('Invalid PPT marker length: $lppt');
    }

    final zppt = view.getUint8(2);
    final dataLength = lppt - 3;
    if (markerPayload.length < 3 + dataLength) {
      throw ArgumentError(
          'PPT marker truncated: expected ${3 + dataLength} bytes');
    }

    final data = markerPayload.sublist(3, 3 + dataLength);
    final tileMap =
        _tilePartInfo.putIfAbsent(tileIdx, () => <int, _TilePartInfo>{});
    final info = tileMap.putIfAbsent(tilePartIdx, () => _TilePartInfo());
    info.pptSegments[zppt] = Uint8List.fromList(data);
    decSpec.pphs.setTileDef(tileIdx, true);
    _packedHeadersDirty = true;
  }

  void setTileOfTileParts(int tileIdx) {
    _tilePartTiles.add(tileIdx);
    _packedHeadersDirty = true;
  }

  List<int> getTilePartTileOrder() => List<int>.unmodifiable(_tilePartTiles);

  void _ensurePackedPacketHeadersResolved() {
    if (!_packedHeadersDirty) {
      return;
    }

    final builders = <int, BytesBuilder>{};

    if (_ppmSeen && _ppmMarkerData.isNotEmpty) {
      final ppmData = _assemblePpmPayload();
      if (ppmData != null) {
        if (_tilePartTiles.isEmpty) {
          throw StateError('PPM markers parsed but tile-part order is unknown');
        }
        final view = ByteData.view(
            ppmData.buffer, ppmData.offsetInBytes, ppmData.lengthInBytes);
        var offset = 0;
        for (final tile in _tilePartTiles) {
          if (offset + 4 > ppmData.length) {
            throw StateError('Insufficient PPM data for tile part sequence');
          }
          final length = view.getUint32(offset);
          offset += 4;
          if (length < 0) {
            throw StateError(
                'Negative packet header length encountered in PPM data');
          }
          if (offset + length > ppmData.length) {
            throw StateError(
                'PPM segment overruns payload while assigning headers');
          }
          final builder = builders.putIfAbsent(tile, () => BytesBuilder());
          if (length > 0) {
            builder.add(ppmData.sublist(offset, offset + length));
          }
          offset += length;
        }
        if (offset != ppmData.length) {
          // Allow trailing padding but keep track for debugging.
        }
      }
    } else {
      _assemblePptHeaders(builders);
    }

    builders.forEach((tile, builder) {
      if (_packedHeaders.containsKey(tile) &&
          _packedHeaders[tile]!.isNotEmpty) {
        return;
      }
      _packedHeaders[tile] = builder.toBytes();
    });

    _packedHeadersDirty = false;
  }

  Uint8List? _assemblePpmPayload() {
    if (_ppmMarkerData.isEmpty) {
      return null;
    }
    final ordered = <Uint8List>[];
    for (var index = 0; index < _ppmMarkerData.length; index++) {
      final segment = _ppmMarkerData[index];
      if (segment == null) {
        throw StateError('Missing PPM marker segment at index $index');
      }
      ordered.add(segment);
    }
    if (ordered.isEmpty) {
      return null;
    }
    final builder = BytesBuilder();
    for (final segment in ordered) {
      builder.add(segment);
    }
    return builder.toBytes();
  }

  void _assemblePptHeaders(Map<int, BytesBuilder> builders) {
    if (_tilePartInfo.isEmpty) {
      return;
    }
    _tilePartInfo.forEach((tileIdx, tileParts) {
      final builder = builders.putIfAbsent(tileIdx, () => BytesBuilder());
      final orderedParts = tileParts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final partEntry in orderedParts) {
        final segments = partEntry.value.pptSegments.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final segment in segments) {
          builder.add(segment.value);
        }
      }
    });
  }

  StdEntropyDecoder createEntropyDecoder(
    CodedCBlkDataSrcDec source,
    ParameterList parameters,
  ) {
    parameters.checkListSingle(
      EntropyDecoder.optionPrefix.codeUnitAt(0),
      ParameterList.toNameArray(EntropyDecoder.parameterInfo),
    );

    final doErrorDetection = _parseBooleanOption(parameters, 'Cer', true);
    final verboseToggle = _parseBooleanOption(parameters, 'Cverber', true);
    final verbose = doErrorDetection && verboseToggle;
    final mQuit = _parseMqQuit(parameters);

    return StdEntropyDecoder(
      source,
      decSpec,
      doErrorDetection,
      verbose,
      mQuit,
    );
  }

  ROIDeScaler createROIDeScaler(
    CBlkQuantDataSrcDec source,
    ParameterList parameters,
  ) {
    return ROIDeScaler.createInstance(source, parameters, decSpec);
  }

  StdDequantizer createDequantizer(
    CBlkQuantDataSrcDec source,
    List<int> rangeBits,
  ) {
    if (rangeBits.length != numComps) {
      throw ArgumentError(
        'Range bit array must contain $numComps entries (found ${rangeBits.length})',
      );
    }
    return StdDequantizer(source, rangeBits, decSpec);
  }

  /// Creates the color space mapper that applies enumerated/ICC transforms.
  BlkImgDataSrc? createColorSpaceMapper(
    BlkImgDataSrc source,
    ColorSpace csMap,
  ) {
    return ColorSpaceMapper.createInstance(source, csMap);
  }

  /// Creates the channel-definition mapper that remaps logical channels.
  BlkImgDataSrc createChannelDefinitionMapper(
    BlkImgDataSrc source,
    ColorSpace csMap,
  ) {
    return ChannelDefinitionMapper.createInstance(source, csMap);
  }

  /// Creates a mapper that expands palette indices into full samples.
  BlkImgDataSrc createPalettizedColorSpaceMapper(
    BlkImgDataSrc source,
    ColorSpace csMap,
  ) {
    return PalettizedColorSpaceMapper.createInstance(source, csMap);
  }

  /// Creates a resampler that upsamples subsampled components to full size.
  BlkImgDataSrc createResampler(
    BlkImgDataSrc source,
    ColorSpace csMap,
  ) {
    return Resampler.createInstance(source, csMap);
  }

  bool isOriginalSigned(int component) {
    final siz = headerInfo.siz;
    if (siz == null) {
      throw StateError('SIZ marker has not been parsed yet');
    }
    return siz.isOrigSigned(component);
  }

  int getOriginalBitDepth(int component) {
    final siz = headerInfo.siz;
    if (siz == null) {
      throw StateError('SIZ marker has not been parsed yet');
    }
    return siz.getOrigBitDepth(component);
  }

  static bool _parseBooleanOption(
    ParameterList parameters,
    String name,
    bool defaultValue,
  ) {
    final raw = parameters.getParameter(name);
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

  static int _parseMqQuit(ParameterList parameters) {
    final raw = parameters.getParameter('m_quit');
    if (raw == null || raw.isEmpty) {
      return -1;
    }
    final value = int.tryParse(raw);
    if (value == null) {
      throw StringFormatException("Invalid integer for 'm_quit': $raw");
    }
    if (value == 0 || value < -1) {
      throw StringFormatException(
          "'m_quit' must be -1 or a positive integer (found $value)");
    }
    return value;
  }

  static Uint8List _readMarkerPayload(RandomAccessIO input) {
    final length = input.readUnsignedShort();
    if (length < 2) {
      throw StateError('Invalid marker segment length: $length');
    }
    final buffer = Uint8List(length);
    buffer[0] = (length >> 8) & 0xff;
    buffer[1] = length & 0xff;
    if (length > 2) {
      input.readFully(buffer, 2, length - 2);
    }
    return buffer;
  }

  static HeaderInfoSIZ _parseSizMarker(
      Uint8List payload, HeaderInfo headerInfo) {
    final view = ByteData.view(
        payload.buffer, payload.offsetInBytes, payload.lengthInBytes);
    final length = view.getUint16(0);
    if (length < 38) {
      throw StateError('SIZ marker too short: $length bytes');
    }

    final siz = headerInfo.getNewSIZ()
      ..lsiz = length
      ..rsiz = view.getUint16(2)
      ..xsiz = view.getUint32(4)
      ..ysiz = view.getUint32(8)
      ..x0siz = view.getUint32(12)
      ..y0siz = view.getUint32(16)
      ..xtsiz = view.getUint32(20)
      ..ytsiz = view.getUint32(24)
      ..xt0siz = view.getUint32(28)
      ..yt0siz = view.getUint32(32)
      ..csiz = view.getUint16(36);

    final components = siz.csiz;
    if (length != 38 + components * 3) {
      throw StateError('SIZ marker length does not match component count');
    }

    siz.ssiz = List<int>.filled(components, 0, growable: false);
    siz.xrsiz = List<int>.filled(components, 0, growable: false);
    siz.yrsiz = List<int>.filled(components, 0, growable: false);

    var offset = 38;
    for (var i = 0; i < components; i++) {
      final ssiz = view.getUint8(offset++);
      final xrsiz = view.getUint8(offset++);
      final yrsiz = view.getUint8(offset++);
      if (xrsiz == 0 || yrsiz == 0) {
        throw StateError(
            'SIZ marker contains zero subsampling factor for component $i');
      }
      siz.ssiz[i] = ssiz;
      siz.xrsiz[i] = xrsiz;
      siz.yrsiz[i] = yrsiz;
    }

    headerInfo.siz = siz;
    _logSizSummary(siz);
    return siz;
  }

  static void _skipUnknownMarker(
      RandomAccessIO input, int marker, MsgLogger logger) {
    final length = input.readUnsignedShort();
    if (length < 2) {
      throw StateError(
          'Invalid marker segment length for 0x${marker.toRadixString(16)}');
    }
    if (length > 2) {
      input.seek(input.getPos() + length - 2);
    }
    logger.printmsg(
      MsgLogger.log,
      'Skipping marker 0x${marker.toRadixString(16)} (${length - 2} bytes)',
    );
  }

  static void _logSizSummary(HeaderInfoSIZ siz) {
    if (!_isInstrumentationEnabled() || _sizLogCount >= _maxSizLogs) {
      return;
    }
    _sizLogCount++;
    final components = siz.csiz;
    final depthLabels = <String>[];
    final previewCount = math.min(components, 4);
    for (var c = 0; c < previewCount; c++) {
      final signed = siz.isOrigSigned(c) ? 's' : 'u';
      depthLabels.add('c$c:$signed${siz.getOrigBitDepth(c)}');
    }
    if (components > previewCount) {
      depthLabels.add('…');
    }
    _log(
      'SIZ summary: comps=$components size=${siz.xsiz - siz.x0siz}x${siz.ysiz - siz.y0siz} '
      'tile=${siz.xtsiz}x${siz.ytsiz} depths=${depthLabels.join(' ')}',
    );
  }

  void _logCodSummary({
    required String contextLabel,
    required int scod,
    required int progression,
    required int layers,
    required int decompLevels,
    required int cblkWidthExp,
    required int cblkHeightExp,
    required int filterId,
    List<int>? precincts,
  }) {
    if (!_isInstrumentationEnabled() || _codLogCount >= _maxCodLogs) {
      return;
    }
    _codLogCount++;
    final cblkWidth = 1 << (cblkWidthExp + 2);
    final cblkHeight = 1 << (cblkHeightExp + 2);
    final usesPrecincts = (scod & Markers.SCOX_PRECINCT_PARTITION) != 0;
    final flags = <String>[];
    if ((scod & Markers.SCOX_USE_SOP) != 0) {
      flags.add('SOP');
    }
    if ((scod & Markers.SCOX_USE_EPH) != 0) {
      flags.add('EPH');
    }
    if (usesPrecincts) {
      flags.add('precincts');
    }
    final filterLabel = filterId == FilterTypes.W5X3 ? '5x3' : '9x7';
    final precinctLabel = usesPrecincts && precincts != null
        ? 'precinctSpec=${precincts.map((v) => '0x${v.toRadixString(16)}').join(',')}'
        : 'precinctSpec=default';
    _log(
      'COD summary ($contextLabel): progression=$progression layers=$layers '
      'levels=$decompLevels cblk=${cblkWidth}x${cblkHeight} filter=$filterLabel '
      'flags=${flags.isEmpty ? 'none' : flags.join('|')} $precinctLabel',
    );
  }

  void _logQuantSummary({
    required String contextLabel,
    required int guardBits,
    required int qType,
    required StdDequantizerParams params,
  }) {
    if (!_isInstrumentationEnabled() || _quantLogCount >= _maxQuantLogs) {
      return;
    }
    _quantLogCount++;
    final expSummary = _summariseExponentTable(params.exp);
    final label = _quantizationTypeLabel(qType);
    _log(
      'Quantization summary ($contextLabel): guardBits=$guardBits type=$label exp=$expSummary',
    );
  }

  String _summariseExponentTable(List<List<int>> table) {
    if (table.isEmpty) {
      return 'none';
    }
    final entries = <String>[];
    for (var res = 0; res < table.length; res++) {
      final row = table[res];
      final startBand = res == 0 ? 0 : 1;
      final endBand = res == 0 ? 0 : math.min(3, row.length - 1);
      final bands = <String>[];
      for (var band = startBand; band <= endBand && band < row.length; band++) {
        final exp = row[band];
        if (exp > 0) {
          bands.add('b$band=$exp');
        }
      }
      if (bands.isNotEmpty) {
        entries.add('r$res{${bands.join(',')}}');
      }
    }
    return entries.isEmpty ? 'none' : entries.join(' ');
  }
}



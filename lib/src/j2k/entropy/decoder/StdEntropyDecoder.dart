import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/util/DecoderDebugConfig.dart';

import '../../decoder/DecoderSpecs.dart';
import '../../image/DataBlk.dart';
import '../../image/DataBlkInt.dart';
import '../../util/ArrayUtil.dart';

import '../../util/DecoderInstrumentation.dart';
import '../../util/FacilityManager.dart';
import '../../util/Int32Utils.dart';
import '../../util/MsgLogger.dart';
import '../../wavelet/subband.dart';
import '../../wavelet/synthesis/SubbandSyn.dart';
import '../StdEntropyCoderOptions.dart';
import 'ByteInputBuffer.dart';
import 'ByteToBitInput.dart';
import 'CodedCBlkDataSrcDec.dart';
import 'DecLyrdCBlk.dart';
import 'EntropyDecoder.dart';
import 'MqDecoder.dart';

/// JPEG 2000 entropy decoder mirroring the JJ2000 reference implementation.
class StdEntropyDecoder extends EntropyDecoder {
  static const String _logSource = 'StdEntropyDecoder';
  static const bool _enableVerboseInstrumentation = false;

  static const int _debugPreviewLimit = 4;
  static final Map<String, int> _debugMetaCounts = <String, int>{};
  static final Map<String, int> _debugPayloadCounts = <String, int>{};
  static final Map<String, int> _debugCoeffCounts = <String, int>{};
  static final Map<String, int> _debugOptionCounts = <String, int>{};
  static const int _debugSegmentLimit = 3;
  static int _debugSegmentCount = 0;
  static final Map<String, int> _debugMqTraceCounts = <String, int>{};
  static const int _debugMqTraceLimit = 4;
  static const int _debugMqTraceSymbolLimit = 256;

  static const bool _doTiming = false;

  static const int _zcLutBits = 8;
  static const int _scLutBits = 9;
  static const int _mrLutBits = 9;

  static const int _numContexts = 19;
  static const int _uniformContext = 0;
  static const int _rlcCtxt = 1;
  static const int _unifCtxt = 0;
  static const int _intSignBit = 1 << 31;
  static const int _segSymbol = 10;

  static const List<int> _mqInit = <int>[
    46,
    3,
    4,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  static final List<int> _zcLutLh = _buildZcLutLh();
  static final List<int> _zcLutHl = _buildZcLutHl();
  static final List<int> _zcLutHh = _buildZcLutHh();
  static final List<int> _scLut = _buildScLut();
  static final List<int> _mrLut = _buildMrLut();

  static const int _stateSep = 16;

  static const int _stateSigR1 = 1 << 15;
  static const int _stateVisitedR1 = 1 << 14;
  static const int _stateNzCtxtR1 = 1 << 13;
  static const int _stateHlSignR1 = 1 << 12;
  static const int _stateHrSignR1 = 1 << 11;
  static const int _stateVuSignR1 = 1 << 10;
  static const int _stateVdSignR1 = 1 << 9;
  static const int _statePrevMrR1 = 1 << 8;
  static const int _stateHlR1 = 1 << 7;
  static const int _stateHrR1 = 1 << 6;
  static const int _stateVuR1 = 1 << 5;
  static const int _stateVdR1 = 1 << 4;
  static const int _stateDulR1 = 1 << 3;
  static const int _stateDurR1 = 1 << 2;
  static const int _stateDdlR1 = 1 << 1;
  static const int _stateDdrR1 = 1;

  static const int _stateSigR2 = _stateSigR1 << _stateSep;
  static const int _stateVisitedR2 = _stateVisitedR1 << _stateSep;
  static const int _stateNzCtxtR2 = _stateNzCtxtR1 << _stateSep;
  static const int _stateHlSignR2 = _stateHlSignR1 << _stateSep;
  static const int _stateHrSignR2 = _stateHrSignR1 << _stateSep;
  static const int _stateVuSignR2 = _stateVuSignR1 << _stateSep;
  static const int _stateVdSignR2 = _stateVdSignR1 << _stateSep;
  static const int _statePrevMrR2 = _statePrevMrR1 << _stateSep;
  static const int _stateHlR2 = _stateHlR1 << _stateSep;
  static const int _stateHrR2 = _stateHrR1 << _stateSep;
  static const int _stateVuR2 = _stateVuR1 << _stateSep;
  static const int _stateVdR2 = _stateVdR1 << _stateSep;
  static const int _stateDulR2 = _stateDulR1 << _stateSep;
  static const int _stateDurR2 = _stateDurR1 << _stateSep;
  static const int _stateDdlR2 = _stateDdlR1 << _stateSep;
  static const int _stateDdrR2 = _stateDdrR1 << _stateSep;

  static const int _sigMaskR1R2 = _stateSigR1 | _stateSigR2;
  static const int _vstdMaskR1R2 = _stateVisitedR1 | _stateVisitedR2;
  static const int _zcMask = (1 << 8) - 1;
  static const int _scMask = (1 << _scLutBits) - 1;
  static const int _scShiftR1 = 4;
  static const int _scShiftR2 = _scShiftR1 + _stateSep;
  static const int _scSpredShift = 31;
  static const int _mrMask = (1 << 9) - 1;

  static int _int32(int value) => Int32Utils.asInt32(value);

  static int _encodeSignSample(int sign, int setmask) =>
      Int32Utils.encodeSignSample(sign, setmask);

  static int _refineMagnitude(
    int current,
    int resetmask,
    int symbol,
    int bitPlane,
    int setmask,
  ) =>
      Int32Utils.refineMagnitude(current, resetmask, symbol, bitPlane, setmask);

  bool tracing = false;
  void trace(String msg) {
    if (tracing) {
      _log('[TRACE] $msg');
    }
  }

  StdEntropyDecoder(
    CodedCBlkDataSrcDec src,
    this.decoderSpecs,
    bool doErrorDetection,
    bool verbose,
    int mQuit,
  )   : _doErrorDetection = doErrorDetection,
        _verboseErrors = verbose,
        _mQuit = mQuit,
        super(src) {
    if (_doTiming) {
      _timings = List<int>.filled(src.getNumComps(), 0);
    }
    final maxWidth = decoderSpecs.cblks.getMaxCBlkWidth();
    final maxHeight = decoderSpecs.cblks.getMaxCBlkHeight();
    state = List<int>.filled(
      (maxWidth + 2) * (((maxHeight + 1) >> 1) + 2),
      0,
      growable: false,
    );
  }

  final DecoderSpecs decoderSpecs;
  final bool _doErrorDetection;
  final bool _verboseErrors;
  final int _mQuit;

  ByteToBitInput? _bin;
  MQDecoder? _mq;
  ByteInputBuffer? _mqInput;
  TraceBlockFilter? _traceFilter;
  void Function(String line)? _mqTraceSink;

  DecLyrdCBlk? _srcBlk;

  List<int>? _timings;

  late final List<int> state;

  int _currentResLevel = -1;
  int _currentBand = -1;
  String _currentBlockLabel = '';
  int _samplePreviewBudget = 0;

  int _options = 0;

  void configureDebug({
    TraceBlockFilter? traceFilter,
    void Function(String line)? mqTraceSink,
  }) {
    _traceFilter = traceFilter;
    _mqTraceSink = mqTraceSink;
  }

  MQDecoder? getMQDecoder() => _mq;

  @override
  DataBlk getCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) {
    final tileIndex = getTileIdx();
    _currentResLevel = subband.resLvl;
    _currentBand = subband.sbandIdx;
    _currentBlockLabel =
        'tile=$tileIndex comp=$component res=${subband.resLvl} band=${subband.sbandIdx} '
        'm=$verticalCodeBlockIndex n=$horizontalCodeBlockIndex';
    _samplePreviewBudget = 32;
    _srcBlk = src.getCodeBlock(
      component,
      verticalCodeBlockIndex,
      horizontalCodeBlockIndex,
      subband,
      1,
      -1,
      _srcBlk,
    );
    final currentBlock = _srcBlk;
    if (currentBlock == null) {
      throw StateError('Entropy source returned null code-block');
    }

    if (_isInstrumentationEnabled()) {
      _logBlockMeta(
        tileIndex,
        component,
        subband,
        currentBlock,
        verticalCodeBlockIndex,
        horizontalCodeBlockIndex,
      );
    }

    int start = 0;
    if (_doTiming) {
      start = DateTime.now().millisecondsSinceEpoch;
    }

    final opt = decoderSpecs.ecopts.getTileCompVal(tileIndex, component);
    _options = opt ?? 0;

    if (_isInstrumentationEnabled()) {
      _logOptions(tileIndex, component, _options);
    }

    ArrayUtil.intArraySet(state, 0);

    DataBlkInt outBlk;
    if (block is DataBlkInt) {
      outBlk = block;
    } else {
      outBlk = DataBlkInt();
    }

    outBlk
      ..progressive = currentBlock.prog
      ..ulx = currentBlock.ulx
      ..uly = currentBlock.uly
      ..w = currentBlock.w
      ..h = currentBlock.h
      ..offset = 0
      ..scanw = currentBlock.w;

    var outData = outBlk.data;
    final required = currentBlock.w * currentBlock.h;
    if (outData == null || outData.length < required) {
      outData = Int32List(required);
      outBlk.data = outData;
    } else {
      ArrayUtil.intArraySet(outData, 0);
    }

    if (currentBlock.nl <= 0 || currentBlock.nTrunc <= 0) {
      if (_isInstrumentationEnabled()) {
        _log(
            'Skipping block m=$verticalCodeBlockIndex n=$horizontalCodeBlockIndex due to nl=${currentBlock.nl} nTrunc=${currentBlock.nTrunc}');
      }
      return outBlk;
    }

    final data = currentBlock.data;
    if (data == null) {
      throw StateError('Decoded code-block payload is missing');
    }

    if (_isInstrumentationEnabled()) {
      _logPayloadPreview(component, subband, currentBlock);
    }

    final tsLengths = currentBlock.tsLengths;
    final initialSegmentLength = tsLengths == null || tsLengths.isEmpty
        ? currentBlock.dl
        : _segmentLength(tsLengths, 0);

    if (_isInstrumentationEnabled()) {
      _logSegmentDiagnostics(currentBlock, initialSegmentLength);
    }

    if (_mq == null) {
      _mqInput = ByteInputBuffer.view(data, 0, initialSegmentLength);
      _mq = MQDecoder(_mqInput!, _numContexts, _mqInit);
    } else {
      _mq!.nextSegment(data, 0, initialSegmentLength);
      _mq!.resetCtxts();
    }

    final matchesTraceFilter = _traceFilter?.matches(
          tileIndex: tileIndex,
          component: component,
          resolutionLevel: subband.resLvl,
          band: subband.sbandIdx,
          cblkY: verticalCodeBlockIndex,
          cblkX: horizontalCodeBlockIndex,
        ) ??
        false;
    final shouldTraceMq = matchesTraceFilter ||
        (_traceFilter == null &&
            _isInstrumentationEnabled() &&
            subband.resLvl == 0 &&
            subband.sbandIdx == 0 &&
            _shouldTraceMq(component));
    if (shouldTraceMq) {
      final traceLabel = 'tile=$tileIndex comp=$component res=${subband.resLvl} '
          'band=${subband.sbandIdx} m=$verticalCodeBlockIndex '
          'n=$horizontalCodeBlockIndex bp=${30 - currentBlock.skipMSBP}';
      _mq!.startTrace(traceLabel, _debugMqTraceSymbolLimit);
    } else {
      _mq!.startTrace('', 0);
    }

    tracing = _isInstrumentationEnabled() &&
        (matchesTraceFilter ||
            (component <= 1 &&
                verticalCodeBlockIndex == 0 &&
                horizontalCodeBlockIndex == 0));
    if (tracing) {
      _log(
          'TRACING ENABLED for m=$verticalCodeBlockIndex n=$horizontalCodeBlockIndex');
    }

    var errorDetected = false;
    if ((_options & StdEntropyCoderOptions.OPT_BYPASS) != 0) {
      _bin ??= ByteToBitInput(_mq!.getByteInputBuffer());
    }

    final zcLut = _selectZcLut(subband.orientation);

    var npasses = currentBlock.nTrunc;
    var curBitPlane = 30 - currentBlock.skipMSBP;

    if (_isInstrumentationEnabled()) {
      _log(
          'BitPlane info: skipMSBP=${currentBlock.skipMSBP}, curBitPlane=$curBitPlane, '
          'npasses=$npasses, w=${currentBlock.w}, h=${currentBlock.h}');
    }

    if (_mQuit != -1 && (_mQuit * 3 - 2) < npasses) {
      npasses = _mQuit * 3 - 2;
    }

    var segmentIndex = 0;

    if (curBitPlane >= 0 && npasses > 0) {
      final isTerminated =
          (_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0 ||
              ((_options & StdEntropyCoderOptions.OPT_BYPASS) != 0 &&
                  (31 -
                          StdEntropyCoderOptions.NUM_NON_BYPASS_MS_BP -
                          currentBlock.skipMSBP) >=
                      curBitPlane);
      _logPass('cleanup-initial', curBitPlane, npasses, segmentIndex, tsLengths,
          initialSegmentLength);
      errorDetected = _cleanupPass(
        outBlk,
        _mq!,
        curBitPlane,
        state,
        zcLut,
        isTerminated,
      );
      _logPassResult('cleanup-initial', curBitPlane, outBlk);
      npasses--;
      if (!errorDetected || !_doErrorDetection) {
        curBitPlane--;
      }
    }

    if (!errorDetected || !_doErrorDetection) {
      while (curBitPlane >= 0 && npasses > 0) {
        if ((_options & StdEntropyCoderOptions.OPT_BYPASS) != 0 &&
            curBitPlane <
                31 -
                    StdEntropyCoderOptions.NUM_NON_BYPASS_MS_BP -
                    currentBlock.skipMSBP) {
          final rawSigLength = _segmentLength(tsLengths, ++segmentIndex);
          _logPass('raw-sig', curBitPlane, npasses, segmentIndex, tsLengths,
              rawSigLength);
          _bin!.setByteArray(null, -1, rawSigLength);
          final isTerminated =
              (_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0;
          errorDetected = _rawSigProgPass(
            outBlk,
            _bin!,
            curBitPlane,
            state,
            isTerminated,
          );
          _logPassResult('raw-sig', curBitPlane, outBlk);
          npasses--;
          if (npasses <= 0 || (errorDetected && _doErrorDetection)) {
            break;
          }

          if ((_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
            final rawMagTermLength = _segmentLength(tsLengths, ++segmentIndex);
            _logPass('raw-mag-term', curBitPlane, npasses, segmentIndex,
                tsLengths, rawMagTermLength);
            _bin!.setByteArray(null, -1, rawMagTermLength);
          }

          final isTerminatedMag =
              (_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0 ||
                  ((_options & StdEntropyCoderOptions.OPT_BYPASS) != 0 &&
                      (31 -
                              StdEntropyCoderOptions.NUM_NON_BYPASS_MS_BP -
                              currentBlock.skipMSBP >
                          curBitPlane));
          final rawMagLength = _segmentLengthOrFallback(
              tsLengths, segmentIndex, currentBlock.dl);
          _logPass('raw-mag', curBitPlane, npasses, segmentIndex, tsLengths,
              rawMagLength);
          errorDetected = _rawMagRefPassStub(
            outBlk,
            _bin!,
            curBitPlane,
            state,
            isTerminatedMag,
          );
          _logPassResult('raw-mag', curBitPlane, outBlk);
        } else {
          int? sigSegmentLength;
          if ((_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
            sigSegmentLength = _segmentLength(tsLengths, ++segmentIndex);
            _mq!.nextSegment(null, -1, sigSegmentLength);
          }
          final isTerminatedSig =
              (_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0;
          final effectiveSigLength = sigSegmentLength ??
              _segmentLengthOrFallback(
                  tsLengths, segmentIndex, currentBlock.dl);
          _logPass('sig', curBitPlane, npasses, segmentIndex, tsLengths,
              effectiveSigLength);
          errorDetected = _sigProgPass(
            outBlk,
            _mq!,
            curBitPlane,
            state,
            zcLut,
            isTerminatedSig,
          );
          _logPassResult('sig', curBitPlane, outBlk);
          npasses--;
          if (npasses <= 0 || (errorDetected && _doErrorDetection)) {
            break;
          }

          int? magSegmentLength;
          if ((_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
            magSegmentLength = _segmentLength(tsLengths, ++segmentIndex);
            _mq!.nextSegment(null, -1, magSegmentLength);
          }
          final isTerminatedMag =
              (_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0 ||
                  ((_options & StdEntropyCoderOptions.OPT_BYPASS) != 0 &&
                      (31 -
                              StdEntropyCoderOptions.NUM_NON_BYPASS_MS_BP -
                              currentBlock.skipMSBP >
                          curBitPlane));
          final effectiveMagLength = magSegmentLength ??
              _segmentLengthOrFallback(
                  tsLengths, segmentIndex, currentBlock.dl);
          _logPass('mag', curBitPlane, npasses, segmentIndex, tsLengths,
              effectiveMagLength);
          errorDetected = _magRefPass(
            outBlk,
            _mq!,
            curBitPlane,
            state,
            isTerminatedMag,
          );
          _logPassResult('mag', curBitPlane, outBlk);
        }

        npasses--;
        if (npasses <= 0 || (errorDetected && _doErrorDetection)) {
          break;
        }

        int? cleanupSegmentLength;
        if ((_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0 ||
            ((_options & StdEntropyCoderOptions.OPT_BYPASS) != 0 &&
                curBitPlane <
                    31 -
                        StdEntropyCoderOptions.NUM_NON_BYPASS_MS_BP -
                        currentBlock.skipMSBP)) {
          cleanupSegmentLength = _segmentLength(tsLengths, ++segmentIndex);
          _mq!.nextSegment(null, -1, cleanupSegmentLength);
        }
        final isTerminatedCleanup =
            (_options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0 ||
                ((_options & StdEntropyCoderOptions.OPT_BYPASS) != 0 &&
                    (31 -
                            StdEntropyCoderOptions.NUM_NON_BYPASS_MS_BP -
                            currentBlock.skipMSBP) >=
                        curBitPlane);
        final effectiveCleanupLength = cleanupSegmentLength ??
            _segmentLengthOrFallback(tsLengths, segmentIndex, currentBlock.dl);
        _logPass('cleanup', curBitPlane, npasses, segmentIndex, tsLengths,
            effectiveCleanupLength);
        errorDetected = _cleanupPass(
          outBlk,
          _mq!,
          curBitPlane,
          state,
          zcLut,
          isTerminatedCleanup,
        );
        _logPassResult('cleanup', curBitPlane, outBlk);
        npasses--;
        if (errorDetected && _doErrorDetection) {
          break;
        }
        curBitPlane--;
      }
    }

    if (errorDetected && _doErrorDetection) {
      if (_verboseErrors) {
        FacilityManager.getMsgLogger().printmsg(
          MsgLogger.warning,
          'Error detected at bit-plane $curBitPlane in code-block '
          '(${verticalCodeBlockIndex},${horizontalCodeBlockIndex}), '
          'sb_idx ${subband.sbandIdx}, res. level ${subband.resLvl}. Concealing...',
        );
      }
      _conceal(outBlk, curBitPlane);
    }

    if (_doTiming) {
      final stop = DateTime.now().millisecondsSinceEpoch;
      _timings![component] += stop - start;
    }

    final traceDump = _mq!.drainTrace();
    if (traceDump != null &&
        traceDump.isNotEmpty &&
        _isInstrumentationEnabled()) {
      _log('MQ trace: $traceDump');
      final sink = _mqTraceSink;
      if (sink != null) {
        sink(traceDump);
      }
    }

    _logBlockSnapshot('final', outBlk);

    return outBlk;
  }

  @override
  DataBlk getInternCodeBlock(
    int component,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
    SubbandSyn subband,
    DataBlk? block,
  ) =>
      getCodeBlock(component, verticalCodeBlockIndex, horizontalCodeBlockIndex,
          subband, block);

  static List<int> _selectZcLut(int orientation) {
    switch (orientation) {
      case Subband.wtOrientHl:
        return _zcLutHl;
      case Subband.wtOrientLh:
      case Subband.wtOrientLl:
        return _zcLutLh;
      case Subband.wtOrientHh:
        return _zcLutHh;
      default:
        throw StateError('Unsupported subband orientation: $orientation');
    }
  }

  static int _segmentLength(List<int>? lengths, int index) {
    if (lengths == null) {
      throw StateError(
          'Missing terminated segment lengths for entropy-coded passes.');
    }
    if (index < 0 || index >= lengths.length) {
      throw RangeError.range(
        index,
        0,
        lengths.length - 1,
        'index',
        'Terminated segment length index out of bounds',
      );
    }
    return lengths[index];
  }

  static int _segmentLengthOrFallback(
      List<int>? lengths, int index, int fallback) {
    if (lengths == null || lengths.isEmpty) {
      return fallback;
    }
    if (index < 0) {
      return lengths.first;
    }
    if (index >= lengths.length) {
      return lengths.last;
    }
    return lengths[index];
  }

  void _logBlockMeta(
    int tileIndex,
    int component,
    SubbandSyn subband,
    DecLyrdCBlk block,
    int verticalCodeBlockIndex,
    int horizontalCodeBlockIndex,
  ) {
    final key =
        't$tileIndex-c$component-r${subband.resLvl}-b${subband.sbandIdx}';
    final seen = _debugMetaCounts[key] ?? 0;
    if (seen >= _debugPreviewLimit) {
      return;
    }
    _debugMetaCounts[key] = seen + 1;
    final segCount = block.tsLengths?.length ?? 0;
    _log('Block meta tile=$tileIndex comp=$component res=${subband.resLvl} '
        'band=${subband.sbandIdx} m=$verticalCodeBlockIndex '
        'n=$horizontalCodeBlockIndex ulx=${block.ulx} uly=${block.uly} '
        'w=${block.w} h=${block.h} skipMSBP=${block.skipMSBP} '
        'layers=${block.nl} trunc=${block.nTrunc} ftp=${block.ftpIdx} '
        'dl=${block.dl} segments=$segCount');
  }

  void _logOptions(int tileIndex, int component, int options) {
    final key = 't$tileIndex-c$component';
    final seen = _debugOptionCounts[key] ?? 0;
    if (seen >= _debugPreviewLimit) {
      return;
    }
    _debugOptionCounts[key] = seen + 1;
    final flags = <String>[];
    if ((options & StdEntropyCoderOptions.OPT_BYPASS) != 0) {
      flags.add('bypass');
    }
    if ((options & StdEntropyCoderOptions.OPT_RESET_MQ) != 0) {
      flags.add('reset-mq');
    }
    if ((options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
      flags.add('term-pass');
    }
    if ((options & StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL) != 0) {
      flags.add('vsc');
    }
    if ((options & StdEntropyCoderOptions.OPT_PRED_TERM) != 0) {
      flags.add('pred-term');
    }
    if ((options & StdEntropyCoderOptions.OPT_SEG_SYMBOLS) != 0) {
      flags.add('seg-symbols');
    }
    if (flags.isEmpty) {
      flags.add('none');
    }
    _log('Entropy options tile=$tileIndex comp=$component value=0x'
        '${options.toRadixString(16)} flags=${flags.join(',')}');
  }

  void _logPayloadPreview(
    int component,
    SubbandSyn subband,
    DecLyrdCBlk block,
  ) {
    final payload = block.data;
    if (payload == null || payload.isEmpty) {
      _log('Payload preview ctx=$_currentBlockLabel bytes=0');
      return;
    }
    final key = 'c$component-r${subband.resLvl}-b${subband.sbandIdx}';
    final seen = _debugPayloadCounts[key] ?? 0;
    if (seen >= _debugPreviewLimit) {
      return;
    }
    _debugPayloadCounts[key] = seen + 1;
    final limit = payload.length < 32 ? payload.length : 32;
    final hex = <String>[];
    final ascii = <String>[];
    for (var i = 0; i < limit; i++) {
      final byte = payload[i];
      hex.add(byte.toRadixString(16).padLeft(2, '0'));
      ascii.add(byte >= 32 && byte <= 126
          ? String.fromCharCode(byte)
          : '.');
    }
    final trailer = payload.length > limit ? '...' : '';
    _log('Payload preview ctx=$_currentBlockLabel bytes=${payload.length} '
        'head=${hex.join(' ')}$trailer ascii=${ascii.join()}$trailer');
  }

  void _logSegmentDiagnostics(DecLyrdCBlk block, int initialSegmentLength) {
    if (_debugSegmentCount >= _debugSegmentLimit) {
      return;
    }
    _debugSegmentCount++;
    final segments = block.tsLengths;
    if (segments == null || segments.isEmpty) {
      _log('Segment diag ctx=$_currentBlockLabel segments=1 '
          'len=$initialSegmentLength total=${block.dl}');
      return;
    }
    final previewCount =
        segments.length < _debugPreviewLimit ? segments.length : _debugPreviewLimit;
    final preview = segments.sublist(0, previewCount).join(', ');
    final suffix = segments.length > previewCount ? ', ...' : '';
    _log('Segment diag ctx=$_currentBlockLabel segments=${segments.length} '
        'total=${block.dl} sizes=[$preview$suffix]');
  }

  bool _shouldTraceMq(int component) {
    final key = 'comp=$component-res=$_currentResLevel-band=$_currentBand';
    final seen = _debugMqTraceCounts[key] ?? 0;
    if (seen >= _debugMqTraceLimit) {
      return false;
    }
    _debugMqTraceCounts[key] = seen + 1;
    return true;
  }

  void _logPass(
    String pass,
    int bitPlane,
    int remainingPasses,
    int segmentIndex,
    List<int>? tsLengths,
    int fallbackLength,
  ) {
    if (!_isVerboseInstrumentationEnabled()) {
      return;
    }
    final segLen =
        _segmentLengthOrFallback(tsLengths, segmentIndex, fallbackLength);
    _log(
        'Pass $pass bitPlane=$bitPlane remaining=$remainingPasses segmentIndex=$segmentIndex segmentLength=$segLen');
  }

  void _logPassResult(String pass, int bitPlane, DataBlkInt block) {
    if (!_isVerboseInstrumentationEnabled()) {
      return;
    }
    final data = block.data;
    if (data == null || data.isEmpty) {
      _log('Samples pass=$pass bitPlane=$bitPlane nonZero=0 min=0 max=0');
      return;
    }
    var nonZero = 0;
    var min = data[0];
    var max = data[0];
    for (var i = 0; i < data.length; i++) {
      final value = data[i];
      if (value != 0) {
        nonZero++;
      }
      if (value < min) {
        min = value;
      }
      if (value > max) {
        max = value;
      }
    }
    _log(
        'Samples pass=$pass bitPlane=$bitPlane nonZero=$nonZero min=$min max=$max');
    if (_shouldLogDetailedSamples(block)) {
      _logSamplePreviewDetailed(pass, bitPlane, block);
    }
  }

  bool _shouldLogDetailedSamples(DataBlkInt block) {
    if (!_isVerboseInstrumentationEnabled()) {
      return false;
    }
    if (_samplePreviewBudget <= 0) {
      return false;
    }
    if (_currentResLevel != 2 || _currentBand != 2) {
      return false;
    }
    return block.w <= 4 && block.h <= 4;
  }

  void _logSamplePreviewDetailed(
    String pass,
    int bitPlane,
    DataBlkInt block,
  ) {
    final data = block.data;
    if (data == null || data.isEmpty) {
      return;
    }
    final key = '$_currentBlockLabel:$pass:$bitPlane';
    final seen = _debugCoeffCounts[key] ?? 0;
    if (seen >= _debugPreviewLimit) {
      return;
    }
    _debugCoeffCounts[key] = seen + 1;
    final width = block.w;
    final height = block.h;
    final rows = height < 4 ? height : 4;
    final cols = width < 4 ? width : 4;
    final gridRows = <String>[];
    for (var row = 0; row < rows; row++) {
      final base = row * width;
      final rowValues = <int>[];
      for (var col = 0; col < cols; col++) {
        rowValues.add(data[base + col]);
      }
      gridRows.add(rowValues.join(', '));
    }
    final flattenedPreview = <int>[];
    final previewLimit = width * height < 16 ? width * height : 16;
    for (var i = 0; i < previewLimit; i++) {
      flattenedPreview.add(data[i]);
    }
    _log(
        'Samples preview ctx=$_currentBlockLabel pass=$pass bitPlane=$bitPlane '
        'rows=${gridRows.join(' | ')} head=${flattenedPreview.join(', ')}');
    _samplePreviewBudget--;
  }

  bool _shouldLogBlockSnapshot(DataBlkInt block) {
    if (!_isVerboseInstrumentationEnabled()) {
      return false;
    }
    if (_currentResLevel != 2 || _currentBand != 2) {
      return false;
    }
    return block.w <= 4 && block.h <= 4;
  }

  void _logBlockSnapshot(String stage, DataBlkInt block) {
    if (!_shouldLogBlockSnapshot(block)) {
      return;
    }
    final data = block.data;
    if (data == null || data.isEmpty) {
      return;
    }
    final width = block.w;
    final height = block.h;
    final rows = <String>[];
    final hexRows = <String>[];
    for (var row = 0; row < height; row++) {
      final base = row * width;
      final decVals = <String>[];
      final hexVals = <String>[];
      for (var col = 0; col < width; col++) {
        final sample = data[base + col];
        decVals.add(sample.toString());
        final hex = sample & 0xFFFFFFFF;
        hexVals.add('0x${hex.toRadixString(16).padLeft(8, '0')}');
      }
      rows.add(decVals.join(', '));
      hexRows.add(hexVals.join(', '));
    }
    _log('Block snapshot stage=$stage ctx=$_currentBlockLabel '
        'dec=[${rows.join(' | ')}] hex=[${hexRows.join(' | ')}]');
  }

  bool _sigProgPass(
    DataBlkInt cblk,
    MQDecoder mq,
    int bitPlane,
    List<int> state,
    List<int> zcLut,
    bool terminated,
  ) {
    trace('sigProgPass start bp=$bitPlane');
    final data = cblk.data!;
    final dscanw = cblk.scanw;
    final sscanw = cblk.w + 2;
    final jstep = sscanw * StdEntropyCoderOptions.STRIPE_HEIGHT ~/ 2 - cblk.w;
    final kstep = dscanw * StdEntropyCoderOptions.STRIPE_HEIGHT - cblk.w;
    final one = 1 << bitPlane;
    final setmask = one | (one >> 1);
    final nstripes = (cblk.h + StdEntropyCoderOptions.STRIPE_HEIGHT - 1) ~/
        StdEntropyCoderOptions.STRIPE_HEIGHT;
    final causal = (_options & StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL) != 0;

    var sampleTraceBudget = tracing ? 32 : 0;
    void traceSample(String stage, int k, int sym, int value) {
      if (sampleTraceBudget <= 0) {
        return;
      }
      sampleTraceBudget--;
      _log('[TRACE] sig:$stage k=$k bp=$bitPlane sym=$sym '
          'setmask=$setmask value=$value');
    }

    final offUl = -sscanw - 1;
    final offUr = -sscanw + 1;
    final offDr = sscanw + 1;
    final offDl = sscanw - 1;

    var sk = cblk.offset;
    var sj = sscanw + 1;
    for (var s = 0; s < nstripes; s++, sk += kstep, sj += jstep) {
      final stripeHeight = (s < nstripes - 1)
          ? StdEntropyCoderOptions.STRIPE_HEIGHT
          : cblk.h - (nstripes - 1) * StdEntropyCoderOptions.STRIPE_HEIGHT;
      final stopSk = sk + cblk.w;
      for (; sk < stopSk; sk++, sj++) {
        var j = sj;
        var csj = state[j];
        if ((((~csj) & (csj << 2)) & _sigMaskR1R2) != 0) {
          var k = sk;
          if ((csj & (_stateSigR1 | _stateNzCtxtR1)) == _stateNzCtxtR1) {
            final zcCtxIndex = csj & _zcMask;
            final zcSym = mq.decodeSymbol(zcLut[zcCtxIndex]);
            trace('sigProgPass ZC R1 k=$k ctx=$zcCtxIndex sym=$zcSym');
            if (zcSym != 0) {
              final signLut = _scLut[(csj >>> _scShiftR1) & _scMask];
              final scCtx = signLut & ((1 << _scShiftR1) - 1);
              final predictedSign = (signLut >>> _scSpredShift) & 1;
              final rawSym = mq.decodeSymbol(scCtx);
              final sym = rawSym ^ predictedSign;
              trace(
                  'sigProgPass SC R1 k=$k ctx=$scCtx pred=$predictedSign rawSym=$rawSym sym=$sym');
              data[k] = _encodeSignSample(sym, setmask);
              if (tracing) {
                traceSample('R1', k, sym, data[k]);
              }
              state[j + offUl] |= _stateNzCtxtR2 | _stateDdrR2;
              state[j + offUr] |= _stateNzCtxtR2 | _stateDdlR2;
              if (sym != 0) {
                csj |= _stateSigR1 |
                    _stateVisitedR1 |
                    _stateNzCtxtR2 |
                    _stateVuR2 |
                    _stateVuSignR2;
                state[j - sscanw] |=
                      _stateNzCtxtR2 | _stateVdR2 | _stateVdSignR2;
                state[j + 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateHlR1 |
                    _stateHlSignR1 |
                    _stateDulR2;
                state[j - 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateHrR1 |
                    _stateHrSignR1 |
                    _stateDurR2;
              } else {
                csj |=
                    _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 | _stateVuR2;
                state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2;
                state[j + 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 | _stateDulR2;
                state[j - 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 | _stateDurR2;
              }
            } else {
              csj |= _stateVisitedR1;
            }
          }
          if (stripeHeight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (_stateSigR2 | _stateNzCtxtR2)) == _stateNzCtxtR2) {
            k += dscanw;
            final zcCtxIndex = (csj >>> _stateSep) & _zcMask;
            final zcSym = mq.decodeSymbol(zcLut[zcCtxIndex]);
            trace('sigProgPass ZC R2 k=$k ctx=$zcCtxIndex sym=$zcSym');
            if (zcSym != 0) {
              final signLut = _scLut[(csj >>> _scShiftR2) & _scMask];
              final scCtx = signLut & ((1 << _scShiftR1) - 1);
              final predictedSign = (signLut >>> _scSpredShift) & 1;
              final rawSym = mq.decodeSymbol(scCtx);
              final sym = rawSym ^ predictedSign;
              trace(
                  'sigProgPass SC R2 k=$k ctx=$scCtx pred=$predictedSign rawSym=$rawSym sym=$sym');
              data[k] = _encodeSignSample(sym, setmask);
              if (tracing) {
                traceSample('R2', k, sym, data[k]);
              }
              state[j + offDl] |= _stateNzCtxtR1 | _stateDurR1;
              state[j + offDr] |= _stateNzCtxtR1 | _stateDulR1;
              if (sym != 0) {
                csj |= _stateSigR2 |
                    _stateVisitedR2 |
                    _stateNzCtxtR1 |
                    _stateVdR1 |
                    _stateVdSignR1;
                state[j + sscanw] |=
                    _stateNzCtxtR1 | _stateVuR1 | _stateVuSignR1;
                state[j + 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateDdlR1 |
                    _stateHlR2 |
                    _stateHlSignR2;
                state[j - 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateDdrR1 |
                    _stateHrR2 |
                    _stateHrSignR2;
              } else {
                csj |=
                    _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 | _stateVdR1;
                state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1;
                state[j + 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 | _stateHlR2;
                state[j - 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 | _stateHrR2;
              }
            } else {
              csj |= _stateVisitedR2;
            }
          }
          if (stripeHeight < 3) {
            state[j] = csj;
            continue;
          }
          j += sscanw;
          csj = state[j];
          if ((((~csj) & (csj << 2)) & _sigMaskR1R2) != 0) {
            var k = sk + (dscanw << 1);
            if ((csj & (_stateSigR1 | _stateNzCtxtR1)) == _stateNzCtxtR1) {
              final zcCtxIndex = csj & _zcMask;
              final zcSym = mq.decodeSymbol(zcLut[zcCtxIndex]);
              trace('sigProgPass ZC R3 k=$k ctx=$zcCtxIndex sym=$zcSym');
              if (zcSym != 0) {
                final signLut = _scLut[(csj >>> _scShiftR1) & _scMask];
                final scCtx = signLut & ((1 << _scShiftR1) - 1);
                final predictedSign = (signLut >>> _scSpredShift) & 1;
                final rawSym = mq.decodeSymbol(scCtx);
                final sym = rawSym ^ predictedSign;
                trace(
                    'sigProgPass SC R3 k=$k ctx=$scCtx pred=$predictedSign rawSym=$rawSym sym=$sym');
                data[k] = _encodeSignSample(sym, setmask);
                if (tracing) {
                  traceSample('R3', k, sym, data[k]);
                }
                if (!causal) {
                  state[j + offUl] |= _stateNzCtxtR2 | _stateDdrR2;
                  state[j + offUr] |= _stateNzCtxtR2 | _stateDdlR2;
                }
                if (sym != 0) {
                  csj |= _stateSigR1 |
                      _stateVisitedR1 |
                      _stateNzCtxtR2 |
                      _stateVuR2 |
                      _stateVuSignR2;
                  state[j - sscanw] |=
                      _stateNzCtxtR2 | _stateVdR2 | _stateVdSignR2;
                  state[j + 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateHlR1 |
                      _stateHlSignR1 |
                      _stateDulR2;
                  state[j - 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateHrR1 |
                      _stateHrSignR1 |
                      _stateDurR2;
                } else {
                  csj |=
                      _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 | _stateVuR2;
                  state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2;
                  state[j + 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 | _stateDulR2;
                  state[j - 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 | _stateDurR2;
                }
              } else {
                csj |= _stateVisitedR1;
              }
            }
            if (stripeHeight < 4) {
              state[j] = csj;
              continue;
            }
            if ((csj & (_stateSigR2 | _stateNzCtxtR2)) == _stateNzCtxtR2) {
              k += dscanw;
              final zcCtxIndex = (csj >>> _stateSep) & _zcMask;
              final zcSym = mq.decodeSymbol(zcLut[zcCtxIndex]);
              trace('sigProgPass ZC R4 k=$k ctx=$zcCtxIndex sym=$zcSym');
              if (zcSym != 0) {
                final signLut = _scLut[(csj >>> _scShiftR2) & _scMask];
                final scCtx = signLut & ((1 << _scShiftR1) - 1);
                final predictedSign = (signLut >>> _scSpredShift) & 1;
                final rawSym = mq.decodeSymbol(scCtx);
                final sym = rawSym ^ predictedSign;
                trace(
                    'sigProgPass SC R4 k=$k ctx=$scCtx pred=$predictedSign rawSym=$rawSym sym=$sym');
                data[k] = _encodeSignSample(sym, setmask);
                if (tracing) {
                  traceSample('R4', k, sym, data[k]);
                }
                state[j + offDl] |= _stateNzCtxtR1 | _stateDurR1;
                state[j + offDr] |= _stateNzCtxtR1 | _stateDulR1;
                if (sym != 0) {
                  csj |= _stateSigR2 |
                      _stateVisitedR2 |
                      _stateNzCtxtR1 |
                      _stateVdR1 |
                      _stateVdSignR1;
                  state[j + sscanw] |=
                      _stateNzCtxtR1 | _stateVuR1 | _stateVuSignR1;
                  state[j + 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateDdlR1 |
                      _stateHlR2 |
                      _stateHlSignR2;
                  state[j - 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateDdrR1 |
                      _stateHrR2 |
                      _stateHrSignR2;
                } else {
                  csj |=
                      _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 | _stateVdR1;
                  state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1;
                  state[j + 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 | _stateHlR2;
                  state[j - 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 | _stateHrR2;
                }
              } else {
                csj |= _stateVisitedR2;
              }
            }
          }
          state[j] = csj;
        }
      }
    }

    var error = false;
    if (terminated && (_options & StdEntropyCoderOptions.OPT_PRED_TERM) != 0) {
      error = mq.checkPredTerm();
    }

    if ((_options & StdEntropyCoderOptions.OPT_RESET_MQ) != 0) {
      mq.resetCtxts();
    }

    return error;
  }

  bool _magRefPass(
    DataBlkInt cblk,
    MQDecoder mqDecoder,
    int bitPlane,
    List<int> state,
    bool terminated,
  ) {
    trace('magRefPass start bp=$bitPlane');
    final data = cblk.data!;
    final dscanw = cblk.scanw;
    final sscanw = cblk.w + 2;
    final jstep = sscanw * StdEntropyCoderOptions.STRIPE_HEIGHT ~/ 2 - cblk.w;
    final kstep = dscanw * StdEntropyCoderOptions.STRIPE_HEIGHT - cblk.w;
    final setmask = (1 << bitPlane) >> 1;
    final resetmask = (-1) << (bitPlane + 1);
    final nstripes = (cblk.h + StdEntropyCoderOptions.STRIPE_HEIGHT - 1) ~/
        StdEntropyCoderOptions.STRIPE_HEIGHT;

    var sampleTraceBudget = tracing ? 32 : 0;
    void traceSample(String stage, int k, int sym, int value) {
      if (sampleTraceBudget <= 0) {
        return;
      }
      sampleTraceBudget--;
      _log('[TRACE] magRef:$stage k=$k bp=$bitPlane sym=$sym '
          'setmask=$setmask resetmask=$resetmask value=$value');
    }

    var sk = cblk.offset;
    var sj = sscanw + 1;
    for (var s = 0; s < nstripes; s++, sk += kstep, sj += jstep) {
      final stripeHeight = (s < nstripes - 1)
          ? StdEntropyCoderOptions.STRIPE_HEIGHT
          : cblk.h - (nstripes - 1) * StdEntropyCoderOptions.STRIPE_HEIGHT;
      final stopSk = sk + cblk.w;
      for (; sk < stopSk; sk++, sj++) {
        var j = sj;
        var csj = state[j];
        if ((((csj >>> 1) & (~csj)) & _vstdMaskR1R2) != 0) {
          var k = sk;
          if ((csj & (_stateSigR1 | _stateVisitedR1)) == _stateSigR1) {
            final ctxIdx = csj & _mrMask;
            final ctx = _mrLut[ctxIdx];
            final sym = mqDecoder.decodeSymbol(ctx);
            trace('magRefPass MR R1 k=$k ctx=$ctxIdx sym=$sym');
            final refined =
                _refineMagnitude(data[k], resetmask, sym, bitPlane, setmask);
            data[k] = refined;
            if (tracing) {
              traceSample('R1', k, sym, refined);
            }
            csj |= _statePrevMrR1;
          }
          if (stripeHeight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (_stateSigR2 | _stateVisitedR2)) == _stateSigR2) {
            k += dscanw;
            final ctxIdx = (csj >>> _stateSep) & _mrMask;
            final ctx = _mrLut[ctxIdx];
            final sym = mqDecoder.decodeSymbol(ctx);
            trace('magRefPass MR R2 k=$k ctx=$ctxIdx sym=$sym');
            final refined =
                _refineMagnitude(data[k], resetmask, sym, bitPlane, setmask);
            data[k] = refined;
            if (tracing) {
              traceSample('R2', k, sym, refined);
            }
            csj |= _statePrevMrR2;
          }
          state[j] = csj;
        }
        if (stripeHeight < 3) {
          continue;
        }
        j += sscanw;
        csj = state[j];
        if ((((csj >>> 1) & (~csj)) & _vstdMaskR1R2) != 0) {
          var k = sk + (dscanw << 1);
          if ((csj & (_stateSigR1 | _stateVisitedR1)) == _stateSigR1) {
            final ctxIdx = csj & _mrMask;
            final ctx = _mrLut[ctxIdx];
            final sym = mqDecoder.decodeSymbol(ctx);
            trace('magRefPass MR R3 k=$k ctx=$ctxIdx sym=$sym');
            final refined =
                _refineMagnitude(data[k], resetmask, sym, bitPlane, setmask);
            data[k] = refined;
            if (tracing) {
              traceSample('R3', k, sym, refined);
            }
            csj |= _statePrevMrR1;
          }
          if (stripeHeight < 4) {
            state[j] = csj;
            continue;
          }
          if ((csj & (_stateSigR2 | _stateVisitedR2)) == _stateSigR2) {
            k += dscanw;
            final ctxIdx = (csj >>> _stateSep) & _mrMask;
            final ctx = _mrLut[ctxIdx];
            final sym = mqDecoder.decodeSymbol(ctx);
            trace('magRefPass MR R4 k=$k ctx=$ctxIdx sym=$sym');
            final refined =
                _refineMagnitude(data[k], resetmask, sym, bitPlane, setmask);
            data[k] = refined;
            if (tracing) {
              traceSample('R4', k, sym, refined);
            }
            csj |= _statePrevMrR2;
          }
          state[j] = csj;
        }
      }
    }

    var error = false;
    if (terminated && (_options & StdEntropyCoderOptions.OPT_PRED_TERM) != 0) {
      error = mqDecoder.checkPredTerm();
    }
    if ((_options & StdEntropyCoderOptions.OPT_RESET_MQ) != 0) {
      mqDecoder.resetCtxts();
    }
    return error;
  }

  bool _rawSigProgPass(
    DataBlkInt cblk,
    ByteToBitInput bin,
    int bitPlane,
    List<int> state,
    bool terminated,
  ) {
    trace('rawSigProgPass start bp=$bitPlane');
    final data = cblk.data!;
    final dscanw = cblk.scanw;
    final sscanw = cblk.w + 2;
    final jstep = sscanw * StdEntropyCoderOptions.STRIPE_HEIGHT ~/ 2 - cblk.w;
    final kstep = dscanw * StdEntropyCoderOptions.STRIPE_HEIGHT - cblk.w;
    final one = 1 << bitPlane;
    final setmask = one | (one >> 1);
    final nstripes = (cblk.h + StdEntropyCoderOptions.STRIPE_HEIGHT - 1) ~/
        StdEntropyCoderOptions.STRIPE_HEIGHT;
    final causal = (_options & StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL) != 0;

    final offUl = -sscanw - 1;
    final offUr = -sscanw + 1;
    final offDr = sscanw + 1;
    final offDl = sscanw - 1;

    var sk = cblk.offset;
    var sj = sscanw + 1;
    for (var s = 0; s < nstripes; s++, sk += kstep, sj += jstep) {
      final stripeHeight = (s < nstripes - 1)
          ? StdEntropyCoderOptions.STRIPE_HEIGHT
          : cblk.h - (nstripes - 1) * StdEntropyCoderOptions.STRIPE_HEIGHT;
      final stopSk = sk + cblk.w;
      for (; sk < stopSk; sk++, sj++) {
        var j = sj;
        var csj = state[j];
        if ((((~csj) & (csj << 2)) & _sigMaskR1R2) != 0) {
          var k = sk;
          if ((csj & (_stateSigR1 | _stateNzCtxtR1)) == _stateNzCtxtR1) {
            if (bin.readBit() != 0) {
              final sym = bin.readBit();
              data[k] = _encodeSignSample(sym, setmask);
              if (!causal) {
                state[j + offUl] |= _stateNzCtxtR2 | _stateDdrR2;
                state[j + offUr] |= _stateNzCtxtR2 | _stateDdlR2;
              }
              if (sym != 0) {
                csj |= _stateSigR1 |
                    _stateVisitedR1 |
                    _stateNzCtxtR2 |
                    _stateVuR2 |
                    _stateVuSignR2;
                state[j - sscanw] |=
                    _stateNzCtxtR2 | _stateVdR2 | _stateVdSignR2;
                state[j + 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateHlR1 |
                    _stateHlSignR1 |
                    _stateDulR2;
                state[j - 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateHrR1 |
                    _stateHrSignR1 |
                    _stateDurR2;
              } else {
                csj |=
                    _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 | _stateVuR2;
                state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2;
                state[j + 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 | _stateDulR2;
                state[j - 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 | _stateDurR2;
              }
            } else {
              csj |= _stateVisitedR1;
            }
          }
          if (stripeHeight < 2) {
            state[j] = csj;
            continue;
          }
          if ((csj & (_stateSigR2 | _stateNzCtxtR2)) == _stateNzCtxtR2) {
            k += dscanw;
            if (bin.readBit() != 0) {
              final sym = bin.readBit();
              data[k] = _encodeSignSample(sym, setmask);
              state[j + offDl] |= _stateNzCtxtR1 | _stateDurR1;
              state[j + offDr] |= _stateNzCtxtR1 | _stateDulR1;
              if (sym != 0) {
                csj |= _stateSigR2 |
                    _stateVisitedR2 |
                    _stateNzCtxtR1 |
                    _stateVdR1 |
                    _stateVdSignR1;
                state[j + sscanw] |=
                    _stateNzCtxtR1 | _stateVuR1 | _stateVuSignR1;
                state[j + 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateDdlR1 |
                    _stateHlR2 |
                    _stateHlSignR2;
                state[j - 1] |= _stateNzCtxtR1 |
                    _stateNzCtxtR2 |
                    _stateDdrR1 |
                    _stateHrR2 |
                    _stateHrSignR2;
              } else {
                csj |=
                    _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 | _stateVdR1;
                state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1;
                state[j + 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 | _stateHlR2;
                state[j - 1] |=
                    _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 | _stateHrR2;
              }
            } else {
              csj |= _stateVisitedR2;
            }
          }
          if (stripeHeight < 3) {
            state[j] = csj;
            continue;
          }
          j += sscanw;
          csj = state[j];
          if ((((~csj) & (csj << 2)) & _sigMaskR1R2) != 0) {
            var k = sk + (dscanw << 1);
            if ((csj & (_stateSigR1 | _stateNzCtxtR1)) == _stateNzCtxtR1) {
              if (bin.readBit() != 0) {
                final sym = bin.readBit();
                data[k] = _encodeSignSample(sym, setmask);
                if (!causal) {
                  state[j + offUl] |= _stateNzCtxtR2 | _stateDdrR2;
                  state[j + offUr] |= _stateNzCtxtR2 | _stateDdlR2;
                }
                if (sym != 0) {
                  csj |= _stateSigR1 |
                      _stateVisitedR1 |
                      _stateNzCtxtR2 |
                      _stateVuR2 |
                      _stateVuSignR2;
                  state[j - sscanw] |=
                      _stateNzCtxtR2 | _stateVdR2 | _stateVdSignR2;
                  state[j + 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateHlR1 |
                      _stateHlSignR1 |
                      _stateDulR2;
                  state[j - 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateHrR1 |
                      _stateHrSignR1 |
                      _stateDurR2;
                } else {
                  csj |=
                      _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 | _stateVuR2;
                  state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2;
                  state[j + 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 | _stateDulR2;
                  state[j - 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 | _stateDurR2;
                }
              } else {
                csj |= _stateVisitedR1;
              }
            }
            if (stripeHeight < 4) {
              state[j] = csj;
              continue;
            }
            if ((csj & (_stateSigR2 | _stateNzCtxtR2)) == _stateNzCtxtR2) {
              k += dscanw;
              if (bin.readBit() != 0) {
                final sym = bin.readBit();
                data[k] = _encodeSignSample(sym, setmask);
                state[j + offDl] |= _stateNzCtxtR1 | _stateDurR1;
                state[j + offDr] |= _stateNzCtxtR1 | _stateDulR1;
                if (sym != 0) {
                  csj |= _stateSigR2 |
                      _stateVisitedR2 |
                      _stateNzCtxtR1 |
                      _stateVdR1 |
                      _stateVdSignR1;
                  state[j + sscanw] |=
                      _stateNzCtxtR1 | _stateVuR1 | _stateVuSignR1;
                  state[j + 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateDdlR1 |
                      _stateHlR2 |
                      _stateHlSignR2;
                  state[j - 1] |= _stateNzCtxtR1 |
                      _stateNzCtxtR2 |
                      _stateDdrR1 |
                      _stateHrR2 |
                      _stateHrSignR2;
                } else {
                  csj |=
                      _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 | _stateVdR1;
                  state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1;
                  state[j + 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 | _stateHlR2;
                  state[j - 1] |=
                      _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 | _stateHrR2;
                }
              } else {
                csj |= _stateVisitedR2;
              }
            }
          }
        }
      }
    }

    var error = false;
    if ((_options & StdEntropyCoderOptions.OPT_SEG_SYMBOLS) != 0) {
      var sym = _mq!.decodeSymbol(_uniformContext) << 3;
      sym |= _mq!.decodeSymbol(_uniformContext) << 2;
      sym |= _mq!.decodeSymbol(_uniformContext) << 1;
      sym |= _mq!.decodeSymbol(_uniformContext);
      error = sym != _segSymbol;
    } else {
      error = false;
    }

    if (terminated && (_options & StdEntropyCoderOptions.OPT_PRED_TERM) != 0) {
      error = _mq!.checkPredTerm();
    }

    if ((_options & StdEntropyCoderOptions.OPT_RESET_MQ) != 0) {
      _mq!.resetCtxts();
    }

    return error;
  }

  void _conceal(DataBlkInt cblk, int bitPlane) {
    final data = cblk.data!;
    final setmask = 1 << bitPlane;
    final resetmask = (-1) << bitPlane;

    var k = cblk.offset;
    for (var line = cblk.h - 1; line >= 0; line--) {
      final lineEnd = k + cblk.w;
      while (k < lineEnd) {
        final value = data[k];
        if ((value & resetmask & 0x7FFFFFFF) != 0) {
          data[k] = _int32((value & resetmask) | setmask);
        } else {
          data[k] = 0;
        }
        k++;
      }
      k += cblk.scanw - cblk.w;
    }
  }

  static List<int> _buildZcLutLh() {
    final lut = List<int>.filled(1 << _zcLutBits, 0, growable: false);
    lut[0] = 2;
    for (var i = 1; i < 16; i++) {
      lut[i] = 4;
    }
    for (var i = 0; i < 4; i++) {
      lut[1 << i] = 3;
    }
    for (var i = 0; i < 16; i++) {
      lut[_stateVuR1 | i] = 5;
      lut[_stateVdR1 | i] = 5;
      lut[_stateVuR1 | _stateVdR1 | i] = 6;
    }
    lut[_stateHlR1] = 7;
    lut[_stateHrR1] = 7;
    for (var i = 1; i < 16; i++) {
      lut[_stateHlR1 | i] = 8;
      lut[_stateHrR1 | i] = 8;
    }
    for (var i = 1; i < 4; i++) {
      for (var j = 0; j < 16; j++) {
        lut[_stateHlR1 | (i << 4) | j] = 9;
        lut[_stateHrR1 | (i << 4) | j] = 9;
      }
    }
    for (var i = 0; i < 64; i++) {
      lut[_stateHlR1 | _stateHrR1 | i] = 10;
    }
    return lut;
  }

  static List<int> _buildZcLutHl() {
    final lut = List<int>.filled(1 << _zcLutBits, 0, growable: false);
    lut[0] = 2;
    for (var i = 1; i < 16; i++) {
      lut[i] = 4;
    }
    for (var i = 0; i < 4; i++) {
      lut[1 << i] = 3;
    }
    for (var i = 0; i < 16; i++) {
      lut[_stateHlR1 | i] = 5;
      lut[_stateHrR1 | i] = 5;
      lut[_stateHlR1 | _stateHrR1 | i] = 6;
    }
    lut[_stateVuR1] = 7;
    lut[_stateVdR1] = 7;
    for (var i = 1; i < 16; i++) {
      lut[_stateVuR1 | i] = 8;
      lut[_stateVdR1 | i] = 8;
    }
    for (var i = 1; i < 4; i++) {
      for (var j = 0; j < 16; j++) {
        lut[(i << 6) | _stateVuR1 | j] = 9;
        lut[(i << 6) | _stateVdR1 | j] = 9;
      }
    }
    for (var i = 0; i < 4; i++) {
      for (var j = 0, k = 1; j < 16; j++, k <<= 1) {
        lut[(i << 6) | _stateVuR1 | _stateVdR1 | j] = 10;
      }
    }
    return lut;
  }

  static List<int> _buildZcLutHh() {
    final lut = List<int>.filled(1 << _zcLutBits, 0, growable: false);
    lut[0] = 2;
    final twoBits = <int>[3, 5, 6, 9, 10, 12];
    final oneBit = <int>[1, 2, 4, 8];
    final twoLeast = <int>[3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15];
    final threeLeast = <int>[7, 11, 13, 14, 15];

    for (final t in oneBit) {
      lut[t << 4] = 3;
    }
    for (final t in twoLeast) {
      lut[t << 4] = 4;
    }
    for (final t in oneBit) {
      lut[t] = 5;
    }
    for (final h in oneBit) {
      for (final d in oneBit) {
        lut[(h << 4) | d] = 6;
      }
    }
    for (final h in twoLeast) {
      for (final d in oneBit) {
        lut[(h << 4) | d] = 7;
      }
    }
    for (final d in twoBits) {
      lut[d] = 8;
    }
    for (var h = 0; h < 16; h++) {
      for (final d in twoBits) {
        lut[(h << 4) | d] = 9;
      }
    }
    for (var h = 0; h < 16; h++) {
      for (final d in threeLeast) {
        lut[(h << 4) | d] = 10;
      }
    }
    return lut;
  }

  static List<int> _buildScLut() {
    final lut = List<int>.filled(1 << _scLutBits, 0, growable: false);
    final inter = List<int>.filled(36, 0, growable: false);
    inter[(2 << 3) | 2] = 15;
    inter[(2 << 3) | 1] = 14;
    inter[(2 << 3) | 0] = 13;
    inter[(1 << 3) | 2] = 12;
    inter[(1 << 3) | 1] = 11;
    inter[(1 << 3) | 0] = 12 | _intSignBit;
    inter[(0 << 3) | 2] = 13 | _intSignBit;
    inter[(0 << 3) | 1] = 14 | _intSignBit;
    inter[(0 << 3) | 0] = 15 | _intSignBit;

    for (var i = 0; i < (1 << _scLutBits) - 1; i++) {
      final ds = i & 0x01;
      final us = (i >> 1) & 0x01;
      final rs = (i >> 2) & 0x01;
      final ls = (i >> 3) & 0x01;
      final dsgn = (i >> 5) & 0x01;
      final usgn = (i >> 6) & 0x01;
      final rsgn = (i >> 7) & 0x01;
      final lsgn = (i >> 8) & 0x01;
      var h = ls * (1 - 2 * lsgn) + rs * (1 - 2 * rsgn);
      h = h >= -1 ? h : -1;
      h = h <= 1 ? h : 1;
      var v = us * (1 - 2 * usgn) + ds * (1 - 2 * dsgn);
      v = v >= -1 ? v : -1;
      v = v <= 1 ? v : 1;
      lut[i] = inter[(h + 1) << 3 | (v + 1)];
    }
    return lut;
  }

  static List<int> _buildMrLut() {
    final lut = List<int>.filled(1 << _mrLutBits, 0, growable: false);
    lut[0] = 16;
    for (var i = 1; i < (1 << (_mrLutBits - 1)); i++) {
      lut[i] = 17;
    }
    for (var i = 1 << (_mrLutBits - 1); i < (1 << _mrLutBits); i++) {
      lut[i] = 18;
    }
    return lut;
  }

  static bool _isInstrumentationEnabled() => DecoderInstrumentation.isEnabled();

  static bool _isVerboseInstrumentationEnabled() =>
      _enableVerboseInstrumentation && _isInstrumentationEnabled();

  static void _logStatic(String message) {
    if (_isInstrumentationEnabled()) {
      DecoderInstrumentation.log(_logSource, message);
    }
  }

  static void _log(String message) => _logStatic(message);

  /// Performs the cleanup pass on the specified data and bit-plane.
  /// Decodes all insignificant samples which have their "visited" state bit
  /// off, using the ZC, SC, and RLC primitives. Toggles the "visited"
  /// state bit to 0 (off) for all samples in the code-block.
  ///
  /// Returns true if an error was detected in the bit stream, false otherwise.
  bool _cleanupPass(
    DataBlkInt cblk,
    MQDecoder mq,
    int bitPlane,
    List<int> state,
    List<int> zcLut,
    bool terminated,
  ) {
    trace('cleanuppass start bp=$bitPlane');
    final data = cblk.data!;
    final dscanw = cblk.scanw;
    final sscanw = cblk.w + 2;
    final jstep = sscanw * StdEntropyCoderOptions.STRIPE_HEIGHT ~/ 2 - cblk.w;
    final kstep = dscanw * StdEntropyCoderOptions.STRIPE_HEIGHT - cblk.w;
    final one = 1 << bitPlane;
    final half = one >> 1;
    final setmask = one | half;
    final nstripes =
        (cblk.h + StdEntropyCoderOptions.STRIPE_HEIGHT - 1) ~/
        StdEntropyCoderOptions.STRIPE_HEIGHT;
    final causal = (_options & StdEntropyCoderOptions.OPT_VERT_STR_CAUSAL) != 0;

    // Pre-calculate offsets in 'state' for diagonal neighbors
    final offUl = -sscanw - 1;  // up-left
    final offUr = -sscanw + 1;  // up-right
    final offDr = sscanw + 1;   // down-right
    final offDl = sscanw - 1;   // down-left

    // Decode stripe by stripe (top to bottom to mirror JJ2000 flow)
    var sk = cblk.offset;
    var sj = sscanw + 1;
    for (var s = 0; s < nstripes; s++, sk += kstep, sj += jstep) {
      final stripeHeight = (s < nstripes - 1)
          ? StdEntropyCoderOptions.STRIPE_HEIGHT
          : cblk.h - (nstripes - 1) * StdEntropyCoderOptions.STRIPE_HEIGHT;
      final stopsk = sk + cblk.w;
      
      // Scan by set of 1 stripe column at a time
      for (; sk < stopsk; sk++, sj++) {
        // Start column
        var j = sj;
        var csj = state[j];
        var broken = false;
        
        // Check for RLC: if all samples are not significant, not visited
        // and do not have a non-zero context, and column is full height
        if (csj == 0 &&
          state[j + sscanw] == 0 &&
          stripeHeight == StdEntropyCoderOptions.STRIPE_HEIGHT) {
          final rlcSym = mq.decodeSymbol(_rlcCtxt);
          trace('cleanuppass RLC k=$sk sym=$rlcSym');
          
          if (rlcSym != 0) {
            // run-length is significant, decode length
            final rlc1 = mq.decodeSymbol(_unifCtxt);
            final rlc2 = mq.decodeSymbol(_unifCtxt);
            final rlclen = (rlc1 << 1) | rlc2;
            trace('cleanuppass RLC len=$rlclen (bits $rlc1, $rlc2)');
            
            // Set 'k' and 'j' accordingly
            var k = sk + rlclen * dscanw;
            if (rlclen > 1) {
              j += sscanw;
              csj = state[j];
            }
            
            // We just decoded significant RLC - use sign coding
            if ((rlclen & 0x01) == 0) {
              // Sample that became significant is first row of its column half
              final signLut = _scLut[(csj >> _scShiftR1) & _scMask];
              final ctxt = signLut & ((1 << _scShiftR1) - 1);
              final rawSym = mq.decodeSymbol(ctxt);
              final sym = rawSym ^ (signLut >>> _scSpredShift);
              trace('cleanuppass SC RLC R1 k=$k ctxt=$ctxt rawSym=$rawSym sym=$sym');
              
              // Update the data
              data[k] = _encodeSignSample(sym, setmask);
              
              // Update state information
              if (rlclen != 0 || !causal) {
                state[j + offUl] |= _stateNzCtxtR2 | _stateDdrR2;
                state[j + offUr] |= _stateNzCtxtR2 | _stateDdlR2;
              }
              
              if (sym != 0) {
                csj |= _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 |
                    _stateVuR2 | _stateVuSignR2;
                if (rlclen != 0 || !causal) {
                  state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2 | _stateVdSignR2;
                }
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 |
                    _stateHlSignR1 | _stateDulR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 |
                    _stateHrSignR1 | _stateDurR2;
              } else {
                csj |= _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 | _stateVuR2;
                if (rlclen != 0 || !causal) {
                  state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2;
                }
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 | _stateDulR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 | _stateDurR2;
              }
              
              if ((rlclen >> 1) != 0) {
                broken = true;
              }
            } else {
              // Sample that became significant is second row of its column half
              final signLut = _scLut[(csj >> _scShiftR2) & _scMask];
              final ctxt = signLut & ((1 << _scShiftR1) - 1);
              final rawSym = mq.decodeSymbol(ctxt);
              final sym = rawSym ^ (signLut >>> _scSpredShift);
              trace('cleanuppass SC RLC R2 k=$k ctxt=$ctxt rawSym=$rawSym sym=$sym');
              
              // Update the data
              data[k] = _encodeSignSample(sym, setmask);
              
              // Update state information
              state[j + offDl] |= _stateNzCtxtR1 | _stateDurR1;
              state[j + offDr] |= _stateNzCtxtR1 | _stateDulR1;
              
              if (sym != 0) {
                csj |= _stateSigR2 | _stateNzCtxtR1 | _stateVdR1 | _stateVdSignR1;
                state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1 | _stateVuSignR1;
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 |
                    _stateHlR2 | _stateHlSignR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 |
                    _stateHrR2 | _stateHrSignR2;
              } else {
                csj |= _stateSigR2 | _stateNzCtxtR1 | _stateVdR1;
                state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1;
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 | _stateHlR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 | _stateHrR2;
              }
              
              // Save changes to csj
              state[j] = csj;
              if ((rlclen >> 1) != 0) {
                continue;
              }
              j += sscanw;
              csj = state[j];
              broken = true;
            }
          } else {
            // RLC is insignificant - goto next column
            continue;
          }
        }
        
        if (!broken) {
          // Do half top of column
          if ((((csj >> 1) | csj) & _vstdMaskR1R2) != _vstdMaskR1R2) {
            var k = sk;
            
            // Scan first row
            if ((csj & (_stateSigR1 | _stateVisitedR1)) == 0) {
              final zcSym = mq.decodeSymbol(zcLut[csj & _zcMask]);
              trace('cleanuppass ZC R1 k=$k ctx=${csj & _zcMask} sym=$zcSym');
              
              if (zcSym != 0) {
                // Became significant - use sign coding
                final signLut = _scLut[(csj >> _scShiftR1) & _scMask];
                final ctxt = signLut & ((1 << _scShiftR1) - 1);
                final rawSym = mq.decodeSymbol(ctxt);
                final sym = rawSym ^ (signLut >>> _scSpredShift);
                trace('cleanuppass SC R1 k=$k ctxt=$ctxt rawSym=$rawSym sym=$sym');
                
                // Update the data
                data[k] = _encodeSignSample(sym, setmask);
                
                // Update state information
                if (!causal) {
                  state[j + offUl] |= _stateNzCtxtR2 | _stateDdrR2;
                  state[j + offUr] |= _stateNzCtxtR2 | _stateDdlR2;
                }
                
                if (sym != 0) {
                  csj |= _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 |
                      _stateVuR2 | _stateVuSignR2;
                  if (!causal) {
                    state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2 | _stateVdSignR2;
                  }
                  state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 |
                      _stateHlSignR1 | _stateDulR2;
                  state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 |
                      _stateHrSignR1 | _stateDurR2;
                } else {
                  csj |= _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 | _stateVuR2;
                  if (!causal) {
                    state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2;
                  }
                  state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 | _stateDulR2;
                  state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 | _stateDurR2;
                }
              }
            }
            
            if (stripeHeight < 2) {
              csj &= ~(_stateVisitedR1 | _stateVisitedR2);
              state[j] = csj;
              continue;
            }
            
            // Scan second row
            if ((csj & (_stateSigR2 | _stateVisitedR2)) == 0) {
              k += dscanw;
              final zcSym = mq.decodeSymbol(zcLut[(csj >>> _stateSep) & _zcMask]);
              trace('cleanuppass ZC R2 k=$k ctx=${(csj >>> _stateSep) & _zcMask} sym=$zcSym');
              
              if (zcSym != 0) {
                // Became significant - use sign coding
                final signLut = _scLut[(csj >> _scShiftR2) & _scMask];
                final ctxt = signLut & ((1 << _scShiftR1) - 1);
                final rawSym = mq.decodeSymbol(ctxt);
                final sym = rawSym ^ (signLut >>> _scSpredShift);
                trace('cleanuppass SC R2 k=$k ctxt=$ctxt rawSym=$rawSym sym=$sym');
                
                // Update the data
                data[k] = _encodeSignSample(sym, setmask);
                
                // Update state information
                state[j + offDl] |= _stateNzCtxtR1 | _stateDurR1;
                state[j + offDr] |= _stateNzCtxtR1 | _stateDulR1;
                
                if (sym != 0) {
                  csj |= _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 |
                      _stateVdR1 | _stateVdSignR1;
                  state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1 | _stateVuSignR1;
                  state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 |
                      _stateHlR2 | _stateHlSignR2;
                  state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 |
                      _stateHrR2 | _stateHrSignR2;
                } else {
                  csj |= _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 | _stateVdR1;
                  state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1;
                  state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 | _stateHlR2;
                  state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 | _stateHrR2;
                }
              }
            }
          }
          
          csj &= ~(_stateVisitedR1 | _stateVisitedR2);
          state[j] = csj;
          
          // Do half bottom of column
          if (stripeHeight < 3) continue;
          j += sscanw;
          csj = state[j];
        }
        
        // Bottom half of column
        if ((((csj >> 1) | csj) & _vstdMaskR1R2) != _vstdMaskR1R2) {
          var k = sk + (dscanw << 1);
          
          // Scan first row
          if ((csj & (_stateSigR1 | _stateVisitedR1)) == 0) {
            final zcSym = mq.decodeSymbol(zcLut[csj & _zcMask]);
            trace('cleanuppass ZC R1 k=$k ctx=${csj & _zcMask} sym=$zcSym');
            
            if (zcSym != 0) {
              // Became significant - use sign coding
              final signLut = _scLut[(csj >> _scShiftR1) & _scMask];
              final ctxt = signLut & ((1 << _scShiftR1) - 1);
              final rawSym = mq.decodeSymbol(ctxt);
              final sym = rawSym ^ (signLut >>> _scSpredShift);
              trace('cleanuppass SC R1 k=$k ctxt=$ctxt rawSym=$rawSym sym=$sym');
              
              // Update the data
              data[k] = _encodeSignSample(sym, setmask);
              
              // Update state information
              state[j + offUl] |= _stateNzCtxtR2 | _stateDdrR2;
              state[j + offUr] |= _stateNzCtxtR2 | _stateDdlR2;
              
              if (sym != 0) {
                csj |= _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 |
                    _stateVuR2 | _stateVuSignR2;
                state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2 | _stateVdSignR2;
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 |
                    _stateHlSignR1 | _stateDulR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 |
                    _stateHrSignR1 | _stateDurR2;
              } else {
                csj |= _stateSigR1 | _stateVisitedR1 | _stateNzCtxtR2 | _stateVuR2;
                state[j - sscanw] |= _stateNzCtxtR2 | _stateVdR2;
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHlR1 | _stateDulR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateHrR1 | _stateDurR2;
              }
            }
          }
          
          if (stripeHeight < 4) {
            csj &= ~(_stateVisitedR1 | _stateVisitedR2);
            state[j] = csj;
            continue;
          }
          
          // Scan second row
          if ((csj & (_stateSigR2 | _stateVisitedR2)) == 0) {
            k += dscanw;
            final zcSym = mq.decodeSymbol(zcLut[(csj >>> _stateSep) & _zcMask]);
            trace('cleanuppass ZC R2 k=$k ctx=${(csj >>> _stateSep) & _zcMask} sym=$zcSym');
            
            if (zcSym != 0) {
              // Became significant - use sign coding
              final signLut = _scLut[(csj >> _scShiftR2) & _scMask];
              final ctxt = signLut & ((1 << _scShiftR1) - 1);
              final rawSym = mq.decodeSymbol(ctxt);
              final sym = rawSym ^ (signLut >>> _scSpredShift);
              trace('cleanuppass SC R2 k=$k ctxt=$ctxt rawSym=$rawSym sym=$sym');
              
              // Update the data
              data[k] = _encodeSignSample(sym, setmask);
              
              // Update state information
              state[j + offDl] |= _stateNzCtxtR1 | _stateDurR1;
              state[j + offDr] |= _stateNzCtxtR1 | _stateDulR1;
              
              if (sym != 0) {
                csj |= _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 |
                    _stateVdR1 | _stateVdSignR1;
                state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1 | _stateVuSignR1;
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 |
                    _stateHlR2 | _stateHlSignR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 |
                    _stateHrR2 | _stateHrSignR2;
              } else {
                csj |= _stateSigR2 | _stateVisitedR2 | _stateNzCtxtR1 | _stateVdR1;
                state[j + sscanw] |= _stateNzCtxtR1 | _stateVuR1;
                state[j + 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdlR1 | _stateHlR2;
                state[j - 1] |= _stateNzCtxtR1 | _stateNzCtxtR2 | _stateDdrR1 | _stateHrR2;
              }
            }
          }
        }
        
        csj &= ~(_stateVisitedR1 | _stateVisitedR2);
        state[j] = csj;
      }
    }

    // Decode segment symbol if we need to
    var error = false;
    if ((_options & StdEntropyCoderOptions.OPT_SEG_SYMBOLS) != 0) {
      var sym = mq.decodeSymbol(_unifCtxt) << 3;
      sym |= mq.decodeSymbol(_unifCtxt) << 2;
      sym |= mq.decodeSymbol(_unifCtxt) << 1;
      sym |= mq.decodeSymbol(_unifCtxt);
      // Set error condition accordingly
      error = sym != _segSymbol;
    }

    // Check the error resilience termination
    if (terminated && (_options & StdEntropyCoderOptions.OPT_PRED_TERM) != 0) {
      error = mq.checkPredTerm();
    }

    // Reset the MQ context states if we need to
    if ((_options & StdEntropyCoderOptions.OPT_RESET_MQ) != 0) {
      mq.resetCtxts();
    }

    return error;
  }

  /// Raw magnitude refinement pass stub - refines magnitude bits using raw coding
  /// This is a placeholder implementation for raw magnitude refinement
  bool _rawMagRefPassStub(
    DataBlkInt cblk,
    ByteToBitInput bin,
    int bitPlane,
    List<int> state,
    bool terminated,
  ) {
    // Raw magnitude refinement pass - processes magnitude refinement using raw bit input
    // without MQ coding. This is used for speed in higher bit-planes.
    trace('rawMagRefPass start bp=$bitPlane');
    final data = cblk.data!;
    final dscanw = cblk.scanw;
    final sscanw = cblk.w + 2;
    final jstep = sscanw * StdEntropyCoderOptions.STRIPE_HEIGHT ~/ 2 - cblk.w;
    final kstep = dscanw * StdEntropyCoderOptions.STRIPE_HEIGHT - cblk.w;
    final setmask = (1 << bitPlane) >> 1;
    final resetmask = (-1) << (bitPlane + 1);
    final nstripes = (cblk.h + StdEntropyCoderOptions.STRIPE_HEIGHT - 1) ~/
        StdEntropyCoderOptions.STRIPE_HEIGHT;

    // Decode stripe by stripe (top to bottom)
    var sk = cblk.offset;
    var sj = sscanw + 1;
    for (var s = 0; s < nstripes; s++, sk += kstep, sj += jstep) {
      final stripeHeight = (s < nstripes - 1)
          ? StdEntropyCoderOptions.STRIPE_HEIGHT
          : cblk.h - (nstripes - 1) * StdEntropyCoderOptions.STRIPE_HEIGHT;
      final stopsk = sk + cblk.w;
      
      // Scan by set of 1 stripe column at a time
      for (; sk < stopsk; sk++, sj++) {
        // Do half top of column
        var j = sj;
        var csj = state[j];
        
        // If any of the two samples is significant and not yet
        // visited in the current bit-plane we can not skip them
        if ((((csj >>> 1) & (~csj)) & _vstdMaskR1R2) != 0) {
          var k = sk;
          
          // Scan first row
          if ((csj & (_stateSigR1 | _stateVisitedR1)) == _stateSigR1) {
            // Read raw bit (no MR primitive)
            final sym = bin.readBit();
            // Update the data
            data[k] &= resetmask;
            data[k] |= (sym << bitPlane) | setmask;
            // No need to set STATE_PREV_MR_R1 since all magnitude 
            // refinement passes to follow are "raw"
          }
          
          if (stripeHeight < 2) continue;
          
          // Scan second row
          if ((csj & (_stateSigR2 | _stateVisitedR2)) == _stateSigR2) {
            k += dscanw;
            // Read raw bit (no MR primitive)
            final sym = bin.readBit();
            // Update the data
            data[k] &= resetmask;
            data[k] |= (sym << bitPlane) | setmask;
            // No need to set STATE_PREV_MR_R2 since all magnitude 
            // refinement passes to follow are "raw"
          }
        }
        
        // Do half bottom of column
        if (stripeHeight < 3) continue;
        j += sscanw;
        csj = state[j];
        
        // If any of the two samples is significant and not yet
        // visited in the current bit-plane we can not skip them
        if ((((csj >>> 1) & (~csj)) & _vstdMaskR1R2) != 0) {
          var k = sk + (dscanw << 1);
          
          // Scan first row
          if ((csj & (_stateSigR1 | _stateVisitedR1)) == _stateSigR1) {
            // Read raw bit (no MR primitive)
            final sym = bin.readBit();
            // Update the data
            data[k] &= resetmask;
            data[k] |= (sym << bitPlane) | setmask;
            // No need to set STATE_PREV_MR_R1 since all magnitude 
            // refinement passes to follow are "raw"
          }
          
          if (stripeHeight < 4) continue;
          
          // Scan second row
          if ((state[j] & (_stateSigR2 | _stateVisitedR2)) == _stateSigR2) {
            k += dscanw;
            // Read raw bit (no MR primitive)
            final sym = bin.readBit();
            // Update the data
            data[k] &= resetmask;
            data[k] |= (sym << bitPlane) | setmask;
            // No need to set STATE_PREV_MR_R2 since all magnitude 
            // refinement passes to follow are "raw"
          }
        }
      }
    }

    var error = false;

    // Check the byte padding if the pass is terminated and the
    // predictable termination is signaled in COx marker.
    if (terminated && (_options & StdEntropyCoderOptions.OPT_PRED_TERM) != 0) {
      error = bin.checkBytePadding();
    }

    // Return error condition
    return error;
  }
}



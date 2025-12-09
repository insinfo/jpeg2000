import 'dart:io';

import 'package:jpeg2000/src/j2k/io/BeBufferedRandomAccessFile.dart';
import 'package:jpeg2000/src/j2k/util/DecoderDebugConfig.dart';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/codestream/HeaderInfo.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/BitstreamReaderAgent.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/HeaderDecoder.dart';
import 'package:jpeg2000/src/j2k/decoder/DecoderSpecs.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/StdEntropyDecoder.dart';
import 'package:jpeg2000/src/j2k/fileformat/FileFormatReader.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/image/DataBlkInt.dart';

import 'package:jpeg2000/src/j2k/io/RandomAccessIO.dart';

import 'package:jpeg2000/src/j2k/util/DecoderInstrumentation.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SubbandSyn.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilter.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilterFloatLift9x7.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilterIntLift5x3.dart';

void main() {
  test('captures MQ trace for checkerboard reference', () {
    const defaultFixture =
        'test_images/visual_tests/checkerboard_32_openjpeg.jp2';
    final fixturePath =
        Platform.environment['MQ_TRACE_FIXTURE'] ?? defaultFixture;
    final fixtureFile = File(fixturePath);

    if (!fixtureFile.existsSync()) {
      fail('Fixture not found: $fixturePath');
    }

    final RandomAccessIO input =
        BEBufferedRandomAccessFile.file(fixtureFile, 'r');
    final instrumentationWasEnabled = DecoderInstrumentation.isEnabled();
    DecoderInstrumentation.configure(true);

    try {
      final headerInfo = HeaderInfo();
      final ffReader = FileFormatReader(input);
      ffReader.readFileFormat();
      if (ffReader.JP2FFUsed) {
        input.seek(ffReader.getFirstCodeStreamPos());
      }

        final headerDecoder =
          HeaderDecoder.readMainHeader(input: input, headerInfo: headerInfo);
        final decSpec = headerDecoder.decSpec;
        expect(decSpec, isNotNull, reason: 'Decoder specs should be available.');
        final specs = decSpec;
        _ensureWaveletFilters(specs);

      final bitstreamReader = BitstreamReaderAgent.createInstance(
        input,
        headerDecoder,
        ParameterList(),
        specs,
        false,
        headerInfo,
      );

      final StdEntropyDecoder entropyDecoder =
          headerDecoder.createEntropyDecoder(
        bitstreamReader,
        ParameterList(),
      );

      const tileIndex = 0;
      const component = 0;
      entropyDecoder.setTile(tileIndex, component);
      final targetSubband =
          _firstLeafSubband(entropyDecoder, tileIndex, component);
      expect(targetSubband, isNotNull,
          reason: 'Expected at least one synthesized subband.');

      final codeBlocks = targetSubband!.numCb;
      expect(_hasCodeBlocks(codeBlocks), isTrue,
          reason: 'Target subband should expose at least one code-block.');

      final traceBuffer = StringBuffer();
      entropyDecoder.configureDebug(
        traceFilter: TraceBlockFilter(
          tileIndex: tileIndex,
          component: component,
          resolutionLevel: targetSubband.resLvl,
          band: targetSubband.sbandIdx,
          cblkY: 0,
          cblkX: 0,
        ),
        mqTraceSink: (line) => traceBuffer.writeln(line),
      );

      final block = DataBlkInt();
      entropyDecoder.getCodeBlock(component, 0, 0, targetSubband, block);

      final traceText = traceBuffer.toString().trim();
      expect(traceText, isNotEmpty,
          reason: 'Expected MQ trace output for the first LL code-block.');
    } finally {
      DecoderInstrumentation.configure(instrumentationWasEnabled);
      input.close();
    }
  });
}

SubbandSyn? _firstLeafSubband(
  StdEntropyDecoder decoder,
  int tileIndex,
  int component,
) {
  SubbandSyn current = decoder.getSynSubbandTree(tileIndex, component);
  while (current.isNode) {
    final next = current.getLL();
    if (next is! SubbandSyn) {
      return null;
    }
    current = next;
  }
  return current;
}

bool _hasCodeBlocks(Coord? coord) =>
    coord != null && coord.x > 0 && coord.y > 0;

List<List<SynWTFilter>> _createDefaultFilters(int levels, bool reversible) {
  final effectiveLevels = levels <= 0 ? 0 : levels;
  if (effectiveLevels == 0) {
    return <List<SynWTFilter>>[
      List<SynWTFilter>.empty(growable: false),
      List<SynWTFilter>.empty(growable: false),
    ];
  }

  SynWTFilter instantiate() =>
      reversible ? SynWTFilterIntLift5x3() : SynWTFilterFloatLift9x7();

  final horizontal =
      List<SynWTFilter>.generate(effectiveLevels, (_) => instantiate(), growable: false);
  final vertical =
      List<SynWTFilter>.generate(effectiveLevels, (_) => instantiate(), growable: false);
  return <List<SynWTFilter>>[horizontal, vertical];
}

void _ensureWaveletFilters(DecoderSpecs specs) {
  final filtersSpec = specs.wfs;
  final tiles = filtersSpec.nTiles;
  final components = filtersSpec.nComp;

  for (var tile = 0; tile < tiles; tile++) {
    for (var component = 0; component < components; component++) {
      var filters = filtersSpec.getTileCompVal(tile, component);
      if (filters != null) {
        continue;
      }

      final levels = specs.dls.getTileCompVal(tile, component) ?? 0;
      final reversible = specs.qts.isReversible(tile, component);
      filters = _createDefaultFilters(levels, reversible);
      filtersSpec.setTileCompVal(tile, component, filters);
    }
  }
}


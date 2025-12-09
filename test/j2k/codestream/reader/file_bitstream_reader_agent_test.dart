import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/codestream/ProgressionType.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/CBlkInfo.dart';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/codestream/HeaderInfo.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/BitstreamReaderAgent.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/HeaderDecoder.dart';
import 'package:jpeg2000/src/j2k/decoder/DecoderSpecs.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/quantization/dequantizer/StdDequantizerParams.dart';

import 'package:jpeg2000/src/j2k/util/ISRandomAccessIO.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';
import 'package:jpeg2000/src/j2k/util/StringFormatException.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilter.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilterIntLift5x3.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SubbandSyn.dart';
import 'package:jpeg2000/src/j2k/wavelet/WaveletFilter.dart';

void main() {
  group('FileBitstreamReaderAgent multi tile-part handling', () {
    test('consumes packet budgets across tile-parts', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 4);
      decSpec.dls.setTileCompVal(0, 0, 0);
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      final quantParams = StdDequantizerParams(
        exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
        nStep: defaultQuant.nStep,
      );
      decSpec.qsss.setTileCompVal(0, 0, quantParams);
      decSpec.gbs.setTileCompVal(0, 0, 1);
      final reversibleFilter = SynWTFilterIntLift5x3();
      decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
        <SynWTFilter>[reversibleFilter],
        <SynWTFilter>[reversibleFilter],
      ]);

      final headerInfo = HeaderInfo();
      final siz = headerInfo.getNewSIZ()
        ..lsiz = 38
        ..rsiz = 0
        ..xsiz = 32
        ..ysiz = 32
        ..x0siz = 0
        ..y0siz = 0
        ..xtsiz = 32
        ..ytsiz = 32
        ..xt0siz = 0
        ..yt0siz = 0
        ..csiz = 1
        ..ssiz = <int>[8]
        ..xrsiz = <int>[1]
        ..yrsiz = <int>[1];
      headerInfo.siz = siz;

      final headerDecoder = HeaderDecoder(
        decSpec: decSpec,
        headerInfo: headerInfo,
        numComps: 1,
        imgWidth: 32,
        imgHeight: 32,
        imgULX: 0,
        imgULY: 0,
        nomTileWidth: 32,
        nomTileHeight: 32,
        cbULX: 0,
        cbULY: 0,
        compSubsX: const <int>[1],
        compSubsY: const <int>[1],
        maxCompImgWidth: 32,
        maxCompImgHeight: 32,
        tilingOrigin: Coord(0, 0),
      );

      headerDecoder.parseSotMarker(
        Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x02]),
      );
      headerDecoder.parseSotMarker(
        Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1E, 0x01, 0x02]),
      );
      headerDecoder.registerTilePartDataOffset(0, 0, 16);
      headerDecoder.registerTilePartBodyLength(0, 0, 20);
      headerDecoder.registerTilePartDataOffset(0, 1, 64);
      headerDecoder.registerTilePartBodyLength(0, 1, 28);

      final input = ISRandomAccessIO(Uint8List(128));
      final parameters = ParameterList()
        ..put('trunc', 'off');
      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      final consumptions = <int>[10, 14, 12, 18];
      final transitions = <String>[];
      var packetIndex = 0;
      var currentTilePart = 0;

      agent.debugSetPacketSimulation(
        consumptions.length,
        (int layer, int resolution, int component, int precinct, List<int> remainingBytes) {
          final tileBudget = remainingBytes[agent.getTileIdx()];
          final consumption = consumptions[packetIndex++];
          final updated = tileBudget - consumption;
          remainingBytes[agent.getTileIdx()] = updated;
          if (updated <= 0) {
            transitions.add('tilePart$currentTilePart-exhausted');
            currentTilePart++;
            return true;
          }
          transitions.add('tilePart$currentTilePart-consumed$consumption');
          return false;
        },
      );

      headerDecoder.registerPackedPacketHeaders(0, Uint8List.fromList(<int>[1, 2, 3]));

      // Ensure tile budgets observed during decoding.
      agent.setTile(0, 0);
      expect(input.getPos(), equals(64));

      agent.debugClearPacketSimulation();
      input.close();

      expect(transitions, contains('tilePart0-consumed10'));
      expect(transitions, contains('tilePart0-exhausted'));
      expect(transitions, contains('tilePart1-consumed12'));
      expect(transitions.last, equals('tilePart1-exhausted'));
      expect(decSpec.pphs.getTileDef(0), isTrue);
      expect(headerDecoder.getTilePartLengths(0), equals(<int>[24, 30]));
    });
  });

  group('FileBitstreamReaderAgent byte budgets', () {
    test('enforces nbytes across tile parts', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 3);
      final reversibleFilter = SynWTFilterIntLift5x3();
      decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
        <SynWTFilter>[reversibleFilter],
        <SynWTFilter>[reversibleFilter],
      ]);
      decSpec.dls.setTileCompVal(0, 0, 0);
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      final quantParams = StdDequantizerParams(
        exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
        nStep: defaultQuant.nStep,
      );
      decSpec.qsss.setTileCompVal(0, 0, quantParams);
      decSpec.gbs.setTileCompVal(0, 0, 1);

      final headerInfo = HeaderInfo();
      final siz = headerInfo.getNewSIZ()
        ..lsiz = 38
        ..rsiz = 0
        ..xsiz = 32
        ..ysiz = 32
        ..x0siz = 0
        ..y0siz = 0
        ..xtsiz = 32
        ..ytsiz = 32
        ..xt0siz = 0
        ..yt0siz = 0
        ..csiz = 1
        ..ssiz = <int>[8]
        ..xrsiz = <int>[1]
        ..yrsiz = <int>[1];
      headerInfo.siz = siz;

      final headerDecoder = HeaderDecoder(
        decSpec: decSpec,
        headerInfo: headerInfo,
        numComps: 1,
        imgWidth: 32,
        imgHeight: 32,
        imgULX: 0,
        imgULY: 0,
        nomTileWidth: 32,
        nomTileHeight: 32,
        cbULX: 0,
        cbULY: 0,
        compSubsX: const <int>[1],
        compSubsY: const <int>[1],
        maxCompImgWidth: 32,
        maxCompImgHeight: 32,
        tilingOrigin: Coord(0, 0),
      );

      headerDecoder.parseSotMarker(
        Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x02]),
      );
      headerDecoder.parseSotMarker(
        Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1E, 0x01, 0x02]),
      );
      headerDecoder.registerTilePartDataOffset(0, 0, 16);
      headerDecoder.registerTilePartBodyLength(0, 0, 20);
      headerDecoder.registerTilePartDataOffset(0, 1, 64);
      headerDecoder.registerTilePartBodyLength(0, 1, 28);

      final input = ISRandomAccessIO(Uint8List(128));
      final parameters = ParameterList()
        ..put('parsing', 'off')
        ..put('rate', '-1')
        ..put('nbytes', '40')
        ..put('ncb_quit', '-1')
        ..put('l_quit', '-1')
        ..put('poc_quit', 'off')
        ..put('one_tp', 'off')
        ..put('trunc', 'off');

      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      final consumptions = <int>[8, 8, 8, 8, 8];
      var packetIndex = 0;

      agent.debugSetPacketSimulation(
        consumptions.length,
        (int layer, int resolution, int component, int precinct, List<int> remainingBytes) {
          expect(packetIndex < consumptions.length, isTrue,
              reason: 'Decoder requested more packets than provided by the test.');
          final tileBudget = remainingBytes[agent.getTileIdx()];
          final consumption = consumptions[packetIndex++];
          final updated = tileBudget - consumption;
          remainingBytes[agent.getTileIdx()] = updated;
          return updated <= 0;
        },
      );

      agent.setTile(0, 0);
      agent.debugClearPacketSimulation();
      input.close();

      expect(packetIndex, equals(5));
      expect(agent.getActualNbytes(), equals(46));
    });

    test('honors truncation codestream tile order', () {
      final decSpec = DecoderSpecs.basic(2, 1);
      final reversibleFilter = SynWTFilterIntLift5x3();
      for (var tile = 0; tile < 2; tile++) {
        decSpec.nls.setTileDef(tile, 3);
        decSpec.wfs.setTileCompVal(tile, 0, <List<SynWTFilter>>[
          <SynWTFilter>[reversibleFilter],
          <SynWTFilter>[reversibleFilter],
        ]);
        decSpec.dls.setTileCompVal(tile, 0, 0);
        final defaultQuant = decSpec.qsss.getDefault();
        if (defaultQuant == null) {
          fail('DecoderSpecs.basic should provide default quantization parameters');
        }
        final quantParams = StdDequantizerParams(
          exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
          nStep: defaultQuant.nStep,
        );
        decSpec.qsss.setTileCompVal(tile, 0, quantParams);
        decSpec.gbs.setTileCompVal(tile, 0, 1);
      }

      final headerInfo = HeaderInfo();
      final siz = headerInfo.getNewSIZ()
        ..lsiz = 38
        ..rsiz = 0
        ..xsiz = 64
        ..ysiz = 32
        ..x0siz = 0
        ..y0siz = 0
        ..xtsiz = 32
        ..ytsiz = 32
        ..xt0siz = 0
        ..yt0siz = 0
        ..csiz = 1
        ..ssiz = <int>[8]
        ..xrsiz = <int>[1]
        ..yrsiz = <int>[1];
      headerInfo.siz = siz;

      final headerDecoder = HeaderDecoder(
        decSpec: decSpec,
        headerInfo: headerInfo,
        numComps: 1,
        imgWidth: 64,
        imgHeight: 32,
        imgULX: 0,
        imgULY: 0,
        nomTileWidth: 32,
        nomTileHeight: 32,
        cbULX: 0,
        cbULY: 0,
        compSubsX: const <int>[1],
        compSubsY: const <int>[1],
        maxCompImgWidth: 64,
        maxCompImgHeight: 32,
        tilingOrigin: Coord(0, 0),
      );

      headerDecoder.parseSotMarker(_buildSotPayload(1, 24));
      headerDecoder.registerTilePartHeaderLength(1, 0, 4);
      headerDecoder.registerTilePartBodyLength(1, 0, 20);
      headerDecoder.setTileOfTileParts(1);

      headerDecoder.parseSotMarker(_buildSotPayload(0, 24));
      headerDecoder.registerTilePartHeaderLength(0, 0, 4);
      headerDecoder.registerTilePartBodyLength(0, 0, 20);
      headerDecoder.setTileOfTileParts(0);

      expect(headerDecoder.getTilePartBodyLengths(0), equals(<int>[20]));
      expect(headerDecoder.getTilePartBodyLengths(1), equals(<int>[20]));
      expect(headerDecoder.getTilePartHeaderLengths(0), equals(<int>[4]));
      expect(headerDecoder.getTilePartHeaderLengths(1), equals(<int>[4]));
      expect(headerDecoder.getTilePartTileOrder(), equals(<int>[1, 0]));

      final input = ISRandomAccessIO(Uint8List(0));
      final parameters = ParameterList()
        ..put('parsing', 'off')
        ..put('rate', '-1')
        ..put('nbytes', '18')
        ..put('ncb_quit', '-1')
        ..put('l_quit', '-1')
        ..put('poc_quit', 'off')
        ..put('one_tp', 'off')
        ..put('trunc', 'off');

      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      final budgets = agent.debugGetTileBudgets();
      expect(budgets.length, equals(2));
      expect(budgets[0], equals(0));
      expect(budgets[1], equals(14));
      final cachedBodies = agent.debugGetCachedTilePartBodyLengths();
      expect(cachedBodies[0], equals(<int>[20]));
      expect(cachedBodies[1], equals(<int>[20]));

      final consumptions = <int>[5, 5, 4];
      final tilesVisited = <int>[];
      var packetIndex = 0;

      agent.debugSetPacketSimulation(
        consumptions.length,
        (int layer, int resolution, int component, int precinct, List<int> remainingBytes) {
          tilesVisited.add(agent.getTileIdx());
          final tileBudget = remainingBytes[agent.getTileIdx()];
          final consumption = consumptions[packetIndex++];
          remainingBytes[agent.getTileIdx()] = tileBudget - consumption;
          return remainingBytes[agent.getTileIdx()] <= 0;
        },
      );

      agent.setTile(0, 0);
      expect(packetIndex, equals(0));
      expect(agent.getActualNbytes(), equals(4));

      agent.setTile(1, 0);
      agent.debugClearPacketSimulation();
      input.close();

      expect(packetIndex, equals(consumptions.length));
      expect(tilesVisited, everyElement(equals(1)));
      expect(agent.getActualNbytes(), equals(18));
    });

    test('one_tp restricts decoding to the first tile part', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 3);
      decSpec.dls.setTileCompVal(0, 0, 0);
      final reversibleFilter = SynWTFilterIntLift5x3();
      decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
        <SynWTFilter>[reversibleFilter],
        <SynWTFilter>[reversibleFilter],
      ]);
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      final quantParams = StdDequantizerParams(
        exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
        nStep: defaultQuant.nStep,
      );
      decSpec.qsss.setTileCompVal(0, 0, quantParams);
      decSpec.gbs.setTileCompVal(0, 0, 1);

      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);

      headerDecoder.parseSotMarker(
        Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x02]),
      );
      headerDecoder.registerTilePartHeaderLength(0, 0, 4);
      headerDecoder.registerTilePartBodyLength(0, 0, 20);
      headerDecoder.registerTilePartDataOffset(0, 0, 16);

      headerDecoder.parseSotMarker(
        Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1E, 0x01, 0x02]),
      );
      headerDecoder.registerTilePartHeaderLength(0, 1, 4);
      headerDecoder.registerTilePartBodyLength(0, 1, 28);
      headerDecoder.registerTilePartDataOffset(0, 1, 64);

      final input = ISRandomAccessIO(Uint8List(128));
      final parameters = _buildBaseParameters(
        parsing: 'off',
        nbytes: '200',
        oneTp: 'on',
      );

      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      final cachedBodies = agent.debugGetCachedTilePartBodyLengths();
      expect(cachedBodies[0], equals(<int>[20]));

      final budgets = agent.debugGetTileBudgets();
      expect(budgets[0], equals(20));

      input.close();
    });
  });

  group('FileBitstreamReaderAgent quit options', () {
    test('rejects ncb_quit when parsing mode is enabled', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 2);

      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);
      _registerSingleTilePart(headerDecoder, 0);

      final input = ISRandomAccessIO(Uint8List(32));
      final parameters = _buildBaseParameters(parsing: 'on', ncbQuit: '2');

      expect(
        () => FileBitstreamReaderAgent(
          headerDecoder,
          input,
          decSpec,
          parameters,
          false,
          headerInfo,
        ),
        throwsA(isA<StringFormatException>()),
      );

      input.close();
    });

    test('propagates ncb_quit to the packet decoder', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 2);
      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);
      _registerSingleTilePart(headerDecoder, 0);

      final input = ISRandomAccessIO(Uint8List(32));
      final parameters = _buildBaseParameters(ncbQuit: '5');

      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      expect(agent.debugGetPktDecoderMaxCodeBlocks(), equals(5));

      input.close();
    });

      test('ncb_quit stops decoding when max code-blocks reached', () {
        final decSpec = DecoderSpecs.basic(1, 1);
        decSpec.nls.setTileDef(0, 2);
        decSpec.dls.setTileCompVal(0, 0, 0);
        final reversibleFilter = SynWTFilterIntLift5x3();
        decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
          <SynWTFilter>[reversibleFilter],
          <SynWTFilter>[reversibleFilter],
        ]);
        final defaultQuant = decSpec.qsss.getDefault();
        if (defaultQuant == null) {
          fail('DecoderSpecs.basic should provide default quantization parameters');
        }
        final quantParams = StdDequantizerParams(
          exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
          nStep: defaultQuant.nStep,
        );
        decSpec.qsss.setTileCompVal(0, 0, quantParams);
        decSpec.gbs.setTileCompVal(0, 0, 1);

        final headerInfo = HeaderInfo();
        final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);
        _registerSingleTilePart(headerDecoder, 0);

        final parameters = _buildBaseParameters(ncbQuit: '2');
        final input = ISRandomAccessIO(Uint8List(64));

        late PktDecoderHarness harness;
        final agent = FileBitstreamReaderAgent(
          headerDecoder,
          input,
          decSpec,
          parameters,
          false,
          headerInfo,
          pktDecoderFactory: (reader) {
            harness = PktDecoderHarness(
              decSpec,
              headerDecoder,
              input,
              reader,
              true,
              reader.debugGetNcbQuitTarget(),
              codeBlocksPerPacket: 1,
            );
            return harness;
          },
        );

        agent.setTile(0, 0);

        expect(harness.quitTriggered, isTrue);
        expect(harness.packetsDecoded, equals(2));

        input.close();
      });

    test('ncb_quit persists across tiles', () {
      final decSpec = DecoderSpecs.basic(2, 1);
      final reversibleFilter = SynWTFilterIntLift5x3();
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      for (var tile = 0; tile < 2; tile++) {
        final quantParams = StdDequantizerParams(
          exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
          nStep: defaultQuant.nStep,
        );
        decSpec.nls.setTileDef(tile, 2);
        decSpec.dls.setTileCompVal(tile, 0, 0);
        decSpec.wfs.setTileCompVal(tile, 0, <List<SynWTFilter>>[
          <SynWTFilter>[reversibleFilter],
          <SynWTFilter>[reversibleFilter],
        ]);
        decSpec.qsss.setTileCompVal(tile, 0, quantParams);
        decSpec.gbs.setTileCompVal(tile, 0, 1);
      }

      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(
        decSpec,
        headerInfo,
        width: 64,
        height: 32,
        tileWidth: 32,
        tileHeight: 32,
      );
      _registerSingleTilePart(headerDecoder, 0);
      _registerSingleTilePart(headerDecoder, 1);

      final parameters = _buildBaseParameters(ncbQuit: '2');
      final input = ISRandomAccessIO(Uint8List(128));

      late PktDecoderHarness harness;
      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
        pktDecoderFactory: (reader) {
          harness = PktDecoderHarness(
            decSpec,
            headerDecoder,
            input,
            reader,
            true,
            reader.debugGetNcbQuitTarget(),
            codeBlocksPerPacket: 1,
          );
          return harness;
        },
      );

      agent.setTile(0, 0);
      expect(harness.packetsDecoded, equals(2));
      expect(harness.quitTriggered, isTrue);

      final packetsBeforeSecondTile = harness.packetsDecoded;
      agent.setTile(1, 0);
      expect(harness.packetsDecoded, equals(packetsBeforeSecondTile));

      input.close();
    });

    test('ncb_quit stops decoding across components and resolutions', () {
      final decSpec = DecoderSpecs.basic(1, 2);
      final reversibleFilter = SynWTFilterIntLift5x3();
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }

      for (var comp = 0; comp < 2; comp++) {
        final quantParams = StdDequantizerParams(
          exp: <List<int>>[
            <int>[0],
            if (comp == 0) <int>[0, 0, 0, 0],
          ],
          nStep: defaultQuant.nStep,
        );
        decSpec.nls.setTileDef(0, 2);
        decSpec.dls.setTileCompVal(0, comp, comp == 0 ? 1 : 0);
        decSpec.wfs.setTileCompVal(0, comp, <List<SynWTFilter>>[
          <SynWTFilter>[reversibleFilter],
          <SynWTFilter>[reversibleFilter],
        ]);
        decSpec.qsss.setTileCompVal(0, comp, quantParams);
        decSpec.gbs.setTileCompVal(0, comp, 1);
      }

      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(
        decSpec,
        headerInfo,
        numComps: 2,
      );
      _registerSingleTilePart(headerDecoder, 0);

      final parameters = _buildBaseParameters(ncbQuit: '1');
      final input = ISRandomAccessIO(Uint8List(128));

      late PktDecoderHarness harness;
      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
        pktDecoderFactory: (reader) {
          harness = PktDecoderHarness(
            decSpec,
            headerDecoder,
            input,
            reader,
            true,
            reader.debugGetNcbQuitTarget(),
            codeBlocksPerPacket: 1,
          );
          return harness;
        },
      );

      agent.setTile(0, 0);
      expect(harness.packetsDecoded, equals(1));
      expect(harness.quitTriggered, isTrue);

      input.close();
    });

    test('l_quit clamps the number of returned layers', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 3);
      decSpec.dls.setTileCompVal(0, 0, 0);
      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);
      _registerSingleTilePart(headerDecoder, 0);

      final input = ISRandomAccessIO(Uint8List(32));
      final parameters = _buildBaseParameters(lQuit: '2');

      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      final blockInfo = CBlkInfo(0, 0, 4, 4, 3);
      for (var layer = 0; layer < 3; layer++) {
        final length = (layer + 1) * 5;
        blockInfo.len[layer] = length;
        blockInfo.body[layer] = Uint8List(length);
        blockInfo.addNTP(layer, 1);
      }

      agent.cbI = _singleBlockGrid(blockInfo);
      final reversibleFilter = SynWTFilterIntLift5x3();
      final filters = <WaveletFilter>[reversibleFilter];
      final tree = SubbandSyn.tree(
        4,
        4,
        0,
        0,
        0,
        filters,
        filters,
      );
      final subband = tree.getSubbandByIdx(0, 0) as SubbandSyn;

      final block = agent.getCodeBlock(0, 0, 0, subband, 1, -1, null);

      expect(block.nl, equals(1));
      expect(block.dl, equals(blockInfo.len[0]));
      expect(block.data, isNotNull);
      expect(block.data!.length, equals(blockInfo.len[0]));

      input.close();
    });

    test('poc_quit restricts traversal to the first POC entry', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 4);
      decSpec.dls.setTileCompVal(0, 0, 1);
      decSpec.pcs.setTileDef(0, <List<int>>[
        <int>[0, 0, 1, 1, 1, ProgressionType.LY_RES_COMP_POS_PROG],
        <int>[1, 0, 4, 2, 1, ProgressionType.RES_LY_COMP_POS_PROG],
      ]);

      final headerInfoOff = HeaderInfo();
      final headerDecoderOff = _createHeaderDecoder(decSpec, headerInfoOff);
      _registerSingleTilePart(headerDecoderOff, 0);
      final inputOff = ISRandomAccessIO(Uint8List(32));

      final offParams = _buildBaseParameters(pocQuit: 'off');
      final agentOff = FileBitstreamReaderAgent(
        headerDecoderOff,
        inputOff,
        decSpec,
        offParams,
        false,
        headerInfoOff,
      );

      final segmentsOff = agentOff.debugDescribeProgressionSegments();
      expect(segmentsOff.length, equals(2));
      expect(segmentsOff[0]['layerEnd'], equals(1));
      expect(segmentsOff[1]['layerEnd'], equals(4));

      final headerInfoOn = HeaderInfo();
      final headerDecoderOn = _createHeaderDecoder(decSpec, headerInfoOn);
      _registerSingleTilePart(headerDecoderOn, 0);
      final inputOn = ISRandomAccessIO(Uint8List(32));

      final onParams = _buildBaseParameters(pocQuit: 'on');
      final agentOn = FileBitstreamReaderAgent(
        headerDecoderOn,
        inputOn,
        decSpec,
        onParams,
        false,
        headerInfoOn,
      );

      final segmentsOn = agentOn.debugDescribeProgressionSegments();
      expect(segmentsOn.length, equals(1));
      expect(segmentsOn.first['layerEnd'], equals(1));
      expect(segmentsOn.first['progression'], equals(ProgressionType.LY_RES_COMP_POS_PROG));

      inputOff.close();
      inputOn.close();
    });

    test('poc_quit halts packet decoding after the first POC entry', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 4);
      decSpec.dls.setTileCompVal(0, 0, 1);
      decSpec.pcs.setTileDef(0, <List<int>>[
        <int>[0, 0, 1, 1, 1, ProgressionType.LY_RES_COMP_POS_PROG],
        <int>[1, 0, 4, 2, 1, ProgressionType.LY_RES_COMP_POS_PROG],
      ]);
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      final quantParams = StdDequantizerParams(
        exp: <List<int>>[
          <int>[0],
          <int>[0, 0, 0, 0],
        ],
        nStep: defaultQuant.nStep,
      );
      decSpec.qsss.setTileCompVal(0, 0, quantParams);
      decSpec.gbs.setTileCompVal(0, 0, 1);
      final reversibleFilter = SynWTFilterIntLift5x3();
      decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
        <SynWTFilter>[reversibleFilter],
        <SynWTFilter>[reversibleFilter],
      ]);

      PktDecoderHarness _runAgent(String pocQuit) {
        final headerInfo = HeaderInfo();
        final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);
        _registerSingleTilePart(headerDecoder, 0);
        final input = ISRandomAccessIO(Uint8List(64));
        final params = _buildBaseParameters(pocQuit: pocQuit);

        late PktDecoderHarness harness;
        final agent = FileBitstreamReaderAgent(
          headerDecoder,
          input,
          decSpec,
          params,
          false,
          headerInfo,
          pktDecoderFactory: (reader) {
            harness = PktDecoderHarness(
              decSpec,
              headerDecoder,
              input,
              reader,
              true,
              reader.debugGetNcbQuitTarget(),
              codeBlocksPerPacket: 1,
            );
            return harness;
          },
        );

        agent.setTile(0, 0);
        input.close();
        return harness;
      }

      final harnessOff = _runAgent('off');
      final harnessOn = _runAgent('on');

      expect(harnessOff.quitTriggered, isFalse);
      expect(harnessOn.quitTriggered, isFalse);
      expect(harnessOff.packetsDecoded, greaterThan(harnessOn.packetsDecoded));
      expect(harnessOn.packetsDecoded, equals(1));
    });
  });

  group('FileBitstreamReaderAgent resolution selection', () {
    test('res option clamps to available levels', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 2);
      decSpec.dls.setDefault(3);
      decSpec.dls.setTileCompVal(0, 0, 3);
      final reversibleFilter = SynWTFilterIntLift5x3();
      decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
        <SynWTFilter>[reversibleFilter],
        <SynWTFilter>[reversibleFilter],
      ]);
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      final quantParams = StdDequantizerParams(
        exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
        nStep: defaultQuant.nStep,
      );
      decSpec.qsss.setTileCompVal(0, 0, quantParams);
      decSpec.gbs.setTileCompVal(0, 0, 1);

      final headerInfoWithin = HeaderInfo();
      final headerDecoderWithin = _createHeaderDecoder(decSpec, headerInfoWithin);
      _registerSingleTilePart(headerDecoderWithin, 0);

      final unrestrictedParams = _buildBaseParameters()
        ..put('res', '2');
      final inputWithin = ISRandomAccessIO(Uint8List(64));
      final agentWithin = FileBitstreamReaderAgent(
        headerDecoderWithin,
        inputWithin,
        decSpec,
        unrestrictedParams,
        false,
        headerInfoWithin,
      );
      expect(agentWithin.targetRes, equals(2));
      inputWithin.close();

      final headerInfoClamp = HeaderInfo();
      final headerDecoderClamp = _createHeaderDecoder(decSpec, headerInfoClamp);
      _registerSingleTilePart(headerDecoderClamp, 0);

      final clampParams = _buildBaseParameters()
        ..put('res', '5');
      final inputClamp = ISRandomAccessIO(Uint8List(64));
      final agentClamp = FileBitstreamReaderAgent(
        headerDecoderClamp,
        inputClamp,
        decSpec,
        clampParams,
        false,
        headerInfoClamp,
      );
      expect(agentClamp.targetRes, equals(3));
      inputClamp.close();
    });
  });

  group('FileBitstreamReaderAgent rate handling', () {
    test('translates rate option into target bytes', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 3);
      decSpec.dls.setTileCompVal(0, 0, 0);
      final reversibleFilter = SynWTFilterIntLift5x3();
      decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
        <SynWTFilter>[reversibleFilter],
        <SynWTFilter>[reversibleFilter],
      ]);
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      final quantParams = StdDequantizerParams(
        exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
        nStep: defaultQuant.nStep,
      );
      decSpec.qsss.setTileCompVal(0, 0, quantParams);
      decSpec.gbs.setTileCompVal(0, 0, 1);

      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);
      _registerSingleTilePart(headerDecoder, 0);

      final parameters = _buildBaseParameters(
        parsing: 'off',
        rate: '0.5',
        nbytes: null,
      );

      final input = ISRandomAccessIO(Uint8List(64));
      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      expect(agent.getTargetRate(), equals(0.5));
      expect(agent.getTargetNbytes(), equals(64));

      input.close();
    });

    test('explicit nbytes overrides rate-derived target', () {
      final decSpec = DecoderSpecs.basic(1, 1);
      decSpec.nls.setTileDef(0, 3);
      decSpec.dls.setTileCompVal(0, 0, 0);
      final reversibleFilter = SynWTFilterIntLift5x3();
      decSpec.wfs.setTileCompVal(0, 0, <List<SynWTFilter>>[
        <SynWTFilter>[reversibleFilter],
        <SynWTFilter>[reversibleFilter],
      ]);
      final defaultQuant = decSpec.qsss.getDefault();
      if (defaultQuant == null) {
        fail('DecoderSpecs.basic should provide default quantization parameters');
      }
      final quantParams = StdDequantizerParams(
        exp: defaultQuant.exp.isNotEmpty ? defaultQuant.exp : <List<int>>[<int>[0]],
        nStep: defaultQuant.nStep,
      );
      decSpec.qsss.setTileCompVal(0, 0, quantParams);
      decSpec.gbs.setTileCompVal(0, 0, 1);

      final headerInfo = HeaderInfo();
      final headerDecoder = _createHeaderDecoder(decSpec, headerInfo);
      _registerSingleTilePart(headerDecoder, 0);

      final parameters = _buildBaseParameters(
        parsing: 'off',
        rate: '1.0',
        nbytes: '80',
      );

      final input = ISRandomAccessIO(Uint8List(64));
      final agent = FileBitstreamReaderAgent(
        headerDecoder,
        input,
        decSpec,
        parameters,
        false,
        headerInfo,
      );

      expect(agent.getTargetNbytes(), equals(80));
      expect(agent.getTargetRate(), closeTo(80 * 8 / 32 / 32, 1e-9));

      input.close();
    });
  });
}

Uint8List _buildSotPayload(int tileIdx, int psot) {
  final buffer = Uint8List(10);
  final view = ByteData.view(buffer.buffer);
  view.setUint16(0, 10);
  view.setUint16(2, tileIdx);
  view.setUint32(4, psot);
  view.setUint8(8, 0);
  view.setUint8(9, 1);
  return buffer;
}

HeaderDecoder _createHeaderDecoder(
  DecoderSpecs decSpec,
  HeaderInfo headerInfo, {
  int width = 32,
  int height = 32,
  int tileWidth = 32,
  int tileHeight = 32,
  int numComps = 1,
}) {
  final siz = headerInfo.getNewSIZ()
    ..lsiz = 38
    ..rsiz = 0
    ..xsiz = width
    ..ysiz = height
    ..x0siz = 0
    ..y0siz = 0
    ..xtsiz = tileWidth
    ..ytsiz = tileHeight
    ..xt0siz = 0
    ..yt0siz = 0
    ..csiz = numComps
    ..ssiz = List<int>.filled(numComps, 8)
    ..xrsiz = List<int>.filled(numComps, 1)
    ..yrsiz = List<int>.filled(numComps, 1);
  headerInfo.siz = siz;

  return HeaderDecoder(
    decSpec: decSpec,
    headerInfo: headerInfo,
    numComps: numComps,
    imgWidth: width,
    imgHeight: height,
    imgULX: 0,
    imgULY: 0,
    nomTileWidth: tileWidth,
    nomTileHeight: tileHeight,
    cbULX: 0,
    cbULY: 0,
    compSubsX: List<int>.filled(numComps, 1),
    compSubsY: List<int>.filled(numComps, 1),
    maxCompImgWidth: width,
    maxCompImgHeight: height,
    tilingOrigin: Coord(0, 0),
  );
}

void _registerSingleTilePart(
  HeaderDecoder headerDecoder,
  int tileIdx, {
  int psot = 24,
  int headerLength = 4,
  int bodyLength = 20,
  int dataOffset = 16,
}) {
  headerDecoder.parseSotMarker(_buildSotPayload(tileIdx, psot));
  headerDecoder.registerTilePartHeaderLength(tileIdx, 0, headerLength);
  headerDecoder.registerTilePartBodyLength(tileIdx, 0, bodyLength);
  headerDecoder.registerTilePartDataOffset(tileIdx, 0, dataOffset);
  headerDecoder.setTileOfTileParts(tileIdx);
}

List<List<List<List<List<CBlkInfo?>?>?>?>?> _singleBlockGrid(CBlkInfo block) {
  final columns = <CBlkInfo?>[block];
  final rows = <List<CBlkInfo?>?>[columns];
  final subbands = <List<List<CBlkInfo?>?>?>[rows];
  final resolutions = <List<List<List<CBlkInfo?>?>?>?>[subbands];
  return <List<List<List<List<CBlkInfo?>?>?>?>?>[resolutions];
}

ParameterList _buildBaseParameters({
  String parsing = 'off',
  String? rate = '-1',
  String? nbytes = '-1',
  String ncbQuit = '-1',
  String lQuit = '-1',
  String pocQuit = 'off',
  String oneTp = 'off',
}) {
  final parameters = ParameterList()
    ..put('parsing', parsing)
    ..put('ncb_quit', ncbQuit)
    ..put('l_quit', lQuit)
    ..put('poc_quit', pocQuit)
    ..put('one_tp', oneTp)
    ..put('trunc', 'off');
  if (rate != null) {
    parameters.put('rate', rate);
  }
  if (nbytes != null) {
    parameters.put('nbytes', nbytes);
  }
  return parameters;
}


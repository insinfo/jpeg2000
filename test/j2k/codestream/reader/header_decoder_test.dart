import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/util/ISRandomAccessIO.dart';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/codestream/HeaderInfo.dart';
import 'package:jpeg2000/src/j2k/codestream/markers.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/HeaderDecoder.dart';
import 'package:jpeg2000/src/j2k/decoder/DecoderSpecs.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/roi/RectangularRoi.dart';
import 'package:jpeg2000/src/j2k/wavelet/FilterTypes.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilterFloatLift9x7.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SynWTFilterIntLift5x3.dart';


import '../test_utils.dart';

void main() {
  group('HeaderDecoder.parsePocMarker', () {
    test('populates decSpec.pcs for main header', () {
      final specs = DecoderSpecs.basic(1, 3);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 3,
      );

      final payload = Uint8List.fromList(<int>[
        0x00,
        0x09,
        0x00,
        0x00,
        0x00,
        0x02,
        0x01,
        0x03,
        0x01,
      ]);

      decoder.parsePocMarker(payload, isMainHeader: true, tileIdx: 0);

      final pocSpec = specs.pcs.getDefault();
      expect(pocSpec, isNotNull);
      expect(pocSpec, hasLength(1));
      expect(pocSpec![0], equals(<int>[0, 0, 2, 1, 3, 1]));

      final pocInfo = info.poc['main'];
      expect(pocInfo, isNotNull);
      expect(pocInfo!.rspoc, equals(<int>[0]));
      expect(pocInfo.cspoc, equals(<int>[0]));
      expect(pocInfo.lyepoc, equals(<int>[2]));
      expect(pocInfo.repoc, equals(<int>[1]));
      expect(pocInfo.cepoc, equals(<int>[3]));
      expect(pocInfo.ppoc, equals(<int>[1]));
    });

    test('applies tile specific progression changes', () {
      final specs = DecoderSpecs.basic(2, 4);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 4,
      );

      final mainPayload = Uint8List.fromList(<int>[
        0x00,
        0x09,
        0x00,
        0x00,
        0x00,
        0x02,
        0x01,
        0x03,
        0x01,
      ]);
      decoder.parsePocMarker(mainPayload, isMainHeader: true, tileIdx: 0);

      final tilePayload = Uint8List.fromList(<int>[
        0x00,
        0x09,
        0x01,
        0x02,
        0x00,
        0x04,
        0x03,
        0x05,
        0x03,
      ]);

      decoder.parsePocMarker(tilePayload, isMainHeader: false, tileIdx: 0);

      final tileSpec = specs.pcs.getTileDef(0);
      expect(tileSpec, isNotNull);
      expect(tileSpec, hasLength(1));
      expect(tileSpec![0], equals(<int>[1, 2, 4, 3, 5, 3]));

      final pocInfo = info.poc['t0'];
      expect(pocInfo, isNotNull);
      expect(pocInfo!.rspoc, equals(<int>[1]));
      expect(pocInfo.cspoc, equals(<int>[2]));
      expect(pocInfo.lyepoc, equals(<int>[4]));
      expect(pocInfo.repoc, equals(<int>[3]));
      expect(pocInfo.cepoc, equals(<int>[5]));
      expect(pocInfo.ppoc, equals(<int>[3]));
    });
  });

  group('HeaderDecoder.parseCodMarker', () {
    test('rejects zero layer count', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final payload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 0,
        sgcodMct: 0x00,
        spcodNdl: 1,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      expect(
        () => decoder.parseCodMarker(payload, isMainHeader: true, tileIdx: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects unsupported progression order ids', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final payload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x05,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 1,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      expect(
        () => decoder.parseCodMarker(payload, isMainHeader: true, tileIdx: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects unsupported coding style flags', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final payload = buildCodMarkerPayload(
        scod: 0x80,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 1,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      expect(
        () => decoder.parseCodMarker(payload, isMainHeader: true, tileIdx: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects unsupported multi-component transform flag', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final payload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x02,
        spcodNdl: 1,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      expect(
        () => decoder.parseCodMarker(payload, isMainHeader: true, tileIdx: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('captures wavelet filter spec for COD defaults', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final codPayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: FilterTypes.W5X3,
      );
      decoder.parseCodMarker(codPayload, isMainHeader: true, tileIdx: 0);

      final hFilters = specs.wfs.getHFilters(0, 0);
      expect(hFilters, hasLength(1));
      expect(hFilters[0], isA<SynWTFilterIntLift5x3>());
    });

    test('locks code-block partition origin after first COD', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final offsetsPayload = buildCodMarkerPayload(
        scod: Markers.SCOX_HOR_CB_PART | Markers.SCOX_VER_CB_PART,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      decoder.parseCodMarker(offsetsPayload, isMainHeader: true, tileIdx: 0);

      expect(decoder.getCbULX(), equals(1));
      expect(decoder.getCbULY(), equals(1));

      final conflictingPayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      expect(
        () =>
            decoder.parseCodMarker(conflictingPayload, isMainHeader: true, tileIdx: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('allows repeated COD markers with identical origins', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final payload = buildCodMarkerPayload(
        scod: Markers.SCOX_HOR_CB_PART | Markers.SCOX_VER_CB_PART,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      decoder.parseCodMarker(payload, isMainHeader: true, tileIdx: 0);
      decoder.parseCodMarker(payload, isMainHeader: true, tileIdx: 0);

      expect(decoder.getCbULX(), equals(1));
      expect(decoder.getCbULY(), equals(1));
    });

    test('rejects tile-specific overrides of code-block origin', () {
      final specs = DecoderSpecs.basic(2, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final mainPayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      decoder.parseCodMarker(mainPayload, isMainHeader: true, tileIdx: 0);

      final tilePayload = buildCodMarkerPayload(
        scod: Markers.SCOX_HOR_CB_PART,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      expect(
        () => decoder.parseCodMarker(tilePayload, isMainHeader: false, tileIdx: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects code-block dimensions above the JPEG 2000 limit', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final payload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 0,
        spcodCw: 0x09, // 1 << (9 + 2) == 2048 > MAX_CB_DIM
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );

      expect(
        () => decoder.parseCodMarker(payload, isMainHeader: true, tileIdx: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('installs tile-scoped precinct defaults even without partition flag', () {
      final specs = DecoderSpecs.basic(2, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final mainPayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 0,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      decoder.parseCodMarker(mainPayload, isMainHeader: true, tileIdx: 0);

      final tilePayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 0,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      decoder.parseCodMarker(tilePayload, isMainHeader: false, tileIdx: 1);

      expect(specs.pss.isTileSpecified(1), isTrue);
      final precincts = specs.pss.getTileDef(1);
      expect(precincts, isNotNull);
      expect(precincts![0], equals(<int>[Markers.PRECINCT_PARTITION_DEF_SIZE]));
      expect(precincts[1], equals(<int>[Markers.PRECINCT_PARTITION_DEF_SIZE]));
    });

    test('applies component-level wavelet filter overrides from COC', () {
      final specs = DecoderSpecs.basic(1, 2);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 2,
      );

      final codPayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: FilterTypes.W5X3,
      );
      decoder.parseCodMarker(codPayload, isMainHeader: true, tileIdx: 0);

      final cocPayload = buildCocMarkerPayload(
        component: 1,
        scoc: 0x00,
        spcocNdl: 1,
        spcocCw: 0x04,
        spcocCh: 0x04,
        spcocCs: 0x00,
        spcocT: FilterTypes.W9X7,
      );
      decoder.parseCocMarker(cocPayload, isMainHeader: true, tileIdx: 0);

      expect(specs.wfs.getHFilters(0, 0)[0], isA<SynWTFilterIntLift5x3>());
      expect(specs.wfs.getHFilters(0, 1)[0], isA<SynWTFilterFloatLift9x7>());
    });

    test('records component precinct defaults when COC omits partition bits', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final codPayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 0,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      decoder.parseCodMarker(codPayload, isMainHeader: true, tileIdx: 0);

      final cocPayload = buildCocMarkerPayload(
        component: 0,
        scoc: 0x00,
        spcocNdl: 0,
        spcocCw: 0x04,
        spcocCh: 0x04,
        spcocCs: 0x00,
        spcocT: 0x01,
      );
      decoder.parseCocMarker(cocPayload, isMainHeader: true, tileIdx: 0);

      expect(specs.pss.isCompSpecified(0), isTrue);
      final precincts = specs.pss.getCompDef(0);
      expect(precincts, isNotNull);
      expect(precincts![0], equals(<int>[Markers.PRECINCT_PARTITION_DEF_SIZE]));
      expect(precincts[1], equals(<int>[Markers.PRECINCT_PARTITION_DEF_SIZE]));
    });
  });

  group('HeaderDecoder.parseCocMarker', () {
    test('rejects unsupported coding style flags', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final codPayload = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 1,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      decoder.parseCodMarker(codPayload, isMainHeader: true, tileIdx: 0);

      final cocPayload = buildCocMarkerPayload(
        component: 0,
        scoc: 0x20,
        spcocNdl: 1,
        spcocCw: 0x03,
        spcocCh: 0x03,
        spcocCs: 0x00,
        spcocT: 0x01,
      );

      expect(
        () => decoder.parseCocMarker(cocPayload, isMainHeader: true, tileIdx: 0),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('HeaderDecoder tile-part metadata', () {
    test('aggregates Psot and exposes packed packet headers', () {
      final specs = DecoderSpecs.basic(2, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
        imgWidth: 0,
        imgHeight: 0,
        imgULX: 0,
        imgULY: 0,
        nomTileWidth: 0,
        nomTileHeight: 0,
        cbULX: 0,
        cbULY: 0,
        compSubsX: const <int>[1],
        compSubsY: const <int>[1],
        maxCompImgWidth: 0,
        maxCompImgHeight: 0,
        tilingOrigin: Coord(0, 0),
      );

      decoder.registerTilePartLength(0, 0, 150);
      decoder.registerTilePartLength(0, 1, 200);
      expect(decoder.nTileParts, contains(2));
      expect(decoder.getTileTotalLength(0), 350);

      decoder.registerTilePartLength(0, 1, 0);
      expect(decoder.getTileTotalLength(0), isNull);

      decoder.registerTilePartLength(0, 1, 200);
      expect(decoder.getTileTotalLength(0), 350);
      final packed = Uint8List.fromList(<int>[1, 2, 3]);
      decoder.registerPackedPacketHeaders(0, packed);
      expect(specs.pphs.getTileDef(0), isTrue);

      final retrieved = decoder.getPackedPacketHeaders(0);
      expect(retrieved, isNotNull);
      expect(retrieved, equals(packed));
    });

    test('parseSotMarker registers tile-part metadata', () {
      final specs = DecoderSpecs.basic(2, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final payload = Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x01, 0x00, 0x00, 0x00, 0x64, 0x02, 0x05]);
      decoder.parseSotMarker(payload);

      final sot = info.sot['t1_tp2'];
      expect(sot, isNotNull);
      expect(sot!.psot, 100);
      expect(decoder.getTileTotalLength(1), 100);
      expect(decoder.nTileParts.length, greaterThan(1));
      expect(decoder.nTileParts[1], greaterThanOrEqualTo(3));
    });

    test('parsePpmMarker assembles packed headers per tile', () {
      final specs = DecoderSpecs.basic(2, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      decoder.setTileOfTileParts(0);
      decoder.setTileOfTileParts(1);

      final ppmPayload = Uint8List.fromList(<int>[
        0x00,
        0x0E,
        0x00,
        0x00,
        0x00,
        0x00,
        0x02,
        0xAA,
        0xBB,
        0x00,
        0x00,
        0x00,
        0x01,
        0xCC,
      ]);

      decoder.parsePpmMarker(ppmPayload);

      final tile0 = decoder.getPackedPacketHeaders(0);
      final tile1 = decoder.getPackedPacketHeaders(1);

      expect(tile0, equals(Uint8List.fromList(<int>[0xAA, 0xBB])));
      expect(tile1, equals(Uint8List.fromList(<int>[0xCC])));
      expect(specs.pphs.getDefault(), isTrue);
    });

    test('parsePptMarker appends headers for each tile part', () {
      final specs = DecoderSpecs.basic(1, 1);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 1,
      );

      final sotPayload = Uint8List.fromList(<int>[0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x01]);
      decoder.parseSotMarker(sotPayload);

      decoder.parsePptMarker(
        Uint8List.fromList(<int>[0x00, 0x04, 0x00, 0x01]),
        tileIdx: 0,
        tilePartIdx: 0,
      );
      decoder.parsePptMarker(
        Uint8List.fromList(<int>[0x00, 0x05, 0x01, 0x02, 0x03]),
        tileIdx: 0,
        tilePartIdx: 0,
      );

      final packed = decoder.getPackedPacketHeaders(0);
      expect(packed, equals(Uint8List.fromList(<int>[0x01, 0x02, 0x03])));
      expect(specs.pphs.getTileDef(0), isTrue);
    });

    test('parseTilePartHeader applies tile-scoped overrides', () {
      final specs = DecoderSpecs.basic(2, 2);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 2,
      );

      final mainCod = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      decoder.parseCodMarker(mainCod, isMainHeader: true, tileIdx: 0);

      final mainSqcd = (2 << Markers.SQCX_GB_SHIFT) | Markers.SQCX_NO_QUANTIZATION;
      final mainQcd = buildQcdMarkerPayload(
        sqcd: mainSqcd,
        stepBytes: <int>[
          5 << Markers.SQCX_EXP_SHIFT,
          4 << Markers.SQCX_EXP_SHIFT,
          4 << Markers.SQCX_EXP_SHIFT,
          4 << Markers.SQCX_EXP_SHIFT,
          3 << Markers.SQCX_EXP_SHIFT,
          3 << Markers.SQCX_EXP_SHIFT,
          3 << Markers.SQCX_EXP_SHIFT,
        ],
      );
      decoder.parseQcdMarker(mainQcd, isMainHeader: true, tileIdx: 0);

      final sotPayload = Uint8List.fromList(<int>[
        0x00,
        0x0A,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x40,
        0x00,
        0x01,
      ]);
      decoder.parseSotMarker(sotPayload);
      final sot = info.sot['t1_tp0'];
      expect(sot, isNotNull);

      final tileCod = buildCodMarkerPayload(
        scod: Markers.SCOX_PRECINCT_PARTITION,
        sgcodPo: 0x00,
        sgcodNl: 2,
        sgcodMct: 0x00,
        spcodNdl: 3,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x01,
        spcodT: 0x01,
        precincts: <int>[0x00, 0x11, 0x22, 0x33],
      );
      final tileCoc = buildCocMarkerPayload(
        component: 1,
        scoc: 0x00,
        spcocNdl: 4,
        spcocCw: 0x02,
        spcocCh: 0x02,
        spcocCs: 0x03,
        spcocT: 0x01,
      );
      final tileSqcd = (3 << Markers.SQCX_GB_SHIFT) | Markers.SQCX_SCALAR_DERIVED;
      final tileQcd = buildQcdMarkerPayload(
        sqcd: tileSqcd,
        stepBytes: uint16List(<int>[0x6400]),
      );
      final tileSqcc = (4 << Markers.SQCX_GB_SHIFT) | Markers.SQCX_SCALAR_EXPOUNDED;
      final tileQcc = buildQccMarkerPayload(
        component: 1,
        sqcc: tileSqcc,
        stepBytes: uint16List(<int>[0xA000, 0x9400, 0x9400, 0x9400]),
      );

      final builder = BytesBuilder();
      addMarkerSegment(builder, Markers.COD, tileCod);
      addMarkerSegment(builder, Markers.COC, tileCoc);
      addMarkerSegment(builder, Markers.QCD, tileQcd);
      addMarkerSegment(builder, Markers.QCC, tileQcc);
      addMarker(builder, Markers.SOD);

      final tileHeaderData = builder.toBytes();
      final io = ISRandomAccessIO(tileHeaderData);

      decoder.parseTilePartHeader(io, sot: sot!);

      expect(decoder.currentTile, equals(1));
      expect(decoder.precinctPartitionUsed(), isTrue);
      expect(specs.nls.getTileDef(1), equals(2));
      expect(specs.dls.getTileDef(1), equals(3));
      expect(specs.cblks.getTileDef(1), equals(<int>[32, 32]));
      expect(specs.ecopts.getTileDef(1), equals(0x01));

      final precincts = specs.pss.getTileDef(1);
      expect(precincts, isNotNull);
      expect(precincts![0], equals(<int>[1, 2, 4, 8]));
      expect(precincts[1], equals(<int>[1, 2, 4, 8]));

      expect(specs.qts.getTileDef(1), equals('derived'));
      expect(specs.gbs.getTileDef(1), equals(3));
      final tileQcdParams = specs.qsss.getTileDef(1);
      expect(tileQcdParams, isNotNull);
      expect(tileQcdParams!.exp[0][0], equals(12));

      final tileCompCblk = specs.cblks.getTileCompVal(1, 1);
      expect(tileCompCblk, equals(<int>[16, 16]));
      expect(specs.dls.getTileCompVal(1, 1), equals(4));
      expect(specs.ecopts.getTileCompVal(1, 1), equals(0x03));
      expect(specs.qts.getTileCompVal(1, 1), equals('expounded'));
      expect(specs.gbs.getTileCompVal(1, 1), equals(4));
      final tileCompParams = specs.qsss.getTileCompVal(1, 1);
      expect(tileCompParams, isNotNull);
      expect(tileCompParams!.exp[0][0], equals(20));
      expect(tileCompParams.exp[1][1], equals(18));

      final tileCodInfo = info.cod['t1'];
      expect(tileCodInfo, isNotNull);
      expect(tileCodInfo!.spcodNdl, equals(3));
      expect(tileCodInfo.spcodCw, equals(3));
      expect(tileCodInfo.spcodCh, equals(3));
      expect(tileCodInfo.spcodPs, equals(<int>[0x00, 0x11, 0x22, 0x33]));

      final tileCocInfo = info.coc['t1_c1'];
      expect(tileCocInfo, isNotNull);
      expect(tileCocInfo!.spcocNdl, equals(4));
      expect(tileCocInfo.spcocCw, equals(2));
      expect(tileCocInfo.spcocCh, equals(2));
      expect(tileCocInfo.spcocCs, equals(0x03));

      final tileQcdInfo = info.qcd['t1'];
      expect(tileQcdInfo, isNotNull);
      expect(tileQcdInfo!.sqcd, equals(tileSqcd));

      final tileQccInfo = info.qcc['t1_c1'];
      expect(tileQccInfo, isNotNull);
      expect(tileQccInfo!.sqcc, equals(tileSqcc));

      expect(io.getPos(), equals(tileHeaderData.length - 2));
      expect(io.readUnsignedShort(), equals(Markers.SOD));
    });
  });

  group('HeaderDecoder.parseRgnMarker', () {
    test('updates component-level ROI shifts from main header', () {
      final specs = DecoderSpecs.basic(1, 3);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 3,
      );

      final payload = buildRgnMarkerPayload(
        component: 2,
        srgn: Markers.SRGN_IMPLICIT,
        sprgn: 7,
      );

      decoder.parseRgnMarker(payload, isMainHeader: true, tileIdx: 0);

      expect(specs.rois.getCompDef(2), equals(7));
      final rgnInfo = info.rgn['main_c2'];
      expect(rgnInfo, isNotNull);
      expect(rgnInfo!.sprgn, equals(7));
    });

    test('updates tile/component ROI shifts from tile headers', () {
      final specs = DecoderSpecs.basic(2, 2);
      final info = HeaderInfo();
      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: info,
        numComps: 2,
      );

      final payload = buildRgnMarkerPayload(
        component: 0,
        srgn: Markers.SRGN_IMPLICIT,
        sprgn: 5,
      );

      decoder.parseRgnMarker(payload, isMainHeader: false, tileIdx: 1);

      expect(specs.rois.getTileCompVal(1, 0), equals(5));
      final rgnInfo = info.rgn['t1_c0'];
      expect(rgnInfo, isNotNull);
      expect(rgnInfo!.sprgn, equals(5));
    });

    test('removes rectangular component defaults when codestream defines ROI shifts', () {
      final specs = DecoderSpecs.basic(1, 1);
      final rectSpec = specs.rectRois!;
      rectSpec.setCompDef(
        0,
        RectangularROI(x0: 0, y0: 0, width: 8, height: 8),
      );
      expect(rectSpec.roiFor(0, 0), isNotNull);

      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: HeaderInfo(),
        numComps: 1,
      );

      final payload = buildRgnMarkerPayload(
        component: 0,
        srgn: Markers.SRGN_IMPLICIT,
        sprgn: 3,
      );

      decoder.parseRgnMarker(payload, isMainHeader: true, tileIdx: 0);

      expect(specs.rois.getCompDef(0), equals(3));
      expect(rectSpec.roiFor(0, 0), isNull);
    });

    test('removes rectangular tile overrides when tile-level ROI shifts arrive', () {
      final specs = DecoderSpecs.basic(2, 1);
      final rectSpec = specs.rectRois!;
      rectSpec.setTileCompVal(
        1,
        0,
        RectangularROI(x0: 4, y0: 4, width: 4, height: 4),
      );
      expect(rectSpec.roiFor(1, 0), isNotNull);

      final decoder = HeaderDecoder.placeholder(
        decSpec: specs,
        headerInfo: HeaderInfo(),
        numComps: 1,
      );

      final payload = buildRgnMarkerPayload(
        component: 0,
        srgn: Markers.SRGN_IMPLICIT,
        sprgn: 2,
      );

      decoder.parseRgnMarker(payload, isMainHeader: false, tileIdx: 1);

      expect(specs.rois.getTileCompVal(1, 0), equals(2));
      expect(rectSpec.roiFor(1, 0), isNull);
    });
  });

  group('HeaderDecoder.parseNextTilePart', () {
    test('reads stream and applies overrides', () {
      final mainCod = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 2,
        spcodCw: 0x04,
        spcodCh: 0x04,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      final mainSqcd = (2 << Markers.SQCX_GB_SHIFT) | Markers.SQCX_NO_QUANTIZATION;
      final mainQcd = buildQcdMarkerPayload(
        sqcd: mainSqcd,
        stepBytes: <int>[
          5 << Markers.SQCX_EXP_SHIFT,
          4 << Markers.SQCX_EXP_SHIFT,
          4 << Markers.SQCX_EXP_SHIFT,
          4 << Markers.SQCX_EXP_SHIFT,
          3 << Markers.SQCX_EXP_SHIFT,
          3 << Markers.SQCX_EXP_SHIFT,
          3 << Markers.SQCX_EXP_SHIFT,
        ],
      );

      final tileCod = buildCodMarkerPayload(
        scod: Markers.SCOX_PRECINCT_PARTITION,
        sgcodPo: 0x00,
        sgcodNl: 2,
        sgcodMct: 0x00,
        spcodNdl: 3,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x01,
        spcodT: 0x01,
        precincts: <int>[0x00, 0x11, 0x22, 0x33],
      );
      final tileCoc = buildCocMarkerPayload(
        component: 1,
        scoc: 0x00,
        spcocNdl: 4,
        spcocCw: 0x02,
        spcocCh: 0x02,
        spcocCs: 0x03,
        spcocT: 0x01,
      );
      final tileSqcd = (3 << Markers.SQCX_GB_SHIFT) | Markers.SQCX_SCALAR_DERIVED;
      final tileQcd = buildQcdMarkerPayload(
        sqcd: tileSqcd,
        stepBytes: uint16List(<int>[0x6400]),
      );
      final tileSqcc = (4 << Markers.SQCX_GB_SHIFT) | Markers.SQCX_SCALAR_EXPOUNDED;
      final tileQcc = buildQccMarkerPayload(
        component: 1,
        sqcc: tileSqcc,
        stepBytes: uint16List(<int>[0xA000, 0x9400, 0x9400, 0x9400]),
      );

      final builder = BytesBuilder();
      addMarker(builder, Markers.SOC);
      addMarkerSegment(
        builder,
        Markers.SIZ,
        buildSizMarkerPayload(
          xsize: 128,
          ysize: 96,
          tileWidth: 64,
          tileHeight: 48,
          numComps: 2,
          subsamplingX: const <int>[1, 1],
          subsamplingY: const <int>[1, 1],
          bitDepths: const <int>[0x07, 0x07],
        ),
      );
      addMarkerSegment(builder, Markers.COD, mainCod);
      addMarkerSegment(builder, Markers.QCD, mainQcd);

      addMarker(builder, Markers.SOT);
      builder.add(
        buildSotMarkerPayload(
          tileIdx: 0,
          tilePartIdx: 0,
          tilePartLength: 0,
          numTileParts: 1,
        ),
      );
      addMarkerSegment(builder, Markers.COD, tileCod);
      addMarkerSegment(builder, Markers.COC, tileCoc);
      addMarkerSegment(builder, Markers.QCD, tileQcd);
      addMarkerSegment(builder, Markers.QCC, tileQcc);
      addMarker(builder, Markers.SOD);
      addMarker(builder, Markers.EOC);

      final data = builder.toBytes();
      final io = ISRandomAccessIO(data);
      final headerInfo = HeaderInfo();

      final decoder = HeaderDecoder.readMainHeader(
        input: io,
        headerInfo: headerInfo,
      );

      expect(io.getPos(), lessThan(data.length));
      expect(io.readUnsignedShort(), equals(Markers.SOT));
      io.seek(io.getPos() - 2);

      final sot = decoder.parseNextTilePart(io);

      expect(sot.isot, equals(0));
      expect(decoder.currentTile, equals(0));
      expect(decoder.precinctPartitionUsed(), isTrue);

      final specs = decoder.decSpec;
      expect(specs.nls.getTileDef(0), equals(2));
      expect(specs.dls.getTileDef(0), equals(3));
      expect(specs.cblks.getTileDef(0), equals(<int>[32, 32]));
      expect(specs.ecopts.getTileDef(0), equals(0x01));

      final precincts = specs.pss.getTileDef(0);
      expect(precincts, isNotNull);
      expect(precincts![0], equals(<int>[1, 2, 4, 8]));
      expect(precincts[1], equals(<int>[1, 2, 4, 8]));

      expect(specs.qts.getTileDef(0), equals('derived'));
      expect(specs.gbs.getTileDef(0), equals(3));
      final tileQcdParams = specs.qsss.getTileDef(0);
      expect(tileQcdParams, isNotNull);
      expect(tileQcdParams!.exp[0][0], equals(12));

      final tileCompCblk = specs.cblks.getTileCompVal(0, 1);
      expect(tileCompCblk, equals(<int>[16, 16]));
      expect(specs.dls.getTileCompVal(0, 1), equals(4));
      expect(specs.ecopts.getTileCompVal(0, 1), equals(0x03));
      expect(specs.qts.getTileCompVal(0, 1), equals('expounded'));
      expect(specs.gbs.getTileCompVal(0, 1), equals(4));
      final tileCompParams = specs.qsss.getTileCompVal(0, 1);
      expect(tileCompParams, isNotNull);
      expect(tileCompParams!.exp[0][0], equals(20));
      expect(tileCompParams.exp[1][1], equals(18));

      final nextMarker = io.readUnsignedShort();
      expect(nextMarker, equals(Markers.EOC));
      io.close();
    });

    test('tracks tile order and Psot lengths across tiles', () {
      final mainCod = buildCodMarkerPayload(
        scod: 0x00,
        sgcodPo: 0x00,
        sgcodNl: 1,
        sgcodMct: 0x00,
        spcodNdl: 1,
        spcodCw: 0x03,
        spcodCh: 0x03,
        spcodCs: 0x00,
        spcodT: 0x01,
      );
      final builder = BytesBuilder();
      addMarker(builder, Markers.SOC);
      addMarkerSegment(
        builder,
        Markers.SIZ,
        buildSizMarkerPayload(
          xsize: 128,
          ysize: 96,
          tileWidth: 64,
          tileHeight: 48,
          numComps: 1,
          subsamplingX: const <int>[1],
          subsamplingY: const <int>[1],
          bitDepths: const <int>[0x07],
        ),
      );
      addMarkerSegment(builder, Markers.COD, mainCod);

      final tilePart00 = buildTilePart(tileIdx: 0, tilePartIdx: 0, numTileParts: 2, bodyLength: 6);
      final tilePart01 = buildTilePart(tileIdx: 0, tilePartIdx: 1, numTileParts: 2, bodyLength: 3);
      final tilePart10 = buildTilePart(tileIdx: 1, tilePartIdx: 0, numTileParts: 1, bodyLength: 4);

      builder
        ..add(tilePart00.bytes)
        ..add(tilePart01.bytes)
        ..add(tilePart10.bytes);
      addMarker(builder, Markers.EOC);

      final data = builder.toBytes();
      final io = ISRandomAccessIO(data);
      final headerInfo = HeaderInfo();
      final decoder = HeaderDecoder.readMainHeader(input: io, headerInfo: headerInfo);

      final observedTiles = <int>[];
      final observedTileParts = <(int tile, int part)>[];
      final observedOffsets = <int>[];
      final observedBodyLengths = <int>[];
      while (true) {
        final start = io.getPos();
        try {
          final sot = decoder.parseNextTilePart(io);
          observedTiles.add(sot.isot);
          observedTileParts.add((sot.isot, sot.tpsot));
          final psot = sot.psot;
          expect(psot, isPositive, reason: 'Psot should expose tile-part length');
          final dataStart = io.getPos();
          observedOffsets.add(dataStart);
          final headerBytes = dataStart - start;
          final bodyLength = psot == 0 ? 0 : psot - headerBytes;
          observedBodyLengths.add(bodyLength);
          final expectedEnd = start + psot;
          expect(expectedEnd, lessThanOrEqualTo(data.length));
          io.seek(expectedEnd);
        } on StateError catch (error) {
          final message = error.message;
          if (message.contains('Reached end of codestream before encountering tile-part header')) {
            break;
          }
          rethrow;
        }
      }

      expect(observedTiles, equals(<int>[0, 0, 1]));
      expect(decoder.nTileParts[0], equals(2));
      expect(decoder.nTileParts[1], equals(1));
      expect(decoder.getTilePartLengths(0), equals(<int>[tilePart00.psot, tilePart01.psot]));
      expect(decoder.getTileTotalLength(0), equals(tilePart00.psot + tilePart01.psot));
      expect(decoder.getTilePartLengths(1), equals(<int>[tilePart10.psot]));
      expect(decoder.getTileTotalLength(1), equals(tilePart10.psot));

      final tile0Offsets = <int>[];
      final tile1Offsets = <int>[];
      final tile0Bodies = <int>[];
      final tile1Bodies = <int>[];
      for (var i = 0; i < observedTileParts.length; i++) {
        final entry = observedTileParts[i];
        if (entry.$1 == 0) {
          tile0Offsets.add(observedOffsets[i]);
          tile0Bodies.add(observedBodyLengths[i]);
        } else if (entry.$1 == 1) {
          tile1Offsets.add(observedOffsets[i]);
           tile1Bodies.add(observedBodyLengths[i]);
        }
      }

      expect(decoder.getTilePartDataOffsets(0), equals(tile0Offsets));
      expect(decoder.getTilePartBodyLengths(0), equals(tile0Bodies));
      expect(tile0Bodies, equals(<int>[tilePart00.bodyLength, tilePart01.bodyLength]));
      expect(decoder.getTilePartBodyLengths(1), equals(tile1Bodies));
      expect(tile1Bodies, equals(<int>[tilePart10.bodyLength]));
      expect(decoder.getTilePartDataOffsets(1), equals(tile1Offsets));

      io.close();
    });
  });
}



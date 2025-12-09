import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/util/ISRandomAccessIO.dart';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/codestream/HeaderInfo.dart';
import 'package:jpeg2000/src/j2k/codestream/markers.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/HeaderDecoder.dart';
import 'package:jpeg2000/src/j2k/image/invcomptransf/InvCompTransf.dart';


void main() {
  group('HeaderDecoder.readMainHeader', () {
    test('parses SIZ/COD/QCD markers and initialises specs', () {
      final data = _buildMinimalCodestream();
      final io = ISRandomAccessIO(data);
      final headerInfo = HeaderInfo();

      final decoder = HeaderDecoder.readMainHeader(
        input: io,
        headerInfo: headerInfo,
      );

      expect(decoder.getNumComps(), equals(1));
      expect(decoder.getImgWidth(), equals(128));
      expect(decoder.getImgHeight(), equals(96));
      expect(decoder.getNomTileWidth(), equals(64));
      expect(decoder.getNomTileHeight(), equals(48));

      final siz = headerInfo.siz;
      expect(siz, isNotNull);
      expect(siz!.csiz, equals(1));
      expect(siz.xsiz - siz.x0siz, equals(128));
      expect(siz.ysiz - siz.y0siz, equals(96));

      expect(decoder.decSpec.dls.getDefault(), equals(2));
      expect(decoder.decSpec.nls.getDefault(), equals(1));
      expect(decoder.decSpec.pos.getDefault(), equals(0));
      expect(decoder.decSpec.cblks.getDefault(), equals(<int>[64, 64]));
      expect(decoder.decSpec.cts.getDefault(), equals(InvCompTransf.none));
      expect(decoder.decSpec.qts.getDefault(), equals('reversible'));
      expect(decoder.decSpec.gbs.getDefault(), equals(2));
      final qcdParams = decoder.decSpec.qsss.getTileCompVal(0, 0);
      expect(qcdParams, isNotNull);
      expect(qcdParams!.nStep, isNull);
      expect(qcdParams.exp.length, equals(3));
      expect(qcdParams.exp[0][0], equals(5));
      expect(qcdParams.exp[1][1], equals(4));
      expect(qcdParams.exp[1][2], equals(4));
      expect(qcdParams.exp[1][3], equals(4));
      expect(qcdParams.exp[2][1], equals(3));
      expect(decoder.precinctPartitionUsed(), isFalse);
      expect(headerInfo.cod['main'], isNotNull);
      final qcdHeader = headerInfo.qcd['main'];
      expect(qcdHeader, isNotNull);
      expect(qcdHeader!.getNumGuardBits(), equals(2));

      final nextMarker = io.readUnsignedShort();
      expect(nextMarker, equals(0xff90)); // SOT marker

      io.close();
    });

    test('parses QCC marker overriding component quantisation', () {
      final data = _buildCodestreamWithQcc();
      final io = ISRandomAccessIO(data);
      final headerInfo = HeaderInfo();

      final decoder = HeaderDecoder.readMainHeader(
        input: io,
        headerInfo: headerInfo,
      );

      expect(decoder.getNumComps(), equals(2));
      expect(decoder.decSpec.qts.getDefault(), equals('reversible'));
      expect(decoder.decSpec.qts.getTileCompVal(0, 1), equals('expounded'));

      final defaultParams = decoder.decSpec.qsss.getTileCompVal(0, 0);
      expect(defaultParams, isNotNull);
      expect(defaultParams!.nStep, isNull);

      final params = decoder.decSpec.qsss.getTileCompVal(0, 1);
      expect(params, isNotNull);
      final steps = params!.nStep;
      expect(steps, isNotNull);
      expect(steps!.length, equals(3));
      expect(steps[0][0], closeTo(1 / 32, 1e-9));
      expect(steps[1][1], closeTo(1 / 64, 1e-9));
      expect(steps[2][1], closeTo(1 / 128, 1e-9));
      expect(decoder.decSpec.gbs.getTileCompVal(0, 1), equals(3));

      final qccHeader = headerInfo.qcc['main_c1'];
      expect(qccHeader, isNotNull);
      expect(qccHeader!.getNumGuardBits(), equals(3));

      io.close();
    });

    test('parses COC marker overriding component coding style', () {
      final data = _buildCodestreamWithCoc();
      final io = ISRandomAccessIO(data);
      final headerInfo = HeaderInfo();

      final decoder = HeaderDecoder.readMainHeader(
        input: io,
        headerInfo: headerInfo,
      );

      expect(decoder.getNumComps(), equals(2));
      expect(decoder.decSpec.dls.getTileCompVal(0, 0), equals(2));
      expect(decoder.decSpec.dls.getTileCompVal(0, 1), equals(3));

      final cblkDefault = decoder.decSpec.cblks.getTileCompVal(0, 0);
      expect(cblkDefault, equals(<int>[64, 64]));
      final cblkOverride = decoder.decSpec.cblks.getTileCompVal(0, 1);
      expect(cblkOverride, equals(<int>[128, 128]));

      expect(decoder.decSpec.ecopts.getTileCompVal(0, 1), equals(0x02));

      final cocHeader = headerInfo.coc['main_c1'];
      expect(cocHeader, isNotNull);
      expect(cocHeader!.spcocNdl, equals(3));
      expect(cocHeader.spcocCw, equals(5));
      expect(cocHeader.spcocCh, equals(5));
      expect(cocHeader.spcocCs, equals(0x02));

      io.close();
    });
  });
}

Uint8List _buildMinimalCodestream() {
  final builder = BytesBuilder();

  void writeMarker(int marker) {
    builder.add(<int>[(marker >> 8) & 0xff, marker & 0xff]);
  }

  void writeMarkerSegment(int marker, List<int> payload) {
    writeMarker(marker);
    builder.add(payload);
  }

  List<int> uint16(int value) => <int>[(value >> 8) & 0xff, value & 0xff];

  List<int> uint32(int value) => <int>[
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  writeMarker(0xff4f); // SOC

  final sizSegment = BytesBuilder();
  sizSegment.add(uint16(38 + 3 * 1)); // Lsiz = 41
  sizSegment.add(uint16(0)); // Rsiz
  sizSegment.add(uint32(128)); // Xsiz
  sizSegment.add(uint32(96)); // Ysiz
  sizSegment.add(uint32(0)); // X0siz
  sizSegment.add(uint32(0)); // Y0siz
  sizSegment.add(uint32(64)); // XTsiz
  sizSegment.add(uint32(48)); // YTsiz
  sizSegment.add(uint32(0)); // XT0siz
  sizSegment.add(uint32(0)); // YT0siz
  sizSegment.add(uint16(1)); // Csiz
  sizSegment.add(<int>[0x07, 0x01, 0x01]); // 8-bit unsigned, no subsampling
  writeMarkerSegment(0xff51, sizSegment.takeBytes());

  final codSegment = BytesBuilder();
  codSegment.add(uint16(12)); // Lcod
  codSegment.add(<int>[0x00]); // Scod (default)
  codSegment.add(<int>[0x00]); // SGcod progression (LRCP)
  codSegment.add(uint16(1)); // SGcod NL (1 layer)
  codSegment.add(<int>[0x00]); // SGcod MCT (none)
  codSegment.add(<int>[0x02]); // SPcod Ndl (2 decompositions)
  codSegment.add(<int>[0x04]); // SPcod Cw (2^(4+2)=64)
  codSegment.add(<int>[0x04]); // SPcod Ch (64)
  codSegment.add(<int>[0x00]); // SPcod Cs (default)
  codSegment.add(<int>[0x01]); // SPcod T (5x3)
  writeMarkerSegment(0xff52, codSegment.takeBytes());

  final qcdSegment = BytesBuilder();
  const guardBits = 2;
  final sqcd =
      (guardBits << Markers.SQCX_GB_SHIFT) | Markers.SQCX_NO_QUANTIZATION;
  final spqcdValues = <int>[
    5 << Markers.SQCX_EXP_SHIFT,
    4 << Markers.SQCX_EXP_SHIFT,
    4 << Markers.SQCX_EXP_SHIFT,
    4 << Markers.SQCX_EXP_SHIFT,
    3 << Markers.SQCX_EXP_SHIFT,
    3 << Markers.SQCX_EXP_SHIFT,
    3 << Markers.SQCX_EXP_SHIFT,
  ];
  qcdSegment.add(uint16(2 + 1 + spqcdValues.length));
  qcdSegment.add(<int>[sqcd]);
  qcdSegment.add(spqcdValues);
  writeMarkerSegment(Markers.QCD, qcdSegment.takeBytes());

  final sotSegment = BytesBuilder();
  sotSegment.add(uint16(10)); // Lsot
  sotSegment.add(uint16(0)); // Isot
  sotSegment.add(uint32(0)); // Psot (unknown)
  sotSegment.add(<int>[0x00]); // TPsot
  sotSegment.add(<int>[0x01]); // TNsot
  writeMarkerSegment(0xff90, sotSegment.takeBytes());

  return builder.takeBytes();
}

Uint8List _buildCodestreamWithQcc() {
  final builder = BytesBuilder();

  void writeMarker(int marker) {
    builder.add(<int>[(marker >> 8) & 0xff, marker & 0xff]);
  }

  void writeMarkerSegment(int marker, List<int> payload) {
    writeMarker(marker);
    builder.add(payload);
  }

  List<int> uint16(int value) => <int>[(value >> 8) & 0xff, value & 0xff];

  List<int> uint32(int value) => <int>[
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  writeMarker(Markers.SOC);

  final sizSegment = BytesBuilder();
  sizSegment.add(uint16(38 + 3 * 2));
  sizSegment.add(uint16(0));
  sizSegment.add(uint32(128));
  sizSegment.add(uint32(96));
  sizSegment.add(uint32(0));
  sizSegment.add(uint32(0));
  sizSegment.add(uint32(64));
  sizSegment.add(uint32(48));
  sizSegment.add(uint32(0));
  sizSegment.add(uint32(0));
  sizSegment.add(uint16(2));
  sizSegment.add(<int>[0x07, 0x01, 0x01]);
  sizSegment.add(<int>[0x07, 0x01, 0x01]);
  writeMarkerSegment(Markers.SIZ, sizSegment.takeBytes());

  final codSegment = BytesBuilder();
  codSegment.add(uint16(12));
  codSegment.add(<int>[0x00]);
  codSegment.add(<int>[0x00]);
  codSegment.add(uint16(1));
  codSegment.add(<int>[0x00]);
  codSegment.add(<int>[0x02]);
  codSegment.add(<int>[0x04]);
  codSegment.add(<int>[0x04]);
  codSegment.add(<int>[0x00]);
  codSegment.add(<int>[0x01]);
  writeMarkerSegment(Markers.COD, codSegment.takeBytes());

  final qcdSegment = BytesBuilder();
  final qcdSqcd =
      (1 << Markers.SQCX_GB_SHIFT) | Markers.SQCX_NO_QUANTIZATION;
  final qcdValues = <int>[
    5 << Markers.SQCX_EXP_SHIFT,
    4 << Markers.SQCX_EXP_SHIFT,
    4 << Markers.SQCX_EXP_SHIFT,
    4 << Markers.SQCX_EXP_SHIFT,
    3 << Markers.SQCX_EXP_SHIFT,
    3 << Markers.SQCX_EXP_SHIFT,
    3 << Markers.SQCX_EXP_SHIFT,
  ];
  qcdSegment.add(uint16(2 + 1 + qcdValues.length));
  qcdSegment.add(<int>[qcdSqcd]);
  qcdSegment.add(qcdValues);
  writeMarkerSegment(Markers.QCD, qcdSegment.takeBytes());

  final qccSegment = BytesBuilder();
  const qccGuardBits = 3;
  final sqcc =
      (qccGuardBits << Markers.SQCX_GB_SHIFT) | Markers.SQCX_SCALAR_EXPOUNDED;
  final qccValues = <int>[
    5 << 11,
    6 << 11,
    6 << 11,
    6 << 11,
    7 << 11,
    7 << 11,
    7 << 11,
  ];
  qccSegment.add(uint16(2 + 1 + 1 + qccValues.length * 2));
  qccSegment.add(<int>[0x01]);
  qccSegment.add(<int>[sqcc]);
  for (final value in qccValues) {
    qccSegment.add(uint16(value));
  }
  writeMarkerSegment(Markers.QCC, qccSegment.takeBytes());

  final sotSegment = BytesBuilder();
  sotSegment.add(uint16(10));
  sotSegment.add(uint16(0));
  sotSegment.add(uint32(0));
  sotSegment.add(<int>[0x00]);
  sotSegment.add(<int>[0x01]);
  writeMarkerSegment(Markers.SOT, sotSegment.takeBytes());

  return builder.takeBytes();
}

Uint8List _buildCodestreamWithCoc() {
  final builder = BytesBuilder();

  void writeMarker(int marker) {
    builder.add(<int>[(marker >> 8) & 0xff, marker & 0xff]);
  }

  void writeMarkerSegment(int marker, List<int> payload) {
    writeMarker(marker);
    builder.add(payload);
  }

  List<int> uint16(int value) => <int>[(value >> 8) & 0xff, value & 0xff];

  List<int> uint32(int value) => <int>[
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  writeMarker(Markers.SOC);

  final sizSegment = BytesBuilder();
  sizSegment.add(uint16(38 + 3 * 2));
  sizSegment.add(uint16(0));
  sizSegment.add(uint32(256));
  sizSegment.add(uint32(256));
  sizSegment.add(uint32(0));
  sizSegment.add(uint32(0));
  sizSegment.add(uint32(128));
  sizSegment.add(uint32(128));
  sizSegment.add(uint32(0));
  sizSegment.add(uint32(0));
  sizSegment.add(uint16(2));
  sizSegment.add(<int>[0x07, 0x01, 0x01]);
  sizSegment.add(<int>[0x07, 0x01, 0x01]);
  writeMarkerSegment(Markers.SIZ, sizSegment.takeBytes());

  final codSegment = BytesBuilder();
  codSegment.add(uint16(12));
  codSegment.add(<int>[0x00]);
  codSegment.add(<int>[0x00]);
  codSegment.add(uint16(1));
  codSegment.add(<int>[0x00]);
  codSegment.add(<int>[0x02]);
  codSegment.add(<int>[0x04]);
  codSegment.add(<int>[0x04]);
  codSegment.add(<int>[0x00]);
  codSegment.add(<int>[0x01]);
  writeMarkerSegment(Markers.COD, codSegment.takeBytes());

  final cocSegment = BytesBuilder();
  cocSegment.add(uint16(9));
  cocSegment.add(<int>[0x01]);
  cocSegment.add(<int>[0x00]);
  cocSegment.add(<int>[0x03]);
  cocSegment.add(<int>[0x05]);
  cocSegment.add(<int>[0x05]);
  cocSegment.add(<int>[0x02]);
  cocSegment.add(<int>[0x00]);
  writeMarkerSegment(Markers.COC, cocSegment.takeBytes());

  final sotSegment = BytesBuilder();
  sotSegment.add(uint16(10));
  sotSegment.add(uint16(0));
  sotSegment.add(uint32(0));
  sotSegment.add(<int>[0x00]);
  sotSegment.add(<int>[0x01]);
  writeMarkerSegment(Markers.SOT, sotSegment.takeBytes());

  return builder.takeBytes();
}


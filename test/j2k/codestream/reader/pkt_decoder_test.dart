import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/codestream/c_blk_coord_info.dart';
import 'package:jpeg2000/src/j2k/util/is_random_access_io.dart';
import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/codestream/reader/c_blk_info.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/header_decoder.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/bitstream_reader_agent.dart';
import 'package:jpeg2000/src/j2k/codestream/header_info.dart';
import 'package:jpeg2000/src/j2k/decoder/decoder_specs.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/dec_lyrd_c_blk.dart';
import 'package:jpeg2000/src/j2k/image/coord.dart';

import 'package:jpeg2000/src/j2k/wavelet/synthesis/subband_syn.dart';

class _TestBitstreamReaderAgent extends BitstreamReaderAgent {
  _TestBitstreamReaderAgent(super.header, super.specs) {
    setTile(0, 0);
  }

  @override
  void setTile(int x, int y) {
    ctX = x;
    ctY = y;
  }

  @override
  void nextTile() {
    // Single tile in tests.
  }

  @override
  int getNomRangeBits(int component) => 8;

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
    throw UnimplementedError('Not required for packet body tests');
  }
}

void main() {
  group('PktDecoder.readPktBody', () {
    test('stores payload bytes in code-block metadata', () {
      final specs = DecoderSpecs.basic(1, 1);
      specs.nls.setTileDef(0, 1);
      specs.dls.setTileCompVal(0, 0, 0);

      final headerInfo = HeaderInfo();
      final headerDecoder = HeaderDecoder(
        decSpec: specs,
        headerInfo: headerInfo,
        numComps: 1,
        imgWidth: 8,
        imgHeight: 8,
        imgULX: 0,
        imgULY: 0,
        nomTileWidth: 8,
        nomTileHeight: 8,
        cbULX: 0,
        cbULY: 0,
        compSubsX: const <int>[1],
        compSubsY: const <int>[1],
        maxCompImgWidth: 8,
        maxCompImgHeight: 8,
        tilingOrigin: Coord(0, 0),
      );

      final agent = _TestBitstreamReaderAgent(headerDecoder, specs);

      final payload = Uint8List.fromList(<int>[0xDE, 0xAD, 0xBE, 0xEF]);
      final io = ISRandomAccessIO(Uint8List.fromList(payload));
      final decoder = PktDecoder(specs, headerDecoder, io, agent, false, -1);

      decoder.debugInitializeForPacketBody(numLayers: 1);

      final blockInfo = CBlkInfo(0, 0, 4, 4, 1);
      blockInfo.len[0] = payload.length;

      final subbandBlocks = <List<List<CBlkInfo?>?>?>[
        <List<CBlkInfo?>?>[
          <CBlkInfo?>[blockInfo],
        ],
      ];

      final coord = CBlkCoordInfo.withIndex(0, 0);
      decoder.debugSetIncludedCodeBlocks(0, <CBlkCoordInfo>[coord]);

      final remaining = <int>[0x7fffffff];

      final truncated =
          decoder.readPktBody(0, 0, 0, 0, subbandBlocks, remaining);
      expect(truncated, isFalse);
      expect(blockInfo.off[0], equals(0));
      expect(blockInfo.body[0], isNotNull);
      expect(blockInfo.body[0], orderedEquals(payload));
      expect(io.getPos(), equals(payload.length));
    });
  });
}

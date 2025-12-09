import 'package:test/test.dart';

import 'package:jpeg2000/src/j2k/codestream/HeaderInfo.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/BitstreamReaderAgent.dart';
import 'package:jpeg2000/src/j2k/codestream/reader/HeaderDecoder.dart';
import 'package:jpeg2000/src/j2k/decoder/DecoderSpecs.dart';
import 'package:jpeg2000/src/j2k/entropy/decoder/DecLyrdCBlk.dart';
import 'package:jpeg2000/src/j2k/image/Coord.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SubbandSyn.dart';

void main() {
  group('BitstreamReaderAgent geometry helpers', () {
    late _GeometryFixture fixture;

    setUp(() {
      fixture = _GeometryFixture();
    });

    test('image dimensions downscale per resolution level', () {
      final agent = fixture.buildAgent();
      agent.setTile(0, 0);

      expect(agent.getImgWidth(2), equals(64));
      expect(agent.getImgHeight(2), equals(48));
      expect(agent.getImgWidth(1), equals(32));
      expect(agent.getImgHeight(1), equals(24));
      expect(agent.getImgWidth(0), equals(16));
      expect(agent.getImgHeight(0), equals(12));
    });

    test('tile widths shrink with resolution and respect ragged edges', () {
      final agent = fixture.buildAgent()..setTile(0, 0);

      expect(agent.getTileWidth(2), equals(30));
      expect(agent.getTileWidth(1), equals(15));
      expect(agent.getTileWidth(0), equals(8));

      agent.setTile(agent.ntX - 1, 0);
      expect(agent.getTileWidth(2), equals(2));
    });

    test('tile heights account for tiling origin', () {
      final agent = fixture.buildAgent()..setTile(0, 0);

      expect(agent.getTileHeight(2), equals(17));
      expect(agent.getTileHeight(1), equals(8));
      expect(agent.getTileHeight(0), equals(4));

      agent.setTile(0, agent.ntY - 1);
      expect(agent.getTileHeight(2), equals(11));
    });

    test('component image geometry honors subsampling', () {
      final agent = fixture.buildAgent()..setTile(0, 0);

      expect(agent.getCompImgWidth(0, 2), equals(64));
      expect(agent.getCompImgWidth(0, 1), equals(32));
      expect(agent.getCompImgWidth(1, 3), equals(32));
      expect(agent.getCompImgWidth(1, 2), equals(16));
      expect(agent.getCompImgHeight(1, 3), equals(24));
      expect(agent.getCompImgHeight(1, 2), equals(12));
    });

    test('tile-component dimensions match component subsampling', () {
      final agent = fixture.buildAgent()..setTile(0, 0);

      final tileIdx = agent.getTileIdx();
      expect(agent.getTileCompWidth(tileIdx, 1, 3), equals(15));
      expect(agent.getTileCompWidth(tileIdx, 1, 2), equals(8));
      expect(agent.getTileCompHeight(tileIdx, 1, 3), equals(8));
      expect(agent.getTileCompHeight(tileIdx, 1, 2), equals(4));
    });

    test('resolution origins follow component and tile offsets', () {
      final agent = fixture.buildAgent()..setTile(1, 1);

      expect(agent.getResULX(1, 2), equals(9));
      expect(agent.getResULY(1, 2), equals(6));
    });
  });
}

class _GeometryFixture {
  _GeometryFixture()
      : imgWidth = 64,
        imgHeight = 48,
        imgULX = 3,
        imgULY = 5,
        nomTileWidth = 32,
        nomTileHeight = 20,
        tilingOrigin = Coord(1, 2),
        compSubsX = const <int>[1, 2],
        compSubsY = const <int>[1, 2] {
    tilesX = _tileCount(imgULX, imgWidth, tilingOrigin.x, nomTileWidth);
    tilesY = _tileCount(imgULY, imgHeight, tilingOrigin.y, nomTileHeight);
    specs = DecoderSpecs.basic(tilesX * tilesY, compSubsX.length)
      ..dls.setDefault(2)
      ..dls.setCompDef(1, 3);
  }

  final int imgWidth;
  final int imgHeight;
  final int imgULX;
  final int imgULY;
  final int nomTileWidth;
  final int nomTileHeight;
  final Coord tilingOrigin;
  final List<int> compSubsX;
  final List<int> compSubsY;
  late final int tilesX;
  late final int tilesY;
  late final DecoderSpecs specs;

  _GeometryAgent buildAgent() {
    final header = HeaderDecoder(
      decSpec: specs,
      headerInfo: HeaderInfo(),
      numComps: compSubsX.length,
      imgWidth: imgWidth,
      imgHeight: imgHeight,
      imgULX: imgULX,
      imgULY: imgULY,
      nomTileWidth: nomTileWidth,
      nomTileHeight: nomTileHeight,
      cbULX: 0,
      cbULY: 0,
      compSubsX: compSubsX,
      compSubsY: compSubsY,
      maxCompImgWidth: imgWidth,
      maxCompImgHeight: imgHeight,
      tilingOrigin: Coord(tilingOrigin.x, tilingOrigin.y),
    );
    return _GeometryAgent(header, specs);
  }

  static int _tileCount(int origin, int span, int tileOrigin, int tileSize) {
    return (origin + span - tileOrigin + tileSize - 1) ~/ tileSize;
  }
}

class _GeometryAgent extends BitstreamReaderAgent {
  _GeometryAgent(HeaderDecoder headerDecoder, DecoderSpecs specs)
      : super(headerDecoder, specs);

  @override
  void setTile(int x, int y) {
    if (x < 0 || y < 0 || x >= ntX || y >= ntY) {
      throw ArgumentError('Invalid tile ($x,$y)');
    }
    ctX = x;
    ctY = y;

    final ctox = x == 0 ? ax : px + x * ntW;
    final ctoy = y == 0 ? ay : py + y * ntH;
    for (var comp = 0; comp < nc; comp++) {
      final subX = hd.getCompSubsX(comp);
      final subY = hd.getCompSubsY(comp);
      culx[comp] = (ctox + subX - 1) ~/ subX;
      culy[comp] = (ctoy + subY - 1) ~/ subY;
      offX[comp] = (px + x * ntW + subX - 1) ~/ subX;
      offY[comp] = (py + y * ntH + subY - 1) ~/ subY;
      final tileIdx = getTileIdx();
      mdl[comp] = decSpec.dls.getTileCompVal(tileIdx, comp) ??
          decSpec.dls.getCompDef(comp) ??
          decSpec.dls.getDefault() ??
          0;
    }
  }

  @override
  void nextTile() {
    if (ctX == ntX - 1 && ctY == ntY - 1) {
      throw StateError('Last tile already selected');
    }
    if (ctX < ntX - 1) {
      setTile(ctX + 1, ctY);
    } else {
      setTile(0, ctY + 1);
    }
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
    throw UnimplementedError('Geometry agent does not decode code-blocks');
  }
}

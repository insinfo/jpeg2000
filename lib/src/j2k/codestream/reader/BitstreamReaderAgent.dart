import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:jpeg2000/src/j2k/codestream/CBlkCoordInfo.dart';

import '../../codestream/HeaderInfo.dart';
import '../../codestream/Markers.dart';
import '../../codestream/PrecInfo.dart';
import '../../codestream/ProgressionType.dart';
import '../../decoder/DecoderSpecs.dart';
import '../../entropy/decoder/CodedCBlkDataSrcDec.dart';
import '../../entropy/decoder/DecLyrdCBlk.dart';
import '../../entropy/StdEntropyCoderOptions.dart';
import '../../image/Coord.dart';
import '../../io/RandomAccessIO.dart';
import '../../io/exceptions.dart';
import '../../ModuleSpec.dart';
import '../../quantization/dequantizer/StdDequantizerParams.dart';
import '../../util/ArrayUtil.dart';
import '../../util/DecoderInstrumentation.dart';
import '../../util/FacilityManager.dart';
import '../../util/MathUtil.dart';
import '../../util/MsgLogger.dart';
import '../../util/ParameterList.dart';
import '../../util/StringFormatException.dart';
import '../../wavelet/Subband.dart';
import '../../wavelet/synthesis/SubbandSyn.dart';
import '../../wavelet/WaveletFilter.dart';
import 'HeaderDecoder.dart';

import 'PktHeaderBitReader.dart';
import 'TagTreeDecoder.dart';
import 'CBlkInfo.dart';

part 'FileBitstreamReaderAgent.dart';
part 'PktDecoder.dart';
part 'PktDecoderHarness.dart';


/// Base port of JJ2000's `BitstreamReaderAgent`.
abstract class BitstreamReaderAgent extends CodedCBlkDataSrcDec {
  static const String optPrefix = 'B';
  static const List<List<String>>? parameterInfo = null;

  BitstreamReaderAgent(this.hd, this.decSpec)
      : nc = hd.getNumComps(),
        imgW = hd.getImgWidth(),
        imgH = hd.getImgHeight(),
        ax = hd.getImgULX(),
        ay = hd.getImgULY(),
        px = hd.getTilingOrigin(null).x,
        py = hd.getTilingOrigin(null).y,
        ntW = hd.getNomTileWidth(),
        ntH = hd.getNomTileHeight(),
        ntX = _computeNtX(hd),
        ntY = _computeNtY(hd),
        offX = List<int>.filled(hd.getNumComps(), 0, growable: false),
        offY = List<int>.filled(hd.getNumComps(), 0, growable: false),
        culx = List<int>.filled(hd.getNumComps(), 0, growable: false),
        culy = List<int>.filled(hd.getNumComps(), 0, growable: false) {
    nt = ntX * ntY;
    derived = List<bool>.filled(nc, false, growable: false);
    guardBits = List<int>.filled(nc, 0, growable: false);
    params = List<StdDequantizerParams?>.filled(nc, null, growable: false);
    mdl = List<int>.filled(nc, 0, growable: false);
    subbTrees = List<SubbandSyn?>.filled(nc, null, growable: false);
  }

  final DecoderSpecs decSpec;
  final HeaderDecoder hd;

  late final List<bool> derived;
  late final List<int> guardBits;
  late final List<StdDequantizerParams?> params;
  late final List<int> mdl;
  late final List<SubbandSyn?> subbTrees;

  final int nc;
  int targetRes = 0;

  final int imgW;
  final int imgH;
  final int ax;
  final int ay;
  final int px;
  final int py;

  final List<int> offX;
  final List<int> offY;
  final List<int> culx;
  final List<int> culy;

  final int ntW;
  final int ntH;
  final int ntX;
  final int ntY;
  late final int nt;

  int ctX = 0;
  int ctY = 0;

  int tnbytes = 0;
  int anbytes = 0;
  double trate = 0;
  double arate = 0;

  @override
  void setTile(int x, int y);

  @override
  void nextTile();

  @override
  int getNomRangeBits(int component);

  @override
  int getCbULX() => hd.getCbULX();

  @override
  int getCbULY() => hd.getCbULY();

  @override
  int getNumComps() => nc;

  @override
  int getCompSubsX(int comp) => hd.getCompSubsX(comp);

  @override
  int getCompSubsY(int comp) => hd.getCompSubsY(comp);

  int getTileWidth(int rl) {
    final mindl = decSpec.dls.getMinInTile(getTileIdx());
    if (rl > mindl) {
      throw ArgumentError('Resolution $rl unavailable in tile $ctX,$ctY');
    }
    final dl = mindl - rl;
    final ctulx = ctX == 0 ? ax : px + ctX * ntW;
    final ntulx = ctX < ntX - 1 ? px + (ctX + 1) * ntW : ax + imgW;
    final div = 1 << dl;
    return _ceilDiv(ntulx, div) - _ceilDiv(ctulx, div);
  }

  int getTileHeight(int rl) {
    final mindl = decSpec.dls.getMinInTile(getTileIdx());
    if (rl > mindl) {
      throw ArgumentError('Resolution $rl unavailable in tile $ctX,$ctY');
    }
    final dl = mindl - rl;
    final ctuly = ctY == 0 ? ay : py + ctY * ntH;
    final ntuly = ctY < ntY - 1 ? py + (ctY + 1) * ntH : ay + imgH;
    final div = 1 << dl;
    return _ceilDiv(ntuly, div) - _ceilDiv(ctuly, div);
  }

  int getImgWidth(int rl) {
    final mindl = decSpec.dls.getMin();
    if (rl > mindl) {
      throw ArgumentError('Resolution $rl unavailable for at least one tile-component');
    }
    final dl = mindl - rl;
    final div = 1 << dl;
    return _ceilDiv(ax + imgW, div) - _ceilDiv(ax, div);
  }

  int getImgHeight(int rl) {
    final mindl = decSpec.dls.getMin();
    if (rl > mindl) {
      throw ArgumentError('Resolution $rl unavailable for at least one tile-component');
    }
    final dl = mindl - rl;
    final div = 1 << dl;
    return _ceilDiv(ay + imgH, div) - _ceilDiv(ay, div);
  }

  int getImgULX(int rl) {
    final mindl = decSpec.dls.getMin();
    if (rl > mindl) {
      throw ArgumentError('Resolution $rl unavailable for at least one tile-component');
    }
    final dl = mindl - rl;
    return _ceilDiv(ax, 1 << dl);
  }

  int getImgULY(int rl) {
    final mindl = decSpec.dls.getMin();
    if (rl > mindl) {
      throw ArgumentError('Resolution $rl unavailable for at least one tile-component');
    }
    final dl = mindl - rl;
    return _ceilDiv(ay, 1 << dl);
  }

  int getTileCompWidth(int t, int c, int rl) {
    final tileIdx = getTileIdx();
    if (t != tileIdx) {
      throw StateError('Tile-component query references non-current tile');
    }
    final dl = mdl[c] - rl;
    final ntulx = ctX < ntX - 1 ? px + (ctX + 1) * ntW : ax + imgW;
    final compNtulx = _ceilDiv(ntulx, hd.getCompSubsX(c));
    final div = 1 << dl;
    return _ceilDiv(compNtulx, div) - _ceilDiv(culx[c], div);
  }

  int getTileCompHeight(int t, int c, int rl) {
    final tileIdx = getTileIdx();
    if (t != tileIdx) {
      throw StateError('Tile-component query references non-current tile');
    }
    final dl = mdl[c] - rl;
    final ntuly = ctY < ntY - 1 ? py + (ctY + 1) * ntH : ay + imgH;
    final compNtuly = _ceilDiv(ntuly, hd.getCompSubsY(c));
    final div = 1 << dl;
    return _ceilDiv(compNtuly, div) - _ceilDiv(culy[c], div);
  }

  int getCompImgWidth(int c, int rl) {
    final dl = decSpec.dls.getMinInComp(c) - rl;
    final start = _ceilDiv(ax, hd.getCompSubsX(c));
    final end = _ceilDiv(ax + imgW, hd.getCompSubsX(c));
    final div = 1 << dl;
    return _ceilDiv(end, div) - _ceilDiv(start, div);
  }

  int getCompImgHeight(int c, int rl) {
    final dl = decSpec.dls.getMinInComp(c) - rl;
    final start = _ceilDiv(ay, hd.getCompSubsY(c));
    final end = _ceilDiv(ay + imgH, hd.getCompSubsY(c));
    final div = 1 << dl;
    return _ceilDiv(end, div) - _ceilDiv(start, div);
  }

  @override
  Coord getTile(Coord? reuse) {
    return reuse == null ? Coord(ctX, ctY) : reuse..x = ctX..y = ctY;
  }

  @override
  int getTileIdx() => ctY * ntX + ctX;

  int getResULX(int c, int rl) {
    final dl = mdl[c] - rl;
    if (dl < 0) {
      throw ArgumentError('Resolution $rl unavailable for component $c in tile $ctX,$ctY');
    }
    final tx0 = math.max(px + ctX * ntW, ax);
    final tcx0 = _ceilDiv(tx0, getCompSubsX(c));
    return _ceilDiv(tcx0, 1 << dl);
  }

  int getResULY(int c, int rl) {
    final dl = mdl[c] - rl;
    if (dl < 0) {
      throw ArgumentError('Resolution $rl unavailable for component $c in tile $ctX,$ctY');
    }
    final ty0 = math.max(py + ctY * ntH, ay);
    final tcy0 = _ceilDiv(ty0, getCompSubsY(c));
    return _ceilDiv(tcy0, 1 << dl);
  }

  @override
  Coord getNumTiles(Coord? reuse) {
    return reuse == null ? Coord(ntX, ntY) : reuse..x = ntX..y = ntY;
  }

  @override
  int getNumTilesTotal() => nt;

  SubbandSyn getSynSubbandTree(int t, int c) {
    if (t != getTileIdx()) {
      throw ArgumentError('Cannot access subband tree of tile $t while current tile is ${getTileIdx()}');
    }
    if (c < 0 || c >= nc) {
      throw ArgumentError('Component index out of range: $c');
    }
    final sb = subbTrees[c];
    if (sb == null) {
      throw StateError('Subband tree not initialised for component $c');
    }
    return sb;
  }

  static BitstreamReaderAgent createInstance(
    RandomAccessIO input,
    HeaderDecoder header,
    ParameterList parameters,
    DecoderSpecs specs,
    bool codestreamInfo,
    HeaderInfo headerInfo,
  ) {
    parameters.checkListSingle(
      optPrefix.codeUnitAt(0),
      ParameterList.toNameArray(BitstreamReaderAgent.getParameterInfo()),
    );
    return FileBitstreamReaderAgent(
      header,
      input,
      specs,
      parameters,
      codestreamInfo,
      headerInfo,
    );
  }

  static List<List<String>>? getParameterInfo() => parameterInfo;

  int getPPX(int tile, int comp, int rl) => decSpec.pss.getPPX(tile, comp, rl);

  int getPPY(int tile, int comp, int rl) => decSpec.pss.getPPY(tile, comp, rl);

  void initSubbandsFields(int comp, SubbandSyn sb) {
    final tileIdx = getTileIdx();
    final rl = sb.resLvl;
    final cbw = decSpec.cblks.getCBlkWidth(ModuleSpec.SPEC_TILE_COMP, tileIdx, comp);
    final cbh = decSpec.cblks.getCBlkHeight(ModuleSpec.SPEC_TILE_COMP, tileIdx, comp);

    if (!sb.isNode) {
      if (hd.precinctPartitionUsed()) {
        final ppxExp = MathUtil.log2(getPPX(tileIdx, comp, rl));
        final ppyExp = MathUtil.log2(getPPY(tileIdx, comp, rl));
        final cbwExp = MathUtil.log2(cbw);
        final cbhExp = MathUtil.log2(cbh);

        if (sb.resLvl == 0) {
          sb
            ..nomCBlkW = 1 << math.min(cbwExp, ppxExp)
            ..nomCBlkH = 1 << math.min(cbhExp, ppyExp);
        } else {
          sb
            ..nomCBlkW = 1 << math.min(cbwExp, ppxExp - 1)
            ..nomCBlkH = 1 << math.min(cbhExp, ppyExp - 1);
        }
      } else {
        sb
          ..nomCBlkW = cbw
          ..nomCBlkH = cbh;
      }

      sb.numCb ??= Coord();
      if (sb.w == 0 || sb.h == 0) {
        sb.numCb!
          ..x = 0
          ..y = 0;
      } else {
        var acb0x = getCbULX();
        var acb0y = getCbULY();

        switch (sb.sbandIdx) {
          case Subband.wtOrientLl:
            break;
          case Subband.wtOrientHl:
            acb0x = 0;
            break;
          case Subband.wtOrientLh:
            acb0y = 0;
            break;
          case Subband.wtOrientHh:
            acb0x = 0;
            acb0y = 0;
            break;
          default:
            throw StateError('Invalid subband orientation');
        }

        if (sb.ulcx - acb0x < 0 || sb.ulcy - acb0y < 0) {
          throw ArgumentError('Invalid code-block partition origin or image offset');
        }

        final tmpX = sb.ulcx - acb0x + sb.nomCBlkW;
        sb.numCb!.x = ((tmpX + sb.w - 1) ~/ sb.nomCBlkW) - ((tmpX ~/ sb.nomCBlkW) - 1);

        final tmpY = sb.ulcy - acb0y + sb.nomCBlkH;
        sb.numCb!.y = ((tmpY + sb.h - 1) ~/ sb.nomCBlkH) - ((tmpY ~/ sb.nomCBlkH) - 1);
      }

      // JJ2000 defines magnitude bits as guardBits + exponent (derived bands use
      // the LL exponent adjusted by the decomposition gap). The original C code
      // subtracts one to ensure the MSB of the reconstructed magnitude lines up
      // with the dequantizer's fixed-point scaling. Omitting the subtraction
      // causes every coefficient to be doubled, which is what we observe when
      // comparing against the reference gradient fixture.
      if (derived[comp]) {
        sb.magBits = guardBits[comp] + (params[comp]!.exp[0][0] - (mdl[comp] - sb.level)) - 1;
      } else {
        sb.magBits = guardBits[comp] + params[comp]!.exp[sb.resLvl][sb.sbandIdx] - 1;
      }
    } else {
      initSubbandsFields(comp, sb.getLL() as SubbandSyn);
      initSubbandsFields(comp, sb.getHL() as SubbandSyn);
      initSubbandsFields(comp, sb.getLH() as SubbandSyn);
      initSubbandsFields(comp, sb.getHH() as SubbandSyn);
    }
  }

  int getImgRes() => targetRes;

  double getTargetRate() => trate;

  double getActualRate() {
    arate = anbytes * 8.0 / hd.getMaxCompImgWidth() / hd.getMaxCompImgHeight();
    return arate;
  }

  int getTargetNbytes() => tnbytes;

  int getActualNbytes() => anbytes;

  int getTilePartULX() => hd.getTilingOrigin(null).x;

  int getTilePartULY() => hd.getTilingOrigin(null).y;

  int getNomTileWidth() => hd.getNomTileWidth();

  int getNomTileHeight() => hd.getNomTileHeight();

  static int _computeNtX(HeaderDecoder hd) {
    final ntW = hd.getNomTileWidth();
    final px = hd.getTilingOrigin(null).x;
    final ax = hd.getImgULX();
    final imgW = hd.getImgWidth();
    return (ax + imgW - px + ntW - 1) ~/ ntW;
  }

  static int _computeNtY(HeaderDecoder hd) {
    final ntH = hd.getNomTileHeight();
    final py = hd.getTilingOrigin(null).y;
    final ay = hd.getImgULY();
    final imgH = hd.getImgHeight();
    return (ay + imgH - py + ntH - 1) ~/ ntH;
  }

  static int _ceilDiv(int value, int divisor) {
    if (divisor <= 0) {
      throw ArgumentError('Divisor must be positive');
    }
    if (value >= 0) {
      return (value + divisor - 1) ~/ divisor;
    }
    return value ~/ divisor;
  }
}



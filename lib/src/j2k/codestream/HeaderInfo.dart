import 'dart:math' as math;
import 'dart:typed_data';

import '../roi/MaxShiftSpec.dart';
import '../roi/RectRoiSpec.dart';
import '../wavelet/FilterTypes.dart';
import 'markers.dart';
import 'ProgressionType.dart';

int _ceilDiv(int numerator, int denominator) {
  return (numerator + denominator - 1) ~/ denominator;
}

/// Mirrors JJ2000's HeaderInfo structure for storing parsed marker metadata.
class HeaderInfo {
  HeaderInfoSIZ? siz;

  final Map<String, HeaderInfoSOT> sot = <String, HeaderInfoSOT>{};
  final Map<String, HeaderInfoCOD> cod = <String, HeaderInfoCOD>{};
  final Map<String, HeaderInfoCOC> coc = <String, HeaderInfoCOC>{};
  final Map<String, HeaderInfoRGN> rgn = <String, HeaderInfoRGN>{};
  final Map<String, HeaderInfoQCD> qcd = <String, HeaderInfoQCD>{};
  final Map<String, HeaderInfoQCC> qcc = <String, HeaderInfoQCC>{};
  final Map<String, HeaderInfoPOC> poc = <String, HeaderInfoPOC>{};
  final Map<String, HeaderInfoCOM> com = <String, HeaderInfoCOM>{};
  final Map<int, HeaderInfoTLM> tlm = <int, HeaderInfoTLM>{};

  HeaderInfoCRG? crg;
  int _comCount = 0;

  HeaderInfoSIZ getNewSIZ() => HeaderInfoSIZ();
  HeaderInfoSOT getNewSOT() => HeaderInfoSOT();
  HeaderInfoCOD getNewCOD() => HeaderInfoCOD();
  HeaderInfoCOC getNewCOC() => HeaderInfoCOC();
  HeaderInfoRGN getNewRGN() => HeaderInfoRGN();
  HeaderInfoQCD getNewQCD() => HeaderInfoQCD();
  HeaderInfoQCC getNewQCC() => HeaderInfoQCC();
  HeaderInfoPOC getNewPOC() => HeaderInfoPOC();
  HeaderInfoCRG getNewCRG() => HeaderInfoCRG();
  HeaderInfoTLM getNewTLM() => HeaderInfoTLM();
  HeaderInfoCOM getNewCOM() {
    _comCount++;
    return HeaderInfoCOM();
  }

  int get numCOM => _comCount;

  /// Applies ROI metadata stored in RGN markers to the provided specifications.
  void populateRoiSpecs({
    required MaxShiftSpec roiMaxShift,
    RectROISpec? rectangularRois,
  }) {
    if (rgn.isEmpty) {
      return;
    }

    rgn.forEach((key, info) {
      if (info.srgn != Markers.srgnImplicit) {
        return;
      }
      final shift = info.sprgn;
      int? tileIndex;
      int? componentIndex;

      if (key == 'main') {
        roiMaxShift.setDefault(shift);
        return;
      }

      for (final token in key.split('_')) {
        if (token.isEmpty) {
          continue;
        }
        if (token.startsWith('t')) {
          tileIndex = int.tryParse(token.substring(1));
        } else if (token.startsWith('c')) {
          componentIndex = int.tryParse(token.substring(1));
        }
      }

      final tile = tileIndex;
      final comp = componentIndex;
      if (tile == null) {
        if (comp == null) {
          roiMaxShift.setDefault(shift);
          if (rectangularRois != null) {
            rectangularRois.defaultROI = null;
          }
        } else {
          roiMaxShift.setCompDef(comp, shift);
          if (rectangularRois != null) {
            rectangularRois.setCompDef(comp, null);
          }
        }
      } else {
        if (comp == null) {
          roiMaxShift.setTileDef(tile, shift);
          if (rectangularRois != null) {
            rectangularRois.setTileDef(tile, null);
          }
        } else {
          roiMaxShift.setTileCompVal(tile, comp, shift);
          if (rectangularRois != null) {
            rectangularRois.setTileCompVal(tile, comp, null);
          }
        }
      }
    });
  }

  String toStringMainHeader() {
    if (siz == null) {
      return '';
    }
    final sb = StringBuffer();
    final localSiz = siz!;
    final components = localSiz.csiz;
    sb.write(localSiz);

    final mainCod = cod['main'];
    if (mainCod != null) {
      sb.write(mainCod);
    }

    for (var c = 0; c < components; c++) {
      final key = 'main_c$c';
      final entry = coc[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    final mainQcd = qcd['main'];
    if (mainQcd != null) {
      sb.write(mainQcd);
    }

    for (var c = 0; c < components; c++) {
      final key = 'main_c$c';
      final entry = qcc[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    for (var c = 0; c < components; c++) {
      final key = 'main_c$c';
      final entry = rgn[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    final mainPoc = poc['main'];
    if (mainPoc != null) {
      sb.write(mainPoc);
    }

    if (crg != null) {
      sb.write(crg);
    }

    for (var i = 0; i < numCOM; i++) {
      final entry = com['main_$i'];
      if (entry != null) {
        sb.write(entry);
      }
    }

    if (tlm.isNotEmpty) {
      final sortedIds = tlm.keys.toList()..sort();
      for (final id in sortedIds) {
        final entry = tlm[id];
        if (entry != null) {
          sb.write(entry);
        }
      }
    }
    return sb.toString();
  }

  String toStringTileHeader(int tile, int tileParts) {
    if (siz == null) {
      return '';
    }
    final sb = StringBuffer();
    final components = siz!.csiz;
    for (var i = 0; i < tileParts; i++) {
      final key = 't${tile}_tp$i';
      final entry = sot[key];
      if (entry != null) {
        sb.writeln('Tile-part $i, tile $tile:');
        sb.write(entry);
      }
    }

    final tileCod = cod['t$tile'];
    if (tileCod != null) {
      sb.write(tileCod);
    }

    for (var c = 0; c < components; c++) {
      final key = 't${tile}_c$c';
      final entry = coc[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    final tileQcd = qcd['t$tile'];
    if (tileQcd != null) {
      sb.write(tileQcd);
    }

    for (var c = 0; c < components; c++) {
      final key = 't${tile}_c$c';
      final entry = qcc[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    for (var c = 0; c < components; c++) {
      final key = 't${tile}_c$c';
      final entry = rgn[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    final tilePoc = poc['t$tile'];
    if (tilePoc != null) {
      sb.write(tilePoc);
    }

    return sb.toString();
  }

  String toStringThNoSOT(int tile, int tileParts) {
    if (siz == null) {
      return '';
    }
    final sb = StringBuffer();
    final components = siz!.csiz;

    final tileCod = cod['t$tile'];
    if (tileCod != null) {
      sb.write(tileCod);
    }

    for (var c = 0; c < components; c++) {
      final key = 't${tile}_c$c';
      final entry = coc[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    final tileQcd = qcd['t$tile'];
    if (tileQcd != null) {
      sb.write(tileQcd);
    }

    for (var c = 0; c < components; c++) {
      final key = 't${tile}_c$c';
      final entry = qcc[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    for (var c = 0; c < components; c++) {
      final key = 't${tile}_c$c';
      final entry = rgn[key];
      if (entry != null) {
        sb.write(entry);
      }
    }

    final tilePoc = poc['t$tile'];
    if (tilePoc != null) {
      sb.write(tilePoc);
    }
    return sb.toString();
  }

  HeaderInfo getCopy(int numTiles) {
    final copy = HeaderInfo();
    copy.siz = siz?.getCopy();
    copy._comCount = _comCount;
    if (cod.containsKey('main')) {
      copy.cod['main'] = cod['main']!.getCopy();
    }
    for (var t = 0; t < numTiles; t++) {
      final key = 't$t';
      final entry = cod[key];
      if (entry != null) {
        copy.cod[key] = entry.getCopy();
      }
    }
    return copy;
  }
}

class HeaderInfoSIZ {
  int lsiz = 0;
  int rsiz = 0;
  int xsiz = 0;
  int ysiz = 0;
  int x0siz = 0;
  int y0siz = 0;
  int xtsiz = 0;
  int ytsiz = 0;
  int xt0siz = 0;
  int yt0siz = 0;
  int csiz = 0;
  List<int> ssiz = <int>[];
  List<int> xrsiz = <int>[];
  List<int> yrsiz = <int>[];

  List<int>? _compWidth;
  int _maxCompWidth = -1;
  List<int>? _compHeight;
  int _maxCompHeight = -1;
  int _numTiles = -1;
  List<bool>? _origSigned;
  List<int>? _origBitDepth;

  int getCompImgWidth(int c) {
    _compWidth ??= List<int>.filled(csiz, 0);
    if (_compWidth![c] == 0) {
      _compWidth![c] = _ceilDiv(xsiz, xrsiz[c]) - _ceilDiv(x0siz, xrsiz[c]);
    }
    return _compWidth![c];
  }

  int getMaxCompWidth() {
    _compWidth ??= List<int>.filled(csiz, 0);
    if (_maxCompWidth == -1) {
      for (var c = 0; c < csiz; c++) {
        if (_compWidth![c] == 0) {
          _compWidth![c] = _ceilDiv(xsiz, xrsiz[c]) - _ceilDiv(x0siz, xrsiz[c]);
        }
        if (_compWidth![c] > _maxCompWidth) {
          _maxCompWidth = _compWidth![c];
        }
      }
    }
    return _maxCompWidth;
  }

  int getCompImgHeight(int c) {
    _compHeight ??= List<int>.filled(csiz, 0);
    if (_compHeight![c] == 0) {
      _compHeight![c] = _ceilDiv(ysiz, yrsiz[c]) - _ceilDiv(y0siz, yrsiz[c]);
    }
    return _compHeight![c];
  }

  int getMaxCompHeight() {
    _compHeight ??= List<int>.filled(csiz, 0);
    if (_maxCompHeight == -1) {
      for (var c = 0; c < csiz; c++) {
        if (_compHeight![c] == 0) {
          _compHeight![c] =
              _ceilDiv(ysiz, yrsiz[c]) - _ceilDiv(y0siz, yrsiz[c]);
        }
        if (_compHeight![c] > _maxCompHeight) {
          _maxCompHeight = _compHeight![c];
        }
      }
    }
    return _maxCompHeight;
  }

  int getNumTiles() {
    if (_numTiles == -1) {
      final tilesX = (xsiz - xt0siz + xtsiz - 1) ~/ xtsiz;
      final tilesY = (ysiz - yt0siz + ytsiz - 1) ~/ ytsiz;
      _numTiles = tilesX * tilesY;
    }
    return _numTiles;
  }

  bool isOrigSigned(int c) {
    _origSigned ??= List<bool>.filled(csiz, false);
    _origSigned![c] =
        _origSigned![c] || ((ssiz[c] >> Markers.SSIZ_DEPTH_BITS) & 0x1) == 1;
    return _origSigned![c];
  }

  int getOrigBitDepth(int c) {
    _origBitDepth ??= List<int>.filled(csiz, 0);
    if (_origBitDepth![c] == 0) {
      _origBitDepth![c] = (ssiz[c] & ((1 << Markers.SSIZ_DEPTH_BITS) - 1)) + 1;
    }
    return _origBitDepth![c];
  }

  HeaderInfoSIZ getCopy() {
    final copy = HeaderInfoSIZ()
      ..lsiz = lsiz
      ..rsiz = rsiz
      ..xsiz = xsiz
      ..ysiz = ysiz
      ..x0siz = x0siz
      ..y0siz = y0siz
      ..xtsiz = xtsiz
      ..ytsiz = ytsiz
      ..xt0siz = xt0siz
      ..yt0siz = yt0siz
      ..csiz = csiz
      ..ssiz = List<int>.from(ssiz)
      ..xrsiz = List<int>.from(xrsiz)
      ..yrsiz = List<int>.from(yrsiz);
    return copy;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- SIZ ($lsiz bytes) ---');
    sb.writeln(' Capabilities : $rsiz');
    sb.writeln(
        ' Image dim.   : ${xsiz - x0siz}x${ysiz - y0siz}, (off=$x0siz,$y0siz)');
    sb.writeln(' Tile dim.    : ${xtsiz}x${ytsiz}, (off=$xt0siz,$yt0siz)');
    sb.writeln(' Component(s) : $csiz');
    sb.write(' Orig. depth  : ');
    for (var i = 0; i < csiz; i++) {
      sb.write('${getOrigBitDepth(i)} ');
    }
    sb.writeln();
    sb.write(' Orig. signed : ');
    for (var i = 0; i < csiz; i++) {
      sb.write('${isOrigSigned(i)} ');
    }
    sb.writeln();
    sb.write(' Subs. factor : ');
    for (var i = 0; i < csiz; i++) {
      sb.write('${xrsiz[i]},${yrsiz[i]} ');
    }
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoSOT {
  int lsot = 0;
  int isot = 0;
  int psot = 0;
  int tpsot = 0;
  int tnsot = 0;

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- SOT ($lsot bytes) ---');
    sb.writeln('Tile index         : $isot');
    sb.writeln('Tile-part length   : $psot bytes');
    sb.writeln('Tile-part index    : $tpsot');
    sb.writeln('Num. of tile-parts : $tnsot');
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoCOD {
  int lcod = 0;
  int scod = 0;
  int sgcodPo = 0;
  int sgcodNl = 0;
  int sgcodMct = 0;
  int spcodNdl = 0;
  int spcodCw = 0;
  int spcodCh = 0;
  int spcodCs = 0;
  List<int> spcodT = <int>[0];
  List<int>? spcodPs;

  HeaderInfoCOD getCopy() {
    final copy = HeaderInfoCOD()
      ..lcod = lcod
      ..scod = scod
      ..sgcodPo = sgcodPo
      ..sgcodNl = sgcodNl
      ..sgcodMct = sgcodMct
      ..spcodNdl = spcodNdl
      ..spcodCw = spcodCw
      ..spcodCh = spcodCh
      ..spcodCs = spcodCs
      ..spcodT = List<int>.from(spcodT)
      ..spcodPs = spcodPs == null ? null : List<int>.from(spcodPs!);
    return copy;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- COD ($lcod bytes) ---');
    sb.write(' Coding style   : ');
    if (scod == 0) {
      sb.write('Default');
    } else {
      if ((scod & Markers.SCOX_PRECINCT_PARTITION) != 0) sb.write('Precints ');
      if ((scod & Markers.SCOX_USE_SOP) != 0) sb.write('SOP ');
      if ((scod & Markers.SCOX_USE_EPH) != 0) sb.write('EPH ');
      final cb0x = (scod & Markers.SCOX_HOR_CB_PART) != 0 ? 1 : 0;
      final cb0y = (scod & Markers.SCOX_VER_CB_PART) != 0 ? 1 : 0;
      if (cb0x != 0 || cb0y != 0) {
        sb.write('Code-blocks offset');
        sb.write('\n Cblk partition : $cb0x,$cb0y');
      }
    }
    sb.writeln();
    sb.write(' Cblk style     : ');
    if (spcodCs == 0) {
      sb.write('Default');
    } else {
      if ((spcodCs & 0x1) != 0) sb.write('Bypass ');
      if ((spcodCs & 0x2) != 0) sb.write('Reset ');
      if ((spcodCs & 0x4) != 0) sb.write('Terminate ');
      if ((spcodCs & 0x8) != 0) sb.write('Vert_causal ');
      if ((spcodCs & 0x10) != 0) sb.write('Predict ');
      if ((spcodCs & 0x20) != 0) sb.write('Seg_symb ');
    }
    sb.writeln();
    sb.writeln(' Num. of levels : $spcodNdl');
    sb.write(' Progress. type : ');
    switch (sgcodPo) {
      case ProgressionType.LY_RES_COMP_POS_PROG:
        sb.writeln('LY_RES_COMP_POS_PROG');
        break;
      case ProgressionType.RES_LY_COMP_POS_PROG:
        sb.writeln('RES_LY_COMP_POS_PROG');
        break;
      case ProgressionType.RES_POS_COMP_LY_PROG:
        sb.writeln('RES_POS_COMP_LY_PROG');
        break;
      case ProgressionType.POS_COMP_RES_LY_PROG:
        sb.writeln('POS_COMP_RES_LY_PROG');
        break;
      case ProgressionType.COMP_POS_RES_LY_PROG:
        sb.writeln('COMP_POS_RES_LY_PROG');
        break;
      default:
        sb.writeln('Unknown');
        break;
    }
    sb.writeln(' Num. of layers : $sgcodNl');
    final cblkWidth = 1 << (spcodCw + 2);
    final cblkHeight = 1 << (spcodCh + 2);
    sb.writeln(' Cblk dimension : ${cblkWidth}x${cblkHeight}');
    switch (spcodT[0]) {
      case FilterTypes.W9X7:
        sb.writeln(' Filter         : 9-7 irreversible');
        break;
      case FilterTypes.W5X3:
        sb.writeln(' Filter         : 5-3 reversible');
        break;
      default:
        sb.writeln(' Filter         : ${spcodT[0]}');
        break;
    }
    sb.writeln(' Multi comp tr. : ${sgcodMct == 1}');
    if (spcodPs != null) {
      sb.write(' Precincts      : ');
      for (final value in spcodPs!) {
        final w = 1 << (value & 0x000F);
        final h = 1 << ((value & 0x00F0) >> 4);
        sb.write('${w}x$h ');
      }
      sb.writeln();
    }
    return sb.toString();
  }
}

class HeaderInfoCOC {
  int lcoc = 0;
  int ccoc = 0;
  int scoc = 0;
  int spcocNdl = 0;
  int spcocCw = 0;
  int spcocCh = 0;
  int spcocCs = 0;
  List<int> spcocT = <int>[0];
  List<int>? spcocPs;

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- COC ($lcoc bytes) ---');
    sb.writeln(' Component      : $ccoc');
    sb.write(' Coding style   : ');
    if (scoc == 0) {
      sb.write('Default');
    } else {
      if ((scoc & 0x1) != 0) sb.write('Precints ');
      if ((scoc & 0x2) != 0) sb.write('SOP ');
      if ((scoc & 0x4) != 0) sb.write('EPH ');
    }
    sb.writeln();
    sb.write(' Cblk style     : ');
    if (spcocCs == 0) {
      sb.write('Default');
    } else {
      if ((spcocCs & 0x1) != 0) sb.write('Bypass ');
      if ((spcocCs & 0x2) != 0) sb.write('Reset ');
      if ((spcocCs & 0x4) != 0) sb.write('Terminate ');
      if ((spcocCs & 0x8) != 0) sb.write('Vert_causal ');
      if ((spcocCs & 0x10) != 0) sb.write('Predict ');
      if ((spcocCs & 0x20) != 0) sb.write('Seg_symb ');
    }
    sb.writeln();
    sb.writeln(' Num. of levels : $spcocNdl');
    sb.writeln(' Cblk dimension : ${1 << (spcocCw + 2)}x${1 << (spcocCh + 2)}');
    switch (spcocT[0]) {
      case FilterTypes.W9X7:
        sb.writeln(' Filter         : 9-7 irreversible');
        break;
      case FilterTypes.W5X3:
        sb.writeln(' Filter         : 5-3 reversible');
        break;
      default:
        sb.writeln(' Filter         : ${spcocT[0]}');
        break;
    }
    if (spcocPs != null) {
      sb.write(' Precincts      : ');
      for (final value in spcocPs!) {
        final w = 1 << (value & 0x000F);
        final h = 1 << ((value & 0x00F0) >> 4);
        sb.write('${w}x$h ');
      }
      sb.writeln();
    }
    return sb.toString();
  }
}

class HeaderInfoRGN {
  int lrgn = 0;
  int crgn = 0;
  int srgn = 0;
  int sprgn = 0;

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- RGN ($lrgn bytes) ---');
    sb.writeln(' Component : $crgn');
    if (srgn == 0) {
      sb.writeln(' ROI style : Implicit');
    } else {
      sb.writeln(' ROI style : Unsupported');
    }
    sb.writeln(' ROI shift : $sprgn');
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoQCD {
  int lqcd = 0;
  int sqcd = 0;
  List<List<int>> spqcd = <List<int>>[];

  int _quantType = -1;
  int getQuantType() {
    if (_quantType == -1) {
      _quantType = sqcd & ~(Markers.SQCX_GB_MSK << Markers.SQCX_GB_SHIFT);
    }
    return _quantType;
  }

  int _guardBits = -1;
  int getNumGuardBits() {
    if (_guardBits == -1) {
      _guardBits = (sqcd >> Markers.SQCX_GB_SHIFT) & Markers.SQCX_GB_MSK;
    }
    return _guardBits;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- QCD ($lqcd bytes) ---');
    sb.write(' Quant. type    : ');
    final qt = getQuantType();
    if (qt == Markers.SQCX_NO_QUANTIZATION) {
      sb.writeln('No quantization');
    } else if (qt == Markers.SQCX_SCALAR_DERIVED) {
      sb.writeln('Scalar derived');
    } else if (qt == Markers.SQCX_SCALAR_EXPOUNDED) {
      sb.writeln('Scalar expounded');
    } else {
      sb.writeln(qt);
    }
    sb.writeln(' Guard bits     : ${getNumGuardBits()}');
    if (qt == Markers.SQCX_NO_QUANTIZATION) {
      sb.writeln(' Exponents   :');
      for (var r = 0; r < spqcd.length; r++) {
        for (var s = 0; s < spqcd[r].length; s++) {
          if ((r == 0 && s == 0) || (r != 0 && s > 0)) {
            final exp =
                (spqcd[r][s] >> Markers.SQCX_EXP_SHIFT) & Markers.SQCX_EXP_MASK;
            sb.writeln('\tr=$r${s == 0 ? '' : ',s=$s'} : $exp');
          }
        }
      }
    } else {
      sb.writeln(' Exp / Mantissa : ');
      for (var r = 0; r < spqcd.length; r++) {
        for (var s = 0; s < spqcd[r].length; s++) {
          if ((r == 0 && s == 0) || (r != 0 && s > 0)) {
            final exp = (spqcd[r][s] >> 11) & 0x1f;
            final mantissa =
                (-1.0 - (spqcd[r][s] & 0x07ff) / math.pow(2, 11)) / (-1 << exp);
            sb.writeln('\tr=$r${s == 0 ? '' : ',s=$s'} : $exp / $mantissa');
          }
        }
      }
    }
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoQCC {
  int lqcc = 0;
  int cqcc = 0;
  int sqcc = 0;
  List<List<int>> spqcc = <List<int>>[];

  int _quantType = -1;
  int getQuantType() {
    if (_quantType == -1) {
      _quantType = sqcc & ~(Markers.SQCX_GB_MSK << Markers.SQCX_GB_SHIFT);
    }
    return _quantType;
  }

  int _guardBits = -1;
  int getNumGuardBits() {
    if (_guardBits == -1) {
      _guardBits = (sqcc >> Markers.SQCX_GB_SHIFT) & Markers.SQCX_GB_MSK;
    }
    return _guardBits;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- QCC ($lqcc bytes) ---');
    sb.writeln(' Component      : $cqcc');
    sb.write(' Quant. type    : ');
    final qt = getQuantType();
    if (qt == Markers.SQCX_NO_QUANTIZATION) {
      sb.writeln('No quantization');
    } else if (qt == Markers.SQCX_SCALAR_DERIVED) {
      sb.writeln('Scalar derived');
    } else if (qt == Markers.SQCX_SCALAR_EXPOUNDED) {
      sb.writeln('Scalar expounded');
    } else {
      sb.writeln(qt);
    }
    sb.writeln(' Guard bits     : ${getNumGuardBits()}');
    if (qt == Markers.SQCX_NO_QUANTIZATION) {
      sb.writeln(' Exponents   :');
      for (var r = 0; r < spqcc.length; r++) {
        for (var s = 0; s < spqcc[r].length; s++) {
          if ((r == 0 && s == 0) || (r != 0 && s > 0)) {
            final exp =
                (spqcc[r][s] >> Markers.SQCX_EXP_SHIFT) & Markers.SQCX_EXP_MASK;
            sb.writeln('\tr=$r${s == 0 ? '' : ',s=$s'} : $exp');
          }
        }
      }
    } else {
      sb.writeln(' Exp / Mantissa : ');
      for (var r = 0; r < spqcc.length; r++) {
        for (var s = 0; s < spqcc[r].length; s++) {
          if ((r == 0 && s == 0) || (r != 0 && s > 0)) {
            final exp = (spqcc[r][s] >> 11) & 0x1f;
            final mantissa =
                (-1.0 - (spqcc[r][s] & 0x07ff) / math.pow(2, 11)) / (-1 << exp);
            sb.writeln('\tr=$r${s == 0 ? '' : ',s=$s'} : $exp / $mantissa');
          }
        }
      }
    }
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoPOC {
  int lpoc = 0;
  List<int> rspoc = <int>[];
  List<int> cspoc = <int>[];
  List<int> lyepoc = <int>[];
  List<int> repoc = <int>[];
  List<int> cepoc = <int>[];
  List<int> ppoc = <int>[];

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- POC ($lpoc bytes) ---');
    sb.writeln(' Chg_idx RSpoc CSpoc LYEpoc REpoc CEpoc Ppoc');
    for (var i = 0; i < rspoc.length; i++) {
      sb.write('   $i      ${rspoc[i]}     ${cspoc[i]}     ${lyepoc[i]}');
      sb.write('      ${repoc[i]}     ${cepoc[i]}');
      sb.write('  ');
      switch (ppoc[i]) {
        case ProgressionType.LY_RES_COMP_POS_PROG:
          sb.writeln('LY_RES_COMP_POS_PROG');
          break;
        case ProgressionType.RES_LY_COMP_POS_PROG:
          sb.writeln('RES_LY_COMP_POS_PROG');
          break;
        case ProgressionType.RES_POS_COMP_LY_PROG:
          sb.writeln('RES_POS_COMP_LY_PROG');
          break;
        case ProgressionType.POS_COMP_RES_LY_PROG:
          sb.writeln('POS_COMP_RES_LY_PROG');
          break;
        case ProgressionType.COMP_POS_RES_LY_PROG:
          sb.writeln('COMP_POS_RES_LY_PROG');
          break;
        default:
          sb.writeln('Unknown');
          break;
      }
    }
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoCRG {
  int lcrg = 0;
  List<int> xcrg = <int>[];
  List<int> ycrg = <int>[];

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- CRG ($lcrg bytes) ---');
    for (var c = 0; c < xcrg.length; c++) {
      sb.writeln(' Component $c offset : ${xcrg[c]},${ycrg[c]}');
    }
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoCOM {
  int lcom = 0;
  int rcom = 0;
  Uint8List ccom = Uint8List(0);

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- COM ($lcom bytes) ---');
    if (rcom == 0) {
      sb.writeln(' Registration : General use (binary values)');
    } else if (rcom == Markers.RCOM_GENERAL_USE) {
      sb.writeln(
          ' Registration : General use (IS 8859-15:1999 (Latin) values)');
      sb.writeln(' Text         : ${String.fromCharCodes(ccom)}');
    } else {
      sb.writeln(' Registration : Unknown');
    }
    sb.writeln();
    return sb.toString();
  }
}

class HeaderInfoTLMEntry {
  const HeaderInfoTLMEntry({
    required this.tileIndex,
    required this.length,
  });

  final int tileIndex;
  final int length;
}

class HeaderInfoTLM {
  int ltlm = 0;
  int ztlm = 0;
  int stlm = 0;
  final List<HeaderInfoTLMEntry> entries = <HeaderInfoTLMEntry>[];

  int get tileIndexFieldBytes => (stlm >> 4) & 0x3;
  int get tilePartLengthFieldBytes => (((stlm >> 6) & 0x1) + 1) * 2;

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('\n --- TLM ($ltlm bytes) ---');
    sb.writeln(' Marker index   : $ztlm');
    final tileLabel = tileIndexFieldBytes == 0
        ? 'implicit'
        : '${tileIndexFieldBytes} byte${tileIndexFieldBytes == 1 ? '' : 's'}';
    sb.writeln(' Tile field     : $tileLabel');
    sb.writeln(' Length field   : ${tilePartLengthFieldBytes} bytes');
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      sb.writeln('  [${i + 1}] tile=${entry.tileIndex} length=${entry.length}');
    }
    sb.writeln();
    return sb.toString();
  }
}


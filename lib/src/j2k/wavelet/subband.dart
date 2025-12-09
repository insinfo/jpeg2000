import '../image/Coord.dart';
import 'WaveletFilter.dart';

/// Represents a node or leaf in the JJ2000 wavelet subband decomposition tree.
abstract class Subband {
  static const int wtOrientLl = 0;
  static const int wtOrientHl = 1;
  static const int wtOrientLh = 2;
  static const int wtOrientHh = 3;

  Subband();

  Subband.tree(
    this.w,
    this.h,
    this.ulcx,
    this.ulcy,
    int levels,
    List<WaveletFilter> hFilters,
    List<WaveletFilter> vFilters,
  ) : resLvl = levels {
    Subband current = this;
    for (var i = 0; i < levels; i++) {
      final hIndex = current.resLvl <= hFilters.length
          ? current.resLvl - 1
          : hFilters.length - 1;
      final vIndex = current.resLvl <= vFilters.length
          ? current.resLvl - 1
          : vFilters.length - 1;
      current = current.split(hFilters[hIndex], vFilters[vIndex]);
    }
  }

  bool isNode = false;
  int orientation = wtOrientLl;
  int level = 0;
  int resLvl = 0;
  Coord? numCb;
  int anGainExp = 0;
  int sbandIdx = 0;
  int ulcx = 0;
  int ulcy = 0;
  int ulx = 0;
  int uly = 0;
  int w = 0;
  int h = 0;
  int nomCBlkW = 0;
  int nomCBlkH = 0;

  Subband? getParent();
  Subband getLL();
  Subband getHL();
  Subband getLH();
  Subband getHH();

  Subband split(WaveletFilter hFilter, WaveletFilter vFilter);

  void initChilds() {
    final subbLL = getLL();
    final subbHL = getHL();
    final subbLH = getLH();
    final subbHH = getHH();

    subbLL
      ..level = level + 1
      ..ulcx = (ulcx + 1) >> 1
      ..ulcy = (ulcy + 1) >> 1
      ..ulx = ulx
      ..uly = uly
      ..w = ((ulcx + w + 1) >> 1) - subbLL.ulcx
      ..h = ((ulcy + h + 1) >> 1) - subbLL.ulcy
      ..resLvl = orientation == wtOrientLl ? resLvl - 1 : resLvl
      ..anGainExp = anGainExp
      ..sbandIdx = sbandIdx << 2;

    subbHL
      ..orientation = wtOrientHl
      ..level = subbLL.level
      ..ulcx = ulcx >> 1
      ..ulcy = subbLL.ulcy
      ..ulx = ulx + subbLL.w
      ..uly = uly
      ..w = ((ulcx + w) >> 1) - subbHL.ulcx
      ..h = subbLL.h
      ..resLvl = resLvl
      ..anGainExp = anGainExp + 1
      ..sbandIdx = (sbandIdx << 2) + 1;

    subbLH
      ..orientation = wtOrientLh
      ..level = subbLL.level
      ..ulcx = subbLL.ulcx
      ..ulcy = ulcy >> 1
      ..ulx = ulx
      ..uly = uly + subbLL.h
      ..w = subbLL.w
      ..h = ((ulcy + h) >> 1) - subbLH.ulcy
      ..resLvl = resLvl
      ..anGainExp = anGainExp + 1
      ..sbandIdx = (sbandIdx << 2) + 2;

    subbHH
      ..orientation = wtOrientHh
      ..level = subbLL.level
      ..ulcx = subbHL.ulcx
      ..ulcy = subbLH.ulcy
      ..ulx = subbHL.ulx
      ..uly = subbLH.uly
      ..w = subbHL.w
      ..h = subbLH.h
      ..resLvl = resLvl
      ..anGainExp = anGainExp + 2
      ..sbandIdx = (sbandIdx << 2) + 3;
  }

  Subband? nextSubband() {
    if (isNode) {
      throw ArgumentError('Cannot iterate nodes directly');
    }

    switch (orientation) {
      case wtOrientLl:
        final parent = getParent();
        if (parent == null || parent.resLvl != resLvl) {
          return null;
        }
        Subband candidate = parent.getHL();
        while (candidate.isNode) {
          candidate = candidate.getLL();
        }
        return candidate;
      case wtOrientHl:
        final parent = getParent();
        return parent?.getLH();
      case wtOrientLh:
        final parent = getParent();
        return parent?.getHH();
      case wtOrientHh:
        Subband? ancestor = this;
        while (ancestor != null && ancestor.orientation == wtOrientHh) {
          ancestor = ancestor.getParent();
        }
        if (ancestor == null) {
          return null;
        }
        late final Subband next;
        switch (ancestor.orientation) {
          case wtOrientLl:
            final parent = ancestor.getParent();
            if (parent == null || parent.resLvl != resLvl) {
              return null;
            }
            next = parent.getHL();
            break;
          case wtOrientHl:
            final parent = ancestor.getParent();
            if (parent == null) {
              return null;
            }
            next = parent.getLH();
            break;
          case wtOrientLh:
            final parent = ancestor.getParent();
            if (parent == null) {
              return null;
            }
            next = parent.getHH();
            break;
          default:
            throw StateError('Invalid subband orientation state');
        }
        Subband currentNode = next;
        while (currentNode.isNode) {
          currentNode = currentNode.getLL();
        }
        return currentNode;
      default:
        throw StateError('Invalid subband orientation state');
    }
  }

  Subband? getNextResLevel() {
    if (level == 0) {
      return null;
    }
    Subband? ancestor = this;
    do {
      ancestor = ancestor?.getParent();
      if (ancestor == null) {
        return null;
      }
    } while (ancestor.resLvl == resLvl);
    Subband currentNode = ancestor.getHL();
    while (currentNode.isNode) {
      currentNode = currentNode.getLL();
    }
    return currentNode;
  }

  Subband getSubbandByIdx(int rl, int sbi) {
    Subband sb = this;
    if (rl > sb.resLvl || rl < 0) {
      throw ArgumentError('Resolution level index out of range');
    }
    if (rl == sb.resLvl && sbi == sb.sbandIdx) {
      return sb;
    }
    if (sb.sbandIdx != 0) {
      final parent = sb.getParent();
      if (parent != null) {
        sb = parent;
      }
    }
    while (sb.resLvl > rl) {
      sb = sb.getLL();
    }
    while (sb.resLvl < rl) {
      final parent = sb.getParent();
      if (parent == null) {
        break;
      }
      sb = parent;
    }
    switch (sbi) {
      case 0:
        return sb;
      case 1:
        return sb.getHL();
      case 2:
        return sb.getLH();
      case 3:
        return sb.getHH();
      default:
        return sb;
    }
  }

  Subband getSubband(int x, int y) {
    if (x < ulx || y < uly || x >= ulx + w || y >= uly + h) {
      throw ArgumentError('Point is outside subband bounds');
    }
    Subband current = this;
    while (current.isNode) {
      final hh = current.getHH();
      if (x < hh.ulx) {
        current = y < hh.uly ? current.getLL() : current.getLH();
      } else {
        current = y < hh.uly ? current.getHL() : current.getHH();
      }
    }
    return current;
  }

  @override
  String toString() {
    return 'w=$w,h=$h,ulx=$ulx,uly=$uly,ulcx=$ulcx,ulcy=$ulcy,'
        'idx=$sbandIdx,orient=$orientation,node=$isNode,level=$level,'
        'resLvl=$resLvl,nomCBlkW=$nomCBlkW,nomCBlkH=$nomCBlkH,numCb=$numCb';
  }

  WaveletFilter getHorWFilter();
  WaveletFilter getVerWFilter();
}


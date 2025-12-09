import 'dart:typed_data';
import 'package:jpeg2000/src/j2k/codestream/CBlkCoordInfo.dart';

import '../../entropy/encoder/CodedCBlkDataSrcEnc.dart';
import '../../encoder/EncoderSpecs.dart';
import '../../image/Coord.dart';
import '../../util/ParameterList.dart';
import '../../codestream/PrecInfo.dart';
import '../../entropy/encoder/CBlkRateDistStats.dart';
import '../../wavelet/analysis/SubbandAn.dart';
import '../../util/MathUtil.dart';
import '../../util/ArrayUtil.dart';
import 'BitOutputBuffer.dart';
import 'TagTreeEncoder.dart';


/// This class builds packets and keeps the state information of packet
/// interdependencies. It also supports saving the state and reverting
/// (restoring) to the last saved state, with the save() and restore() methods.
///
/// Each time the encodePacket() method is called a new packet is encoded,
/// the packet header is returned by the method, and the packet body can be
/// obtained with the getLastBodyBuf() and getLastBodyLen() methods.
class PktEncoder {
  /// The prefix for packet encoding options: 'P'
  static const String optPrefix = 'P';

  /// The list of parameters that is accepted for packet encoding.
  static const List<List<String>> pinfo = [
    [
      "Psop",
      "[<tile idx>] on|off" + "[ [<tile idx>] on|off ...]",
      "Specifies whether start of packet (SOP) markers should be used. " +
          "'on' enables, 'off' disables it.",
      "off"
    ],
    [
      "Peph",
      "[<tile idx>] on|off" + "[ [<tile  idx>] on|off ...]",
      "Specifies whether end of packet header (EPH) markers should be " +
          " used. 'on' enables, 'off' disables it.",
      "off"
    ]
  ];

  /// The initial value for the lblock
  static const int initLblock = 3;

  /// The source object
  final CodedCBlkDataSrcEnc infoSrc;

  /// The encoder specs
  final EncoderSpecs encSpec;

  /// The tag tree for inclusion information.
  /// 1st index: tile index
  /// 2nd index: component index
  /// 3rd index: resolution level
  /// 4th index: precinct index
  /// 5th index: subband index
  late List<List<List<List<List<TagTreeEncoder>>>>> ttIncl;

  /// The tag tree for the maximum significant bit-plane.
  late List<List<List<List<List<TagTreeEncoder>>>>> ttMaxBP;

  /// The base number of bits for sending code-block length information.
  /// 1st index: tile index
  /// 2nd index: component index
  /// 3rd index: resolution level
  /// 4th index: subband index
  /// 5th index: code-block index
  late List<List<List<List<List<int>>>>> lblock;

  /// The last encoded truncation point for each code-block.
  late List<List<List<List<List<int>>>>> prevtIdxs;

  /// The saved base number of bits for sending code-block length information.
  List<List<List<List<List<int>>>>>? bakLblock;

  /// The saved last encoded truncation point for each code-block.
  List<List<List<List<List<int>>>>>? bakPrevtIdxs;

  /// The body buffer of the last encoded packet
  Uint8List? lbbuf;

  /// The body length of the last encoded packet
  int lblen = 0;

  /// The saved state
  bool saved = false;

  /// Whether or not there is ROI information in the last encoded Packet
  bool roiInPkt = false;

  /// Length to read in current packet body to get all the ROI information
  int roiLen = 0;

  /// Array containing the coordinates, width, height, indexes, ... of the
  /// precincts.
  /// 1st dim: tile index.
  /// 2nd dim: component index.
  /// 3rd dim: resolution level index.
  /// 4th dim: precinct index.
  late List<List<List<List<PrecInfo>>>> ppinfo;

  /// Whether or not the current packet is writable
  bool packetWritable = false;

  /// Creates a new packet encoder object, using the information from the
  /// 'infoSrc' object.
  PktEncoder(
      this.infoSrc, this.encSpec, List<List<List<Coord>>> numPrec, ParameterList pl) {
    // Check parameters
    pl.checkList([optPrefix.codeUnitAt(0)], ParameterList.toNameArray(pinfo));

    // Get number of components and tiles
    int nc = infoSrc.getNumComps();
    int nt = infoSrc.getNumTiles();

    // Do initial allocation
    ttIncl = List.generate(nt, (_) => List.generate(nc, (_) => []));
    ttMaxBP = List.generate(nt, (_) => List.generate(nc, (_) => []));
    lblock = List.generate(nt, (_) => List.generate(nc, (_) => []));
    prevtIdxs = List.generate(nt, (_) => List.generate(nc, (_) => []));
    ppinfo = List.generate(nt, (_) => List.generate(nc, (_) => []));

    // Finish allocation
    SubbandAn root, sb;
    int maxs, mins;
    int mrl;
    int numcb; // Number of code-blocks
    infoSrc.setTile(0, 0);
    for (int t = 0; t < nt; t++) {
      // Loop on tiles
      for (int c = 0; c < nc; c++) {
        // Loop on components
        // Get number of resolution levels
        root = infoSrc.getAnSubbandTree(t, c);
        mrl = root.resLvl;

        lblock[t][c] = List.generate(mrl + 1, (_) => []);
        ttIncl[t][c] = List.generate(mrl + 1, (_) => []);
        ttMaxBP[t][c] = List.generate(mrl + 1, (_) => []);
        prevtIdxs[t][c] = List.generate(mrl + 1, (_) => []);
        ppinfo[t][c] = List.generate(mrl + 1, (_) => []);

        for (int r = 0; r <= mrl; r++) {
          // Loop on resolution levels
          mins = (r == 0) ? 0 : 1;
          maxs = (r == 0) ? 1 : 4;

          int maxPrec = numPrec[t][c][r].x * numPrec[t][c][r].y;

          ttIncl[t][c][r] = List.generate(maxPrec, (_) => List.filled(maxs, TagTreeEncoder(0, 0, null)));
          ttMaxBP[t][c][r] = List.generate(maxPrec, (_) => List.filled(maxs, TagTreeEncoder(0, 0, null)));
          prevtIdxs[t][c][r] = List.generate(maxs, (_) => []);
          lblock[t][c][r] = List.generate(maxs, (_) => []);

          // Precincts and code-blocks
          ppinfo[t][c][r] = List.filled(maxPrec, PrecInfo(0, 0, 0, 0, 0, 0, 0, 0, 0));
          _fillPrecInfo(t, c, r);

          for (int s = mins; s < maxs; s++) {
            // Loop on subbands
            sb = root.getSubbandByIdx(r, s) as SubbandAn;
            numcb = sb.numCb!.x * sb.numCb!.y;

            lblock[t][c][r][s] = List.filled(numcb, initLblock);
            prevtIdxs[t][c][r][s] = List.filled(numcb, -1);
          }
        }
      }
      if (t != nt - 1) infoSrc.nextTile();
    }
  }

  /// Retrives precincts and code-blocks coordinates in the given resolution,
  /// component and tile. It terminates TagTreeEncoder initialization as
  /// well.
  void _fillPrecInfo(int t, int c, int r) {
    if (ppinfo[t][c][r].isEmpty) return; // No precinct in this resolution level

    Coord tileI = infoSrc.getTile(null);
    Coord nTiles = infoSrc.getNumTilesCoord(null);

    int x0siz = infoSrc.getImgULX();
    int y0siz = infoSrc.getImgULY();
    int xsiz = x0siz + infoSrc.getImgWidth();
    int ysiz = y0siz + infoSrc.getImgHeight();
    int xt0siz = infoSrc.getTilePartULX();
    int yt0siz = infoSrc.getTilePartULY();
    int xtsiz = infoSrc.getNomTileWidth();
    int ytsiz = infoSrc.getNomTileHeight();

    int tx0 = (tileI.x == 0) ? x0siz : xt0siz + tileI.x * xtsiz;
    int ty0 = (tileI.y == 0) ? y0siz : yt0siz + tileI.y * ytsiz;
    int tx1 = (tileI.x != nTiles.x - 1) ? xt0siz + (tileI.x + 1) * xtsiz : xsiz;
    int ty1 = (tileI.y != nTiles.y - 1) ? yt0siz + (tileI.y + 1) * ytsiz : ysiz;

    int xrsiz = infoSrc.getCompSubsX(c);
    int yrsiz = infoSrc.getCompSubsY(c);

    int tcx0 = (tx0 / xrsiz).ceil();
    int tcy0 = (ty0 / yrsiz).ceil();
    int tcx1 = (tx1 / xrsiz).ceil();
    int tcy1 = (ty1 / yrsiz).ceil();

    int ndl = infoSrc.getAnSubbandTree(t, c).resLvl - r;
    int trx0 = (tcx0 / (1 << ndl)).ceil();
    int try0 = (tcy0 / (1 << ndl)).ceil();
    int trx1 = (tcx1 / (1 << ndl)).ceil();
    int try1 = (tcy1 / (1 << ndl)).ceil();

    int cb0x = infoSrc.getCbULX();
    int cb0y = infoSrc.getCbULY();

    double twoppx = encSpec.pss.getPPX(t, c, r).toDouble();
    double twoppy = encSpec.pss.getPPY(t, c, r).toDouble();
    int twoppx2 = (twoppx / 2).toInt();
    int twoppy2 = (twoppy / 2).toInt();

    // Precincts are located at (cb0x+i*twoppx,cb0y+j*twoppy)
    // Valid precincts are those which intersect with the current
    // resolution level
    int nPrec = 0;

    int istart = ((try0 - cb0y) / twoppy).floor();
    int iend = ((try1 - 1 - cb0y) / twoppy).floor();
    int jstart = ((trx0 - cb0x) / twoppx).floor();
    int jend = ((trx1 - 1 - cb0x) / twoppx).floor();

    int acb0x, acb0y;

    SubbandAn root = infoSrc.getAnSubbandTree(t, c);
    SubbandAn sb;

    int p0x, p0y, p1x, p1y; // Precinct projection in subband
    int s0x, s0y, s1x, s1y; // Active subband portion
    int cw, ch;
    int kstart, kend, lstart, lend, k0, l0;
    int prgUlx, prgUly;
    int prgW = (twoppx.toInt()) << ndl;
    int prgH = (twoppy.toInt()) << ndl;

    CBlkCoordInfo cb;

    for (int i = istart; i <= iend; i++) {
      // Vertical precincts
      for (int j = jstart; j <= jend; j++, nPrec++) {
        // Horizontal precincts
        if (j == jstart && (trx0 - cb0x) % (xrsiz * (twoppx.toInt())) != 0) {
          prgUlx = tx0;
        } else {
          prgUlx = cb0x + j * xrsiz * ((twoppx.toInt()) << ndl);
        }
        if (i == istart && (try0 - cb0y) % (yrsiz * (twoppy.toInt())) != 0) {
          prgUly = ty0;
        } else {
          prgUly = cb0y + i * yrsiz * ((twoppy.toInt()) << ndl);
        }

        ppinfo[t][c][r][nPrec] = PrecInfo(
            r,
            (cb0x + j * twoppx).toInt(),
            (cb0y + i * twoppy).toInt(),
            twoppx.toInt(),
            twoppy.toInt(),
            prgUlx,
            prgUly,
            prgW,
            prgH);

        if (r == 0) {
          // LL subband
          acb0x = cb0x;
          acb0y = cb0y;

          p0x = acb0x + j * twoppx.toInt();
          p1x = p0x + twoppx.toInt();
          p0y = acb0y + i * twoppy.toInt();
          p1y = p0y + twoppy.toInt();

          sb = root.getSubbandByIdx(0, 0) as SubbandAn;
          s0x = (p0x < sb.ulcx) ? sb.ulcx : p0x;
          s1x = (p1x > sb.ulcx + sb.w) ? sb.ulcx + sb.w : p1x;
          s0y = (p0y < sb.ulcy) ? sb.ulcy : p0y;
          s1y = (p1y > sb.ulcy + sb.h) ? sb.ulcy + sb.h : p1y;

          // Code-blocks are located at (acb0x+k*cw,acb0y+l*ch)
          cw = sb.nomCBlkW;
          ch = sb.nomCBlkH;
          k0 = ((sb.ulcy - acb0y) / ch).floor();
          kstart = ((s0y - acb0y) / ch).floor();
          kend = ((s1y - 1 - acb0y) / ch).floor();
          l0 = ((sb.ulcx - acb0x) / cw).floor();
          lstart = ((s0x - acb0x) / cw).floor();
          lend = ((s1x - 1 - acb0x) / cw).floor();

          if (s1x - s0x <= 0 || s1y - s0y <= 0) {
            ppinfo[t][c][r][nPrec].nblk[0] = 0;
            ttIncl[t][c][r][nPrec][0] = TagTreeEncoder(0, 0, null);
            ttMaxBP[t][c][r][nPrec][0] = TagTreeEncoder(0, 0, null);
          } else {
            ttIncl[t][c][r][nPrec][0] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ttMaxBP[t][c][r][nPrec][0] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ppinfo[t][c][r][nPrec].cblk[0] = List.generate(
                kend - kstart + 1, (_) => List.filled(lend - lstart + 1, null));
            ppinfo[t][c][r][nPrec].nblk[0] =
                (kend - kstart + 1) * (lend - lstart + 1);

            for (int k = kstart; k <= kend; k++) {
              // Vertical cblks
              for (int l = lstart; l <= lend; l++) {
                // Horiz. cblks
                cb = CBlkCoordInfo.withIndex(k - k0, l - l0);
                ppinfo[t][c][r][nPrec].cblk[0][k - kstart][l - lstart] = cb;
              } // Horizontal code-blocks
            } // Vertical code-blocks
          }
        } else {
          // HL, LH and HH subbands
          // HL subband
          acb0x = 0;
          acb0y = cb0y;

          p0x = acb0x + j * twoppx2;
          p1x = p0x + twoppx2;
          p0y = acb0y + i * twoppy2;
          p1y = p0y + twoppy2;

          sb = root.getSubbandByIdx(r, 1) as SubbandAn;
          s0x = (p0x < sb.ulcx) ? sb.ulcx : p0x;
          s1x = (p1x > sb.ulcx + sb.w) ? sb.ulcx + sb.w : p1x;
          s0y = (p0y < sb.ulcy) ? sb.ulcy : p0y;
          s1y = (p1y > sb.ulcy + sb.h) ? sb.ulcy + sb.h : p1y;

          // Code-blocks are located at (acb0x+k*cw,acb0y+l*ch)
          cw = sb.nomCBlkW;
          ch = sb.nomCBlkH;
          k0 = ((sb.ulcy - acb0y) / ch).floor();
          kstart = ((s0y - acb0y) / ch).floor();
          kend = ((s1y - 1 - acb0y) / ch).floor();
          l0 = ((sb.ulcx - acb0x) / cw).floor();
          lstart = ((s0x - acb0x) / cw).floor();
          lend = ((s1x - 1 - acb0x) / cw).floor();

          if (s1x - s0x <= 0 || s1y - s0y <= 0) {
            ppinfo[t][c][r][nPrec].nblk[1] = 0;
            ttIncl[t][c][r][nPrec][1] = TagTreeEncoder(0, 0, null);
            ttMaxBP[t][c][r][nPrec][1] = TagTreeEncoder(0, 0, null);
          } else {
            ttIncl[t][c][r][nPrec][1] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ttMaxBP[t][c][r][nPrec][1] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ppinfo[t][c][r][nPrec].cblk[1] = List.generate(
                kend - kstart + 1, (_) => List.filled(lend - lstart + 1, null));
            ppinfo[t][c][r][nPrec].nblk[1] =
                (kend - kstart + 1) * (lend - lstart + 1);

            for (int k = kstart; k <= kend; k++) {
              // Vertical cblks
              for (int l = lstart; l <= lend; l++) {
                // Horiz. cblks
                cb = CBlkCoordInfo.withIndex(k - k0, l - l0);
                ppinfo[t][c][r][nPrec].cblk[1][k - kstart][l - lstart] = cb;
              } // Horizontal code-blocks
            } // Vertical code-blocks
          }

          // LH subband
          acb0x = cb0x;
          acb0y = 0;

          p0x = acb0x + j * twoppx2;
          p1x = p0x + twoppx2;
          p0y = acb0y + i * twoppy2;
          p1y = p0y + twoppy2;

          sb = root.getSubbandByIdx(r, 2) as SubbandAn;
          s0x = (p0x < sb.ulcx) ? sb.ulcx : p0x;
          s1x = (p1x > sb.ulcx + sb.w) ? sb.ulcx + sb.w : p1x;
          s0y = (p0y < sb.ulcy) ? sb.ulcy : p0y;
          s1y = (p1y > sb.ulcy + sb.h) ? sb.ulcy + sb.h : p1y;

          // Code-blocks are located at (acb0x+k*cw,acb0y+l*ch)
          cw = sb.nomCBlkW;
          ch = sb.nomCBlkH;
          k0 = ((sb.ulcy - acb0y) / ch).floor();
          kstart = ((s0y - acb0y) / ch).floor();
          kend = ((s1y - 1 - acb0y) / ch).floor();
          l0 = ((sb.ulcx - acb0x) / cw).floor();
          lstart = ((s0x - acb0x) / cw).floor();
          lend = ((s1x - 1 - acb0x) / cw).floor();

          if (s1x - s0x <= 0 || s1y - s0y <= 0) {
            ppinfo[t][c][r][nPrec].nblk[2] = 0;
            ttIncl[t][c][r][nPrec][2] = TagTreeEncoder(0, 0, null);
            ttMaxBP[t][c][r][nPrec][2] = TagTreeEncoder(0, 0, null);
          } else {
            ttIncl[t][c][r][nPrec][2] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ttMaxBP[t][c][r][nPrec][2] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ppinfo[t][c][r][nPrec].cblk[2] = List.generate(
                kend - kstart + 1, (_) => List.filled(lend - lstart + 1, null));
            ppinfo[t][c][r][nPrec].nblk[2] =
                (kend - kstart + 1) * (lend - lstart + 1);

            for (int k = kstart; k <= kend; k++) {
              // Vertical cblks
              for (int l = lstart; l <= lend; l++) {
                // Horiz cblks
                cb = CBlkCoordInfo.withIndex(k - k0, l - l0);
                ppinfo[t][c][r][nPrec].cblk[2][k - kstart][l - lstart] = cb;
              } // Horizontal code-blocks
            } // Vertical code-blocks
          }

          // HH subband
          acb0x = 0;
          acb0y = 0;

          p0x = acb0x + j * twoppx2;
          p1x = p0x + twoppx2;
          p0y = acb0y + i * twoppy2;
          p1y = p0y + twoppy2;

          sb = root.getSubbandByIdx(r, 3) as SubbandAn;
          s0x = (p0x < sb.ulcx) ? sb.ulcx : p0x;
          s1x = (p1x > sb.ulcx + sb.w) ? sb.ulcx + sb.w : p1x;
          s0y = (p0y < sb.ulcy) ? sb.ulcy : p0y;
          s1y = (p1y > sb.ulcy + sb.h) ? sb.ulcy + sb.h : p1y;

          // Code-blocks are located at (acb0x+k*cw,acb0y+l*ch)
          cw = sb.nomCBlkW;
          ch = sb.nomCBlkH;
          k0 = ((sb.ulcy - acb0y) / ch).floor();
          kstart = ((s0y - acb0y) / ch).floor();
          kend = ((s1y - 1 - acb0y) / ch).floor();
          l0 = ((sb.ulcx - acb0x) / cw).floor();
          lstart = ((s0x - acb0x) / cw).floor();
          lend = ((s1x - 1 - acb0x) / cw).floor();

          if (s1x - s0x <= 0 || s1y - s0y <= 0) {
            ppinfo[t][c][r][nPrec].nblk[3] = 0;
            ttIncl[t][c][r][nPrec][3] = TagTreeEncoder(0, 0, null);
            ttMaxBP[t][c][r][nPrec][3] = TagTreeEncoder(0, 0, null);
          } else {
            ttIncl[t][c][r][nPrec][3] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ttMaxBP[t][c][r][nPrec][3] =
                TagTreeEncoder(kend - kstart + 1, lend - lstart + 1, null);
            ppinfo[t][c][r][nPrec].cblk[3] = List.generate(
                kend - kstart + 1, (_) => List.filled(lend - lstart + 1, null));
            ppinfo[t][c][r][nPrec].nblk[3] =
                (kend - kstart + 1) * (lend - lstart + 1);

            for (int k = kstart; k <= kend; k++) {
              // Vertical cblks
              for (int l = lstart; l <= lend; l++) {
                // Horiz cblks
                cb = CBlkCoordInfo.withIndex(k - k0, l - l0);
                ppinfo[t][c][r][nPrec].cblk[3][k - kstart][l - lstart] = cb;
              } // Horizontal code-blocks
            } // Vertical code-blocks
          }
        }
      } // Horizontal precincts
    } // Vertical precincts
  }

  BitOutputBuffer encodePacket(
      int ly,
      int c,
      int r,
      int t,
      List<List<CBlkRateDistStats>> cbs,
      List<List<int>> tIndx,
      BitOutputBuffer? hbuf,
      Uint8List? bbuf,
      int pIdx) {
    int b, i, maxi;
    int thmax;
    int newtp;
    int cblen;
    int prednbits, nbits;
    TagTreeEncoder curTtIncl, curTtMaxBP;
    List<int> curPrevtIdxs;
    List<CBlkRateDistStats> curCbs;
    List<int> curTIndx;
    int minsb = (r == 0) ? 0 : 1;
    int maxsb = (r == 0) ? 1 : 4;
    Coord? cbCoord;
    SubbandAn root = infoSrc.getAnSubbandTree(t, c);
    SubbandAn sb;
    roiInPkt = false;
    roiLen = 0;
    int mend, nend;

    // Checks if a precinct with such an index exists in this resolution
    // level
    if (pIdx >= ppinfo[t][c][r].length) {
      packetWritable = false;
      return hbuf ?? BitOutputBuffer();
    }
    PrecInfo prec = ppinfo[t][c][r][pIdx];

    // First, we check if packet is empty (i.e precinct 'pIdx' has no
    // code-block in any of the subbands)
    bool isPrecVoid = true;

    for (int s = minsb; s < maxsb; s++) {
      if (prec.nblk[s] == 0) {
        // The precinct has no code-block in this subband.
        continue;
      } else {
        // The precinct is not empty in at least one subband ->
        // stop
        isPrecVoid = false;
        break;
      }
    }

    if (isPrecVoid) {
      packetWritable = true;

      if (hbuf == null) {
        hbuf = BitOutputBuffer();
      } else {
        hbuf.reset();
      }
      if (bbuf == null) {
        lbbuf = bbuf = Uint8List(1);
      }
      hbuf.writeBit(0);
      lblen = 0;

      return hbuf;
    }

    if (hbuf == null) {
      hbuf = BitOutputBuffer();
    } else {
      hbuf.reset();
    }

    // Invalidate last body buffer
    lbbuf = null;
    lblen = 0;

    // Signal that packet is present
    hbuf.writeBit(1);

    for (int s = minsb; s < maxsb; s++) {
      // Loop on subbands
      sb = root.getSubbandByIdx(r, s) as SubbandAn;

      // Go directly to next subband if the precinct has no code-block
      // in the current one.
      if (prec.nblk[s] == 0) {
        continue;
      }

      curTtIncl = ttIncl[t][c][r][pIdx][s];
      curTtMaxBP = ttMaxBP[t][c][r][pIdx][s];
      curPrevtIdxs = prevtIdxs[t][c][r][s];
      curCbs = cbs[s];
      curTIndx = tIndx[s];

      // Set tag tree values for code-blocks in this precinct
      mend = prec.cblk[s].length;
      for (int m = 0; m < mend; m++) {
        nend = prec.cblk[s][m].length;
        for (int n = 0; n < nend; n++) {
          cbCoord = prec.cblk[s][m][n]!.idx;
          b = cbCoord.x + cbCoord.y * sb.numCb!.x;

          if (curTIndx[b] > curPrevtIdxs[b] && curPrevtIdxs[b] < 0) {
            // First inclusion
            curTtIncl.setValue(m, n, ly - 1);
          }
          if (ly == 1) {
            // First layer, need to set the skip of MSBP
            curTtMaxBP.setValue(m, n, curCbs[b].skipMSBP);
          }
        }
      }

      // Now encode the information
      for (int m = 0; m < prec.cblk[s].length; m++) {
        // Vertical code-blocks
        for (int n = 0; n < prec.cblk[s][m].length; n++) {
          // Horiz. cblks
          cbCoord = prec.cblk[s][m][n]!.idx;
          b = cbCoord.x + cbCoord.y * sb.numCb!.x;

          // 1) Inclusion information
          if (curTIndx[b] > curPrevtIdxs[b]) {
            // Code-block included in this layer
            if (curPrevtIdxs[b] < 0) {
              // First inclusion
              // Encode layer info
              curTtIncl.encode(m, n, ly, hbuf);

              // 2) Max bitdepth info. Encode value
              thmax = curCbs[b].skipMSBP + 1;
              for (i = 1; i <= thmax; i++) {
                curTtMaxBP.encode(m, n, i, hbuf);
              }

              // Count body size for packet
              lblen += curCbs[b].truncRates[curCbs[b].truncIdxs[curTIndx[b]]];
            } else {
              // Already in previous layer
              // Send "1" bit
              hbuf.writeBit(1);
              // Count body size for packet
              lblen += curCbs[b].truncRates[curCbs[b].truncIdxs[curTIndx[b]]] -
                  curCbs[b].truncRates[curCbs[b].truncIdxs[curPrevtIdxs[b]]];
            }

            // 3) Truncation point information
            if (curPrevtIdxs[b] < 0) {
              newtp = curCbs[b].truncIdxs[curTIndx[b]];
            } else {
              newtp = curCbs[b].truncIdxs[curTIndx[b]] -
                  curCbs[b].truncIdxs[curPrevtIdxs[b]] -
                  1;
            }

            // Mix of switch and if is faster
            switch (newtp) {
              case 0:
                hbuf.writeBit(0); // Send one "0" bit
                break;
              case 1:
                hbuf.writeBits(2, 2); // Send one "1" and one "0"
                break;
              case 2:
              case 3:
              case 4:
                // Send two "1" bits followed by 2 bits
                // representation of newtp-2
                hbuf.writeBits((3 << 2) | (newtp - 2), 4);
                break;
              default:
                if (newtp <= 35) {
                  // Send four "1" bits followed by a five bits
                  // representation of newtp-5
                  hbuf.writeBits((15 << 5) | (newtp - 5), 9);
                } else if (newtp <= 163) {
                  // Send nine "1" bits followed by a seven bits
                  // representation of newtp-36
                  hbuf.writeBits((511 << 7) | (newtp - 36), 16);
                } else {
                  throw Exception("Maximum number of truncation points exceeded");
                }
            }
          } else {
            // Block not included in this layer
            if (curPrevtIdxs[b] >= 0) {
              // Already in previous layer. Send "0" bit
              hbuf.writeBit(0);
            } else {
              // Not in any previous layers
              curTtIncl.encode(m, n, ly, hbuf);
            }
            // Go to the next one.
            continue;
          }

          // Code-block length

          // We need to compute the maximum number of bits needed to
          // signal the length of each terminated segment and the
          // final truncation point.
          newtp = 1;
          maxi = curCbs[b].truncIdxs[curTIndx[b]];
          cblen = (curPrevtIdxs[b] < 0)
              ? 0
              : curCbs[b].truncRates[curCbs[b].truncIdxs[curPrevtIdxs[b]]];

          // Loop on truncation points
          i = (curPrevtIdxs[b] < 0)
              ? 0
              : curCbs[b].truncIdxs[curPrevtIdxs[b]] + 1;
          int minbits = 0;
          for (; i < maxi; i++, newtp++) {
            // If terminated truncation point calculate length
            if (curCbs[b].isTermPass != null && curCbs[b].isTermPass![i]) {
              // Calculate length
              cblen = curCbs[b].truncRates[i] - cblen;

              // Calculate number of needed bits
              prednbits = lblock[t][c][r][s][b] + MathUtil.log2(newtp);
              minbits = ((cblen > 0) ? MathUtil.log2(cblen) : 0) + 1;

              // Update Lblock increment if needed
              for (int j = prednbits; j < minbits; j++) {
                lblock[t][c][r][s][b]++;
                hbuf.writeBit(1);
              }
              // Initialize for next length
              newtp = 0;
              cblen = curCbs[b].truncRates[i];
            }
          }

          // Last truncation point length always sent

          // Calculate length
          cblen = curCbs[b].truncRates[i] - cblen;

          // Calculate number of bits
          prednbits = lblock[t][c][r][s][b] + MathUtil.log2(newtp);
          minbits = ((cblen > 0) ? MathUtil.log2(cblen) : 0) + 1;
          // Update Lblock increment if needed
          for (int j = prednbits; j < minbits; j++) {
            lblock[t][c][r][s][b]++;
            hbuf.writeBit(1);
          }

          // End of comma-code increment
          hbuf.writeBit(0);

          // There can be terminated several segments, send length
          // info for all terminated truncation points in addition
          // to final one
          newtp = 1;
          maxi = curCbs[b].truncIdxs[curTIndx[b]];
          cblen = (curPrevtIdxs[b] < 0)
              ? 0
              : curCbs[b].truncRates[curCbs[b].truncIdxs[curPrevtIdxs[b]]];
          // Loop on truncation points and count the groups
          i = (curPrevtIdxs[b] < 0)
              ? 0
              : curCbs[b].truncIdxs[curPrevtIdxs[b]] + 1;
          for (; i < maxi; i++, newtp++) {
            // If terminated truncation point, send length
            if (curCbs[b].isTermPass != null && curCbs[b].isTermPass![i]) {
              cblen = curCbs[b].truncRates[i] - cblen;
              nbits = MathUtil.log2(newtp) + lblock[t][c][r][s][b];
              hbuf.writeBits(cblen, nbits);

              // Initialize for next length
              newtp = 0;
              cblen = curCbs[b].truncRates[i];
            }
          }
          // Last truncation point length is always signalled
          // First calculate number of bits needed to signal
          // Calculate length
          cblen = curCbs[b].truncRates[i] - cblen;
          nbits = MathUtil.log2(newtp) + lblock[t][c][r][s][b];
          hbuf.writeBits(cblen, nbits);
        } // End loop on horizontal code-blocks
      } // End loop on vertical code-blocks
    } // End loop on subband

    // -> Copy the data to the body buffer

    // Ensure size for body data
    if (bbuf == null || bbuf.length < lblen) {
      bbuf = Uint8List(lblen);
    }
    lbbuf = bbuf;
    lblen = 0;

    for (int s = minsb; s < maxsb; s++) {
      // Loop on subbands
      sb = root.getSubbandByIdx(r, s) as SubbandAn;

      curPrevtIdxs = prevtIdxs[t][c][r][s];
      curCbs = cbs[s];
      curTIndx = tIndx[s];

      mend = prec.cblk[s].length;
      for (int m = 0; m < mend; m++) {
        // Vertical code-blocks
        nend = prec.cblk[s][m].length;
        for (int n = 0; n < nend; n++) {
          // Horiz. cblks
          cbCoord = prec.cblk[s][m][n]!.idx;
          b = cbCoord.x + cbCoord.y * sb.numCb!.x;

          if (curTIndx[b] > curPrevtIdxs[b]) {
            // Block included in this precinct -> Copy data to
            // body buffer and get code-size
            if (curPrevtIdxs[b] < 0) {
              cblen = curCbs[b].truncRates[curCbs[b].truncIdxs[curTIndx[b]]];
              // System.arraycopy(cur_cbs[b].data,0, lbbuf,lblen,cblen);
              lbbuf!.setRange(lblen, lblen + cblen, curCbs[b].data!, 0);
            } else {
              cblen = curCbs[b].truncRates[curCbs[b].truncIdxs[curTIndx[b]]] -
                  curCbs[b].truncRates[curCbs[b].truncIdxs[curPrevtIdxs[b]]];
              // System.arraycopy(cur_cbs[b].data, cur_cbs[b].truncRates[cur_cbs[b].truncIdxs[cur_prevtIdxs[b]]], lbbuf,lblen,cblen);
              int srcPos = curCbs[b]
                  .truncRates[curCbs[b].truncIdxs[curPrevtIdxs[b]]];
              lbbuf!.setRange(lblen, lblen + cblen, curCbs[b].data!, srcPos);
            }
            lblen += cblen;

            // Verifies if this code-block contains new ROI
            // information
            if (curCbs[b].nROIcoeff != 0 &&
                (curPrevtIdxs[b] == -1 ||
                    curCbs[b].truncIdxs[curPrevtIdxs[b]] <=
                        curCbs[b].nROIcp - 1)) {
              roiInPkt = true;
              roiLen = lblen;
            }

            // Update truncation point
            curPrevtIdxs[b] = curTIndx[b];
          }
        } // End loop on horizontal code-blocks
      } // End loop on vertical code-blocks
    } // End loop on subbands

    packetWritable = true;

    // Must never happen
    if (hbuf.getLength() == 0) {
      throw Error();
    }

    return hbuf;
  }

  /// Returns the buffer of the body of the last encoded packet. The length
  /// of the body can be retrieved with the getLastBodyLen() method. The
  /// length of the array returned by this method may be larger than the
  /// actual body length.
  Uint8List getLastBodyBuf() {
    if (lbbuf == null) {
      throw ArgumentError();
    }
    return lbbuf!;
  }

  /// Returns the length of the body of the last encoded packet, in
  /// bytes. The body itself can be retrieved with the getLastBodyBuf()
  /// method.
  int getLastBodyLen() {
    return lblen;
  }

  /// Saves the current state of this object. The last saved state
  /// can be restored with the restore() method.
  void save() {
    int maxsbi, minsbi;

    // Have we done any save yet?
    if (bakLblock == null) {
      // Allocate backup buffers
      bakLblock = List.generate(ttIncl.length, (_) => []);
      bakPrevtIdxs = List.generate(ttIncl.length, (_) => []);
      for (int t = ttIncl.length - 1; t >= 0; t--) {
        bakLblock![t] = List.generate(ttIncl[t].length, (_) => []);
        bakPrevtIdxs![t] = List.generate(ttIncl[t].length, (_) => []);
        for (int c = ttIncl[t].length - 1; c >= 0; c--) {
          bakLblock![t][c] = List.generate(lblock[t][c].length, (_) => []);
          bakPrevtIdxs![t][c] = List.generate(prevtIdxs[t][c].length, (_) => []);
          for (int r = lblock[t][c].length - 1; r >= 0; r--) {
            bakLblock![t][c][r] = List.generate(lblock[t][c][r].length, (_) => []);
            bakPrevtIdxs![t][c][r] = List.generate(prevtIdxs[t][c][r].length, (_) => []);
            minsbi = (r == 0) ? 0 : 1;
            maxsbi = (r == 0) ? 1 : 4;
            for (int s = minsbi; s < maxsbi; s++) {
              bakLblock![t][c][r][s] = List.filled(lblock[t][c][r][s].length, 0);
              bakPrevtIdxs![t][c][r][s] = List.filled(prevtIdxs[t][c][r][s].length, 0);
            }
          }
        }
      }
    }

    //-- Save the data

    // Loop on tiles
    for (int t = ttIncl.length - 1; t >= 0; t--) {
      // Loop on components
      for (int c = ttIncl[t].length - 1; c >= 0; c--) {
        // Loop on resolution levels
        for (int r = lblock[t][c].length - 1; r >= 0; r--) {
          // Loop on subbands
          minsbi = (r == 0) ? 0 : 1;
          maxsbi = (r == 0) ? 1 : 4;
          for (int s = minsbi; s < maxsbi; s++) {
            // Save 'lblock'
            List.copyRange(bakLblock![t][c][r][s], 0, lblock[t][c][r][s]);
            // Save 'prevtIdxs'
            List.copyRange(bakPrevtIdxs![t][c][r][s], 0, prevtIdxs[t][c][r][s]);
          } // End loop on subbands

          // Loop on precincts
          for (int p = ppinfo[t][c][r].length - 1; p >= 0; p--) {
            if (p < ttIncl[t][c][r].length) {
              // Loop on subbands
              for (int s = minsbi; s < maxsbi; s++) {
                ttIncl[t][c][r][p][s].save();
                ttMaxBP[t][c][r][p][s].save();
              } // End loop on subbands
            }
          } // End loop on precincts
        } // End loop on resolutions
      } // End loop on components
    } // End loop on tiles

    // Set the saved state
    saved = true;
  }

  /// Restores the last saved state of this object. An
  /// IllegalArgumentException is thrown if no state has been saved.
  void restore() {
    int maxsbi, minsbi;

    if (!saved) {
      throw ArgumentError();
    }

    // Invalidate last encoded body buffer
    lbbuf = null;

    //-- Restore tha data

    // Loop on tiles
    for (int t = ttIncl.length - 1; t >= 0; t--) {
      // Loop on components
      for (int c = ttIncl[t].length - 1; c >= 0; c--) {
        // Loop on resolution levels
        for (int r = lblock[t][c].length - 1; r >= 0; r--) {
          // Loop on subbands
          minsbi = (r == 0) ? 0 : 1;
          maxsbi = (r == 0) ? 1 : 4;
          for (int s = minsbi; s < maxsbi; s++) {
            // Restore 'lblock'
            List.copyRange(lblock[t][c][r][s], 0, bakLblock![t][c][r][s]);
            // Restore 'prevtIdxs'
            List.copyRange(prevtIdxs[t][c][r][s], 0, bakPrevtIdxs![t][c][r][s]);
          } // End loop on subbands

          // Loop on precincts
          for (int p = ppinfo[t][c][r].length - 1; p >= 0; p--) {
            if (p < ttIncl[t][c][r].length) {
              // Loop on subbands
              for (int s = minsbi; s < maxsbi; s++) {
                ttIncl[t][c][r][p][s].restore();
                ttMaxBP[t][c][r][p][s].restore();
              } // End loop on subbands
            }
          } // End loop on precincts
        } // End loop on resolution levels
      } // End loop on components
    } // End loop on tiles
  }

  /// Resets the state of the object to the initial state, as if the object
  /// was just created.
  void reset() {
    int maxsbi, minsbi;

    // Invalidate save
    saved = false;
    // Invalidate last encoded body buffer
    lbbuf = null;

    // Reinitialize each element in the arrays

    // Loop on tiles
    for (int t = ttIncl.length - 1; t >= 0; t--) {
      // Loop on components
      for (int c = ttIncl[t].length - 1; c >= 0; c--) {
        // Loop on resolution levels
        for (int r = lblock[t][c].length - 1; r >= 0; r--) {
          // Loop on subbands
          minsbi = (r == 0) ? 0 : 1;
          maxsbi = (r == 0) ? 1 : 4;
          for (int s = minsbi; s < maxsbi; s++) {
            // Reset 'prevtIdxs'
            ArrayUtil.intArraySet(prevtIdxs[t][c][r][s], -1);
            // Reset 'lblock'
            ArrayUtil.intArraySet(lblock[t][c][r][s], initLblock);
          } // End loop on subbands

          // Loop on precincts
          for (int p = ppinfo[t][c][r].length - 1; p >= 0; p--) {
            if (p < ttIncl[t][c][r].length) {
              // Loop on subbands
              for (int s = minsbi; s < maxsbi; s++) {
                ttIncl[t][c][r][p][s].reset();
                ttMaxBP[t][c][r][p][s].reset();
              } // End loop on subbands
            }
          } // End loop on precincts
        } // End loop on resolution levels
      } // End loop on components
    } // End loop on tiles
  }

  /// Returns true if the current packet is writable i.e. should be written.
  /// Returns false otherwise.
  bool isPacketWritable() {
    return packetWritable;
  }

  /// Tells if there was ROI information in the last written packet
  bool isROIinPkt() {
    return roiInPkt;
  }

  /// Gives the length to read in current packet body to get all ROI
  /// information
  int getROILen() {
    return roiLen;
  }

  /// Returns the parameters that are used in this class and implementing
  /// classes. It returns a 2D String array. Each of the 1D arrays is for a
  /// different option, and they have 3 elements. The first element is the
  /// option name, the second one is the synopsis, the third one is a long
  /// description of what the parameter is and the fourth is its default
  /// value. The synopsis or description may be 'null', in which case it is
  /// assumed that there is no synopsis or description of the option,
  /// respectively. Null may be returned if no options are supported.
  static List<List<String>> getParameterInfo() {
    return pinfo;
  }

  /// Returns information about a given precinct
  ///
  /// [t] Tile index.
  ///
  /// [c] Component index.
  ///
  /// [r] Resolution level index.
  ///
  /// [p] Precinct index
  PrecInfo getPrecInfo(int t, int c, int r, int p) {
    return ppinfo[t][c][r][p];
  }
}



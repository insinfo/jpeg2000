import 'dart:typed_data';

import '../../encoder/EncoderSpecs.dart';
import '../../util/MathUtil.dart';
import '../../wavelet/analysis/AnWTFilterSpec.dart';
import '../BlkImgDataSrc.dart';
import '../DataBlk.dart';
import '../DataBlkFloat.dart';
import '../DataBlkInt.dart';
import '../ImgDataAdapter.dart';
import '../invcomptransf/InvCompTransf.dart';
import 'ForwCompTransfSpec.dart';

/// This class applies the forward component transformation (RCT or ICT) to
/// the image data before the wavelet transform. It mirrors JJ2000's
/// `ForwCompTransf` class.
///
/// Component transformations improve compression efficiency; they are not
/// related to colour transforms used for display purposes. JPEG 2000 part I
/// defines two: RCT (Reversible Component Transformation) and ICT
/// (Irreversible Component Transformation).
class ForwCompTransf extends ImgDataAdapter implements BlkImgDataSrc {
  /// Identifier for no component transformation. Value is 0.
  static const int NONE = 0;

  /// Identifier for the Forward Reversible Component Transformation. Value 1.
  static const int FORW_RCT = 1;

  /// Identifier for the Forward Irreversible Component Transformation.
  /// Value 2.
  static const int FORW_ICT = 2;

  /// The prefix for component transformation type: 'M'
  static const String OPT_PREFIX = 'M';

  /// The list of parameters that is accepted by the forward component
  /// transformation module. Options start with an 'M'.
  static const List<List<String?>> pinfo = [
    [
      "Mct",
      "[<tile index>] [true|false] ...",
      "Specifies to use component transformation with some tiles. "
          " If the wavelet transform is reversible (w5x3 filter), the "
          "Reversible Component Transformation (RCT) is applied. If not "
          "(w9x7 filter), the Irreversible Component Transformation (ICT)"
          " is used.",
      null
    ],
  ];

  /// The source of image data
  final BlkImgDataSrc src;

  /// The component transformations specifications
  final ForwCompTransfSpec cts;

  /// The wavelet filter specifications
  final AnWTFilterSpec wfs;

  /// The type of the current component transformation. JPEG 2000 part I
  /// only supports NONE, FORW_RCT and FORW_ICT types.
  int transfType = NONE;

  /// The bit-depths of the transformed components
  List<int>? tdepth;

  /// Output block used instead of the one provided as an argument if the
  /// latter is of the wrong type.
  DataBlk? outBlk;

  /// Block used to request component with index 0
  DataBlkInt? block0;

  /// Block used to request component with index 1
  DataBlkInt? block1;

  /// Block used to request component with index 2
  DataBlkInt? block2;

  /// Constructs a new ForwCompTransf object that operates on the specified
  /// source of image data. Mirrors the original JJ2000 constructor that
  /// reads `cts` and `wfs` from the encoder specifications.
  ForwCompTransf(BlkImgDataSrc imgSrc, EncoderSpecs encSpec)
      : src = imgSrc,
        cts = encSpec.cts,
        wfs = encSpec.wfs,
        super(imgSrc);

  static List<List<String?>> getParameterInfo() => pinfo;

  /// Returns the position of the fixed point in the specified component.
  /// The color transform does not affect it.
  @override
  int getFixedPoint(int c) => src.getFixedPoint(c);

  /// Calculates the bitdepths of the transformed components, given the
  /// bitdepth of the un-transformed components and the component
  /// transformation type.
  static List<int> calcMixedBitDepths(
      List<int> ntdepth, int ttype, List<int>? tdepth) {
    if (ntdepth.length < 3 && ttype != NONE) {
      throw ArgumentError();
    }

    tdepth ??= List<int>.filled(ntdepth.length, 0);

    switch (ttype) {
      case NONE:
        for (var i = 0; i < ntdepth.length; i++) {
          tdepth[i] = ntdepth[i];
        }
        break;
      case FORW_RCT:
        if (ntdepth.length > 3) {
          for (var i = 3; i < ntdepth.length; i++) {
            tdepth[i] = ntdepth[i];
          }
        }
        // The MathUtil.log2(x) function calculates floor(log2(x)), so we
        // use 'MathUtil.log2(2*x-1)+1', which calculates ceil(log2(x))
        // for any x>=1, x integer.
        tdepth[0] = MathUtil.log2(
                (1 << ntdepth[0]) + (2 << ntdepth[1]) + (1 << ntdepth[2]) - 1) -
            2 +
            1;
        tdepth[1] =
            MathUtil.log2((1 << ntdepth[2]) + (1 << ntdepth[1]) - 1) + 1;
        tdepth[2] =
            MathUtil.log2((1 << ntdepth[0]) + (1 << ntdepth[1]) - 1) + 1;
        break;
      case FORW_ICT:
        if (ntdepth.length > 3) {
          for (var i = 3; i < ntdepth.length; i++) {
            tdepth[i] = ntdepth[i];
          }
        }
        tdepth[0] = MathUtil.log2(((1 << ntdepth[0]) * 0.299072 +
                        (1 << ntdepth[1]) * 0.586914 +
                        (1 << ntdepth[2]) * 0.114014)
                    .floor() -
                1) +
            1;
        tdepth[1] = MathUtil.log2(((1 << ntdepth[0]) * 0.168701 +
                        (1 << ntdepth[1]) * 0.331299 +
                        (1 << ntdepth[2]) * 0.5)
                    .floor() -
                1) +
            1;
        tdepth[2] = MathUtil.log2(((1 << ntdepth[0]) * 0.5 +
                        (1 << ntdepth[1]) * 0.418701 +
                        (1 << ntdepth[2]) * 0.081299)
                    .floor() -
                1) +
            1;
        break;
    }

    return tdepth;
  }

  /// Initializes variables used with RCT. Must be called, at least, at the
  /// beginning of each new tile.
  void _initForwRCT() {
    final tileIndex = getTileIdx();

    if (src.getNumComps() < 3) {
      throw ArgumentError();
    }
    // Check that the 3 components have the same dimensions
    if (src.getTileCompWidth(tileIndex, 0) !=
            src.getTileCompWidth(tileIndex, 1) ||
        src.getTileCompWidth(tileIndex, 0) !=
            src.getTileCompWidth(tileIndex, 2) ||
        src.getTileCompHeight(tileIndex, 0) !=
            src.getTileCompHeight(tileIndex, 1) ||
        src.getTileCompHeight(tileIndex, 0) !=
            src.getTileCompHeight(tileIndex, 2)) {
      throw ArgumentError(
          'Can not use RCT on components with different dimensions');
    }
    // Initialize bitdepths
    final utd = List<int>.generate(src.getNumComps(), src.getNomRangeBits,
        growable: false);
    tdepth = calcMixedBitDepths(utd, FORW_RCT, null);
  }

  /// Initializes variables used with ICT. Must be called, at least, at the
  /// beginning of each new tile.
  void _initForwICT() {
    final tileIndex = getTileIdx();

    if (src.getNumComps() < 3) {
      throw ArgumentError();
    }
    // Check that the 3 components have the same dimensions
    if (src.getTileCompWidth(tileIndex, 0) !=
            src.getTileCompWidth(tileIndex, 1) ||
        src.getTileCompWidth(tileIndex, 0) !=
            src.getTileCompWidth(tileIndex, 2) ||
        src.getTileCompHeight(tileIndex, 0) !=
            src.getTileCompHeight(tileIndex, 1) ||
        src.getTileCompHeight(tileIndex, 0) !=
            src.getTileCompHeight(tileIndex, 2)) {
      throw ArgumentError(
          'Can not use ICT on components with different dimensions');
    }
    // Initialize bitdepths
    final utd = List<int>.generate(src.getNumComps(), src.getNomRangeBits,
        growable: false);
    tdepth = calcMixedBitDepths(utd, FORW_ICT, null);
  }

  @override
  String toString() {
    switch (transfType) {
      case FORW_RCT:
        return 'Forward RCT';
      case FORW_ICT:
        return 'Forward ICT';
      case NONE:
        return 'No component transformation';
      default:
        throw ArgumentError('Non JPEG 2000 part I component transformation');
    }
  }

  /// Returns the number of "range bits" of the data in the specified
  /// component and current tile, after mixing.
  @override
  int getNomRangeBits(int c) {
    switch (transfType) {
      case FORW_RCT:
      case FORW_ICT:
        return tdepth![c];
      case NONE:
        return src.getNomRangeBits(c);
      default:
        throw ArgumentError('Non JPEG 2000 part I component transformation');
    }
  }

  /// Returns true if this transform is reversible in the current tile.
  bool isReversible() {
    switch (transfType) {
      case NONE:
      case FORW_RCT:
        return true;
      case FORW_ICT:
        return false;
      default:
        throw ArgumentError('Non JPEG 2000 part I component transformation');
    }
  }

  @override
  DataBlk getCompData(DataBlk blk, int c) {
    // If requesting a component whose index is greater than 3 or there is
    // no transform return a copy of data (getInternCompData returns the
    // actual data in those cases)
    if (c >= 3 || transfType == NONE) {
      return src.getCompData(blk, c);
    }
    // We can use getInternCompData (since data is a copy anyways)
    return getInternCompData(blk, c);
  }

  @override
  DataBlk getInternCompData(DataBlk blk, int c) {
    switch (transfType) {
      case NONE:
        return src.getInternCompData(blk, c);
      case FORW_RCT:
        return _forwRCT(blk, c);
      case FORW_ICT:
        return _forwICT(blk, c);
      default:
        throw ArgumentError(
            'Non JPEG 2000 part I component transformation for tile: $tileIndex');
    }
  }

  /// Applies the forward reversible component transformation. Whatever the
  /// type of requested DataBlk, it always returns a DataBlkInt.
  DataBlk _forwRCT(DataBlk blk, int c) {
    final w = blk.w;
    final h = blk.h;

    if (c >= 0 && c <= 2) {
      // Check that requested data type is int
      if (blk.getDataType() != DataBlk.typeInt) {
        if (outBlk == null || outBlk!.getDataType() != DataBlk.typeInt) {
          outBlk = DataBlkInt();
        }
        outBlk!
          ..w = w
          ..h = h
          ..ulx = blk.ulx
          ..uly = blk.uly;
        blk = outBlk!;
      }

      // Reference to output block data array
      var outdata = blk.getData() as List<int>?;

      // Create data array of blk if necessary
      if (outdata == null || outdata.length < h * w) {
        outdata = Int32List(h * w);
        blk.setData(outdata);
      }

      block0 ??= DataBlkInt();
      block1 ??= DataBlkInt();
      block2 ??= DataBlkInt();
      block0!.w = block1!.w = block2!.w = blk.w;
      block0!.h = block1!.h = block2!.h = blk.h;
      block0!.ulx = block1!.ulx = block2!.ulx = blk.ulx;
      block0!.uly = block1!.uly = block2!.uly = blk.uly;

      // Fill in buffer blocks (to be read only)
      // Returned blocks may have different size and position
      block0 = src.getInternCompData(block0!, 0) as DataBlkInt;
      final data0 = block0!.getData() as List<int>;
      block1 = src.getInternCompData(block1!, 1) as DataBlkInt;
      final data1 = block1!.getData() as List<int>;
      block2 = src.getInternCompData(block2!, 2) as DataBlkInt;
      final bdata = block2!.getData() as List<int>;

      // Set the progressiveness of the output data
      blk.progressive =
          block0!.progressive || block1!.progressive || block2!.progressive;
      blk.offset = 0;
      blk.scanw = w;

      // Perform conversion

      // Initialize general indexes
      var k = w * h - 1;
      var k0 = block0!.offset + (h - 1) * block0!.scanw + w - 1;
      var k1 = block1!.offset + (h - 1) * block1!.scanw + w - 1;
      var k2 = block2!.offset + (h - 1) * block2!.scanw + w - 1;

      switch (c) {
        case 0: // RGB to Yr conversion
          for (var i = h - 1; i >= 0; i--) {
            for (var mink = k - w; k > mink; k--, k0--, k1--, k2--) {
              outdata[k] = (data0[k0] + 2 * data1[k1] + bdata[k2]) >> 2;
            }
            // Jump to beginning of previous line in input
            k0 -= block0!.scanw - w;
            k1 -= block1!.scanw - w;
            k2 -= block2!.scanw - w;
          }
          break;

        case 1: // RGB to Ur conversion
          for (var i = h - 1; i >= 0; i--) {
            for (var mink = k - w; k > mink; k--, k1--, k2--) {
              outdata[k] = bdata[k2] - data1[k1];
            }
            k1 -= block1!.scanw - w;
            k2 -= block2!.scanw - w;
          }
          break;

        case 2: // RGB to Vr conversion
          for (var i = h - 1; i >= 0; i--) {
            for (var mink = k - w; k > mink; k--, k0--, k1--) {
              outdata[k] = data0[k0] - data1[k1];
            }
            k0 -= block0!.scanw - w;
            k1 -= block1!.scanw - w;
          }
          break;
      }
    } else if (c >= 3) {
      // Requesting a component which is not Y, Ur or Vr => just pass the data
      return src.getInternCompData(blk, c);
    } else {
      // Requesting a non valid component index
      throw ArgumentError();
    }
    return blk;
  }

  /// Applies the forward irreversible component transformation. Whatever the
  /// type of requested DataBlk, it always returns a DataBlkFloat.
  DataBlk _forwICT(DataBlk blk, int c) {
    final w = blk.w;
    final h = blk.h;

    if (blk.getDataType() != DataBlk.typeFloat) {
      if (outBlk == null || outBlk!.getDataType() != DataBlk.typeFloat) {
        outBlk = DataBlkFloat();
      }
      outBlk!
        ..w = w
        ..h = h
        ..ulx = blk.ulx
        ..uly = blk.uly;
      blk = outBlk!;
    }

    // Reference to output block data array
    var outdata = blk.getData() as Float32List?;

    // Create data array of blk if necessary
    if (outdata == null || outdata.length < w * h) {
      outdata = Float32List(h * w);
      blk.setData(outdata);
    }

    if (c >= 0 && c <= 2) {
      block0 ??= DataBlkInt();
      block1 ??= DataBlkInt();
      block2 ??= DataBlkInt();
      block0!.w = block1!.w = block2!.w = blk.w;
      block0!.h = block1!.h = block2!.h = blk.h;
      block0!.ulx = block1!.ulx = block2!.ulx = blk.ulx;
      block0!.uly = block1!.uly = block2!.uly = blk.uly;

      // Returned blocks may have different size and position
      block0 = src.getInternCompData(block0!, 0) as DataBlkInt;
      final data0 = block0!.getData() as List<int>;
      block1 = src.getInternCompData(block1!, 1) as DataBlkInt;
      final data1 = block1!.getData() as List<int>;
      block2 = src.getInternCompData(block2!, 2) as DataBlkInt;
      final data2 = block2!.getData() as List<int>;

      // Set the progressiveness of the output data
      blk.progressive =
          block0!.progressive || block1!.progressive || block2!.progressive;
      blk.offset = 0;
      blk.scanw = w;

      // Perform conversion

      // Initialize general indexes
      var k = w * h - 1;
      var k0 = block0!.offset + (h - 1) * block0!.scanw + w - 1;
      var k1 = block1!.offset + (h - 1) * block1!.scanw + w - 1;
      var k2 = block2!.offset + (h - 1) * block2!.scanw + w - 1;

      switch (c) {
        case 0: // RGB to Y conversion
          for (var i = h - 1; i >= 0; i--) {
            for (var mink = k - w; k > mink; k--, k0--, k1--, k2--) {
              outdata[k] =
                  0.299 * data0[k0] + 0.587 * data1[k1] + 0.114 * data2[k2];
            }
            k0 -= block0!.scanw - w;
            k1 -= block1!.scanw - w;
            k2 -= block2!.scanw - w;
          }
          break;

        case 1: // RGB to Cb conversion
          for (var i = h - 1; i >= 0; i--) {
            for (var mink = k - w; k > mink; k--, k0--, k1--, k2--) {
              outdata[k] =
                  -0.16875 * data0[k0] - 0.33126 * data1[k1] + 0.5 * data2[k2];
            }
            k0 -= block0!.scanw - w;
            k1 -= block1!.scanw - w;
            k2 -= block2!.scanw - w;
          }
          break;

        case 2: // RGB to Cr conversion
          for (var i = h - 1; i >= 0; i--) {
            for (var mink = k - w; k > mink; k--, k0--, k1--, k2--) {
              outdata[k] =
                  0.5 * data0[k0] - 0.41869 * data1[k1] - 0.08131 * data2[k2];
            }
            k0 -= block0!.scanw - w;
            k1 -= block1!.scanw - w;
            k2 -= block2!.scanw - w;
          }
          break;
      }
    } else if (c >= 3) {
      // Requesting a component which is not Y, Cb or Cr => just pass the
      // data, converting from int to float.
      final indb = DataBlkInt.withGeometry(blk.ulx, blk.uly, w, h);
      src.getInternCompData(indb, c);
      final indata = indb.getData() as List<int>;

      var k = w * h - 1;
      var k0 = indb.offset + (h - 1) * indb.scanw + w - 1;
      for (var i = h - 1; i >= 0; i--) {
        for (var mink = k - w; k > mink; k--, k0--) {
          outdata[k] = indata[k0].toDouble();
        }
        k0 += indb.w - w;
      }

      blk.progressive = indb.progressive;
      blk.offset = 0;
      blk.scanw = w;
      return blk;
    } else {
      // Requesting a non valid component index
      throw ArgumentError();
    }
    return blk;
  }

  void _initTileTransform() {
    // The Dart ForwCompTransfSpec stores the component transformation as the
    // InvCompTransf integer constants rather than the Java strings
    // ("none"/"rct"/"ict").
    final def = cts.getTileDef(tileIndex);
    if (def == InvCompTransf.none) {
      transfType = NONE;
    } else if (def == InvCompTransf.invRct) {
      transfType = FORW_RCT;
      _initForwRCT();
    } else if (def == InvCompTransf.invIct) {
      transfType = FORW_ICT;
      _initForwICT();
    } else {
      throw ArgumentError('Component transformation not recognized');
    }
  }

  @override
  void setTile(int x, int y) {
    src.setTile(x, y);
    tileIndex = getTileIdx(); // index of the current tile
    _initTileTransform();
  }

  @override
  void nextTile() {
    src.nextTile();
    tileIndex = getTileIdx(); // index of the current tile
    _initTileTransform();
  }
}

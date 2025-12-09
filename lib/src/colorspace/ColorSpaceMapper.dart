import 'dart:typed_data';

import '../icc/ICCProfiler.dart';
import '../j2k/image/BlkImgDataSrc.dart';
import '../j2k/image/DataBlk.dart';
import '../j2k/image/DataBlkFloat.dart';
import '../j2k/image/DataBlkInt.dart';
import '../j2k/image/ImgDataAdapter.dart';
import '../j2k/util/ParameterList.dart';
import 'ColorSpace.dart';
import 'ColorSpaceException.dart';
import 'EnumeratedColorSpaceMapper.dart';
import 'PalettizedColorSpaceMapper.dart';
import 'SYccColorSpaceMapper.dart';

abstract class ColorSpaceMapper extends ImgDataAdapter
    implements BlkImgDataSrc {
  /** The prefix for ICC Profiler options */
  static const String OPT_PREFIX = 'I';

  /** Platform dependant end of line String. */
  static const String eol = '\n';

  // Temporary data buffers needed during profiling.
  List<DataBlkInt?> inInt = []; // Integer input data.
  List<DataBlkFloat?> inFloat = []; // Floating point input data.
  List<DataBlkInt?> workInt = []; // Input data shifted to zero-offset
  List<DataBlkFloat?> workFloat = []; // Input data shifted to zero-offset.
  List<List<int>?> dataInt = []; // Points to input data.
  List<List<double>?> dataFloat = []; // Points to input data.
  List<List<double>?> workDataFloat = []; // References working data pixels.
  List<List<int>?> workDataInt = []; // References working data pixels.

  /* input data parameters by component */
  List<int>? shiftValueArray;
  List<int>? maxValueArray;
  List<int>? fixedPtBitsArray;

  /** The list of parameters that are accepted for ICC profiling.*/
  static const List<List<String?>> pinfo = [
    ["IcolorSpacedebug", null, "Print debugging messages during colorspace mapping.", "off"]
  ];

  /** Parameter Specs */
  ParameterList? pl;

  /** ColorSpace info */
  ColorSpace? csMap;

  /** Number of image components */
  int ncomps = 0;

  /** The image source. */
  BlkImgDataSrc? src;

  /** The image source data per component. */
  List<DataBlk?>? srcBlk;

  ComputedComponents computed = ComputedComponents();

  /**
     * Returns the parameters that are used in this class and implementing
     * classes.
     */
  static List<List<String?>> getParameterInfo() {
    return pinfo;
  }

  /**
     * Arrange for the input DataBlk to receive an
     * appropriately sized and typed data buffer
     *   @param db input DataBlk
     */
  static void setInternalBuffer(DataBlk db) {
    switch (db.getDataType()) {
      case DataBlk.typeInt:
        final existingInt = db.getData();
        if (existingInt is Int32List && existingInt.length >= db.w * db.h) {
          return;
        }
        db.setData(Int32List(db.w * db.h));
        break;

      case DataBlk.typeFloat:
        final existingFloat = db.getData();
        if (existingFloat is Float32List && existingFloat.length >= db.w * db.h) {
          return;
        }
        db.setData(Float32List(db.w * db.h));
        break;

      default:
        throw ArgumentError("Invalid output datablock type");
    }
  }

  /**
     * Copy the DataBlk geometry from source to target
     * DataBlk and assure that the target has an appropriate
     * data buffer.
     *   @param tgt has its geometry set.
     *   @param src used to get the new geometric parameters.
     */
  static void copyGeometry(DataBlk tgt, DataBlk src) {
    tgt.offset = 0;
    tgt.h = src.h;
    tgt.w = src.w;
    tgt.ulx = src.ulx;
    tgt.uly = src.uly;
    tgt.scanw = src.w;

    // Create data array if necessary
    setInternalBuffer(tgt);
  }

  /**
     * Factory method for creating instances of this class.
     *   @param src -- source of image data
     *   @param csMap -- provides colorspace info
     * @return ColorSpaceMapper instance
     * @exception IOException profile access exception
     */
  static BlkImgDataSrc? createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    csMap.pl.checkListSingle(
        OPT_PREFIX.codeUnitAt(0), ParameterList.toNameArray(pinfo));

    if (csMap.isPalettized()) {
      return PalettizedColorSpaceMapper.createInstance(src, csMap);
    }

    if (csMap.getMethod() == ColorSpace.ICC_PROFILED) {
      return ICCProfiler.createInstance(src, csMap);
    }

    final colorspace = csMap.getColorSpace();
    if (colorspace == ColorSpace.sRGB || colorspace == ColorSpace.GreyScale) {
      return EnumeratedColorSpaceMapper.createInstance(src, csMap);
    }
    if (colorspace == ColorSpace.sYCC) {
      return SYccColorSpaceMapper.createInstance(src, csMap);
    }
    if (colorspace == ColorSpace.Unknown) {
      return null;
    }
    throw ColorSpaceException('Bad color space specification in image');
  }

  /**
     * Ctor which creates an ICCProfile for the image and initializes
     * all data objects (input, working, and output).
     *
     *   @param src -- Source of image data
     *   @param csm -- provides colorspace info
     *
     */
  ColorSpaceMapper(BlkImgDataSrc src, ColorSpace csMap) : super(src) {
    this.src = src;
    this.csMap = csMap;
    initialize();
  }

  /** General utility used by ctors */
  void initialize() {
    this.pl = csMap!.pl;
    this.ncomps = src!.getNumComps();

    shiftValueArray = List.filled(ncomps, 0);
    maxValueArray = List.filled(ncomps, 0);
    fixedPtBitsArray = List.filled(ncomps, 0);

    srcBlk = List.filled(ncomps, null);
    inInt = List.filled(ncomps, null);
    inFloat = List.filled(ncomps, null);
    workInt = List.filled(ncomps, null);
    workFloat = List.filled(ncomps, null);
    dataInt = List.filled(ncomps, null);
    dataFloat = List.filled(ncomps, null);
    workDataInt = List.filled(ncomps, null);
    workDataFloat = List.filled(ncomps, null);

    /* For each component, get a reference to the pixel data and
         * set up working DataBlks for both integer and float output.
         */
    for (int i = 0; i < ncomps; ++i) {
      shiftValueArray![i] = 1 << (src!.getNomRangeBits(i) - 1);
      maxValueArray![i] = (1 << src!.getNomRangeBits(i)) - 1;
      fixedPtBitsArray![i] = src!.getFixedPoint(i);

      inInt[i] = DataBlkInt();
      inFloat[i] = DataBlkFloat();
      workInt[i] = DataBlkInt();
      workInt[i]!.progressive = inInt[i]!.progressive;
      workFloat[i] = DataBlkFloat();
      workFloat[i]!.progressive = inFloat[i]!.progressive;
    }
  }

  @override
  int getFixedPoint(int c) {
    return src!.getFixedPoint(c);
  }

  @override
  DataBlk getCompData(DataBlk out, int c) {
    return src!.getCompData(out, c);
  }

  @override
  DataBlk getInternCompData(DataBlk out, int c) {
    return src!.getInternCompData(out, c);
  }
}

class ComputedComponents {
  int tIdx = -1;
  int h = -1;
  int w = -1;
  int ulx = -1;
  int uly = -1;
  int offset = -1;
  int scanw = -1;

  ComputedComponents() {
    clear();
  }

  ComputedComponents.fromDataBlk(DataBlk db) {
    set(db);
  }

  void set(DataBlk db) {
    h = db.h;
    w = db.w;
    ulx = db.ulx;
    uly = db.uly;
    offset = db.offset;
    scanw = db.scanw;
  }

  void clear() {
    h = w = ulx = uly = offset = scanw = -1;
  }

  bool equals(ComputedComponents cc) {
    return (h == cc.h &&
        w == cc.w &&
        ulx == cc.ulx &&
        uly == cc.uly &&
        offset == cc.offset &&
        scanw == cc.scanw);
  }
}


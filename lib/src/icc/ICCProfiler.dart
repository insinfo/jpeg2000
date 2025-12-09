import '../colorspace/ColorSpaceMapper.dart';
import '../j2k/image/BlkImgDataSrc.dart';
import '../colorspace/ColorSpace.dart';
import 'RestrictedICCProfile.dart';
import 'ICCProfile.dart';
import '../j2k/image/DataBlkInt.dart';
import '../j2k/image/DataBlkFloat.dart';
import '../j2k/image/DataBlk.dart';
import 'ICCMonochromeInputProfile.dart';
import 'ICCMatrixBasedInputProfile.dart';
import 'lut/MonochromeTransformTosRGB.dart';
import 'lut/MatrixBasedTransformTosRGB.dart';
import 'lut/MatrixBasedTransformException.dart';
import 'lut/MonochromeTransformException.dart';
import '../j2k/util/FacilityManager.dart';
import '../j2k/util/MsgLogger.dart';

/// This class provides ICC Profiling API for the ucar.jpeg.jj2000.j2k imaging chain
/// by implementing the BlkImgDataSrc interface, in particular the getCompData
/// and getInternCompData methods.
class ICCProfiler extends ColorSpaceMapper {
  /// The prefix for ICC Profiler options
  static const String OPT_PREFIX = 'I';

  /// Platform dependant end of line String.
  static const String eol = '\n'; // System.getProperty("line.separator");

  // Renamed for convenience:
  static const int GRAY = RestrictedICCProfile.GRAY;
  static const int RED = RestrictedICCProfile.RED;
  static const int GREEN = RestrictedICCProfile.GREEN;
  static const int BLUE = RestrictedICCProfile.BLUE;

  // ICCProfiles.
  RestrictedICCProfile? rICC;
  ICCProfile? ICC;

  // Temporary variables needed during profiling.
  late final List<DataBlkInt> tempInt; // Holds the results of the transform.
  late final List<DataBlkFloat>
      tempFloat; // Holds the results of the transform.

  Object? xform;

  /// The image's ICC profile.
  RestrictedICCProfile? ICCp;

  /// Factory method for creating instances of this class.
  ///   @param src -- source of image data
  ///   @param csMap -- provides colorspace info
  /// @return ICCProfiler instance
  /// @exception IOException profile access exception
  /// @exception ICCProfileException profile content exception
  static BlkImgDataSrc createInstance(BlkImgDataSrc src, ColorSpace csMap) {
    return ICCProfiler(src, csMap);
  }

  /// Ctor which creates an ICCProfile for the image and initializes
  /// all data objects (input, working, output).
  ///
  ///   @param src -- Source of image data
  ///   @param csm -- provides colorspace info
  ///
  /// @exception IOException
  /// @exception ICCProfileException
  /// @exception IllegalArgumentException
  ICCProfiler(BlkImgDataSrc src, ColorSpace csMap) : super(src, csMap) {
    // initialize(); // Called by super

    ICCp = getICCProfile(csMap);
    if (ncomps == 1) {
      xform = MonochromeTransformTosRGB(
          ICCp!, maxValueArray![0], shiftValueArray![0]);
    } else {
      xform = MatrixBasedTransformTosRGB(ICCp!, maxValueArray!, shiftValueArray!);
    }
  }

  /// General utility used by ctors
  @override
  void initialize() {
    super.initialize();
    tempInt = List.generate(ncomps, (_) => DataBlkInt());
    tempFloat = List.generate(ncomps, (_) => DataBlkFloat());
  }

  /// Get the ICCProfile information JP2 ColorSpace
  ///   @param csm provides all necessary info about the ucar.jpeg.colorspace
  /// @return ICCMatrixBasedInputProfile for 3 component input and
  /// ICCMonochromeInputProfile for a 1 component source.  Returns
  /// null if exceptions were encountered.
  /// @exception ColorSpaceException
  /// @exception ICCProfileException
  /// @exception IllegalArgumentException
  RestrictedICCProfile getICCProfile(ColorSpace csm) {
    switch (ncomps) {
      case 1:
        ICC = ICCMonochromeInputProfile.createInstance(csm);
        rICC = ICC!.parse();
        if (rICC!.getType() != RestrictedICCProfile.kMonochromeInput)
          throw ArgumentError("wrong ICCProfile type for image");
        break;
      case 3:
        ICC = ICCMatrixBasedInputProfile.createInstance(csm);
        rICC = ICC!.parse();
        if (rICC!.getType() != RestrictedICCProfile.kThreeCompInput)
          throw ArgumentError("wrong ICCProfile type for image");
        break;
      default:
        throw ArgumentError("illegal number of components ($ncomps) in image");
    }
    return rICC!;
  }

  /// Returns, in the blk argument, a block of image data containing the
  /// specifed rectangular area, in the specified component. The data is
  /// returned, as a copy of the internal data, therefore the returned data
  /// can be modified "in place".
  ///
  /// <P>The rectangular area to return is specified by the 'ulx', 'uly', 'w'
  /// and 'h' members of the 'blk' argument, relative to the current
  /// tile. These members are not modified by this method. The 'offset' of
  /// the returned data is 0, and the 'scanw' is the same as the block's
  /// width. See the 'DataBlk' class.
  ///
  /// <P>If the data array in 'blk' is 'null', then a new one is created. If
  /// the data array is not 'null' then it is reused, and it must be large
  /// enough to contain the block's data. Otherwise an 'ArrayStoreException'
  /// or an 'IndexOutOfBoundsException' is thrown by the Java system.
  ///
  /// <P>The returned data has its 'progressive' attribute set to that of the
  /// input data.
  ///
  /// @param out Its coordinates and dimensions specify the area to
  /// return. If it contains a non-null data array, then it must have the
  /// correct dimensions. If it contains a null data array a new one is
  /// created. The fields in this object are modified to return the data.
  ///
  /// @param c The index of the component from which to get the data. Only 0
  /// and 3 are valid.
  ///
  /// @return The requested DataBlk
  ///
  /// @see #getInternCompData
  @override
  DataBlk getCompData(DataBlk outblk, int c) {
    try {
      if (ncomps != 1 && ncomps != 3) {
        String msg =
            "ICCProfiler: ICC profile _not_ applied to $ncomps component image";
        FacilityManager.getMsgLogger().printmsg(MsgLogger.warning, msg);
        return src!.getCompData(outblk, c);
      }

      int type = outblk.getDataType();

      int leftedgeOut = -1; // offset to the start of the output scanline
      // scanline + 1
      int leftedgeIn = -1; // offset to the start of the input scanline
      int rightedgeIn = -1; // offset to the end of the input
      // scanline + 1

      // Calculate all components:
      for (int i = 0; i < ncomps; ++i) {
        int fixedPtBits = src!.getFixedPoint(i);
        int shiftVal = shiftValueArray![i];
        int maxVal = maxValueArray![i];

        // Initialize general input and output indexes
        int kOut = -1;
        int kIn = -1;

        switch (type) {
          // Int and Float data only

          case DataBlk.typeInt:

            // Set up the DataBlk geometry
            ColorSpaceMapper.copyGeometry(workInt[i]!, outblk);
            ColorSpaceMapper.copyGeometry(tempInt[i], outblk);
            ColorSpaceMapper.copyGeometry(inInt[i]!, outblk);
            ColorSpaceMapper.setInternalBuffer(outblk);

            // Reference the output array
            workDataInt[i] = workInt[i]!.getDataInt();

            // Request data from the source.
            inInt[i] = src!.getInternCompData(inInt[i]!, i) as DataBlkInt;
            dataInt[i] = inInt[i]!.getDataInt();

            // The nitty-gritty.

            for (int row = 0; row < outblk.h; ++row) {
              leftedgeIn = inInt[i]!.offset + row * inInt[i]!.scanw;
              rightedgeIn = leftedgeIn + inInt[i]!.w;
              leftedgeOut = outblk.offset + row * outblk.scanw;

              kOut = leftedgeOut;
              kIn = leftedgeIn;
              for (; kIn < rightedgeIn; ++kIn, ++kOut) {
                int tmpInt = (dataInt[i]![kIn] >> fixedPtBits) + shiftVal;
                workDataInt[i]![kOut] = ((tmpInt < 0)
                    ? 0
                    : ((tmpInt > maxVal) ? maxVal : tmpInt));
              }
            }
            break;

          case DataBlk.typeFloat:

            // Set up the DataBlk geometry
            ColorSpaceMapper.copyGeometry(workFloat[i]!, outblk);
            ColorSpaceMapper.copyGeometry(tempFloat[i], outblk);
            ColorSpaceMapper.copyGeometry(inFloat[i]!, outblk);
            ColorSpaceMapper.setInternalBuffer(outblk);

            // Reference the output array
            workDataFloat[i] = workFloat[i]!.getDataFloat();

            // Request data from the source.
            inFloat[i] = src!.getInternCompData(inFloat[i]!, i) as DataBlkFloat;
            dataFloat[i] = inFloat[i]!.getDataFloat();

            // The nitty-gritty.

            for (int row = 0; row < outblk.h; ++row) {
              leftedgeIn = inFloat[i]!.offset + row * inFloat[i]!.scanw;
              rightedgeIn = leftedgeIn + inFloat[i]!.w;
              leftedgeOut = outblk.offset + row * outblk.scanw;

              kOut = leftedgeOut;
              kIn = leftedgeIn;
              for (; kIn < rightedgeIn; ++kIn, ++kOut) {
                double tmpFloat =
                    dataFloat[i]![kIn] / (1 << fixedPtBits) + shiftVal;
                workDataFloat[i]![kOut] = ((tmpFloat < 0)
                    ? 0.0
                    : ((tmpFloat > maxVal) ? maxVal.toDouble() : tmpFloat));
              }
            }
            break;

          case DataBlk.typeShort:
          case DataBlk.typeByte:
          default:
            // Unsupported output type.
            throw ArgumentError("Invalid source datablock type");
        }
      }

      switch (type) {
        // Int and Float data only

        case DataBlk.typeInt:
          if (ncomps == 1) {
            (xform as MonochromeTransformTosRGB)
                .applyInt(workInt[c]!, tempInt[c]);
          } else {
            // ncomps == 3
            // Cast List<DataBlkInt?> to List<DataBlkInt>
            List<DataBlkInt> workIntNonNull = workInt.cast<DataBlkInt>();
            (xform as MatrixBasedTransformTosRGB)
                .applyInt(workIntNonNull, tempInt);
          }

          outblk.progressive = inInt[c]!.progressive;
          outblk.setData(tempInt[c].getData());
          break;

        case DataBlk.typeFloat:
          if (ncomps == 1) {
            (xform as MonochromeTransformTosRGB)
                .applyFloat(workFloat[c]!, tempFloat[c]);
          } else {
            // ncomps == 3
            // Cast List<DataBlkFloat?> to List<DataBlkFloat>
            List<DataBlkFloat> workFloatNonNull =
                workFloat.cast<DataBlkFloat>();
            (xform as MatrixBasedTransformTosRGB)
                .applyFloat(workFloatNonNull, tempFloat);
          }

          outblk.progressive = inFloat[c]!.progressive;
          outblk.setData(tempFloat[c].getData());
          break;

        case DataBlk.typeShort:
        case DataBlk.typeByte:
        default:
          // Unsupported output type.
          throw ArgumentError("invalid source datablock type");
      }

      // Initialize the output block geometry and set the profiled
      // data into the output block.
      outblk.offset = 0;
      outblk.scanw = outblk.w;
    } on MatrixBasedTransformException catch (e) {
      FacilityManager.getMsgLogger().printmsg(
          MsgLogger.error, "matrix transform problem:\n${e.message}");
      if (pl!.getParameter("debug") == "on") {
        // e.printStackTrace(); // Not available in Dart
        print(e);
      } else {
        FacilityManager.getMsgLogger()
            .printmsg(MsgLogger.error, "Use '-debug' option for more details");
      }
      throw StateError("MatrixBasedTransformException: ${e.message}");
    } on MonochromeTransformException catch (e) {
      FacilityManager.getMsgLogger().printmsg(
          MsgLogger.error, "monochrome transform problem:\n${e.message}");
      if (pl!.getParameter("debug") == "on") {
        // e.printStackTrace(); // Not available in Dart
        print(e);
      } else {
        FacilityManager.getMsgLogger()
            .printmsg(MsgLogger.error, "Use '-debug' option for more details");
      }
      throw StateError("MonochromeTransformException: ${e.message}");
    }

    return outblk;
  }

  /// Returns, in the blk argument, a block of image data containing the
  /// specifed rectangular area, in the specified component. The data is
  /// returned, as a reference to the internal data, if any, instead of as a
  /// copy, therefore the returned data should not be modified.
  ///
  /// <P>The rectangular area to return is specified by the 'ulx', 'uly', 'w'
  /// and 'h' members of the 'blk' argument, relative to the current
  /// tile. These members are not modified by this method. The 'offset' and
  /// 'scanw' of the returned data can be arbitrary. See the 'DataBlk' class.
  ///
  /// <P>This method, in general, is more efficient than the 'getCompData()'
  /// method since it may not copy the data. However if the array of returned
  /// data is to be modified by the caller then the other method is probably
  /// preferable.
  ///
  /// <P>If possible, the data in the returned 'DataBlk' should be the
  /// internal data itself, instead of a copy, in order to increase the data
  /// transfer efficiency. However, this depends on the particular
  /// implementation (it may be more convenient to just return a copy of the
  /// data). This is the reason why the returned data should not be modified.
  ///
  /// <P>If the data array in <tt>blk</tt> is <tt>null</tt>, then a new one
  /// is created if necessary. The implementation of this interface may
  /// choose to return the same array or a new one, depending on what is more
  /// efficient. Therefore, the data array in <tt>blk</tt> prior to the
  /// method call should not be considered to contain the returned data, a
  /// new array may have been created. Instead, get the array from
  /// <tt>blk</tt> after the method has returned.
  ///
  /// <P>The returned data may have its 'progressive' attribute set. In this
  /// case the returned data is only an approximation of the "final" data.
  ///
  /// @param blk Its coordinates and dimensions specify the area to return,
  /// relative to the current tile. Some fields in this object are modified
  /// to return the data.
  ///
  /// @param c The index of the component from which to get the data.
  ///
  /// @return The requested DataBlk
  ///
  /// @see #getCompData
  @override
  DataBlk getInternCompData(DataBlk out, int c) {
    return getCompData(out, c);
  }

  /// Return a suitable String representation of the class instance.
  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ICCProfiler:");
    StringBuffer body = StringBuffer();
    if (ICC != null)
      body.write("$eol${ColorSpace.indent("  ", ICC.toString())}");
    if (xform != null)
      body.write("$eol${ColorSpace.indent("  ", xform.toString())}");
    rep.write(ColorSpace.indent("  ", body.toString()));
    return (rep..write("]")).toString();
  }
}


import '../../encoder/EncoderSpecs.dart';
import '../../image/BlkImgDataSrc.dart';
import '../../image/ImgData.dart';
import '../../image/ImgDataAdapter.dart';
import '../../util/ParameterList.dart';
import 'CBlkWTDataSrc.dart';
import 'ForwWT.dart';
import 'ForwWTFull.dart';

/// This abstract class represents the forward wavelet transform functional
/// block. The functional block may actually be comprised of several classes
/// linked together, but a subclass of this abstract class is the one that is
/// returned as the functional block that performs the forward wavelet
/// transform.
///
/// This class assumes that data is transferred in code-blocks, as defined
/// by the 'CBlkWTDataSrc' interface. The internal calculation of the wavelet
/// transform may be done differently but a buffering class should convert to
/// that type of transfer.
abstract class ForwardWT extends ImgDataAdapter
    implements ForwWT, CBlkWTDataSrc {
  /// ID for the dyadic wavelet tree decomposition (also called "Mallat" in
  /// JPEG 2000): 0x00.
  static const int WT_DECOMP_DYADIC = 0;

  /// The prefix for wavelet transform options: 'W'
  static const String OPT_PREFIX = 'W';

  /// The list of parameters that is accepted for wavelet transform. Options
  /// for the wavelet transform start with 'W'.
  static const List<List<String>> pinfo = [
    [
      "Wlev",
      "<number of decomposition levels>",
      "Specifies the number of decomposition levels to apply to the image. If 0 no wavelet transform is performed. All components and all tiles have the same number of decomposition levels.",
      "5"
    ],
    [
      "Wwt",
      "[full]",
      "Specifies the wavelet transform to be used. Possible value is: 'full' (full page). The value 'full' performs a normal DWT.",
      "full"
    ],
    [
      "Wcboff",
      "<x y>",
      "Code-blocks partition offset in the reference grid. Allowed for <x> and <y> are 0 and 1.\nNote: This option is defined in JPEG 2000 part 2 and may not be supported by all JPEG 2000 decoders.",
      "0 0"
    ]
  ];

  /// Initializes this object for the specified number of tiles 'nt' and
  /// components 'nc'.
  ///
  /// @param src The source of ImgData
  ForwardWT(ImgData src) : super(src);

  /// Returns the parameters that are used in this class and implementing
  /// classes. It returns a 2D String array. Each of the 1D arrays is for a
  /// different option, and they have 3 elements. The first element is the
  /// option name, the second element is the synopsis and the third one is a long
  /// description of what the parameter is. The synopsis or description may
  /// be 'null', in which case it is assumed that there is no synopsis or
  /// description of the option, respectively. Null may be returned if no
  /// options are supported.
  ///
  /// @return the options name, their synopsis and their explanation, or null
  /// if no options are supported.
  static List<List<String>> getParameterInfo() {
    return pinfo;
  }

  /// Creates a ForwardWT object with the specified filters, and with other
  /// options specified in the parameter list 'pl'.
  ///
  /// @param src The source of data to be transformed
  ///
  /// @param pl The parameter list (or options).
  ///
  /// @param kers The encoder specifications.
  ///
  /// @return A new ForwardWT object with the specified filters and options
  /// from 'pl'.
  ///
  /// @exception IllegalArgumentException If mandatory parameters are missing
  /// or if invalid values are given.
  static ForwardWT createInstance(
      BlkImgDataSrc src, ParameterList pl, EncoderSpecs encSpec) {
    // Check parameters
    pl.checkListSingle(OPT_PREFIX.codeUnitAt(0),
        ParameterList.toNameArray(pinfo as List<List<String?>>));

    // Code-block partition origin
    if (pl.getParameter("Wcboff") == null) {
      throw Error(); // "You must specify an argument to the '-Wcboff' option..."
    }
    var parts = pl.getParameter("Wcboff")!.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) {
      throw ArgumentError(
          "'-Wcboff' option needs two arguments. See usage with the '-u' option.");
    }
    int cb0x = 0;
    try {
      cb0x = int.parse(parts[0]);
    } catch (e) {
      throw ArgumentError(
          "Bad first parameter for the '-Wcboff' option: ${parts[0]}");
    }
    if (cb0x < 0 || cb0x > 1) {
      throw ArgumentError("Invalid horizontal code-block partition origin.");
    }
    int cb0y = 0;
    try {
      cb0y = int.parse(parts[1]);
    } catch (e) {
      throw ArgumentError(
          "Bad second parameter for the '-Wcboff' option: ${parts[1]}");
    }
    if (cb0y < 0 || cb0y > 1) {
      throw ArgumentError("Invalid vertical code-block partition origin.");
    }
    if (cb0x != 0 || cb0y != 0) {
      // FacilityManager.getMsgLogger().printmsg(MsgLogger.WARNING, ...);
    }

    return ForwWTFull(src, encSpec, cb0x, cb0y);
  }
}



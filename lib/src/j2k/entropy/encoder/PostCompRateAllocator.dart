import '../../codestream/writer/CodestreamWriter.dart';
import '../../codestream/writer/HeaderEncoder.dart';
import '../../encoder/EncoderSpecs.dart';
import '../../image/ImgDataAdapter.dart';
import '../../util/ParameterList.dart';
import 'CodedCBlkDataSrcEnc.dart';
import 'LayersInfo.dart';

/// This is the abstract class from which post-compression rate allocators
/// which generate layers should inherit. The source of data is a
/// 'CodedCBlkDataSrcEnc' which delivers entropy coded blocks with
/// rate-distortion statistics.
///
/// The post compression rate allocator implementation should create the
/// layers, according to a rate allocation policy, and send the packets to a
/// CodestreamWriter. Since the rate allocator sends the packets to the bit
/// stream then it should output the packets to the bit stream in the order
/// imposed by the bit stream profiles.
///
/// @see CodedCBlkDataSrcEnc
/// @see ucar.jpeg.jj2000.j2k.codestream.writer.CodestreamWriter
abstract class PostCompRateAllocator extends ImgDataAdapter {
  /// The prefix for rate allocation options: 'A'
  static const String OPT_PREFIX = 'A';

  /// The list of parameters that is accepted for entropy coding. Options
  /// for entropy coding start with 'R'.
  static const List<List<String?>> pinfo = [
    [
      "Aptype",
      "[<tile idx>] res|layer|res-pos|" +
          "pos-comp|comp-pos [res_start comp_start layer_end res_end " +
          "comp_end " +
          "prog] [[res_start comp_start ly_end res_end comp_end prog] ...] [" +
          "[<tile-component idx>] ...]",
      "Specifies which type of progression should be used when " +
          "generating " +
          "the codestream. The 'res' value generates a resolution " +
          "progressive codestream with the number of layers specified by " +
          "'Alayers' option. The 'layer' value generates a layer progressive " +
          "codestream with multiple layers. In any case the rate-allocation " +
          "algorithm optimizes for best quality in each layer. The quality " +
          "measure is mean squared error (MSE) or a weighted version of it " +
          "(WMSE). If no progression type is specified or imposed by other " +
          "modules, the default value is 'layer'.\n" +
          "It is also possible to describe progression order changes. In " +
          "this case, 'res_start' is the index (from 0) of the first " +
          "resolution " +
          "level, 'comp_start' is the index (from 0) of the first component, " +
          "'ly_end' is the index (from 0) of the first layer not included, " +
          "'res_end' is the index (from 0) of the first resolution level not " +
          "included, 'comp_end' is index (from 0) of the first component not " +
          "included and 'prog' is the progression type to be used " +
          "for the rest of the tile/image. Several progression order changes " +
          "can be specified, one after the other.",
      null
    ],
    [
      "Alayers",
      "[<rate> [+<layers>] [<rate [+<layers>] [...]] | sl]",
      "Explicitly specifies the codestream layer formation parameters. " +
          "The <rate> parameter specifies the bitrate to which the first " +
          "layer should be optimized. The <layers> parameter, if present, " +
          "specifies the number of extra layers that should be added for " +
          "scalability. These extra layers are not optimized. " +
          "Any extra <rate> and <layers> parameters add more layers, in the " +
          "same way. An additional layer is always added at the end, which" +
          " is " +
          "optimized to the overall target bitrate of the bit stream. Any " +
          "layers (optimized or not) whose target bitrate is higher that the " +
          "overall target bitrate are silently ignored. The bitrates of the " +
          "extra layers that are added through the <layers> parameter are " +
          "approximately log-spaced between the other target bitrates. If " +
          "several <rate> [+<layers>] constructs appear the <rate>" +
          " parameters " +
          "must appear in increasing order. The rate allocation algorithm " +
          "ensures that all coded layers have a minimal reasonable size, if " +
          "not these layers are silently ignored.\n" +
          "If the 'sl' (i.e. 'single layer') argument is specified, the " +
          "generated codestream will" +
          " only contain one layer (with a bit rate specified thanks to the" +
          " '-rate' or 'nbytes' options).",
      "0.015 +20 2.0 +10"
    ]
  ];

  /// The source of entropy coded data
  CodedCBlkDataSrcEnc src;

  /// The source of entropy coded data
  EncoderSpecs encSpec;

  /// The number of layers.
  int numLayers;

  /// The bit-stream writer
  CodestreamWriter bsWriter;

  /// The header encoder
  HeaderEncoder? headEnc;

  /// Initializes the source of entropy coded data.
  ///
  /// [src] The source of entropy coded data.
  ///
  /// [nl] The number of layers to create
  ///
  /// [bw] The packet bit stream writer.
  ///
  /// [encSpec] The encoder specifications.
  PostCompRateAllocator(
      this.src, int nl, this.bsWriter, this.encSpec)
      : numLayers = nl,
        super(src);

  /// Keep a reference to the header encoder.
  ///
  /// [headEnc] The header encoder
  void setHeaderEncoder(HeaderEncoder headEnc) {
    this.headEnc = headEnc;
  }

  /// Initializes the rate allocation points, taking into account header
  /// overhead and such. This method must be called after the header has been
  /// simulated but before calling the runAndWrite() one. The header must be
  /// rewritten after a call to this method since the number of layers may
  /// change.
  ///
  /// @see #runAndWrite
  void initialize();

  /// Runs the rate allocation algorithm and writes the data to the
  /// bit stream. This must be called after the initialize() method.
  ///
  /// @see #initialize
  void runAndWrite();

  /// Returns the number of layers that are actually generated.
  ///
  /// @return The number of layers generated.
  int getNumLayers() {
    return numLayers;
  }

  /// Returns the parameters that are used in this class and implementing
  /// classes. It returns a 2D String array. Each of the 1D arrays is for a
  /// different option, and they have 3 elements. The first element is the
  /// option name, the second one is the synopsis, the third one is a long
  /// description of what the parameter is and the fourth is its default
  /// value. The synopsis or description may be 'null', in which case it is
  /// assumed that there is no synopsis or description of the option,
  /// respectively. Null may be returned if no options are supported.
  ///
  /// @return the options name, their synopsis and their explanation,
  /// or null if no options are supported.
  static List<List<String?>> getParameterInfo() {
    return pinfo;
  }

  /// Creates a PostCompRateAllocator object for the appropriate rate
  /// allocation parameters in the parameter list 'pl', having 'src' as the
  /// source of entropy coded data, 'rate' as the target bitrate and 'bw' as
  /// the bit stream writer object.
  ///
  /// [src] The source of entropy coded data.
  ///
  /// [pl] The parameter lis (or options).
  ///
  /// [rate] The target bitrate for the rate allocation
  ///
  /// [bw] The bit stream writer object, where the bit stream data will
  /// be written.
  static PostCompRateAllocator createInstance(
      CodedCBlkDataSrcEnc src,
      ParameterList pl,
      double rate,
      CodestreamWriter bw,
      EncoderSpecs encSpec) {
    // Check parameters
    // pl.checkList(OPT_PREFIX, pl.toNameArray(pinfo));

    // Construct the layer specification from the 'Alayers' option
    // LayersInfo lyrs = parseAlayers(pl.getParameter("Alayers"), rate);

    // int nTiles = encSpec.nTiles;
    // int nComp = encSpec.nComp;
    // int numLayers = lyrs.getTotNumLayers();

    // Parse the progressive type
    // encSpec.pocs = new ProgressionSpec(nTiles, nComp, numLayers, encSpec.dls,
    //     ModuleSpec.SPEC_TYPE_TILE_COMP, pl);

    // return new EBCOTRateAllocator(src, lyrs, bw, encSpec, pl);
    throw UnimplementedError("EBCOTRateAllocator not implemented yet");
  }

  /// Convenience method that parses the 'Alayers' option.
  ///
  /// [params] The parameters of the 'Alayers' option
  ///
  /// [rate] The overall target bitrate
  ///
  /// @return The layer specification.
  static LayersInfo parseAlayers(String params, double rate) {
    LayersInfo lyrs = LayersInfo(rate);

    if (params.trim() == 'sl') {
      return lyrs;
    }

    List<String> tokens =
        params.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

    bool ratePending = false;
    double r = 0.0;

    for (int i = 0; i < tokens.length; i++) {
      String token = tokens[i];
      if (token.startsWith('+')) {
        // Layer parameter
        if (!ratePending) {
          throw ArgumentError(
              "Layer parameter without previous rate parameter in 'Alayers' option");
        }
        int layers = int.parse(token.substring(1));
        lyrs.addOptPoint(r, layers);
        ratePending = false;
      } else {
        // Rate parameter
        if (ratePending) {
          lyrs.addOptPoint(r, 0);
        }
        r = double.parse(token);
        ratePending = true;
      }
    }

    if (ratePending) {
      lyrs.addOptPoint(r, 0);
    }

    return lyrs;
  }
}



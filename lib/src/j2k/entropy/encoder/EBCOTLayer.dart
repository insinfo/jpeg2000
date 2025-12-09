/// This class holds information about each layer that is to be, or has already
/// been, allocated . It is used in the rate-allocation process to keep the
/// necessary layer information. It is used by EBCOTRateAllocator.
///
/// @see EBCOTRateAllocator
class EBCOTLayer {
  /// This is the maximum number of bytes that should be allocated for this
  /// and previous layers. This is actually the target length for the layer.
  int maxBytes = 0;

  /// The actual number of bytes which are consumed by the the current and
  /// any previous layers. This is the result from a simulation when the
  /// threshold for the layer has been set.
  int actualBytes = 0;

  /// If true the `maxBytes' value is the hard maximum and the threshold is
  /// determined iteratively. If false the `maxBytes' value is a target
  /// bitrate and the threshold is estimated from summary information
  /// accumulated during block coding.
  bool optimize = false;

  /// The rate-distortion threshold associated with the bit-stream
  /// layer. When set the layer includes data up to the truncation points
  /// that have a slope no smaller than 'rdThreshold'.
  double rdThreshold = 0.0;
}

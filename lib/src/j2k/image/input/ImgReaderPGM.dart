/// Placeholder for the PGM image reader used by ROI mask generation.
///
/// The original JJ2000 implementation exposes an `ImgReaderPGM` capable of
/// loading 8-bit portable graymap images and exposing them through JJ2000's
/// `ImgData` interface. The ROI encoder relies on this reader when an
/// arbitrary-shape ROI is supplied.
///
/// TODO: Port the full reader from the JJ2000 Java sources and wire it into
/// the image input module once the arbitrary-shape ROI pipeline is needed.
class ImgReaderPGM {
  const ImgReaderPGM(this.path);

  /// Location of the mask file on disk.
  final String path;

  @override
  String toString() => 'ImgReaderPGM($path)';
}

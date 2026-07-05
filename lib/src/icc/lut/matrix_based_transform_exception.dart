/// Thrown by MatrixBasedTransformTosRGB
class MatrixBasedTransformException implements Exception {
  final String? message;

  /// Contruct with message
  ///   @param msg returned by getMessage()
  MatrixBasedTransformException([this.message]);

  @override
  String toString() {
    if (message == null) return "MatrixBasedTransformException";
    return "MatrixBasedTransformException: $message";
  }
}

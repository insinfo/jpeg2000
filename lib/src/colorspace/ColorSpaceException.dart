class ColorSpaceException implements Exception {
  final String? message;

  ColorSpaceException([this.message]);

  @override
  String toString() {
    if (message == null) return "ColorSpaceException";
    return "ColorSpaceException: $message";
  }
}

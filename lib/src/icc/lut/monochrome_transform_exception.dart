class MonochromeTransformException implements Exception {
  final String? message;

  MonochromeTransformException([this.message]);

  @override
  String toString() {
    if (message == null) return "MonochromeTransformException";
    return "MonochromeTransformException: $message";
  }
}

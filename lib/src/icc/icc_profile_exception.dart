class ICCProfileException implements Exception {
  final String? message;

  ICCProfileException([this.message]);

  @override
  String toString() {
    if (message == null) return "ICCProfileException";
    return "ICCProfileException: $message";
  }
}

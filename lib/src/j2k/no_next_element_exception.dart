/// Raised when attempting to advance past the last element in a JJ2000 iterator.
class NoNextElementException extends StateError {
  NoNextElementException([String? message])
      : super(message ?? 'No more elements available.');
}

/// Identifiers for wavelet filter choices mirrored from JJ2000.
class FilterTypes {
  FilterTypes._();

  static const int w9x7 = 0;
  static const int w5x3 = 1;
  static const int custom = -1;

  // Java-compat aliases.
  static const int W9X7 = w9x7;
  static const int W5X3 = w5x3;
  static const int CUSTOM = custom;
}

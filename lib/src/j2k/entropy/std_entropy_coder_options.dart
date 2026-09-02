/// Constants describing entropy coder options and limits from JJ2000.
class StdEntropyCoderOptions {
  StdEntropyCoderOptions._();

  static const int optBypass = 1;
  static const int optResetMq = 1 << 1;
  static const int optTermPass = 1 << 2;
  static const int optVertStrCausal = 1 << 3;
  static const int optPredTerm = 1 << 4;
  static const int optSegSymbols = 1 << 5;

  static const int minCbDim = 4;
  static const int maxCbDim = 1024;
  static const int maxCbArea = 4096;
  static const int stripeHeight = 4;
  static const int numPasses = 3;
  static const int numNonBypassMsBp = 4;
  static const int numEmptyPassesInMsBp = 2;
  static const int firstBypassPassIdx =
      numPasses * numNonBypassMsBp - numEmptyPassesInMsBp;
}

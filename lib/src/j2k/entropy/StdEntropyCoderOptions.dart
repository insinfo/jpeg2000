/// Constants describing entropy coder options and limits from JJ2000.
class StdEntropyCoderOptions {
  StdEntropyCoderOptions._();

  static const int OPT_BYPASS = 1;
  static const int OPT_RESET_MQ = 1 << 1;
  static const int OPT_TERM_PASS = 1 << 2;
  static const int OPT_VERT_STR_CAUSAL = 1 << 3;
  static const int OPT_PRED_TERM = 1 << 4;
  static const int OPT_SEG_SYMBOLS = 1 << 5;

  static const int MIN_CB_DIM = 4;
  static const int MAX_CB_DIM = 1024;
  static const int MAX_CB_AREA = 4096;
  static const int STRIPE_HEIGHT = 4;
  static const int NUM_PASSES = 3;
  static const int NUM_NON_BYPASS_MS_BP = 4;
  static const int NUM_EMPTY_PASSES_IN_MS_BP = 2;
  static const int FIRST_BYPASS_PASS_IDX =
      NUM_PASSES * NUM_NON_BYPASS_MS_BP - NUM_EMPTY_PASSES_IN_MS_BP;
}

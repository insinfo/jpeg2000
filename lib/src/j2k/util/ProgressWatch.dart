/// Interface for progress reporting hooks used by the JJ2000 decoder.
abstract class ProgressWatch {
  void initProgressWatch(int min, int max, String info);

  void updateProgressWatch(int value, String info);

  void terminateProgressWatch();
}

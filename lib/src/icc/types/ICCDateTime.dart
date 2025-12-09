import '../ICCProfile.dart';

class ICCDateTime {
  static const int size = 6 * ICCProfile.short_size;

  /** Year datum.   */
  int wYear; // Number of the actual year (i.e. 1994)
  /** Month datum.  */
  int wMonth; // Number of the month (1-12)
  /** Day datum.    */
  int wDay; // Number of the day
  /** Hour datum.   */
  int wHours; // Number of hours (0-23)
  /** Minute datum. */
  int wMinutes; // Number of minutes (0-59)
  /** Second datum. */
  int wSeconds; // Number of seconds (0-59)

  /** Construct an ICCDateTime from parts */
  ICCDateTime(this.wYear, this.wMonth, this.wDay, this.wHours, this.wMinutes,
      this.wSeconds);

  /** Return a ICCDateTime representation. */
  @override
  String toString() {
    return "$wYear/$wMonth/$wDay $wHours:$wMinutes:$wSeconds";
  }
}


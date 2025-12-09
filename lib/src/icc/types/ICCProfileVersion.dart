import '../ICCProfile.dart';

class ICCProfileVersion {
  /** Field size */
  static const int size = 4 * ICCProfile.byte_size;

  /** Major revision number in binary coded decimal */
  int uMajor;
  /** Minor revision in high nibble, bug fix revision           
        in low nibble, both in binary coded decimal   */
  int uMinor;

  int reserved1;
  int reserved2;

  /** Construct from constituent parts. */
  ICCProfileVersion(this.uMajor, this.uMinor, this.reserved1, this.reserved2);

  /** String representation of class instance. */
  @override
  String toString() {
    return "Version $uMajor.$uMinor";
  }
}


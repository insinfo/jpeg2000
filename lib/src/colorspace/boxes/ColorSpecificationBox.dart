import 'dart:typed_data';
import '../../j2k/io/RandomAccessIO.dart';
import '../ColorSpaceException.dart';
import '../../icc/IccProfile.dart';
import 'JP2Box.dart';
import '../ColorSpace.dart';

class ColorSpecificationBox extends JP2Box {
  static const int boxType = 0x636f6c72; // 'colr'

  @override
  int get type => boxType;

  MethodEnum? method;
  CSEnum? colorSpace;
  Uint8List? iccProfile;
  int cs = 0;
  int rawmethod = 0;
  int approxAccuracy = 0;

  ColorSpecificationBox(RandomAccessIO in_io, int boxStart)
      : super(in_io, boxStart) {
    readBox();
  }

  void readBox() {
    Uint8List boxHeader = Uint8List(256);
    in_io.seek(dataStart);
    in_io.readFully(boxHeader, 0, 11);
    rawmethod = boxHeader[0];
    approxAccuracy = boxHeader[2];
    switch (rawmethod) {
      case 1:
        method = ColorSpace.ENUMERATED;
        cs = ICCProfile.getInt(boxHeader, 3);
        switch (cs) {
          case 16:
            colorSpace = ColorSpace.sRGB;
            break;
          case 17:
            colorSpace = ColorSpace.GreyScale;
            break;
          case 18:
            colorSpace = ColorSpace.sYCC;
            break;
          default:
            // TODO: pipe warning through FacilityManager equivalent once available.
            print(
              "Unknown enumerated colorspace ($cs) in color specification box");
            colorSpace = ColorSpace.Unknown;
        }
        break;
      case 2:
        method = ColorSpace.ICC_PROFILED;
        cs = -1;
        int size = ICCProfile.getInt(boxHeader, 3);
        iccProfile = Uint8List(size);
        in_io.seek(dataStart + 3);
        in_io.readFully(iccProfile!, 0, size);
        break;
      default:
        throw ColorSpaceException(
            "Bad specification method ($rawmethod) in $this");
    }
  }

  MethodEnum getMethod() {
    return method!;
  }

  CSEnum getColorSpace() {
    return colorSpace!;
  }

  int getRawMethod() {
    return rawmethod;
  }

  int getRawApproximationAccuracy() {
    return approxAccuracy;
  }

  int getRawColorSpace() {
    return cs;
  }

  String getColorSpaceString() {
    return colorSpace!.value;
  }

  String getMethodString() {
    return method!.value;
  }

  Uint8List? getICCProfile() {
    return iccProfile;
  }

  @override
  String toString() {
    StringBuffer rep = StringBuffer("[ColorSpecificationBox ");
    rep.write("method= $method, ");
    rep.write("colorspace= $colorSpace]");
    return rep.toString();
  }
}


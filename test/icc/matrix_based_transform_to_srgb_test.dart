import 'dart:typed_data';

import 'package:jpeg2000/src/icc/restricted_icc_profile.dart';
import 'package:jpeg2000/src/icc/lut/matrix_based_transform_to_srgb.dart';
import 'package:jpeg2000/src/icc/tags/icc_curve_type.dart';
import 'package:jpeg2000/src/icc/tags/icc_tag.dart';
import 'package:jpeg2000/src/icc/tags/icc_xyz_type.dart';
import 'package:test/test.dart';

void main() {
  test('MatrixBasedTransformTosRGB M12 uses blue Y colorant dfPCS12', () {
    final curve = _gammaCurve();
    final profile = RestrictedICCProfile.createInstance3Comp(
      curve,
      curve,
      curve,
      _xyz(ICCTag.kdwRXYZSignature, 0.10, 0.20, 0.30),
      _xyz(ICCTag.kdwGXYZSignature, 0.40, 0.25, 0.60),
      _xyz(ICCTag.kdwBXYZSignature, 0.70, 0.75, 0.90),
    );

    final transform = MatrixBasedTransformTosRGB(
      profile,
      const <int>[255, 255, 255],
      const <int>[0, 0, 0],
    );

    final blueY = ICCXYZType.xyzToDouble(profile.colorant![2]!.y);
    final greenY = ICCXYZType.xyzToDouble(profile.colorant![1]!.y);
    final expected = 255 *
        (MatrixBasedTransformTosRGB.SRGB10 *
                ICCXYZType.xyzToDouble(profile.colorant![2]!.x) +
            MatrixBasedTransformTosRGB.SRGB11 * blueY +
            MatrixBasedTransformTosRGB.SRGB12 *
                ICCXYZType.xyzToDouble(profile.colorant![2]!.z));
    final oldTypoValue = 255 *
        (MatrixBasedTransformTosRGB.SRGB10 *
                ICCXYZType.xyzToDouble(profile.colorant![2]!.x) +
            MatrixBasedTransformTosRGB.SRGB11 * greenY +
            MatrixBasedTransformTosRGB.SRGB12 *
                ICCXYZType.xyzToDouble(profile.colorant![2]!.z));

    expect(transform.matrix[MatrixBasedTransformTosRGB.M12],
        closeTo(expected, 1e-9));
    expect(
      transform.matrix[MatrixBasedTransformTosRGB.M12],
      isNot(closeTo(oldTypoValue, 1e-6)),
    );
  });
}

ICCCurveType _gammaCurve() {
  final data = Uint8List(14);
  _writeInt(data, 0, ICCTag.kdwCurveType);
  _writeInt(data, 4, 0);
  _writeInt(data, 8, 1);
  _writeShort(data, 12, 256);
  return ICCCurveType(ICCTag.kdwRTRCSignature, data, 0, data.length);
}

ICCXYZType _xyz(int signature, double x, double y, double z) {
  final data = Uint8List(20);
  _writeInt(data, 0, ICCTag.kdwXYZType);
  return ICCXYZType.fromValues(
    signature,
    data,
    0,
    data.length,
    ICCXYZType.doubleToXYZ(x),
    ICCXYZType.doubleToXYZ(y),
    ICCXYZType.doubleToXYZ(z),
  );
}

void _writeInt(Uint8List data, int offset, int value) {
  data[offset] = (value >> 24) & 0xff;
  data[offset + 1] = (value >> 16) & 0xff;
  data[offset + 2] = (value >> 8) & 0xff;
  data[offset + 3] = value & 0xff;
}

void _writeShort(Uint8List data, int offset, int value) {
  data[offset] = (value >> 8) & 0xff;
  data[offset + 1] = value & 0xff;
}

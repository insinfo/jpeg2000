import '../../quantization/dequantizer/CBlkQuantDataSrcDec.dart';
import '../../wavelet/synthesis/MultiResImgDataAdapter.dart';
import '../../wavelet/synthesis/SubbandSyn.dart';
import 'CodedCBlkDataSrcDec.dart';

/// Base class for entropy decoders that exposes the [CBlkQuantDataSrcDec]
/// contract while delegating resolution metadata to an upstream source.
///
/// The original JJ2000 implementation surfaces decoder options via a static
/// table so the CLI can advertise valid switches; we keep the same metadata to
/// support the Dart port of the command-line tooling.
abstract class EntropyDecoder extends MultiResImgDataAdapter
    implements CBlkQuantDataSrcDec {
  EntropyDecoder(this.src) : super(src);

  static const List<List<String>> parameterInfo = <List<String>>[
    <String>[
      'Cverber',
      '[on|off]',
      'Enables verbose logging when bit stream errors are detected during entropy decoding.',
      'on',
    ],
    <String>[
      'Cer',
      '[on|off]',
      'Controls whether the entropy decoder performs error detection and concealment when error resilience markers are present.',
      'on',
    ],
  ];

  /// Prefix used by JJ2000 to namespace entropy options ("C").
  static const String optionPrefix = 'C';

  /// Source of coded code-blocks for the current tile.
  final CodedCBlkDataSrcDec src;

  @override
  SubbandSyn getSynSubbandTree(int tile, int component) =>
      src.getSynSubbandTree(tile, component);

  @override
  int getCbULX() => src.getCbULX();

  @override
  int getCbULY() => src.getCbULY();
}



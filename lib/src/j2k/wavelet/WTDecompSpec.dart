import '../NotImplementedError.dart';

/// Mirrors JJ2000's `WTDecompSpec`, tracking the decomposition type and
/// levels per tile/component.
class WTDecompSpec {
  WTDecompSpec(int numComps, this._mainDefDecompType, this._mainDefLevels)
      : _specValType = List<int>.filled(numComps, decSpecMainDef, growable: false);

  // Decomposition identifiers.
  static const int wtDecompDyadic = 0;
  static const int wtDecompPacket = 1;
  static const int wtDecompSpacl = 2;

  // Specification scoping constants.
  static const int decSpecMainDef = 0;
  static const int decSpecCompDef = 1;
  static const int decSpecTileDef = 2;
  static const int decSpecTileComp = 3;

  final List<int> _specValType;
  final int _mainDefDecompType;
  final int _mainDefLevels;

  List<int>? _compMainDefDecompType;
  List<int>? _compMainDefLevels;

  void setMainCompDefDecompType(int comp, int decompType, int levels) {
    if (decompType < 0 && levels < 0) {
      throw ArgumentError('decompType and levels cannot both be negative');
    }
    _specValType[comp] = decSpecCompDef;
    _compMainDefDecompType ??= List<int>.filled(_specValType.length, _mainDefDecompType, growable: false);
    _compMainDefLevels ??= List<int>.filled(_specValType.length, _mainDefLevels, growable: false);
    _compMainDefDecompType![comp] = decompType >= 0 ? decompType : _mainDefDecompType;
    _compMainDefLevels![comp] = levels >= 0 ? levels : _mainDefLevels;

    throw NotImplementedError(
      'Component-specific decomposition not yet supported (matches JJ2000 limitation).',
    );
  }

  int getDecSpecType(int comp) => _specValType[comp];

  int getMainDefDecompType() => _mainDefDecompType;

  int getMainDefLevels() => _mainDefLevels;

  int getDecompType(int comp) {
    switch (_specValType[comp]) {
      case decSpecMainDef:
        return _mainDefDecompType;
      case decSpecCompDef:
        return _compMainDefDecompType![comp];
      case decSpecTileDef:
      case decSpecTileComp:
        throw NotImplementedError();
      default:
        throw StateError('Invalid decomposition spec type ${_specValType[comp]}');
    }
  }

  int getLevels(int comp) {
    switch (_specValType[comp]) {
      case decSpecMainDef:
        return _mainDefLevels;
      case decSpecCompDef:
        return _compMainDefLevels![comp];
      case decSpecTileDef:
      case decSpecTileComp:
        throw NotImplementedError();
      default:
        throw StateError('Invalid decomposition spec type ${_specValType[comp]}');
    }
  }

  /// Returns a deep copy of this specification.
  WTDecompSpec getCopy() {
    final copy = WTDecompSpec(_specValType.length, _mainDefDecompType, _mainDefLevels);
    for (var i = 0; i < _specValType.length; i++) {
      copy._specValType[i] = _specValType[i];
    }
    if (_compMainDefDecompType != null) {
      copy._compMainDefDecompType = List<int>.from(_compMainDefDecompType!);
      copy._compMainDefLevels = List<int>.from(_compMainDefLevels!);
    }
    return copy;
  }
}


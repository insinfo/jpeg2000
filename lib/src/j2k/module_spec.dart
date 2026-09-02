import 'dart:collection';

import 'image/coord.dart';

/// Generic container for tile/component module specifications.
class ModuleSpec<T> {
  ModuleSpec(int numTiles, int numComps, this.specType)
      : nTiles = numTiles,
        nComp = numComps,
        specValType = List<List<int>>.generate(
          numTiles,
          (_) => List<int>.filled(numComps, specDef),
          growable: false,
        );

  static const int specTypeComp = 0;
  static const int specTypeTile = 1;
  static const int specTypeTileComp = 2;

  static const int specDef = 0;
  static const int specCompDef = 1;
  static const int specTileDef = 2;
  static const int specTileComp = 3;

  final int specType;
  final int nTiles;
  final int nComp;

  List<List<int>> specValType;
  T? def;
  List<T?>? compDef;
  List<T?>? tileDef;
  Map<String, T>? tileCompVal;

  ModuleSpec<T> getCopy() => clone();

  ModuleSpec<T> clone() {
    final copy = ModuleSpec<T>(nTiles, nComp, specType)
      ..def = def
      ..compDef = compDef == null ? null : List<T?>.from(compDef!)
      ..tileDef = tileDef == null ? null : List<T?>.from(tileDef!)
      ..tileCompVal =
          tileCompVal == null ? null : HashMap<String, T>.from(tileCompVal!);
    for (var t = 0; t < nTiles; t++) {
      copy.specValType[t] = List<int>.from(specValType[t]);
    }
    return copy;
  }

  void rotate90(Coord newTiles) {
    final rotatedType = List<List<int>>.generate(
      nTiles,
      (_) => List<int>.filled(nComp, specDef),
      growable: false,
    );
    final rotatedCoord = Coord(newTiles.y, newTiles.x);
    for (var by = 0; by < rotatedCoord.y; by++) {
      for (var bx = 0; bx < rotatedCoord.x; bx++) {
        final ay = bx;
        final ax = rotatedCoord.y - by - 1;
        rotatedType[ay * newTiles.x + ax] =
            specValType[by * rotatedCoord.x + bx];
      }
    }
    specValType = rotatedType;

    if (tileDef != null) {
      final rotatedTileDef = List<T?>.filled(nTiles, null);
      for (var by = 0; by < rotatedCoord.y; by++) {
        for (var bx = 0; bx < rotatedCoord.x; bx++) {
          final ay = bx;
          final ax = rotatedCoord.y - by - 1;
          rotatedTileDef[ay * newTiles.x + ax] =
              tileDef![by * rotatedCoord.x + bx];
        }
      }
      tileDef = rotatedTileDef;
    }

    if (tileCompVal != null && tileCompVal!.isNotEmpty) {
      final rotatedMap = <String, T>{};
      tileCompVal!.forEach((key, value) {
        final tIndex = key.indexOf('t');
        final cIndex = key.indexOf('c');
        final oldTile = int.parse(key.substring(tIndex + 1, cIndex));
        final bx = oldTile % rotatedCoord.x;
        final by = oldTile ~/ rotatedCoord.x;
        final ay = bx;
        final ax = rotatedCoord.y - by - 1;
        final newTile = ax + ay * newTiles.x;
        rotatedMap['t$newTile${key.substring(cIndex)}'] = value;
      });
      tileCompVal = rotatedMap;
    }
  }

  void setDefault(T value) {
    def = value;
  }

  T? getDefault() => def;

  void setCompDef(int component, T value) {
    if (specType == specTypeTile) {
      throw StateError(
        "Option whose value is '$value' cannot be specified for components",
      );
    }
    compDef ??= List<T?>.filled(nComp, null);
    for (var tile = 0; tile < nTiles; tile++) {
      if (specValType[tile][component] < specCompDef) {
        specValType[tile][component] = specCompDef;
      }
    }
    compDef![component] = value;
  }

  T? getCompDef(int component) {
    if (specType == specTypeTile) {
      throw StateError('Illegal use of ModuleSpec for component query');
    }
    if (compDef == null || compDef![component] == null) {
      return def;
    }
    return compDef![component];
  }

  void setTileDef(int tile, T value) {
    if (specType == specTypeComp) {
      throw StateError(
        "Option whose value is '$value' cannot be specified for tiles",
      );
    }
    tileDef ??= List<T?>.filled(nTiles, null);
    for (var c = 0; c < nComp; c++) {
      if (specValType[tile][c] < specTileDef) {
        specValType[tile][c] = specTileDef;
      }
    }
    tileDef![tile] = value;
  }

  T? getTileDef(int tile) {
    if (specType == specTypeComp) {
      throw StateError('Illegal use of ModuleSpec for tile query');
    }
    if (tileDef == null || tileDef![tile] == null) {
      return def;
    }
    return tileDef![tile];
  }

  void setTileCompVal(int tile, int component, T value) {
    if (specType != specTypeTileComp) {
      final buffer = StringBuffer()
        ..write("Option whose value is '$value' cannot be specified for ");
      switch (specType) {
        case specTypeTile:
          buffer.write('components as it is tile-only');
          break;
        case specTypeComp:
          buffer.write('tiles as it is component-only');
          break;
      }
      throw StateError(buffer.toString());
    }
    tileCompVal ??= <String, T>{};
    specValType[tile][component] = specTileComp;
    tileCompVal!['t${tile}c$component'] = value;
  }

  T? getTileCompVal(int tile, int component) {
    if (specType != specTypeTileComp) {
      throw StateError('Illegal use of ModuleSpec for tile-component query');
    }
    return getSpec(tile, component);
  }

  T? getSpec(int tile, int component) {
    switch (specValType[tile][component]) {
      case specDef:
        return def;
      case specCompDef:
        return getCompDef(component);
      case specTileDef:
        return getTileDef(tile);
      case specTileComp:
        return tileCompVal?['t${tile}c$component'];
      default:
        throw ArgumentError('Unrecognised spec type');
    }
  }

  int getSpecValType(int tile, int component) => specValType[tile][component];

  bool isCompSpecified(int component) =>
      compDef != null && compDef![component] != null;

  bool isTileSpecified(int tile) => tileDef != null && tileDef![tile] != null;

  bool isTileCompSpecified(int tile, int component) {
    if (tileCompVal == null) {
      return false;
    }
    return tileCompVal!.containsKey('t${tile}c$component');
  }

  static List<bool> parseIdx(String token, int maxIdx) {
    final indexes = List<bool>.filled(maxIdx, false);
    var current = -1;
    var last = -1;
    var dash = false;

    for (var i = 1; i < token.length; i++) {
      final codeUnit = token.codeUnitAt(i);
      final char = String.fromCharCode(codeUnit);
      if (codeUnit >= 0x30 && codeUnit <= 0x39) {
        current =
            current == -1 ? codeUnit - 0x30 : current * 10 + (codeUnit - 0x30);
      } else {
        if (current == -1 || (char != ',' && char != '-')) {
          throw ArgumentError('Bad construction for parameter: $token');
        }
        if (current < 0 || current >= maxIdx) {
          throw ArgumentError(
              'Index out of range in parameter $token: $current');
        }
        if (char == ',') {
          if (dash) {
            for (var j = last + 1; j < current; j++) {
              indexes[j] = true;
            }
          }
          dash = false;
        } else {
          dash = true;
        }
        indexes[current] = true;
        last = current;
        current = -1;
      }
    }

    if (current < 0 || current >= maxIdx) {
      throw ArgumentError('Index out of range in parameter $token: $current');
    }
    if (dash) {
      for (var j = last + 1; j < current; j++) {
        indexes[j] = true;
      }
    }
    indexes[current] = true;
    return indexes;
  }
}

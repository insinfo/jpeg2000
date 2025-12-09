import '../../ModuleSpec.dart';
import 'SynWTFilter.dart';

/// Specification container for synthesis wavelet filters per tile/component.
class SynWTFilterSpec extends ModuleSpec<List<List<SynWTFilter>>> {
  SynWTFilterSpec(int numTiles, int numComps, int specType)
      : super(numTiles, numComps, specType);

  /// Returns the data type advertised by the filters for the given tile/component.
  int getWTDataType(int tile, int component) {
    final filters = _getFilters(tile, component);
    if (filters.isEmpty || filters[0].isEmpty) {
      throw StateError('Missing synthesis filter configuration for tile=$tile component=$component');
    }
    return filters[0][0].getDataType();
  }

  /// Returns the horizontal synthesis filters for the tile/component pair.
  List<SynWTFilter> getHFilters(int tile, int component) {
    final filters = _getFilters(tile, component);
    if (filters.isEmpty) {
      throw StateError('No synthesis filters configured for tile=$tile component=$component');
    }
    return filters[0];
  }

  /// Returns the vertical synthesis filters for the tile/component pair.
  List<SynWTFilter> getVFilters(int tile, int component) {
    final filters = _getFilters(tile, component);
    if (filters.length < 2) {
      throw StateError('Incomplete synthesis filter pair for tile=$tile component=$component');
    }
    return filters[1];
  }

  /// Reports whether the configured filters for the tile/component are reversible.
  bool isReversible(int tile, int component) {
    final hFilters = getHFilters(tile, component);
    final vFilters = getVFilters(tile, component);
    final length = hFilters.length < vFilters.length ? hFilters.length : vFilters.length;
    for (var i = 0; i < length; i++) {
      if (!hFilters[i].isReversible() || !vFilters[i].isReversible()) {
        return false;
      }
    }
    return true;
  }

  List<List<SynWTFilter>> _getFilters(int tile, int component) {
    final filters = getSpec(tile, component);
    if (filters == null) {
      throw StateError('Synthesis filter specification missing for tile=$tile component=$component');
    }
    return filters;
  }

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('nTiles=$nTiles')
      ..writeln('nComp=$nComp')
      ..writeln();
    for (var t = 0; t < nTiles; t++) {
      for (var c = 0; c < nComp; c++) {
        final filters = _getFilters(t, c);
        buffer
          ..writeln('(t:$t,c:$c)')
          ..write('\tH:');
        for (final filter in filters.isNotEmpty ? filters[0] : const <SynWTFilter>[]) {
          buffer.write(' $filter');
        }
        buffer.write('\n\tV:');
        if (filters.length > 1) {
          for (final filter in filters[1]) {
            buffer.write(' $filter');
          }
        }
        buffer.writeln();
      }
    }
    return buffer.toString();
  }
}


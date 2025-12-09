import '../../util/ArrayUtil.dart';
import 'PktHeaderBitReader.dart';

/// Decoder for JPEG 2000 tag trees.
class TagTreeDecoder {
  factory TagTreeDecoder(int height, int width) {
    if (width < 0 || height < 0) {
      throw ArgumentError('TagTree dimensions must be non-negative');
    }
    final levels = _computeLevels(height, width);
    final decoder = TagTreeDecoder._(height, width, levels);
    decoder._initialiseLevels();
    return decoder;
  }

  TagTreeDecoder._(this._height, this._width, int levels)
      : _levels = levels,
        _values = List<List<int>>.generate(levels, (_) => <int>[], growable: false),
        _states = List<List<int>>.generate(levels, (_) => <int>[], growable: false);

  final int _width;
  final int _height;
  final int _levels;
  final List<List<int>> _values;
  final List<List<int>> _states;

  int get width => _width;
  int get height => _height;

  int update(int m, int n, int threshold, PktHeaderBitReader reader) {
    if (m >= _height || n >= _width || threshold < 0) {
      throw ArgumentError('Invalid coordinates or threshold for tag-tree update');
    }

    var level = _levels - 1;
    var tMin = _states[level][0];
    var idx = _indexFor(level, m, n);

    while (true) {
      var state = _states[level][idx];
      var value = _values[level][idx];
      if (state < tMin) {
        state = tMin;
      }
      while (threshold > state) {
        if (value >= state) {
          if (reader.readBit() == 0) {
            state++;
          } else {
            value = state++;
          }
        } else {
          state = threshold;
          break;
        }
      }
      _states[level][idx] = state;
      _values[level][idx] = value;

      if (level == 0) {
        return value;
      }

      tMin = state < value ? state : value;
      level--;
      idx = _indexFor(level, m, n);
    }
  }

  int getValue(int m, int n) {
    if (m >= _height || n >= _width) {
      throw ArgumentError('Invalid coordinates for tag-tree value');
    }
    return _values[0][m * _width + n];
  }

  void _initialiseLevels() {
    var levelWidth = _width;
    var levelHeight = _height;
    for (var level = 0; level < _levels; level++) {
      final size = levelWidth * levelHeight;
      final values = List<int>.filled(size, 0);
      final states = List<int>.filled(size, 0);
      ArrayUtil.intArraySet(values, 0x7fffffff);
      _values[level] = values;
      _states[level] = states;
      levelWidth = (levelWidth + 1) >> 1;
      levelHeight = (levelHeight + 1) >> 1;
    }
  }

  int _indexFor(int level, int m, int n) {
    final shift = level;
    final cols = (_width + (1 << level) - 1) >> level;
    final row = m >> shift;
    final col = n >> shift;
    return row * cols + col;
  }

  static int _computeLevels(int height, int width) {
    if (height == 0 || width == 0) {
      return 0;
    }
    var lvls = 1;
    var h = height;
    var w = width;
    while (h != 1 || w != 1) {
      w = (w + 1) >> 1;
      h = (h + 1) >> 1;
      lvls++;
    }
    return lvls;
  }
}


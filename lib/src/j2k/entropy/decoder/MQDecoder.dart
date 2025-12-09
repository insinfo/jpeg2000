import 'dart:typed_data';

import '../../util/ArrayUtil.dart';
import '../../util/Int32Utils.dart';
import 'ByteInputBuffer.dart';

/// Software-convention implementation of the JPEG 2000 MQ arithmetic decoder.
///
/// The class mirrors the JJ2000 reference closely to ensure the bit-exact
/// behaviour required by the JPX entropy pipeline. Optimisations such as the
/// "fast decode" path are preserved to keep throughput in line with the
/// original Java implementation.
class MQDecoder {
  MQDecoder(ByteInputBuffer input, int numContexts, List<int> initialStates)
      : _input = input,
        _mps = List<int>.filled(numContexts, 0, growable: false),
        _states = List<int>.filled(numContexts, 0, growable: false),
        _initialStates = List<int>.from(initialStates, growable: false) {
    _initDecoder();
    resetCtxts();
  }

  // Probability tables (Qe values and state transitions) copied from JJ2000.
  static const List<int> _qe = <int>[
    0x5601,
    0x3401,
    0x1801,
    0x0ac1,
    0x0521,
    0x0221,
    0x5601,
    0x5401,
    0x4801,
    0x3801,
    0x3001,
    0x2401,
    0x1c01,
    0x1601,
    0x5601,
    0x5401,
    0x5101,
    0x4801,
    0x3801,
    0x3401,
    0x3001,
    0x2801,
    0x2401,
    0x2201,
    0x1c01,
    0x1801,
    0x1601,
    0x1401,
    0x1201,
    0x1101,
    0x0ac1,
    0x09c1,
    0x08a1,
    0x0521,
    0x0441,
    0x02a1,
    0x0221,
    0x0141,
    0x0111,
    0x0085,
    0x0049,
    0x0025,
    0x0015,
    0x0009,
    0x0005,
    0x0001,
    0x5601,
  ];

  static const List<int> _nextMps = <int>[
    1,
    2,
    3,
    4,
    5,
    38,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    29,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    45,
    46,
  ];

  static const List<int> _nextLps = <int>[
    1,
    6,
    9,
    12,
    29,
    33,
    6,
    14,
    14,
    14,
    17,
    18,
    20,
    21,
    14,
    14,
    15,
    16,
    17,
    18,
    19,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    46,
  ];

  static const List<int> _switchLM = <int>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  final ByteInputBuffer _input;
  final List<int> _mps;
  final List<int> _states;
  final List<int> _initialStates;

  int _codeRegister = 0;
  int _codeBits = 0;
  int _interval = 0;
  int _lastByte = 0;
  bool _markerFound = false;
  String? _traceLabel;
  int _traceLimit = 0;
  List<int>? _traceData;
  bool _traceTruncated = false;

  /// Fast path that decodes [n] symbols from [context] assuming a long run of
  /// most-probable symbols. Returns true if all decoded symbols are identical
  /// (stored in [bits][0]).
  bool fastDecodeSymbols(List<int> bits, int context, int n) {
    var idx = _states[context];
    var q = _qe[idx];

    if (q < 0x4000 && n <= (_interval - (_codeRegister >>> 16) - 1) ~/ q &&
        n <= (_interval - 0x8000) ~/ q + 1) {
      _interval -= n * q;
      if (_interval >= 0x8000) {
        bits[0] = _mps[context];
        return true;
      }

      _states[context] = _nextMps[idx];
      if (_codeBits == 0) {
        _byteIn();
      }
      _interval <<= 1;
      _codeRegister = Int32Utils.mask32(_codeRegister << 1);
      _codeBits--;
      bits[0] = _mps[context];
      return true;
    }

    var localInterval = _interval;
    var localCode = _codeRegister;
    var localBits = _codeBits;

    for (var i = 0; i < n; i++) {
      localInterval -= q;
      if ((localCode >>> 16) < localInterval) {
        if (localInterval >= 0x8000) {
          bits[i] = _mps[context];
        } else {
          if (localInterval >= q) {
            bits[i] = _mps[context];
            idx = _nextMps[idx];
            q = _qe[idx];
            if (localBits == 0) {
              _codeRegister = localCode;
              _byteIn();
              localCode = _codeRegister;
              localBits = _codeBits;
            }
            localInterval <<= 1;
            localCode = Int32Utils.mask32(localCode << 1);
            localBits--;
          } else {
            bits[i] = 1 - _mps[context];
            if (_switchLM[idx] == 1) {
              _mps[context] = 1 - _mps[context];
            }
            idx = _nextLps[idx];
            q = _qe[idx];
            do {
              if (localBits == 0) {
                _codeRegister = localCode;
                _byteIn();
                localCode = _codeRegister;
                localBits = _codeBits;
              }
              localInterval <<= 1;
              localCode = Int32Utils.mask32(localCode << 1);
              localBits--;
            } while (localInterval < 0x8000);
          }
        }
      } else {
        localCode = Int32Utils.mask32(localCode - (localInterval << 16));
        if (localInterval < q) {
          localInterval = q;
          bits[i] = _mps[context];
          idx = _nextMps[idx];
          q = _qe[idx];
          if (localBits == 0) {
            _codeRegister = localCode;
            _byteIn();
            localCode = _codeRegister;
            localBits = _codeBits;
          }
          localInterval <<= 1;
          localCode = Int32Utils.mask32(localCode << 1);
          localBits--;
        } else {
          localInterval = q;
          bits[i] = 1 - _mps[context];
          if (_switchLM[idx] == 1) {
            _mps[context] = 1 - _mps[context];
          }
          idx = _nextLps[idx];
          q = _qe[idx];
          do {
            if (localBits == 0) {
              _codeRegister = localCode;
              _byteIn();
              localCode = _codeRegister;
              localBits = _codeBits;
            }
            localInterval <<= 1;
            localCode = Int32Utils.mask32(localCode << 1);
            localBits--;
          } while (localInterval < 0x8000);
        }
      }
    }

    _interval = localInterval;
    _codeRegister = localCode;
    _codeBits = localBits;
    _states[context] = idx;
    return false;
  }

  /// Decodes [n] symbols using the supplied context sequence [contexts].
  void decodeSymbols(List<int> bits, List<int> contexts, int n) {
    var localInterval = _interval;
    var localCode = _codeRegister;
    var localBits = _codeBits;

    for (var i = 0; i < n; i++) {
      final context = contexts[i];
      var idx = _states[context];
      var q = _qe[idx];

      localInterval -= q;
      if ((localCode >>> 16) < localInterval) {
        if (localInterval >= 0x8000) {
          bits[i] = _mps[context];
        } else {
          if (localInterval >= q) {
            bits[i] = _mps[context];
            _states[context] = _nextMps[idx];
            if (localBits == 0) {
              _codeRegister = localCode;
              _byteIn();
              localCode = _codeRegister;
              localBits = _codeBits;
            }
            localInterval <<= 1;
            localCode = Int32Utils.mask32(localCode << 1);
            localBits--;
          } else {
            bits[i] = 1 - _mps[context];
            if (_switchLM[idx] == 1) {
              _mps[context] = 1 - _mps[context];
            }
            _states[context] = _nextLps[idx];
            do {
              if (localBits == 0) {
                _codeRegister = localCode;
                _byteIn();
                localCode = _codeRegister;
                localBits = _codeBits;
              }
              localInterval <<= 1;
              localCode = Int32Utils.mask32(localCode << 1);
              localBits--;
            } while (localInterval < 0x8000);
          }
        }
      } else {
        localCode = Int32Utils.mask32(localCode - (localInterval << 16));
        if (localInterval < q) {
          localInterval = q;
          bits[i] = _mps[context];
          _states[context] = _nextMps[idx];
          if (localBits == 0) {
            _codeRegister = localCode;
            _byteIn();
            localCode = _codeRegister;
            localBits = _codeBits;
          }
          localInterval <<= 1;
          localCode = Int32Utils.mask32(localCode << 1);
          localBits--;
        } else {
          localInterval = q;
          bits[i] = 1 - _mps[context];
          if (_switchLM[idx] == 1) {
            _mps[context] = 1 - _mps[context];
          }
          _states[context] = _nextLps[idx];
          do {
            if (localBits == 0) {
              _codeRegister = localCode;
              _byteIn();
              localCode = _codeRegister;
              localBits = _codeBits;
            }
            localInterval <<= 1;
            localCode = Int32Utils.mask32(localCode << 1);
            localBits--;
          } while (localInterval < 0x8000);
        }
      }
    }

    _interval = localInterval;
    _codeRegister = localCode;
    _codeBits = localBits;
  }

  /// Decodes a single symbol using [context].
  int decodeSymbol(int context) {
    final index = _states[context];
    final q = _qe[index];
    _interval -= q;
    int decision;

    if ((_codeRegister >>> 16) < _interval) {
      if (_interval >= 0x8000) {
        decision = _mps[context];
      } else {
        var la = _interval;
        if (la >= q) {
          decision = _mps[context];
          _states[context] = _nextMps[index];
          if (_codeBits == 0) {
            _byteIn();
          }
          la <<= 1;
          _codeRegister = Int32Utils.mask32(_codeRegister << 1);
          _codeBits--;
        } else {
          decision = 1 - _mps[context];
          if (_switchLM[index] == 1) {
            _mps[context] = 1 - _mps[context];
          }
          _states[context] = _nextLps[index];
          do {
            if (_codeBits == 0) {
              _byteIn();
            }
            la <<= 1;
            _codeRegister = Int32Utils.mask32(_codeRegister << 1);
            _codeBits--;
          } while (la < 0x8000);
        }
        _interval = la;
      }
    } else {
      var la = _interval;
      _codeRegister = Int32Utils.mask32(_codeRegister - (la << 16));
      if (la < q) {
        la = q;
        decision = _mps[context];
        _states[context] = _nextMps[index];
        if (_codeBits == 0) {
          _byteIn();
        }
        la <<= 1;
        _codeRegister = Int32Utils.mask32(_codeRegister << 1);
        _codeBits--;
      } else {
        la = q;
        decision = 1 - _mps[context];
        if (_switchLM[index] == 1) {
          _mps[context] = 1 - _mps[context];
        }
        _states[context] = _nextLps[index];
        do {
          if (_codeBits == 0) {
            _byteIn();
          }
          la <<= 1;
          _codeRegister = Int32Utils.mask32(_codeRegister << 1);
          _codeBits--;
        } while (la < 0x8000);
      }
      _interval = la;
    }

    _recordTrace(context, decision);
    return decision;
  }

  void startTrace(String label, int limit) {
    if (limit <= 0) {
      _traceLabel = null;
      _traceLimit = 0;
      _traceData = null;
      return;
    }
    _traceLabel = label;
    _traceLimit = limit;
    _traceData = <int>[];
    _traceTruncated = false;
  }

  String? drainTrace() {
    final data = _traceData;
    if (data == null) {
      _traceLabel = null;
      _traceLimit = 0;
      _traceTruncated = false;
      return null;
    }
    final label = _traceLabel ?? '';
    if (data.isEmpty) {
      _traceLabel = null;
      _traceLimit = 0;
      _traceData = null;
      _traceTruncated = false;
      return 'label=$label count=0';
    }
    final buffer = StringBuffer()
      ..write('label=$label count=${data.length ~/ 2} truncated=$_traceTruncated entries=');
    for (var i = 0; i < data.length; i += 2) {
      if (i > 0) {
        buffer.write(' ');
      }
      buffer
        ..write('[')
        ..write(data[i])
        ..write(':')
        ..write(data[i + 1])
        ..write(']');
    }
    _traceLabel = null;
    _traceLimit = 0;
    _traceData = null;
    _traceTruncated = false;
    return buffer.toString();
  }

  void _recordTrace(int context, int decision) {
    final data = _traceData;
    if (data == null) {
      return;
    }
    if (data.length >= _traceLimit * 2) {
      _traceTruncated = true;
      return;
    }
    data..add(context)..add(decision & 1);
  }

  /// Validates predictable termination (Annex D.4.2). Returns true when an
  /// error is detected in the MQ terminated segment.
  bool checkPredTerm() {
    if (_lastByte != 0xFF && !_markerFound) {
      return true;
    }
    if (_codeBits != 0 && !_markerFound) {
      return true;
    }
    if (_codeBits == 1) {
      return false;
    }
    if (_codeBits == 0) {
      if (!_markerFound) {
        _lastByte = _readByte();
        if (_lastByte <= 0x8F) {
          return true;
        }
      }
      _codeBits = 8;
    }

    final k = _codeBits - 1;
    final q = 0x8000 >> k;

    _interval -= q;
    if ((_codeRegister >>> 16) < _interval) {
      return true;
    }

    _codeRegister = Int32Utils.mask32(_codeRegister - (_interval << 16));
    _interval = q;
    do {
      if (_codeBits == 0) {
        _byteIn();
      }
      _interval <<= 1;
      _codeRegister = Int32Utils.mask32(_codeRegister << 1);
      _codeBits--;
    } while (_interval < 0x8000);

    return false;
  }

  /// Returns the number of registered contexts.
  int getNumCtxts() => _states.length;

  /// Resets a single [context] back to its initial state.
  void resetCtxt(int context) {
    _states[context] = _initialStates[context];
    _mps[context] = 0;
  }

  /// Resets all contexts back to their initial states.
  void resetCtxts() {
    for (var i = 0; i < _states.length; i++) {
      _states[i] = _initialStates[i];
    }
    ArrayUtil.intArraySet(_mps, 0);
  }

  /// Starts decoding a new arithmetic coding segment.
  void nextSegment(Uint8List? buffer, int offset, int length) {
    _input.setByteArray(buffer, offset, length);
    _initDecoder();
  }

  /// Exposes the underlying byte-oriented buffer for raw bypass decoding.
  ByteInputBuffer getByteInputBuffer() => _input;

  void _initDecoder() {
    _markerFound = false;
    _lastByte = _readByte();
    _codeRegister = (_lastByte ^ 0xFF) << 16;
    _byteIn();
    _codeRegister = Int32Utils.mask32(_codeRegister << 7);
    _codeBits = _codeBits - 7;  // _codeBits foi definido por _byteIn() acima
    _interval = 0x8000;
  }

  void _byteIn() {
    if (!_markerFound) {
      if (_lastByte == 0xFF) {
        _lastByte = _readByte();
        if (_lastByte > 0x8F) {
          _markerFound = true;
          _codeBits = 8;
        } else {
          _codeRegister = Int32Utils.mask32(
            _codeRegister + 0xFE00 - (_lastByte << 9),
          );
          _codeBits = 7;
        }
      } else {
        _lastByte = _readByte();
        _codeRegister = Int32Utils.mask32(
          _codeRegister + 0xFF00 - (_lastByte << 8),
        );
        _codeBits = 8;
      }
    } else {
      _codeBits = 8;
    }
  }

  int _readByte() {
    final b = _input.read();
    return b == -1 ? 0xFF : b;
  }
}


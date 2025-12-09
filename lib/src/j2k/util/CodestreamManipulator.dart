import 'dart:typed_data';

import '../codestream/markers.dart';
import '../io/BeBufferedRandomAccessFile.dart';
import '../io/BufferedRandomAccessFile.dart';

/// Rewrites codestream structures (tile-parts, packed packet headers) to match
/// the manipulations performed by the original JJ2000 implementation.
///
/// Most callers rely on this utility when they need to emit codestreams with
/// tile-parts or packed packet headers after the encoder already produced a
/// valid JPEG 2000 stream. The port keeps the mutable state from the Java
/// version so higher-level code can continue to queue operations in the same
/// order. The actual byte-level layout matches the reference implementation,
/// but the threading-specific code paths (synchronisation around I/O) are not
/// required on Dart and were omitted.
class CodestreamManipulator {
  CodestreamManipulator(
    this._outName,
    this._numTiles,
    this._packetsPerTilePart,
    this._ppmUsed,
    this._pptUsed,
    this._tempSop,
    this._tempEph,
  );

  static const int _tilePartHeaderLength = 14;

  final String _outName;
  final int _numTiles;
  final int _packetsPerTilePart;
  final bool _ppmUsed;
  final bool _pptUsed;
  final bool _tempSop;
  final bool _tempEph;

  late List<int> _packetsPerTile;
  late List<int> _markerPositions;
  late Uint8List _mainHeader;
  late List<List<Uint8List>> _tileParts;
  late List<Uint8List> _tileHeaders;
  late List<List<Uint8List>> _packetHeaders;
  late List<List<Uint8List>> _packetData;
  late List<List<Uint8List?>> _sopMarkerSegments;
  int _maxTileParts = 0;

  /// Performs the manipulation and returns the delta of the codestream size.
  int doCodestreamManipulation() {
    if (!_ppmUsed && !_pptUsed && _packetsPerTilePart == 0) {
      return 0;
    }

    final file = BEBufferedRandomAccessFile.path(_outName, 'rw+');
    var byteDelta = -file.length();

    try {
      _parseAndFind(file);
      _readAndBuffer(file);
    } finally {
      file.close();
    }

    final writer = BEBufferedRandomAccessFile.path(_outName, 'rw');
    try {
      _createTileParts();
      _writeNewCodestream(writer);
      writer.flush();
      byteDelta += writer.length();
    } finally {
      writer.close();
    }

    return byteDelta;
  }

  void _parseAndFind(BufferedRandomAccessFile file) {
    final markerPositions = <int>[];
    _packetsPerTile = List<int>.filled(_numTiles, 0);

    file.readUnsignedShort(); // SOC
    var marker = file.readUnsignedShort();
    while (marker != Markers.SOT) {
      final pos = file.getPos();
      final length = file.readUnsignedShort();

      if (marker == Markers.COD) {
        final scod = file.readUnsignedByte();
        final updated = (scod & (_tempSop ? 0xfd : 0xff)) & (_tempEph ? 0xfb : 0xff);
        if (updated != scod) {
          file.seek(pos + 2);
          file.write(updated);
        }
      }

      file.seek(pos + length);
      marker = file.readUnsignedShort();
    }

    var pos = file.getPos();
    file.seek(pos - 2);

    for (var tile = 0; tile < _numTiles; tile++) {
      file.readUnsignedShort(); // SOT
      pos = file.getPos();
      markerPositions.add(pos);
      file.readInt(); // Lsot + Isot
      final length = file.readInt();
      file.readUnsignedShort();
      final tileEnd = pos + length - 2;

      marker = file.readUnsignedShort();
      while (marker != Markers.SOD) {
        final innerPos = file.getPos();
        final innerLength = file.readUnsignedShort();

        if (marker == Markers.COD) {
          final scod = file.readUnsignedByte();
          final updated = (scod & (_tempSop ? 0xfd : 0xff)) & (_tempEph ? 0xfb : 0xff);
          if (updated != scod) {
            file.seek(innerPos + 2);
            file.write(updated);
          }
        }

        file.seek(innerPos + innerLength);
        marker = file.readUnsignedShort();
      }

      var index = file.getPos();
      while (index < tileEnd) {
        final halfMarker = file.readUnsignedByte();
        if (halfMarker == 0xff) {
          marker = (halfMarker << 8) | file.readUnsignedByte();
          index++;
          if (marker == Markers.SOP) {
            markerPositions.add(file.getPos());
            _packetsPerTile[tile]++;
            file.skipBytes(Markers.SOP_LENGTH - 2);
            index += Markers.SOP_LENGTH - 2;
          } else if (marker == Markers.EPH) {
            markerPositions.add(file.getPos());
          }
        }
        index++;
      }
    }

    markerPositions.add(file.getPos() + 2);
    _markerPositions = List<int>.from(markerPositions);
  }

  void _readAndBuffer(BufferedRandomAccessFile file) {
    _tileParts = List<List<Uint8List>>.generate(_numTiles, (_) => <Uint8List>[]);
    _tileHeaders = List<Uint8List>.generate(_numTiles, (_) => Uint8List(0));
    _packetHeaders =
        List<List<Uint8List>>.generate(_numTiles, (_) => <Uint8List>[]);
    _packetData =
        List<List<Uint8List>>.generate(_numTiles, (_) => <Uint8List>[]);
    _sopMarkerSegments =
        List<List<Uint8List?>>.generate(_numTiles, (_) => <Uint8List?>[]);

    file.seek(0);
    final headerLength = _markerPositions[0] - 2;
    final mainHeader = Uint8List(headerLength);
    file.readFully(mainHeader, 0, headerLength);
    _mainHeader = mainHeader;

    var markerIndex = 0;

    for (var tile = 0; tile < _numTiles; tile++) {
      final totalPackets = _packetsPerTile[tile];

      final tileHeaderLength = _markerPositions[markerIndex + 1] - _markerPositions[markerIndex];
      final tileHeader = Uint8List(tileHeaderLength);
      file.readFully(tileHeader, 0, tileHeaderLength);
      markerIndex++;

      final headers = List<Uint8List>.generate(totalPackets, (_) => Uint8List(0));
      final data = List<Uint8List>.generate(totalPackets, (_) => Uint8List(0));
      final sopSegments = List<Uint8List?>.filled(totalPackets, null);

      for (var packet = 0; packet < totalPackets; packet++) {
        var length = _markerPositions[markerIndex + 1] - _markerPositions[markerIndex];

        if (_tempSop) {
          length -= Markers.SOP_LENGTH;
          file.skipBytes(Markers.SOP_LENGTH);
        } else {
          length -= Markers.SOP_LENGTH;
          final sopBytes = Uint8List(Markers.SOP_LENGTH);
          file.readFully(sopBytes, 0, sopBytes.length);
          sopSegments[packet] = sopBytes;
        }

        if (!_tempEph) {
          length += Markers.EPH_LENGTH;
        }

        final headerBytes = Uint8List(length);
        file.readFully(headerBytes, 0, length);
        headers[packet] = headerBytes;
        markerIndex++;

        var dataLength = _markerPositions[markerIndex + 1] - _markerPositions[markerIndex];
        dataLength -= Markers.EPH_LENGTH;
        if (_tempEph) {
          file.skipBytes(Markers.EPH_LENGTH);
        }
        final dataBytes = Uint8List(dataLength);
        file.readFully(dataBytes, 0, dataLength);
        data[packet] = dataBytes;
        markerIndex++;
      }

      _tileHeaders[tile] = tileHeader;
      _packetHeaders[tile] = headers;
      _packetData[tile] = data;
      _sopMarkerSegments[tile] = sopSegments;
    }
  }

  void _createTileParts() {
    _tileParts = List<List<Uint8List>>.generate(_numTiles, (_) => <Uint8List>[]);
    _maxTileParts = 0;

    for (var tile = 0; tile < _numTiles; tile++) {
      var remainingPackets = _packetsPerTile[tile];
      final packetsPerPart = _packetsPerTilePart == 0 ? remainingPackets : _packetsPerTilePart;
      final numTileParts = remainingPackets == 0
          ? 0
          : (remainingPackets / packetsPerPart).ceil();
      if (numTileParts > _maxTileParts) {
        _maxTileParts = numTileParts;
      }

      final tileParts = <Uint8List>[];
      var tilePartStart = 0;
      var packetIndex = 0;

      for (var tilePart = 0; tilePart < numTileParts; tilePart++) {
        final packetsThisPart = packetsPerPart > remainingPackets ? remainingPackets : packetsPerPart;
        var np = packetsThisPart;
        final builder = BytesBuilder();

        if (tilePart == 0) {
          builder.add(_tileHeaders[tile].sublist(0, _tileHeaders[tile].length - 2));
        } else {
          builder.add(Uint8List(_tilePartHeaderLength - 2));
        }

        if (_pptUsed) {
          var pptLength = 3;
          var pptIndex = 0;
          var p = packetIndex;
          var remainingForMarker = np;

          while (remainingForMarker > 0) {
            final headerLength = _packetHeaders[tile][p].length;
            if (pptLength + headerLength > Markers.MAX_LPPT) {
              _emitPptSegment(builder, tile, pptLength, pptIndex++, packetIndex, p);
              pptLength = 3;
              packetIndex = p;
            }
            pptLength += headerLength;
            p++;
            remainingForMarker--;
          }

          _emitPptSegment(builder, tile, pptLength, pptIndex, packetIndex, p);
          packetIndex = p;
        }

        builder.add([Markers.SOD >> 8, Markers.SOD & 0xff]);

        for (var packet = tilePartStart; packet < tilePartStart + np; packet++) {
          final sop = _sopMarkerSegments[tile][packet];
          if (!_tempSop && sop != null) {
            builder.add(sop);
          }

          if (!(_ppmUsed || _pptUsed)) {
            builder.add(_packetHeaders[tile][packet]);
          }

          builder.add(_packetData[tile][packet]);
        }

        final bytes = builder.takeBytes();
        if (tilePart == 0) {
          _writeIntToBuffer(bytes, 6, bytes.length);
          bytes[10] = 0;
          bytes[11] = numTileParts;
        } else {
          _writeShortToBuffer(bytes, 0, Markers.SOT);
          _writeShortToBuffer(bytes, 2, 10);
          _writeShortToBuffer(bytes, 4, tile);
          _writeIntToBuffer(bytes, 6, bytes.length);
          bytes[10] = tilePart;
          bytes[11] = numTileParts;
        }

        tileParts.add(Uint8List.fromList(bytes));
        tilePartStart += np;
        remainingPackets -= np;
      }

      _tileParts[tile] = tileParts;
    }
  }

  void _emitPptSegment(
    BytesBuilder builder,
    int tile,
    int length,
    int index,
    int start,
    int end,
  ) {
    builder.add([Markers.PPT >> 8, Markers.PPT & 0xff]);
    builder.add([(length >> 8) & 0xff, length & 0xff]);
    builder.add([index & 0xff]);
    for (var i = start; i < end; i++) {
      builder.add(_packetHeaders[tile][i]);
    }
  }

  void _writeNewCodestream(BEBufferedRandomAccessFile file) {
    file.writeBytes(_mainHeader, 0, _mainHeader.length);

    if (_ppmUsed) {
      final packetHeaderLengths = List.generate(
        _numTiles,
        (_) => List<int>.filled(_maxTileParts, 0),
      );

      final remaining = List<int>.generate(
        _numTiles,
        (index) => _packetHeaders[index].length,
      );

      for (var tilePart = 0; tilePart < _maxTileParts; tilePart++) {
        for (var tile = 0; tile < _numTiles; tile++) {
          if (_tileParts[tile].length <= tilePart) {
            continue;
          }
          final totalPackets = _packetHeaders[tile].length;
          final packetsInPart = tilePart == _tileParts[tile].length - 1
              ? remaining[tile]
              : (_packetsPerTilePart == 0 ? remaining[tile] : _packetsPerTilePart);

          final start = totalPackets - remaining[tile];
          final stop = start + packetsInPart;

          for (var packet = start; packet < stop; packet++) {
            packetHeaderLengths[tile][tilePart] += _packetHeaders[tile][packet].length;
          }

          remaining[tile] -= packetsInPart;
        }
      }

      final ppmBuilder = BytesBuilder();
      var ppmIndex = 0;
      var ppmLength = 3;
      final remainingForSegments = List<int>.generate(
        _numTiles,
        (index) => _packetHeaders[index].length,
      );

      ppmBuilder.add([Markers.PPM >> 8, Markers.PPM & 0xff, 0, 0, ppmIndex++]);

      for (var tilePart = 0; tilePart < _maxTileParts; tilePart++) {
        for (var tile = 0; tile < _numTiles; tile++) {
          if (_tileParts[tile].length <= tilePart) {
            continue;
          }
          final totalPackets = _packetHeaders[tile].length;
          final packetsInPart = tilePart == _tileParts[tile].length - 1
              ? remainingForSegments[tile]
              : (_packetsPerTilePart == 0 ? remainingForSegments[tile] : _packetsPerTilePart);

          final start = totalPackets - remainingForSegments[tile];
          final stop = start + packetsInPart;

          final headerLength = packetHeaderLengths[tile][tilePart];
          if (ppmLength + 4 > Markers.MAX_LPPM) {
            _flushPpm(file, ppmBuilder);
            ppmBuilder.add([Markers.PPM >> 8, Markers.PPM & 0xff, 0, 0, ppmIndex++]);
            ppmLength = 3;
          }

          ppmBuilder.add([
            (headerLength >> 24) & 0xff,
            (headerLength >> 16) & 0xff,
            (headerLength >> 8) & 0xff,
            headerLength & 0xff,
          ]);
          ppmLength += 4;

          for (var packet = start; packet < stop; packet++) {
            final headerBytes = _packetHeaders[tile][packet];
            if (ppmLength + headerBytes.length > Markers.MAX_LPPM) {
              _flushPpm(file, ppmBuilder);
              ppmBuilder.add([Markers.PPM >> 8, Markers.PPM & 0xff, 0, 0, ppmIndex++]);
              ppmLength = 3;
            }
            ppmBuilder.add(headerBytes);
            ppmLength += headerBytes.length;
          }

          remainingForSegments[tile] -= packetsInPart;
        }
      }

      _flushPpm(file, ppmBuilder);
    }

    for (var tilePart = 0; tilePart < _maxTileParts; tilePart++) {
      for (var tile = 0; tile < _numTiles; tile++) {
        if (_tileParts[tile].length <= tilePart) {
          continue;
        }
        final part = _tileParts[tile][tilePart];
        file.writeBytes(part, 0, part.length);
      }
    }

    file.writeShort(Markers.EOC);
  }

  void _flushPpm(BEBufferedRandomAccessFile file, BytesBuilder builder) {
    final bytes = builder.takeBytes();
    final actualLength = bytes.length - 2;
    bytes[2] = (actualLength >> 8) & 0xff;
    bytes[3] = actualLength & 0xff;
    file.writeBytes(bytes, 0, bytes.length);
  }

  void _writeIntToBuffer(List<int> buffer, int offset, int value) {
    buffer[offset] = (value >> 24) & 0xff;
    buffer[offset + 1] = (value >> 16) & 0xff;
    buffer[offset + 2] = (value >> 8) & 0xff;
    buffer[offset + 3] = value & 0xff;
  }

  void _writeShortToBuffer(List<int> buffer, int offset, int value) {
    buffer[offset] = (value >> 8) & 0xff;
    buffer[offset + 1] = value & 0xff;
  }
}


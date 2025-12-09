part of 'BitstreamReaderAgent.dart';

class PktDecoder {
  PktDecoder(
    this.decSpec,
    this.hd,
    this.ehs,
    this.src,
    this.isTruncMode,
    this.maxCB,
  ) : _headerReader = PktHeaderBitReader(ehs);

  final DecoderSpecs decSpec;
  final HeaderDecoder hd;
  final RandomAccessIO ehs;
  final BitstreamReaderAgent src;
  final bool isTruncMode;
  final int maxCB;

  static const int _initLBlock = 3;

  final PktHeaderBitReader _headerReader;
  PktHeaderBitReader? _packedHeaderReader;
  bool _usingPackedHeaders = false;

  late List<List<Coord>> _numPrecincts;
  late List<List<List<PrecInfo?>>> _precinctInfo;
  late List<List<List<List<List<int>>?>?>> _lblock;
  late List<List<List<List<TagTreeDecoder?>>>> _ttIncl;
  late List<List<List<List<TagTreeDecoder?>>>> _ttMaxBP;

  late List<List<CBlkCoordInfo>> _includedCodeBlocks;

  int _numLayers = 0;
  int _currentTileIdx = 0;

  bool _sopUsed = false;
  bool _ephUsed = false;

  int _packetIndex = 0;

  int _codeBlockCounter = 0;
  bool _ncbQuit = false;
  int _tileQuit = -1;
  int _compQuit = -1;
  int _subbandQuit = -1;
  int _resQuit = -1;
  int _xQuit = -1;
  int _yQuit = -1;

  bool get hasReachedNcbQuit => _ncbQuit;

  _CodeBlockGrid restart(
    int numComponents,
    List<int> maxDecompositionLevels,
    int numLayers,
    _CodeBlockGrid? existing,
    bool packedHeaders,
    Uint8List? packedHeaderData,
  ) {
    if (packedHeaders && packedHeaderData == null) {
      throw ArgumentError('Packed packet headers requested but no data provided');
    }

    _numLayers = numLayers;
    _currentTileIdx = src.getTileIdx();
    _usingPackedHeaders = packedHeaders;
    _packedHeaderReader = packedHeaders ? PktHeaderBitReader.fromBytes(packedHeaderData!) : null;

    final sopSpec = decSpec.sops.getTileDef(_currentTileIdx);
    _sopUsed = sopSpec is bool ? sopSpec : (sopSpec as bool? ?? false);
    final ephSpec = decSpec.ephs.getTileDef(_currentTileIdx);
    _ephUsed = ephSpec is bool ? ephSpec : (ephSpec as bool? ?? false);

    _packetIndex = 0;

    _includedCodeBlocks = List<List<CBlkCoordInfo>>.generate(4, (_) => <CBlkCoordInfo>[]);

    _numPrecincts = List<List<Coord>>.generate(
      numComponents,
      (c) => List<Coord>.generate(maxDecompositionLevels[c] + 1, (_) => Coord(), growable: false),
      growable: false,
    );

    _precinctInfo = List.generate(
      numComponents,
      (c) => List<List<PrecInfo?>>.generate(
        maxDecompositionLevels[c] + 1,
        (_) => <PrecInfo?>[],
        growable: false,
      ),
      growable: false,
    );

    _ttIncl = List.generate(
      numComponents,
      (c) => List<List<List<TagTreeDecoder?>>>.generate(
        maxDecompositionLevels[c] + 1,
        (_) => <List<TagTreeDecoder?>>[],
        growable: false,
      ),
      growable: false,
    );

    _ttMaxBP = List.generate(
      numComponents,
      (c) => List<List<List<TagTreeDecoder?>>>.generate(
        maxDecompositionLevels[c] + 1,
        (_) => <List<TagTreeDecoder?>>[],
        growable: false,
      ),
      growable: false,
    );

    _lblock = List.generate(
      numComponents,
      (c) => List<List<List<List<int>>?>?>.filled(
        maxDecompositionLevels[c] + 1,
        null,
        growable: false,
      ),
      growable: false,
    );

    final grid = List.generate(
      numComponents,
      (c) => List<List<List<List<CBlkInfo?>?>?>?>.filled(
        maxDecompositionLevels[c] + 1,
        null,
        growable: false,
      ),
      growable: false,
    );

    final cb0x = src.getCbULX();
    final cb0y = src.getCbULY();

    for (var comp = 0; comp < numComponents; comp++) {
      final maxResolutions = maxDecompositionLevels[comp];

      final tcx0 = src.getResULX(comp, maxResolutions);
      final tcy0 = src.getResULY(comp, maxResolutions);
      final tcx1 = tcx0 + src.getTileCompWidth(_currentTileIdx, comp, maxResolutions);
      final tcy1 = tcy0 + src.getTileCompHeight(_currentTileIdx, comp, maxResolutions);

      for (var res = 0; res <= maxResolutions; res++) {
        final mins = res == 0 ? 0 : 1;
        final maxs = res == 0 ? 1 : 4;

        final divisor = 1 << (maxResolutions - res);
        final trx0 = _ceilDivInt(tcx0, divisor);
        final try0 = _ceilDivInt(tcy0, divisor);
        final trx1 = _ceilDivInt(tcx1, divisor);
        final try1 = _ceilDivInt(tcy1, divisor);

        final ppx = getPPX(_currentTileIdx, comp, res);
        final ppy = getPPY(_currentTileIdx, comp, res);

        final numPrec = _numPrecincts[comp][res];
        if (trx1 > trx0) {
          numPrec.x = _ceilDivInt(trx1 - cb0x, ppx) - _floorDivInt(trx0 - cb0x, ppx);
        } else {
          numPrec.x = 0;
        }
        if (try1 > try0) {
          numPrec.y = _ceilDivInt(try1 - cb0y, ppy) - _floorDivInt(try0 - cb0y, ppy);
        } else {
          numPrec.y = 0;
        }

        final maxPrec = numPrec.x * numPrec.y;
        final precinctList = List<PrecInfo?>.filled(maxPrec, null, growable: false);
        _precinctInfo[comp][res] = precinctList;

        final inclByPrecinct = List<List<TagTreeDecoder?>>.generate(
          maxPrec,
          (_) => List<TagTreeDecoder?>.filled(maxs + 1, null, growable: false),
          growable: false,
        );
        final maxBpByPrecinct = List<List<TagTreeDecoder?>>.generate(
          maxPrec,
          (_) => List<TagTreeDecoder?>.filled(maxs + 1, null, growable: false),
          growable: false,
        );
        _ttIncl[comp][res] = inclByPrecinct;
        _ttMaxBP[comp][res] = maxBpByPrecinct;

        _fillPrecinctInfo(comp, res, maxResolutions);

        final root = src.getSynSubbandTree(_currentTileIdx, comp);

        final subbandEntries = List<List<List<CBlkInfo?>?>?>.filled(maxs + 1, null, growable: false);
        final lblockEntries = List<List<List<int>>?>.filled(maxs + 1, null, growable: false);

        for (var s = mins; s < maxs; s++) {
          final sb = root.getSubbandByIdx(res, s) as SubbandSyn?;
          if (sb == null) {
            continue;
          }
          final blocks = sb.numCb;
          if (blocks == null) {
            continue;
          }

          final rows = List<List<CBlkInfo?>?>.generate(
            blocks.y,
            (_) => List<CBlkInfo?>.filled(blocks.x, null, growable: false),
            growable: false,
          );
          subbandEntries[s] = rows;

          final lblockRows = List<List<int>>.generate(
            blocks.y,
            (_) => List<int>.filled(blocks.x, _initLBlock, growable: false),
            growable: false,
          );
          lblockEntries[s] = lblockRows;
        }

        grid[comp][res] = subbandEntries;
        _lblock[comp][res] = lblockEntries;
      }
    }

    return grid;
  }

  void syncHeaderReader() {
    _headerReader.sync();
    _packedHeaderReader?.sync();
  }

  PrecInfo getPrecInfo(int component, int resolution, int precinct) {
    if (component < 0 || component >= _precinctInfo.length) {
      throw ArgumentError('Component index out of range: $component');
    }
    final resolutions = _precinctInfo[component];
    if (resolution < 0 || resolution >= resolutions.length) {
      throw ArgumentError('Resolution index out of range: $resolution');
    }
    final precincts = resolutions[resolution];
    if (precinct < 0 || precinct >= precincts.length) {
      throw ArgumentError('Precinct index out of range: $precinct');
    }
    final info = precincts[precinct];
    if (info == null) {
      throw StateError('Precinct metadata not initialised (c:$component r:$resolution p:$precinct)');
    }
    return info;
  }

  int getNumPrecinct(int component, int resolution) {
    if (component < 0 || component >= _numPrecincts.length) {
      throw ArgumentError('Component index out of range: $component');
    }
    final resolutions = _numPrecincts[component];
    if (resolution < 0 || resolution >= resolutions.length) {
      throw ArgumentError('Resolution index out of range: $resolution');
    }
    final coord = resolutions[resolution];
    return coord.x * coord.y;
  }

  Coord getPrecinctGridSize(int component, int resolution) {
    if (component < 0 || component >= _numPrecincts.length) {
      throw ArgumentError('Component index out of range: $component');
    }
    final resolutions = _numPrecincts[component];
    if (resolution < 0 || resolution >= resolutions.length) {
      throw ArgumentError('Resolution index out of range: $resolution');
    }
    final coord = resolutions[resolution];
    return Coord.copy(coord);
  }

  bool readPktHead(
    int layer,
    int resolution,
    int component,
    int precinct,
    List<List<List<CBlkInfo?>?>?>? subbandBlocks,
    List<int> remainingBytesPerTile,
  ) {
    // print('PktDecoder: t=${src.getTileIdx()} c=$component r=$resolution p=$precinct l=$layer pktIdx=$_packetIndex offset=${ehs.getPos()}');

    final startOfHeader = ehs.getPos();
    if (startOfHeader >= ehs.length()) {
      return true;
    }

    if (component < 0 || component >= _precinctInfo.length) {
      throw ArgumentError('Component $component out of range');
    }
    if (resolution < 0 || resolution >= _precinctInfo[component].length) {
      throw ArgumentError('Resolution $resolution out of range for component $component');
    }

    final precinctList = _precinctInfo[component][resolution];
    if (precinct >= precinctList.length) {
      return false;
    }

    final precInfo = precinctList[precinct];
    if (precInfo == null) {
      return false;
    }

    final reader = _usingPackedHeaders ? _packedHeaderReader : _headerReader;
    if (reader == null) {
      throw StateError('Packed packet headers requested but not initialised');
    }
    reader.sync();

    final tileIdx = src.getTileIdx();
    final mins = resolution == 0 ? 0 : 1;
    final maxs = resolution == 0 ? 1 : 4;

      // Empty packet: nothing to decode beyond the inclusion bit.
    if (reader.readBit() == 0) {
      // print('PktDecoder: Empty packet');
      for (var s = mins; s < maxs; s++) {
        _includedCodeBlocks[s].clear();
      }
      _packetIndex++;

      final consumed = ehs.getPos() - startOfHeader;
      if (consumed > remainingBytesPerTile[tileIdx]) {
        remainingBytesPerTile[tileIdx] = 0;
        return true;
      }
      remainingBytesPerTile[tileIdx] -= consumed;

      if (_ephUsed) {
        // print('PktDecoder: Reading EPH (empty packet)');
        _readEphMarker(reader);
      }
      return false;
    }    final options = decSpec.ecopts.getTileCompVal(tileIdx, component) ?? 0;

    for (var list in _includedCodeBlocks) {
      list.clear();
    }

    for (var subband = mins; subband < maxs; subband++) {
      if (precInfo.nblk[subband] == 0) {
        continue;
      }

      final included = _includedCodeBlocks[subband];
      final tagIncl = _ttIncl[component][resolution][precinct][subband];
      final tagMax = _ttMaxBP[component][resolution][precinct][subband];
      final lblockBands = _lblock[component][resolution];
      if (tagIncl == null || tagMax == null || lblockBands == null) {
        continue;
      }
      if (subband >= lblockBands.length) {
        continue;
      }
      final lblockRows = lblockBands[subband];
      if (lblockRows == null) {
        continue;
      }
      final subbandGrid = subbandBlocks == null ? null : subbandBlocks[subband];

      final rows = precInfo.cblk[subband];
      if (rows.isEmpty) {
        continue;
      }

      for (var m = 0; m < rows.length; m++) {
        final row = rows[m];
        final lblockRowCandidate = m < lblockRows.length ? lblockRows[m] : null;
        if (row.isEmpty || lblockRowCandidate == null) {
          continue;
        }
        final lblockRow = lblockRowCandidate;

        for (var n = 0; n < row.length; n++) {
          final coord = row[n];
          if (coord == null) continue;
          final coordIdx = coord.idx;
          if (coordIdx.x >= lblockRow.length) {
            continue;
          }

          CBlkInfo? blockInfo;
          if (subbandGrid != null && coordIdx.y < subbandGrid.length) {
            final blockRow = subbandGrid[coordIdx.y];
            if (blockRow != null && coordIdx.x < blockRow.length) {
              blockInfo = blockRow[coordIdx.x];
              blockInfo ??= blockRow[coordIdx.x] =
                  CBlkInfo(coord.ulx, coord.uly, coord.w, coord.h, _numLayers);
            }
          }

          if (blockInfo == null) {
            continue;
          }

          try {
            if (blockInfo.ctp == 0) {
              blockInfo.pktIdx[layer] = _packetIndex;
              final inclusion = tagIncl.update(m, n, layer + 1, reader);
              // if (_packetIndex == 90) print('Pkt90: CB($m,$n) incl=$inclusion');
              if (inclusion > layer) {
                continue;
              }

              var threshold = 1;
              var value = 1;
              while (value >= threshold) {
                value = tagMax.update(m, n, threshold, reader);
                threshold++;
              }
              blockInfo.msbSkipped = threshold - 2;
              // if (_packetIndex == 90) print('Pkt90: CB($m,$n) msb=${blockInfo.msbSkipped}');
              blockInfo.addNTP(layer, 0);

              _codeBlockCounter++;
              if (maxCB != -1 && !_ncbQuit && _codeBlockCounter == maxCB) {
                _ncbQuit = true;
                _tileQuit = tileIdx;
                _compQuit = component;
                _subbandQuit = subband;
                _resQuit = resolution;
                _xQuit = coordIdx.x;
                _yQuit = coordIdx.y;
              }
            } else {
              blockInfo.pktIdx[layer] = _packetIndex;
              if (reader.readBit() == 0) {
                continue;
              }
            }

            blockInfo.len[layer] = 0;
            blockInfo.segLen[layer] = null;

            var newTruncPoints = 1;
            if (reader.readBit() == 1) {
              newTruncPoints++;
              if (reader.readBit() == 1) {
                newTruncPoints++;
                var extra = reader.readBits(2);
                newTruncPoints += extra;
                if (extra == 0x3) {
                  extra = reader.readBits(5);
                  newTruncPoints += extra;
                  if (extra == 0x1f) {
                    newTruncPoints += reader.readBits(7);
                  }
                }
              }
            }

            blockInfo.addNTP(layer, newTruncPoints);
            // if (_packetIndex == 90) print('Pkt90: CB($m,$n) ntp=$newTruncPoints');
            included.add(coord);

            // if (_packetIndex == 90) print('Pkt90: c=$component r=$resolution s=$subband CB($m,$n) lblock_before=${lblockRow[coordIdx.x]}');
            while (reader.readBit() == 1) {
              lblockRow[coordIdx.x]++;
            }

            final baseLengthBits = lblockRow[coordIdx.x] + MathUtil.log2(newTruncPoints);
            final segmentCount = _computeSegmentCount(blockInfo, newTruncPoints, options);

            if (DecoderInstrumentation.isEnabled()) {
              DecoderInstrumentation.log(
                'PktDecoder',
                'pkt=$_packetIndex tile=$tileIdx comp=$component res=$resolution band=$subband '
                'block=${coordIdx.x}x${coordIdx.y} layer=$layer newTruncPoints=$newTruncPoints '
                'lblock=${lblockRow[coordIdx.x]} baseBits=$baseLengthBits segments=$segmentCount',
              );
            }

            if (segmentCount == 1) {
              blockInfo.len[layer] = reader.readBits(baseLengthBits);
              // if (_packetIndex == 90) print('Pkt90: CB($m,$n) len=${blockInfo.len[layer]}');
              if (blockInfo.len[layer] > 32768) {
                // final tileIdx = src.getTileIdx();
                /*
                print(
                  'PktDecoder header len anomaly: tile=$tileIdx layer=$layer res=$resolution comp=$component '
                  'precinct=$precinct subband=$subband block=${coordIdx.x}x${coordIdx.y} '
                  'len=${blockInfo.len[layer]} bits=$baseLengthBits lblock=${lblockRow[coordIdx.x]} '
                  'newTruncPoints=$newTruncPoints',
                );
                */
              }
            } else {
              final lengths = List<int>.filled(segmentCount, 0, growable: false);
              blockInfo.segLen[layer] = lengths;
              var tpIndex = blockInfo.ctp - newTruncPoints;
              var lastTerminated = blockInfo.ctp - newTruncPoints - 1;
              var cursor = 0;

              if ((options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
                while (cursor < segmentCount) {
                  final value = reader.readBits(lblockRow[coordIdx.x]);
                  lengths[cursor++] = value;
                  blockInfo.len[layer] += value;
                }
              } else {
                while (cursor < segmentCount - 1) {
                  if (tpIndex >= StdEntropyCoderOptions.FIRST_BYPASS_PASS_IDX - 1) {
                    final passType =
                        (tpIndex + StdEntropyCoderOptions.NUM_EMPTY_PASSES_IN_MS_BP) %
                            StdEntropyCoderOptions.NUM_PASSES;
                    if (passType != 0) {
                      final value = reader.readBits(
                        lblockRow[coordIdx.x] + MathUtil.log2(tpIndex - lastTerminated),
                      );
                      lengths[cursor++] = value;
                      blockInfo.len[layer] += value;
                      lastTerminated = tpIndex;
                    }
                  }
                  tpIndex++;
                }

                final finalValue = reader.readBits(
                  lblockRow[coordIdx.x] + MathUtil.log2(tpIndex - lastTerminated),
                );
                blockInfo.len[layer] += finalValue;
                lengths[cursor] = finalValue;
                // if (_packetIndex == 90) print('Pkt90: CB($m,$n) len=${blockInfo.len[layer]}');
                if (blockInfo.len[layer] > 32768) {
                  // final tileIdx = src.getTileIdx();
                  /*
                  print(
                    'PktDecoder header segmented len anomaly: tile=$tileIdx layer=$layer res=$resolution comp=$component '
                    'precinct=$precinct subband=$subband block=${coordIdx.x}x${coordIdx.y} '
                    'len=${blockInfo.len[layer]} segments=$segmentCount lblock=${lblockRow[coordIdx.x]} '
                    'newTruncPoints=$newTruncPoints',
                  );
                  */
                }
              }
            }

            if (DecoderInstrumentation.isEnabled()) {
              DecoderInstrumentation.log(
                'PktDecoder',
                'pkt=$_packetIndex tile=$tileIdx comp=$component res=$resolution band=$subband '
                'block=${coordIdx.x}x${coordIdx.y} layer=$layer payload=${blockInfo.len[layer]} '
                'segLen=${blockInfo.segLen[layer]}',
              );
            }

            if (isTruncMode && maxCB == -1) {
              final consumed = ehs.getPos() - startOfHeader;
              if (consumed > remainingBytesPerTile[tileIdx]) {
                remainingBytesPerTile[tileIdx] = 0;
                if (layer == 0) {
                  _discardCodeBlock(subbandBlocks, subband, coordIdx.y, coordIdx.x, blockInfo);
                } else {
                  _rewindLayer(blockInfo, layer);
                }
                return true;
              }
              remainingBytesPerTile[tileIdx] -= consumed;
            }
          } on EOFException {
            if (layer == 0) {
              _discardCodeBlock(subbandBlocks, subband, coordIdx.y, coordIdx.x, blockInfo);
            } else {
              _rewindLayer(blockInfo, layer);
            }
            rethrow;
          }
        }
      }
    }

    if (_ephUsed) {
      // print('PktDecoder: Reading EPH (full packet)');
      _readEphMarker(reader);
    }

    _packetIndex++;

    final consumed = ehs.getPos() - startOfHeader;
    if (consumed > remainingBytesPerTile[tileIdx]) {
      remainingBytesPerTile[tileIdx] = 0;
      return true;
    }
    remainingBytesPerTile[tileIdx] -= consumed;

    return false;
  }

  bool readPktBody(
    int layer,
    int resolution,
    int component,
    int precinct,
    List<List<List<CBlkInfo?>?>?>? subbandBlocks,
    List<int> remainingBytesPerTile,
  ) {
    var currentOffset = ehs.getPos();
    final tileIdx = src.getTileIdx();
    final mins = resolution == 0 ? 0 : 1;
    final maxs = resolution == 0 ? 1 : 4;

    var stopReading = false;

    for (var subband = mins; subband < maxs; subband++) {
      final included = _includedCodeBlocks[subband];
      for (final coord in included) {
        final coordIdx = coord.idx;
        final blockInfo = _getCodeBlock(subbandBlocks, subband, coordIdx.y, coordIdx.x);
        if (blockInfo == null) {
          continue;
        }

        blockInfo.off[layer] = currentOffset;
        final payloadLength = blockInfo.len[layer];
        currentOffset += payloadLength;

        final shouldReadPayload =
            payloadLength > 0 && !(isTruncMode && (stopReading || payloadLength > remainingBytesPerTile[tileIdx]));

        Uint8List? payload;
        if (payloadLength == 0) {
          payload = Uint8List(0);
          try {
            ehs.seek(currentOffset);
          } on EOFException {
            _handleBodyRollback(subbandBlocks, subband, coordIdx.y, coordIdx.x, blockInfo, layer);
            rethrow;
          }
        } else if (shouldReadPayload) {
          payload = Uint8List(payloadLength);
          try {
            ehs.readFully(payload, 0, payloadLength);
          } on EOFException {
            // final currentPos = ehs.getPos();
            /*
            print(
              'PktDecoder payload EOF: tile=$tileIdx layer=$layer res=$resolution comp=$component '
              'precinct=$precinct subband=$subband block=${coordIdx.x}x${coordIdx.y} '
              'len=$payloadLength currentOffset=$currentOffset pos=$currentPos remaining=${remainingBytesPerTile[tileIdx]}',
            );
            */
            payload = null;
            _handleBodyRollback(subbandBlocks, subband, coordIdx.y, coordIdx.x, blockInfo, layer);
            rethrow;
          }
        } else {
          try {
            ehs.seek(currentOffset);
          } on EOFException {
            _handleBodyRollback(subbandBlocks, subband, coordIdx.y, coordIdx.x, blockInfo, layer);
            rethrow;
          }
        }
        blockInfo.body[layer] = payload;

        if (isTruncMode) {
          if (stopReading || payloadLength > remainingBytesPerTile[tileIdx]) {
            _handleBodyRollback(subbandBlocks, subband, coordIdx.y, coordIdx.x, blockInfo, layer);
            stopReading = true;
            currentOffset = blockInfo.off[layer];
          } else {
            remainingBytesPerTile[tileIdx] -= payloadLength;
          }
        } else {
          remainingBytesPerTile[tileIdx] -= payloadLength;
        }

        if (_ncbQuit &&
            resolution == _resQuit &&
            subband == _subbandQuit &&
            coordIdx.x == _xQuit &&
            coordIdx.y == _yQuit &&
            tileIdx == _tileQuit &&
            component == _compQuit) {
          _discardCodeBlock(subbandBlocks, subband, coordIdx.y, coordIdx.x, blockInfo);
          stopReading = true;
        }
      }
    }

    ehs.seek(currentOffset);
    return stopReading;
  }

  bool readSOPMarker(List<int> remainingBytesPerTile, int precinct, int component, int resolution) {
    final mins = resolution == 0 ? 0 : 1;
    final maxs = resolution == 0 ? 1 : 4;

    var precinctExists = false;
    for (var subband = mins; subband < maxs; subband++) {
      if (precinct < _precinctInfo[component][resolution].length) {
        precinctExists = true;
        break;
      }
    }
    if (!precinctExists) {
      return false;
    }

    if (!_sopUsed) {
      return false;
    }

    final tileIdx = src.getTileIdx();
    final position = ehs.getPos();
    try {
      final high = ehs.read();
      final low = ehs.read();
      final marker = ((high & 0xff) << 8) | (low & 0xff);
      if (marker != Markers.SOP) {
        ehs.seek(position);
        return false;
      }
      ehs.seek(position);
    } on EOFException {
      ehs.seek(position);
      return true;
    }

    if (remainingBytesPerTile[tileIdx] < Markers.SOP_LENGTH) {
      return true;
    }
    remainingBytesPerTile[tileIdx] -= Markers.SOP_LENGTH;

    final buffer = Uint8List(Markers.SOP_LENGTH);
    ehs.readFully(buffer, 0, buffer.length);

    final marker = ((buffer[0] & 0xff) << 8) | (buffer[1] & 0xff);
    if (marker != Markers.SOP) {
      throw StateError('Corrupted bitstream: expected SOP marker, found $marker');
    }

    final length = ((buffer[2] & 0xff) << 8) | (buffer[3] & 0xff);
    if (length != 4) {
      throw StateError('Corrupted bitstream: invalid SOP marker length $length');
    }

    final sequence = ((buffer[4] & 0xff) << 8) | (buffer[5] & 0xff);
    if (!_usingPackedHeaders && sequence != _packetIndex) {
      throw StateError('Corrupted bitstream: SOP marker out of sequence (expected $_packetIndex, got $sequence)');
    }
    if (_usingPackedHeaders && sequence != _packetIndex - 1) {
      throw StateError('Corrupted bitstream: SOP marker out of sequence for packed headers (expected ${_packetIndex - 1}, got $sequence)');
    }

    return false;
  }

  int _computeSegmentCount(CBlkInfo info, int newTruncPoints, int options) {
    if ((options & StdEntropyCoderOptions.OPT_TERM_PASS) != 0) {
      return newTruncPoints;
    }
    if ((options & StdEntropyCoderOptions.OPT_BYPASS) != 0) {
      if (info.ctp <= StdEntropyCoderOptions.FIRST_BYPASS_PASS_IDX) {
        return 1;
      }
      var segments = 1;
      for (var tp = info.ctp - newTruncPoints; tp < info.ctp - 1; tp++) {
        if (tp >= StdEntropyCoderOptions.FIRST_BYPASS_PASS_IDX - 1) {
          final passType =
              (tp + StdEntropyCoderOptions.NUM_EMPTY_PASSES_IN_MS_BP) % StdEntropyCoderOptions.NUM_PASSES;
          if (passType == 0 || passType == 1 || passType == 2) {
            segments++;
          }
        }
      }
      return segments;
    }
    return 1;
  }

  void _rewindLayer(CBlkInfo info, int layer) {
    info.off[layer] = 0;
    info.len[layer] = 0;
    info.ctp -= info.ntp[layer];
    info.ntp[layer] = 0;
    info.pktIdx[layer] = -1;
    info.segLen[layer] = null;
    info.body[layer] = null;
  }

  void _handleBodyRollback(
    List<List<List<CBlkInfo?>?>?>? subbandBlocks,
    int subband,
    int y,
    int x,
    CBlkInfo info,
    int layer,
  ) {
    if (layer == 0) {
      _discardCodeBlock(subbandBlocks, subband, y, x, info);
    } else {
      _rewindLayer(info, layer);
    }
  }

  CBlkInfo? _getCodeBlock(
    List<List<List<CBlkInfo?>?>?>? subbandBlocks,
    int subband,
    int y,
    int x,
  ) {
    if (subbandBlocks == null || subband >= subbandBlocks.length) {
      return null;
    }
    final rows = subbandBlocks[subband];
    if (rows == null || y >= rows.length) {
      return null;
    }
    final row = rows[y];
    if (row == null || x >= row.length) {
      return null;
    }
    return row[x];
  }

  void _discardCodeBlock(
    List<List<List<CBlkInfo?>?>?>? subbandBlocks,
    int subband,
    int y,
    int x,
    CBlkInfo info,
  ) {
    info.ctp -= info.ntp.where((value) => value > 0).fold<int>(0, (sum, value) => sum + value);
    if (subbandBlocks == null || subband >= subbandBlocks.length) {
      return;
    }
    final rows = subbandBlocks[subband];
    if (rows == null || y >= rows.length) {
      return;
    }
    final row = rows[y];
    if (row == null || x >= row.length) {
      return;
    }
    row[x] = null;
  }

  @visibleForTesting
  void debugSetIncludedCodeBlocks(int subband, List<CBlkCoordInfo> blocks) {
    if (subband < 0 || subband >= _includedCodeBlocks.length) {
      throw ArgumentError('Subband index out of range: $subband');
    }
    final target = _includedCodeBlocks[subband];
    target
      ..clear()
      ..addAll(blocks);
  }

  @visibleForTesting
  void debugInitializeForPacketBody({required int numLayers, int tileIdx = 0}) {
    _numLayers = numLayers;
    _currentTileIdx = tileIdx;
    _includedCodeBlocks = List<List<CBlkCoordInfo>>.generate(4, (_) => <CBlkCoordInfo>[]);
  }

  void _readEphMarker(PktHeaderBitReader reader) {
    final buffer = Uint8List(Markers.EPH_LENGTH);
    reader.readBytes(buffer, 0, buffer.length);
    final value = ((buffer[0] & 0xff) << 8) | (buffer[1] & 0xff);
    if (value != Markers.EPH) {
      // print('PktDecoder: Expected EPH, found $value at pos ${ehs.getPos()}');
      throw StateError('Corrupted bitstream: expected EPH marker, found $value');
    }
  }

  void _fillPrecinctInfo(int component, int resolution, int maxDecompositionLevel) {
    final precincts = _precinctInfo[component][resolution];
    if (precincts.isEmpty) {
      return;
    }

    final tileCoord = src.getTile(null);

    final xt0siz = src.getTilePartULX();
    final yt0siz = src.getTilePartULY();
    final xtsiz = src.getNomTileWidth();
    final ytsiz = src.getNomTileHeight();
    final x0siz = hd.getImgULX();
    final y0siz = hd.getImgULY();
    final tx0 = tileCoord.x == 0 ? x0siz : xt0siz + tileCoord.x * xtsiz;
    final ty0 = tileCoord.y == 0 ? y0siz : yt0siz + tileCoord.y * ytsiz;
    final subsX = hd.getCompSubsX(component);
    final subsY = hd.getCompSubsY(component);

    final tcx0 = src.getResULX(component, maxDecompositionLevel);
    final tcy0 = src.getResULY(component, maxDecompositionLevel);
    final tcx1 = tcx0 + src.getTileCompWidth(_currentTileIdx, component, maxDecompositionLevel);
    final tcy1 = tcy0 + src.getTileCompHeight(_currentTileIdx, component, maxDecompositionLevel);

    final ndl = maxDecompositionLevel - resolution;
    final trx0 = _ceilDivInt(tcx0, 1 << ndl);
    final try0 = _ceilDivInt(tcy0, 1 << ndl);
    final trx1 = _ceilDivInt(tcx1, 1 << ndl);
    final try1 = _ceilDivInt(tcy1, 1 << ndl);

    final cb0x = src.getCbULX();
    final cb0y = src.getCbULY();

    final twoppx = getPPX(_currentTileIdx, component, resolution);
    final twoppy = getPPY(_currentTileIdx, component, resolution);
    final twoppx2 = twoppx >> 1;
    final twoppy2 = twoppy >> 1;

    final istart = _floorDivInt(try0 - cb0y, twoppy);
    final iend = _floorDivInt(try1 - 1 - cb0y, twoppy);
    final jstart = _floorDivInt(trx0 - cb0x, twoppx);
    final jend = _floorDivInt(trx1 - 1 - cb0x, twoppx);

    final root = src.getSynSubbandTree(_currentTileIdx, component);

    var precinctIndex = 0;
    for (var i = istart; i <= iend; i++) {
      for (var j = jstart; j <= jend; j++, precinctIndex++) {
        final twoPow = 1 << ndl;
        final progW = twoppx * twoPow;
        final progH = twoppy * twoPow;

        final alignedX = subsX * progW;
        final alignedY = subsY * progH;

        final progUlx = (j == jstart && ((trx0 - cb0x) % (subsX * twoppx)) != 0)
            ? tx0
            : cb0x + j * alignedX;
        final progUly = (i == istart && ((try0 - cb0y) % (subsY * twoppy)) != 0)
            ? ty0
            : cb0y + i * alignedY;

        final precinct = PrecInfo(
          resolution,
          cb0x + j * twoppx,
          cb0y + i * twoppy,
          twoppx,
          twoppy,
          progUlx,
          progUly,
          progW,
          progH,
        );
        precincts[precinctIndex] = precinct;

        if (resolution == 0) {
          _populateLlPrecinct(
            precinct,
            component,
            resolution,
            root,
            i,
            j,
            tcx0,
            tcy0,
            twoppx,
            twoppy,
            cb0x,
            cb0y,
            subsX,
            subsY,
            precinctIndex,
          );
        } else {
          _populateHlPrecinct(
            precinct,
            component,
            resolution,
            root,
            i,
            j,
            twoppx2,
            twoppy2,
            cb0x,
            cb0y,
            precinctIndex,
          );
        }
      }
    }
  }

  void _populateLlPrecinct(
    PrecInfo precinct,
    int component,
    int resolution,
    SubbandSyn root,
    int i,
    int j,
    int tcx0,
    int tcy0,
    int twoppx,
    int twoppy,
    int cb0x,
    int cb0y,
    int subsX,
    int subsY,
    int precinctIndex,
  ) {
    final sb = root.getSubbandByIdx(0, 0) as SubbandSyn?;
    if (sb == null) {
      _ttIncl[component][resolution][precinctIndex][0] = TagTreeDecoder(0, 0);
      _ttMaxBP[component][resolution][precinctIndex][0] = TagTreeDecoder(0, 0);
      precinct.nblk[0] = 0;
      return;
    }

    final p0x = cb0x + j * twoppx;
    final p1x = p0x + twoppx;
    final p0y = cb0y + i * twoppy;
    final p1y = p0y + twoppy;

    final s0x = math.max(p0x, sb.ulcx);
    final s1x = math.min(p1x, sb.ulcx + sb.w);
    final s0y = math.max(p0y, sb.ulcy);
    final s1y = math.min(p1y, sb.ulcy + sb.h);

    if (s1x - s0x <= 0 || s1y - s0y <= 0) {
      precinct.nblk[0] = 0;
      _ttIncl[component][resolution][precinctIndex][0] = TagTreeDecoder(0, 0);
      _ttMaxBP[component][resolution][precinctIndex][0] = TagTreeDecoder(0, 0);
      return;
    }

    final cw = sb.nomCBlkW;
    final ch = sb.nomCBlkH;
    final k0 = _floorDivInt(sb.ulcy - cb0y, ch);
    final kstart = _floorDivInt(s0y - cb0y, ch);
    final kend = _floorDivInt(s1y - 1 - cb0y, ch);
    final l0 = _floorDivInt(sb.ulcx - cb0x, cw);
    final lstart = _floorDivInt(s0x - cb0x, cw);
    final lend = _floorDivInt(s1x - 1 - cb0x, cw);

    final height = kend - kstart + 1;
    final width = lend - lstart + 1;
    precinct.nblk[0] = height * width;
    _ttIncl[component][resolution][precinctIndex][0] = TagTreeDecoder(height, width);
    _ttMaxBP[component][resolution][precinctIndex][0] = TagTreeDecoder(height, width);

    final rows = List.generate(
      height,
      (_) => List<CBlkCoordInfo>.filled(width, CBlkCoordInfo(), growable: false),
      growable: false,
    );
    precinct.cblk[0] = rows;

    for (var k = kstart; k <= kend; k++) {
      for (var l = lstart; l <= lend; l++) {
        final cb = CBlkCoordInfo.withIndex(k - k0, l - l0);
        cb.ulx = l == l0 ? sb.ulx : sb.ulx + l * cw - (sb.ulcx - cb0x);
        cb.uly = k == k0 ? sb.uly : sb.uly + k * ch - (sb.ulcy - cb0y);

        var minX = math.max(cb0x + l * cw, sb.ulcx);
        var maxX = math.min(cb0x + (l + 1) * cw, sb.ulcx + sb.w);
        cb.w = maxX - minX;

        var minY = math.max(cb0y + k * ch, sb.ulcy);
        var maxY = math.min(cb0y + (k + 1) * ch, sb.ulcy + sb.h);
        cb.h = maxY - minY;

        rows[k - kstart][l - lstart] = cb;
      }
    }
  }

  void _populateHlPrecinct(
    PrecInfo precinct,
    int component,
    int resolution,
    SubbandSyn root,
    int i,
    int j,
    int twoppx2,
    int twoppy2,
    int cb0x,
    int cb0y,
    int precinctIndex,
  ) {
    final bands = [root.getSubbandByIdx(resolution, 1), root.getSubbandByIdx(resolution, 2), root.getSubbandByIdx(resolution, 3)];
    final offsets = [
      [0, cb0y],
      [cb0x, 0],
      [0, 0],
    ];

    for (var band = 0; band < bands.length; band++) {
      final sb = bands[band] as SubbandSyn?;
      if (sb == null) {
        precinct.nblk[band + 1] = 0;
        _ttIncl[component][resolution][precinctIndex][band + 1] = TagTreeDecoder(0, 0);
        _ttMaxBP[component][resolution][precinctIndex][band + 1] = TagTreeDecoder(0, 0);
        continue;
      }

      final acb0x = offsets[band][0];
      final acb0y = offsets[band][1];

      final p0x = acb0x + j * twoppx2;
      final p1x = p0x + twoppx2;
      final p0y = acb0y + i * twoppy2;
      final p1y = p0y + twoppy2;

      final s0x = math.max(p0x, sb.ulcx);
      final s1x = math.min(p1x, sb.ulcx + sb.w);
      final s0y = math.max(p0y, sb.ulcy);
      final s1y = math.min(p1y, sb.ulcy + sb.h);

      if (s1x - s0x <= 0 || s1y - s0y <= 0) {
        precinct.nblk[band + 1] = 0;
        _ttIncl[component][resolution][precinctIndex][band + 1] = TagTreeDecoder(0, 0);
        _ttMaxBP[component][resolution][precinctIndex][band + 1] = TagTreeDecoder(0, 0);
        continue;
      }

      final cw = sb.nomCBlkW;
      final ch = sb.nomCBlkH;
      final k0 = _floorDivInt(sb.ulcy - acb0y, ch);
      final kstart = _floorDivInt(s0y - acb0y, ch);
      final kend = _floorDivInt(s1y - 1 - acb0y, ch);
      final l0 = _floorDivInt(sb.ulcx - acb0x, cw);
      final lstart = _floorDivInt(s0x - acb0x, cw);
      final lend = _floorDivInt(s1x - 1 - acb0x, cw);

      final height = kend - kstart + 1;
      final width = lend - lstart + 1;
      precinct.nblk[band + 1] = height * width;
      _ttIncl[component][resolution][precinctIndex][band + 1] = TagTreeDecoder(height, width);
      _ttMaxBP[component][resolution][precinctIndex][band + 1] = TagTreeDecoder(height, width);

      final rows = List.generate(
        height,
        (_) => List<CBlkCoordInfo>.filled(width, CBlkCoordInfo(), growable: false),
        growable: false,
      );
      precinct.cblk[band + 1] = rows;

      for (var k = kstart; k <= kend; k++) {
        for (var l = lstart; l <= lend; l++) {
          final cb = CBlkCoordInfo.withIndex(k - k0, l - l0);
          cb.ulx = l == l0 ? sb.ulx : sb.ulx + l * cw - (sb.ulcx - acb0x);
          cb.uly = k == k0 ? sb.uly : sb.uly + k * ch - (sb.ulcy - acb0y);

          var minX = math.max(acb0x + l * cw, sb.ulcx);
          var maxX = math.min(acb0x + (l + 1) * cw, sb.ulcx + sb.w);
          cb.w = maxX - minX;

          var minY = math.max(acb0y + k * ch, sb.ulcy);
          var maxY = math.min(acb0y + (k + 1) * ch, sb.ulcy + sb.h);
          cb.h = maxY - minY;

          rows[k - kstart][l - lstart] = cb;
        }
      }
    }
  }

  int _ceilDivInt(int value, int divisor) {
    if (divisor == 0) {
      throw ArgumentError('Divisor must be non-zero');
    }
    return (value / divisor).ceil();
  }

  int _floorDivInt(int value, int divisor) {
    if (divisor == 0) {
      throw ArgumentError('Divisor must be non-zero');
    }
    return (value / divisor).floor();
  }

  int getPPX(int tile, int component, int resolution) => decSpec.pss.getPPX(tile, component, resolution);

  int getPPY(int tile, int component, int resolution) => decSpec.pss.getPPY(tile, component, resolution);
}


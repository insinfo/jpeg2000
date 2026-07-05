import 'dart:typed_data';

import '../j2k/codestream/markers.dart';
import '../j2k/codestream/writer/codestream_writer.dart';
import '../j2k/codestream/writer/header_encoder.dart';

/// Codestream writer that accumulates a J2K codestream in memory.
class MemoryCodestreamWriter extends CodestreamWriter {
  MemoryCodestreamWriter(super.maxBytes) {
    _initMarkers();
  }

  static const int _sopMarkerLimit = 65535;

  final BytesBuilder _bytes = BytesBuilder();
  late final Uint8List _sopMarker;
  late final Uint8List _ephMarker;

  int _packetIndex = 0;
  int _offLastRoiPacket = 0;
  int _lenLastNoRoi = 0;
  bool _closed = false;

  Uint8List toBytes() => _bytes.toBytes();

  @override
  int getMaxAvailableBytes() => maxBytes - ndata;

  @override
  int getLength() => getMaxAvailableBytes() >= 0 ? ndata : maxBytes;

  @override
  int writePacketHead(
    Uint8List head,
    int hlen,
    bool sim,
    bool sop,
    bool eph,
  ) {
    var len =
        hlen + (sop ? Markers.SOP_LENGTH : 0) + (eph ? Markers.EPH_LENGTH : 0);

    if (!sim) {
      if (getMaxAvailableBytes() < len) {
        len = getMaxAvailableBytes();
      }
      if (len > 0) {
        if (sop) {
          _sopMarker[4] = (_packetIndex >> 8) & 0xff;
          _sopMarker[5] = _packetIndex & 0xff;
          _writeBytes(_sopMarker, Markers.SOP_LENGTH);
          _packetIndex++;
          if (_packetIndex > _sopMarkerLimit) {
            _packetIndex = 0;
          }
        }
        _writeBytes(head, hlen);
        ndata += len;
        if (eph) {
          _writeBytes(_ephMarker, Markers.EPH_LENGTH);
        }
        _lenLastNoRoi += len;
      }
    }
    return len;
  }

  @override
  int writePacketBody(
    Uint8List body,
    int blen,
    bool sim,
    bool roiInPkt,
    int roiLen,
  ) {
    var len = blen;
    if (!sim) {
      if (getMaxAvailableBytes() < len) {
        len = getMaxAvailableBytes();
      }
      if (blen > 0) {
        _writeBytes(body, len);
      }
      ndata += len;
      if (roiInPkt) {
        _offLastRoiPacket += _lenLastNoRoi + roiLen;
        _lenLastNoRoi = len - roiLen;
      } else {
        _lenLastNoRoi += len;
      }
    }
    return len;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _bytes.add(<int>[Markers.EOC >> 8, Markers.EOC & 0xff]);
    ndata += 2;
    _closed = true;
  }

  @override
  void commitBitstreamHeader(HeaderEncoder he) {
    final header = he.getBuffer();
    ndata += header.length;
    _bytes.add(header);
    _packetIndex = 0;
    _lenLastNoRoi += header.length;
  }

  @override
  int getOffLastROIPkt() => _offLastRoiPacket;

  void _writeBytes(Uint8List bytes, int length) {
    if (length <= 0) {
      return;
    }
    if (length == bytes.length) {
      _bytes.add(bytes);
    } else {
      _bytes.add(Uint8List.sublistView(bytes, 0, length));
    }
  }

  void _initMarkers() {
    _sopMarker = Uint8List(Markers.SOP_LENGTH)
      ..[0] = Markers.SOP >> 8
      ..[1] = Markers.SOP & 0xff
      ..[2] = 0x00
      ..[3] = 0x04;

    _ephMarker = Uint8List(Markers.EPH_LENGTH)
      ..[0] = Markers.EPH >> 8
      ..[1] = Markers.EPH & 0xff;
  }
}

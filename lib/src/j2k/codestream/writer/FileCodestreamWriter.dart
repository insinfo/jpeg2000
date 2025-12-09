import 'dart:io';
import 'dart:typed_data';
import '../markers.dart';
import 'CodestreamWriter.dart';
import 'HeaderEncoder.dart';

/// This class implements a CodestreamWriter for Dart streams. The streams can
/// be files or network connections, or any other resource that presents itself
/// as a IOSink. See the CodestreamWriter abstract class for more details
/// on the implementation of the CodestreamWriter abstract class.
///
/// <p>Before any packet data is written to the bit stream (even in simulation
/// mode) the complete header should be written otherwise incorrect estimates
/// are given by getMaxAvailableBytes() for rate allocation.
class FileCodestreamWriter extends CodestreamWriter {
  /// The upper limit for the value of the Nsop field of the SOP marker
  static const int SOP_MARKER_LIMIT = 65535;

  /// Index of the current tile
  int tileIdx = 0;

  /// The file to write
  IOSink out;

  /// The default buffer length, 1024 bytes
  static const int DEF_BUF_LEN = 1024;

  /// Array used to store the SOP markers values
  late Uint8List sopMarker;

  /// Array used to store the EPH markers values
  late Uint8List ephMarker;

  /// The packet index (when start of packet markers i.e. SOP markers) are
  ///  used.
  int packetIdx = 0;

  /// Offset of end of last packet containing ROI information
  int offLastROIPkt = 0;

  /// Length of last packets containing no ROI information
  int lenLastNoROI = 0;

  /// Opens the file 'file' for writing the codestream. The magic number is
  /// written to the bit stream. Normally, the header encoder must be empty
  /// (i.e. no data has been written to it yet).
  ///
  /// [file] The file where to write the bit stream
  ///
  /// [mb] The maximum number of bytes that can be written to the bit
  /// stream.
  FileCodestreamWriter.fromFile(File file, int mb) : out = file.openWrite(), super(mb) {
    initSOP_EPHArrays();
  }

  /// Opens the file named 'fname' for writing the bit stream, using the 'he'
  /// header encoder. The magic number is written to the bit
  /// stream. Normally, the header encoder must be empty (i.e. no data has
  /// been written to it yet).
  ///
  /// [fname] The name of file where to write the bit stream
  ///
  /// [mb] The maximum number of bytes that can be written to the bit
  /// stream.
  FileCodestreamWriter.fromPath(String fname, int mb) : out = File(fname).openWrite(), super(mb) {
    initSOP_EPHArrays();
  }

  /// Uses the output stream 'os' for writing the bit stream, using the 'he'
  /// header encoder. The magic number is written to the bit
  /// stream. Normally, the header encoder must be empty (i.e. no data has
  /// been written to it yet).
  ///
  /// [os] The output stream where to write the bit stream.
  ///
  /// [mb] The maximum number of bytes that can be written to the bit
  /// stream.
  FileCodestreamWriter.fromStream(this.out, int mb) : super(mb) {
    initSOP_EPHArrays();
  }

  @override
  int getMaxAvailableBytes() {
    return maxBytes - ndata;
  }

  @override
  int getLength() {
    if (getMaxAvailableBytes() >= 0) {
      return ndata;
    } else {
      return maxBytes;
    }
  }

  @override
  int writePacketHead(
      Uint8List head, int hlen, bool sim, bool sop, bool eph) {
    int len = hlen +
        (sop ? Markers.SOP_LENGTH : 0) +
        (eph ? Markers.EPH_LENGTH : 0);

    // If not in simulation mode write the data
    if (!sim) {
      // Write the head bytes
      if (getMaxAvailableBytes() < len) {
        len = getMaxAvailableBytes();
      }

      if (len > 0) {
        // Write Start Of Packet header markers if necessary
        if (sop) {
          // The first 4 bytes of the array have been filled in the
          // classe's constructor.
          sopMarker[4] = (packetIdx >> 8);
          sopMarker[5] = (packetIdx);
          out.add(sopMarker.sublist(0, Markers.SOP_LENGTH));
          packetIdx++;
          if (packetIdx > SOP_MARKER_LIMIT) {
            // Reset SOP value as we have reached its upper limit
            packetIdx = 0;
          }
        }
        out.add(head.sublist(0, hlen));
        // Update data length
        ndata += len;

        // Write End of Packet Header markers if necessary
        if (eph) {
          out.add(ephMarker.sublist(0, Markers.EPH_LENGTH));
        }

        // Deal with ROI Information
        lenLastNoROI += len;
      }
    }
    return len;
  }

  @override
  int writePacketBody(
      Uint8List body, int blen, bool sim, bool roiInPkt, int roiLen) {
    int len = blen;

    // If not in simulation mode write the data
    if (!sim) {
      // Write the body bytes
      len = blen;
      if (getMaxAvailableBytes() < len) {
        len = getMaxAvailableBytes();
      }
      if (blen > 0) {
        out.add(body.sublist(0, len));
      }
      // Update data length
      ndata += len;

      // Deal with ROI information
      if (roiInPkt) {
        offLastROIPkt += lenLastNoROI + roiLen;
        lenLastNoROI = len - roiLen;
      } else {
        lenLastNoROI += len;
      }
    }
    return len;
  }

  @override
  void close() {
    // Write the EOC marker and close the codestream.
    out.add([Markers.EOC >> 8, Markers.EOC & 0xFF]);

    ndata += 2; // Add two to length of codestream for EOC marker

    out.close();
  }

  @override
  int getOffLastROIPkt() {
    return offLastROIPkt;
  }

  @override
  void commitBitstreamHeader(HeaderEncoder he) {
    // Actualize ndata
    ndata += he.getLength();
    he.writeTo(out); // Write the header
    // Reset packet index used for SOP markers
    packetIdx = 0;

    // Deal with ROI information
    lenLastNoROI += he.getLength();
  }

  /// Performs the initialisation of the arrays that are used to store the
  /// values used to write SOP and EPH markers
  void initSOP_EPHArrays() {
    // Allocate and set first values of SOP marker as they will not be
    // modified
    sopMarker = Uint8List(Markers.SOP_LENGTH);
    sopMarker[0] = (Markers.SOP >> 8);
    sopMarker[1] = (Markers.SOP & 0xFF);
    sopMarker[2] = 0x00;
    sopMarker[3] = 0x04;

    // Allocate and set values of EPH marker as they will not be
    // modified
    ephMarker = Uint8List(Markers.EPH_LENGTH);
    ephMarker[0] = (Markers.EPH >> 8);
    ephMarker[1] = (Markers.EPH & 0xFF);
  }
}


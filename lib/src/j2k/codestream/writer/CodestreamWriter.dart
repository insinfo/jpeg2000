import 'dart:typed_data';
import 'HeaderEncoder.dart';

/// This is the abstract class for writing to a codestream. A codestream
/// corresponds to headers (main and tile-parts) and packets. Each packet has a
/// head and a body. The codestream always has a maximum number of bytes that
/// can be written to it. After that many number of bytes no more data is
/// written to the codestream but the number of bytes is counted so that the
/// value returned by getMaxAvailableBytes() is negative. If the number of
/// bytes is unlimited a ridicoulosly large value, such as Integer.MAX_VALUE,
/// is equivalent.
///
/// <p>Data writting to the codestream can be simulated. In this case, no byto
/// is effectively written to the codestream but the resulting number of bytes
/// is calculated and returned (although it is not accounted in the bit
/// stream). This can be used in rate control loops.</p>
///
/// <p>Implementing classes should write the header of the bit stream before
/// writing any packets. The bit stream header can be written with the help of
/// the HeaderEncoder class.</p>
abstract class CodestreamWriter {
  /// The number of bytes already written to the bit stream
  int ndata = 0;

  /// The maximum number of bytes that can be written to the bit stream
  int maxBytes;

  /// Allocates this object and initializes the maximum number of bytes.
  ///
  /// [mb] The maximum number of bytes that can be written to the
  /// codestream.
  CodestreamWriter(this.maxBytes);

  /// Returns the number of bytes remaining available in the codestream. This
  /// is the maximum allowed number of bytes minus the number of bytes that
  /// have already been written to the bit stream. If more bytes have been
  /// written to the bit stream than the maximum number of allowed bytes,
  /// then a negative value is returned.
  ///
  /// Returns The number of bytes remaining available in the bit stream.
  int getMaxAvailableBytes();

  /// Returns the current length of the entire codestream.
  ///
  /// Returns the current length of the codestream
  int getLength();

  /// Writes a packet head into the codestream and returns the number of
  /// bytes used by this header. If in simulation mode then no data is
  /// effectively written to the codestream but the number of bytes is
  /// calculated. This can be used for iterative rate allocation.
  ///
  /// <p>If the number of bytes that has to be written to the codestream is
  /// more than the space left (as returned by getMaxAvailableBytes()), only
  /// the data that does not exceed the allowed length is effectively written
  /// and the rest is discarded. However the value returned by the method is
  /// the total length of the packet, as if all of it was written to the bit
  /// stream.</p>
  ///
  /// <p>If the codestream header has not been commited yet and if 'sim' is
  /// false, then the bit stream header is automatically commited (see
  /// commitBitstreamHeader() method) before writting the packet.
  ///
  /// [head] The packet head data.
  ///
  /// [hlen] The number of bytes in the packet head.
  ///
  /// [sim] Simulation mode flag. If true nothing is written to the bit
  /// stream, but the number of bytes that would be written is returned.
  ///
  /// [sop] Start of packet header marker flag. This flag indicates
  /// whether or not SOP markers should be written. If true, SOP markers
  /// should be written, if false, they should not.
  ///
  /// [eph] End of Packet Header marker flag. This flag indicates
  /// whether or not EPH markers should be written. If true, EPH markers
  /// should be written, if false, they should not.
  ///
  /// Returns The number of bytes spent by the packet head.
  int writePacketHead(Uint8List head, int hlen, bool sim, bool sop, bool eph);

  /// Writes a packet body to the codestream and returns the number of bytes
  /// used by this body. If in simulation mode then no data is written to the
  /// bit stream but the number of bytes is calculated. This can be used for
  /// iterative rate allocation.
  ///
  /// <p>If the number of bytes that has to be written to the codestream is
  /// more than the space left (as returned by getMaxAvailableBytes()), only
  /// the data that does not exceed the allowed length is effectively written
  /// and the rest is discarded. However the value returned by the method is
  /// the total length of the packet, as if all of it was written to the bit
  /// stream.</p>
  ///
  /// [body] The packet body data.
  ///
  /// [blen] The number of bytes in the packet body.
  ///
  /// [sim] Simulation mode flag. If true nothing is written to the bit
  /// stream, but the number of bytes that would be written is returned.
  ///
  /// [roiInPkt] Whether or not there is ROI information in this packet
  ///
  /// [roiLen] Number of byte to read in packet body to get all the ROI
  /// information
  ///
  /// Returns The number of bytes spent by the packet body.
  int writePacketBody(
      Uint8List body, int blen, bool sim, bool roiInPkt, int roiLen);

  /// Closes the underlying resource (file, stream, network connection,
  /// etc.). After a CodestreamWriter is closed no more data can be written
  /// to it.
  void close();

  /// Writes the header data to the bit stream, if it has not been already
  /// done. In some implementations this method can be called only once, and
  /// an IllegalArgumentException is thrown if called more than once.
  void commitBitstreamHeader(HeaderEncoder he);

  /// Gives the offset of the end of last packet containing ROI information
  ///
  /// Returns End of last ROI packet
  int getOffLastROIPkt();
}


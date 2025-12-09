import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/codestream/markers.dart';

/// Shared helpers for constructing synthetic codestream marker payloads in tests.
Uint8List buildCodMarkerPayload({
  required int scod,
  required int sgcodPo,
  required int sgcodNl,
  required int sgcodMct,
  required int spcodNdl,
  required int spcodCw,
  required int spcodCh,
  required int spcodCs,
  required int spcodT,
  List<int>? precincts,
}) {
  final body = <int>[
    scod & 0xff,
    sgcodPo & 0xff,
    ...uint16Bytes(sgcodNl),
    sgcodMct & 0xff,
    spcodNdl & 0xff,
    spcodCw & 0xff,
    spcodCh & 0xff,
    spcodCs & 0xff,
    spcodT & 0xff,
  ];
  if (precincts != null && precincts.isNotEmpty) {
    body.addAll(precincts.map((value) => value & 0xff));
  }
  return Uint8List.fromList(<int>[...uint16Bytes(2 + body.length), ...body]);
}

Uint8List buildCocMarkerPayload({
  required int component,
  required int scoc,
  required int spcocNdl,
  required int spcocCw,
  required int spcocCh,
  required int spcocCs,
  required int spcocT,
  List<int>? precincts,
  bool shortComponentIndex = true,
}) {
  final body = <int>[];
  if (shortComponentIndex) {
    body.add(component & 0xff);
  } else {
    body.addAll(uint16Bytes(component));
  }
  body
    ..add(scoc & 0xff)
    ..add(spcocNdl & 0xff)
    ..add(spcocCw & 0xff)
    ..add(spcocCh & 0xff)
    ..add(spcocCs & 0xff)
    ..add(spcocT & 0xff);
  if (precincts != null && precincts.isNotEmpty) {
    body.addAll(precincts.map((value) => value & 0xff));
  }
  return Uint8List.fromList(<int>[...uint16Bytes(2 + body.length), ...body]);
}

Uint8List buildQcdMarkerPayload({
  required int sqcd,
  required List<int> stepBytes,
}) {
  final body = <int>[sqcd & 0xff];
  body.addAll(stepBytes.map((value) => value & 0xff));
  return Uint8List.fromList(<int>[...uint16Bytes(2 + body.length), ...body]);
}

Uint8List buildQccMarkerPayload({
  required int component,
  required int sqcc,
  required List<int> stepBytes,
  bool shortComponentIndex = true,
}) {
  final body = <int>[];
  if (shortComponentIndex) {
    body.add(component & 0xff);
  } else {
    body.addAll(uint16Bytes(component));
  }
  body.add(sqcc & 0xff);
  body.addAll(stepBytes.map((value) => value & 0xff));
  return Uint8List.fromList(<int>[...uint16Bytes(2 + body.length), ...body]);
}

Uint8List buildRgnMarkerPayload({
  required int component,
  required int srgn,
  required int sprgn,
  bool shortComponentIndex = true,
}) {
  final componentBytes = shortComponentIndex
      ? <int>[component & 0xff]
      : uint16Bytes(component);
  final body = <int>[...componentBytes, srgn & 0xff, sprgn & 0xff];
  return Uint8List.fromList(<int>[...uint16Bytes(2 + body.length), ...body]);
}

Uint8List buildSizMarkerPayload({
  required int xsize,
  required int ysize,
  required int tileWidth,
  required int tileHeight,
  required int numComps,
  required List<int> subsamplingX,
  required List<int> subsamplingY,
  required List<int> bitDepths,
}) {
  if (subsamplingX.length != numComps ||
      subsamplingY.length != numComps ||
      bitDepths.length != numComps) {
    throw ArgumentError('Component metadata lengths must match numComps');
  }
  final body = <int>[]
    ..addAll(uint16Bytes(0))
    ..addAll(uint32Bytes(xsize))
    ..addAll(uint32Bytes(ysize))
    ..addAll(uint32Bytes(0))
    ..addAll(uint32Bytes(0))
    ..addAll(uint32Bytes(tileWidth))
    ..addAll(uint32Bytes(tileHeight))
    ..addAll(uint32Bytes(0))
    ..addAll(uint32Bytes(0))
    ..addAll(uint16Bytes(numComps));

  for (var i = 0; i < numComps; i++) {
    body
      ..add(bitDepths[i] & 0xff)
      ..add(subsamplingX[i] & 0xff)
      ..add(subsamplingY[i] & 0xff);
  }

  return Uint8List.fromList(<int>[...uint16Bytes(2 + body.length), ...body]);
}

Uint8List buildSotMarkerPayload({
  required int tileIdx,
  required int tilePartIdx,
  required int tilePartLength,
  required int numTileParts,
}) {
  final body = <int>[]
    ..addAll(uint16Bytes(tileIdx))
    ..addAll(uint32Bytes(tilePartLength))
    ..add(tilePartIdx & 0xff)
    ..add(numTileParts & 0xff);
  return Uint8List.fromList(<int>[...uint16Bytes(2 + body.length), ...body]);
}

List<int> uint16Bytes(int value) => <int>[(value >> 8) & 0xff, value & 0xff];

List<int> uint16List(List<int> values) {
  final result = <int>[];
  for (final value in values) {
    result.addAll(uint16Bytes(value));
  }
  return result;
}

List<int> uint32Bytes(int value) => <int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

void addMarkerSegment(BytesBuilder builder, int marker, Uint8List payload) {
  addMarker(builder, marker);
  builder.add(payload);
}

void addMarker(BytesBuilder builder, int marker) {
  builder.add(<int>[(marker >> 8) & 0xff, marker & 0xff]);
}

({Uint8List bytes, int psot, int bodyLength}) buildTilePart({
  required int tileIdx,
  required int tilePartIdx,
  required int numTileParts,
  required int bodyLength,
}) {
  final headerBuilder = BytesBuilder()
    ..add(<int>[(Markers.SOD >> 8) & 0xff, Markers.SOD & 0xff]);
  final headerBytes = headerBuilder.toBytes();
  final bodyBytes = Uint8List.fromList(
    List<int>.generate(bodyLength, (index) => (tileIdx + tilePartIdx + index) & 0xff),
  );
  final tilePartLength = 2 + 2 + 8 + headerBytes.length + bodyBytes.length;
  final builder = BytesBuilder();
  addMarker(builder, Markers.SOT);
  builder.add(
    buildSotMarkerPayload(
      tileIdx: tileIdx,
      tilePartIdx: tilePartIdx,
      tilePartLength: tilePartLength,
      numTileParts: numTileParts,
    ),
  );
  builder.add(headerBytes);
  builder.add(bodyBytes);
  return (bytes: builder.toBytes(), psot: tilePartLength, bodyLength: bodyLength);
}

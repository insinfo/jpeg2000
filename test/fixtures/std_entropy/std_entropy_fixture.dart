import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jpeg2000/src/j2k/entropy/decoder/DecLyrdCBlk.dart';
import 'package:jpeg2000/src/j2k/wavelet/synthesis/SubbandSyn.dart';

/// Deserializes recorded StdEntropy fixtures captured from the Java decoder.
class StdEntropyFixture {
  StdEntropyFixture({
    required this.tile,
    required this.component,
    required this.blockIndices,
    required this.subband,
    required this.block,
    required this.tsLengths,
    required this.payload,
    required this.coefficients,
  });

  factory StdEntropyFixture.fromJson(Map<String, dynamic> json) {
    final payloadJson = json['payload'] as List<dynamic>?;
    Uint8List? payloadBytes;
    if (payloadJson != null) {
      payloadBytes = Uint8List.fromList(
        payloadJson.map((dynamic value) => value as int).toList(),
      );
    }
    return StdEntropyFixture(
      tile: json['tile'] as int,
      component: json['component'] as int,
      blockIndices: StdEntropyBlockIndices.fromJson(
        json['blockIndices'] as Map<String, dynamic>,
      ),
      subband: StdEntropySubband.fromJson(
        json['subband'] as Map<String, dynamic>,
      ),
      block: StdEntropyBlock.fromJson(json['block'] as Map<String, dynamic>),
      tsLengths: (json['tsLengths'] as List<dynamic>?)
          ?.map((dynamic value) => value as int)
          .toList(),
      payload: payloadBytes,
      coefficients: List<int>.from(json['coefficients'] as List<dynamic>),
    );
  }

  /// Loads the fixture located at [relativePath], throwing if it does not exist.
  factory StdEntropyFixture.load(String relativePath) {
    final file = File(relativePath);
    if (!file.existsSync()) {
      throw FileSystemException('Fixture not found', file.path);
    }
    final content = file.readAsStringSync();
    final data = json.decode(content) as Map<String, dynamic>;
    return StdEntropyFixture.fromJson(data);
  }

  final int tile;
  final int component;
  final StdEntropyBlockIndices blockIndices;
  final StdEntropySubband subband;
  final StdEntropyBlock block;
  final List<int>? tsLengths;
  final Uint8List? payload;
  final List<int> coefficients;

  DecLyrdCBlk toCodeBlock() {
    final target = DecLyrdCBlk()
      ..m = blockIndices.m
      ..n = blockIndices.n
      ..w = block.w
      ..h = block.h
      ..ulx = block.ulx
      ..uly = block.uly
      ..nl = block.nl
      ..nTrunc = block.nTrunc
      ..skipMSBP = block.skipMSBP
      ..prog = block.prog
      ..dl = block.dl
      ..tsLengths = tsLengths == null ? null : List<int>.from(tsLengths!);
    final bytes = payload;
    if (bytes != null) {
      target.data = Uint8List.fromList(bytes);
    }
    return target;
  }

  SubbandSyn toSubband() {
    return SubbandSyn()
      ..isNode = false
      ..orientation = subband.orientation
      ..resLvl = subband.resLvl
      ..sbandIdx = subband.sbandIdx
      ..w = subband.width
      ..h = subband.height;
  }
}

class StdEntropyBlockIndices {
  StdEntropyBlockIndices({required this.m, required this.n});

  factory StdEntropyBlockIndices.fromJson(Map<String, dynamic> json) {
    return StdEntropyBlockIndices(
      m: json['m'] as int,
      n: json['n'] as int,
    );
  }

  final int m;
  final int n;
}

class StdEntropySubband {
  StdEntropySubband({
    required this.resLvl,
    required this.sbandIdx,
    required this.orientation,
    required this.width,
    required this.height,
  });

  factory StdEntropySubband.fromJson(Map<String, dynamic> json) {
    return StdEntropySubband(
      resLvl: json['resLvl'] as int,
      sbandIdx: json['sbandIdx'] as int,
      orientation: json['orientation'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
    );
  }

  final int resLvl;
  final int sbandIdx;
  final int orientation;
  final int width;
  final int height;
}

class StdEntropyBlock {
  StdEntropyBlock({
    required this.w,
    required this.h,
    required this.ulx,
    required this.uly,
    required this.nl,
    required this.nTrunc,
    required this.skipMSBP,
    required this.prog,
    required this.dl,
    required this.options,
  });

  factory StdEntropyBlock.fromJson(Map<String, dynamic> json) {
    return StdEntropyBlock(
      w: json['w'] as int,
      h: json['h'] as int,
      ulx: json['ulx'] as int,
      uly: json['uly'] as int,
      nl: json['nl'] as int,
      nTrunc: json['nTrunc'] as int,
      skipMSBP: json['skipMSBP'] as int,
      prog: json['prog'] as bool,
      dl: json['dl'] as int,
      options: json['options'] as int,
    );
  }

  final int w;
  final int h;
  final int ulx;
  final int uly;
  final int nl;
  final int nTrunc;
  final int skipMSBP;
  final bool prog;
  final int dl;
  final int options;
}


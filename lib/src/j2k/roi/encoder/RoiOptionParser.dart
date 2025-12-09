import 'package:meta/meta.dart';

import '../../ModuleSpec.dart';
import '../../image/input/ImgReaderPgm.dart';
import 'roi.dart';

/// Parses command-line style ROI specifications used by JJ2000's encoder.
@visibleForTesting
List<ROI> parseRoiOptions(String roiSpecification, int numComponents) {
  if (roiSpecification.trim().isEmpty) {
    return <ROI>[];
  }

  final tokens = roiSpecification
      .split(RegExp(r'\s+'))
      .where((element) => element.isNotEmpty)
      .toList(growable: false);

  final rois = <ROI>[];
  List<bool>? componentsMask;
  var index = 0;

  int nextInt(String context) {
    if (index >= tokens.length) {
      throw ArgumentError('Missing integer parameter for $context');
    }
    final token = tokens[index++];
    try {
      return int.parse(token);
    } on FormatException {
      throw ArgumentError('Expected integer for $context but found "$token"');
    }
  }

  String nextToken(String context) {
    if (index >= tokens.length) {
      throw ArgumentError('Missing parameter for $context');
    }
    return tokens[index++];
  }

  void emitForComponents(ROI Function(int component) builder) {
    final mask = componentsMask;
    if (mask == null) {
      for (var component = 0; component < numComponents; component++) {
        rois.add(builder(component));
      }
      return;
    }
    for (var component = 0; component < numComponents; component++) {
      if (mask[component]) {
        rois.add(builder(component));
      }
    }
  }

  while (index < tokens.length) {
    final token = tokens[index++];
    if (token.isEmpty) {
      continue;
    }
    final prefix = token[0];
    switch (prefix) {
      case 'c':
        componentsMask = ModuleSpec.parseIdx(token, numComponents);
        break;
      case 'R':
        final ulx = nextInt('R rectangular ROI x');
        final uly = nextInt('R rectangular ROI y');
        final width = nextInt('R rectangular ROI width');
        final height = nextInt('R rectangular ROI height');
        emitForComponents(
          (component) => ROI.rectangular(
            component: component,
            ulx: ulx,
            uly: uly,
            w: width,
            h: height,
          ),
        );
        break;
      case 'C':
        final cx = nextInt('C circular ROI center x');
        final cy = nextInt('C circular ROI center y');
        final radius = nextInt('C circular ROI radius');
        emitForComponents(
          (component) => ROI.circular(
            component: component,
            x: cx,
            y: cy,
            radius: radius,
          ),
        );
        break;
      case 'A':
        final path = nextToken('A arbitrary ROI mask path');
        final reader = ImgReaderPGM(path);
        emitForComponents(
          (component) => ROI.arbitrary(
            component: component,
            mask: reader,
          ),
        );
        break;
      default:
        throw ArgumentError('Unsupported ROI token "$token"');
    }
  }

  return rois;
}


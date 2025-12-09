import 'dart:math' as math;
import 'dart:typed_data';

import '../subband.dart';
import '../WaveletFilter.dart';
import 'AnWtFilter.dart';

/// Analysis-side specialization of [Subband] with energy weighting support.
class SubbandAn extends Subband {
  SubbandAn? parent;
  SubbandAn? subbLL;
  SubbandAn? subbHL;
  SubbandAn? subbLH;
  SubbandAn? subbHH;
  AnWTFilter? hFilter;
  AnWTFilter? vFilter;
  double l2Norm = -1.0;
  double stepWMSE = 0.0;

  SubbandAn();

  SubbandAn.tree(
    int w,
    int h,
    int ulcx,
    int ulcy,
    int levels,
    List<WaveletFilter> hFilters,
    List<WaveletFilter> vFilters,
  ) : super.tree(w, h, ulcx, ulcy, levels, hFilters, vFilters) {
    calcL2Norms();
  }

  @override
  Subband? getParent() => parent;

  @override
  Subband getLL() {
    final child = subbLL;
    if (child == null) {
      throw StateError('LL child not initialized');
    }
    return child;
  }

  @override
  Subband getHL() {
    final child = subbHL;
    if (child == null) {
      throw StateError('HL child not initialized');
    }
    return child;
  }

  @override
  Subband getLH() {
    final child = subbLH;
    if (child == null) {
      throw StateError('LH child not initialized');
    }
    return child;
  }

  @override
  Subband getHH() {
    final child = subbHH;
    if (child == null) {
      throw StateError('HH child not initialized');
    }
    return child;
  }

  @override
  Subband split(WaveletFilter hfilter, WaveletFilter vfilter) {
    if (isNode) {
      throw ArgumentError('Subband already split');
    }
    if (hfilter is! AnWTFilter || vfilter is! AnWTFilter) {
      throw ArgumentError('Analysis filters must be AnWTFilter instances');
    }

    isNode = true;
    hFilter = hfilter;
    vFilter = vfilter;

    subbLL = SubbandAn();
    subbHL = SubbandAn();
    subbLH = SubbandAn();
    subbHH = SubbandAn();

    subbLL!.parent = this;
    subbHL!.parent = this;
    subbLH!.parent = this;
    subbHH!.parent = this;

    initChilds();
    return subbLL!;
  }

  @override
  WaveletFilter getHorWFilter() {
    final filter = hFilter;
    if (filter == null) {
      throw StateError('Horizontal analysis filter not set');
    }
    return filter;
  }

  @override
  WaveletFilter getVerWFilter() {
    final filter = vFilter;
    if (filter == null) {
      throw StateError('Vertical analysis filter not set');
    }
    return filter;
  }

  void calcL2Norms() {
    final waveforms = List<Float32List?>.filled(2, null);
    while (l2Norm < 0.0) {
      _calcBasisWaveForms(waveforms);
      final line = waveforms[0]!;
      final column = waveforms[1]!;

      var acc = 0.0;
      for (var i = 0; i < line.length; i++) {
        final sample = line[i];
        acc += sample * sample;
      }
      var l2n = math.sqrt(acc);

      acc = 0.0;
      for (var i = 0; i < column.length; i++) {
        final sample = column[i];
        acc += sample * sample;
      }
      l2n *= math.sqrt(acc);

      waveforms[0] = null;
      waveforms[1] = null;
      _assignL2Norm(l2n);
    }
  }

  void _calcBasisWaveForms(List<Float32List?> waveforms) {
    if (l2Norm >= 0.0) {
      throw StateError('Basis waveforms already computed for this subband');
    }

    if (isNode) {
      final h = hFilter;
      final v = vFilter;
      if (h == null || v == null) {
        throw StateError('Analysis filters must be set before computing norms');
      }
      if (subbLL == null || subbHL == null || subbLH == null || subbHH == null) {
        throw StateError('Child subbands must be initialized');
      }

      if (subbLL!.l2Norm < 0.0) {
        subbLL!._calcBasisWaveForms(waveforms);
        waveforms[0] = h.getLPSynWaveForm(waveforms[0]);
        waveforms[1] = v.getLPSynWaveForm(waveforms[1]);
      } else if (subbHL!.l2Norm < 0.0) {
        subbHL!._calcBasisWaveForms(waveforms);
        waveforms[0] = h.getHPSynWaveForm(waveforms[0]);
        waveforms[1] = v.getLPSynWaveForm(waveforms[1]);
      } else if (subbLH!.l2Norm < 0.0) {
        subbLH!._calcBasisWaveForms(waveforms);
        waveforms[0] = h.getLPSynWaveForm(waveforms[0]);
        waveforms[1] = v.getHPSynWaveForm(waveforms[1]);
      } else if (subbHH!.l2Norm < 0.0) {
        subbHH!._calcBasisWaveForms(waveforms);
        waveforms[0] = h.getHPSynWaveForm(waveforms[0]);
        waveforms[1] = v.getHPSynWaveForm(waveforms[1]);
      } else {
        throw StateError('Unexpected completed state while computing L2 norms');
      }
    } else {
      final line = Float32List(1)..[0] = 1.0;
      final column = Float32List(1)..[0] = 1.0;
      waveforms[0] = line;
      waveforms[1] = column;
    }
  }

  void _assignL2Norm(double value) {
    if (l2Norm >= 0.0) {
      throw StateError('L2-norm already assigned');
    }

    if (isNode) {
      if (subbLL == null || subbHL == null || subbLH == null || subbHH == null) {
        throw StateError('Child subbands must be initialized');
      }
      if (subbLL!.l2Norm < 0.0) {
        subbLL!._assignL2Norm(value);
      } else if (subbHL!.l2Norm < 0.0) {
        subbHL!._assignL2Norm(value);
      } else if (subbLH!.l2Norm < 0.0) {
        subbLH!._assignL2Norm(value);
      } else if (subbHH!.l2Norm < 0.0) {
        subbHH!._assignL2Norm(value);
        if (subbHH!.l2Norm >= 0.0) {
          l2Norm = 0.0;
        }
      } else {
        throw StateError('Unexpected completed state while assigning L2 norm');
      }
    } else {
      l2Norm = value;
    }
  }
}


import '../subband.dart';
import '../WaveletFilter.dart';
import 'SynWTFilter.dart';

/// Synthesis-side specialization of [Subband] holding reconstruction filters.
class SubbandSyn extends Subband {
  SubbandSyn? parent;
  SubbandSyn? subbLL;
  SubbandSyn? subbHL;
  SubbandSyn? subbLH;
  SubbandSyn? subbHH;
  SynWTFilter? hFilter;
  SynWTFilter? vFilter;
  int magBits = 0;

  SubbandSyn();

  SubbandSyn.tree(
    int w,
    int h,
    int ulcx,
    int ulcy,
    int levels,
    List<WaveletFilter> hFilters,
    List<WaveletFilter> vFilters,
  ) : super.tree(w, h, ulcx, ulcy, levels, hFilters, vFilters);

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
    if (hfilter is! SynWTFilter || vfilter is! SynWTFilter) {
      throw ArgumentError('Synthesis filters must be SynWTFilter instances');
    }

    isNode = true;
    hFilter = hfilter;
    vFilter = vfilter;

    subbLL = SubbandSyn();
    subbHL = SubbandSyn();
    subbLH = SubbandSyn();
    subbHH = SubbandSyn();

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
      throw StateError('Horizontal synthesis filter not set');
    }
    return filter;
  }

  @override
  WaveletFilter getVerWFilter() {
    final filter = vFilter;
    if (filter == null) {
      throw StateError('Vertical synthesis filter not set');
    }
    return filter;
  }
}


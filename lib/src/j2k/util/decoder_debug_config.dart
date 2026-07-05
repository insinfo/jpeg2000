class TraceBlockFilter {
  const TraceBlockFilter({
    this.tileIndex,
    this.component,
    this.resolutionLevel,
    this.band,
    this.cblkY,
    this.cblkX,
  });

  final int? tileIndex;
  final int? component;
  final int? resolutionLevel;
  final int? band;
  final int? cblkY;
  final int? cblkX;

  bool matches({
    required int tileIndex,
    required int component,
    required int resolutionLevel,
    required int band,
    required int cblkY,
    required int cblkX,
  }) {
    if (this.tileIndex != null && this.tileIndex != tileIndex) {
      return false;
    }
    if (this.component != null && this.component != component) {
      return false;
    }
    if (resolutionLevel != -1 &&
        this.resolutionLevel != null &&
        this.resolutionLevel != resolutionLevel) {
      return false;
    }
    if (this.band != null && this.band != band) {
      return false;
    }
    if (this.cblkY != null && this.cblkY != cblkY) {
      return false;
    }
    if (this.cblkX != null && this.cblkX != cblkX) {
      return false;
    }
    return true;
  }
}

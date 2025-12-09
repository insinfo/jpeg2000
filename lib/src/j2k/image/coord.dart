/// Simple mutable 2-D coordinate used across the JJ2000 port.
class Coord {
  Coord([this.x = 0, this.y = 0]);

  Coord.copy(Coord other)
      : x = other.x,
        y = other.y;

  int x;
  int y;

  @override
  String toString() => '($x,$y)';
}

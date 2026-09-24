import 'dart:math' as math;

/// Minimal 2D point in world units. World space has y pointing UP, with the
/// playfield spanning `0..LevelData.worldHeight` vertically; x grows to the
/// right as the wave flies forward. Kept free of any Flutter type so the
/// whole engine (and its tests/solver) is plain Dart.
class Vec {
  final double x;
  final double y;
  const Vec(this.x, this.y);

  @override
  String toString() => 'Vec(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// A spike triangle. Floor spikes point up, ceiling spikes point down.
class Spike {
  final Vec a;
  final Vec b;
  final Vec c;
  final bool fromCeiling;
  late final double minX = math.min(a.x, math.min(b.x, c.x));
  late final double maxX = math.max(a.x, math.max(b.x, c.x));

  Spike(this.a, this.b, this.c, {required this.fromCeiling});
}

/// A spinning saw blade (circle hazard).
class Saw {
  final double x;
  final double y;
  final double radius;
  const Saw(this.x, this.y, this.radius);
}

enum PortalKind { speedSlow, speedNormal, speedFast, speedVeryFast, miniOn, miniOff }

extension PortalKindInfo on PortalKind {
  bool get isSpeed => index <= PortalKind.speedVeryFast.index;

  double get speedMultiplier => switch (this) {
        PortalKind.speedSlow => 0.8,
        PortalKind.speedNormal => 1.0,
        PortalKind.speedFast => 1.25,
        PortalKind.speedVeryFast => 1.5,
        _ => 1.0,
      };
}

class Portal {
  final double x;
  final PortalKind kind;
  const Portal(this.x, this.kind);
}

/// Speed multiplier + mini flag in effect at some x (portals are applied in
/// order as the wave passes them).
class ModeState {
  final double speedMultiplier;
  final bool mini;
  const ModeState(this.speedMultiplier, this.mini);

  static const initial = ModeState(1.0, false);

  ModeState apply(PortalKind kind) => kind.isSpeed
      ? ModeState(kind.speedMultiplier, mini)
      : ModeState(speedMultiplier, kind == PortalKind.miniOn);
}

/// All geometry of one level (or of the endless run generated so far).
///
/// Every list is kept sorted by x so lookups are binary searches — endless
/// runs keep appending to the same object for minutes on end.
class LevelData {
  static const double worldHeight = 10;

  /// Normal wave flies at 45°, mini wave at ~63°.
  static const double normalSlope = 1.0;
  static const double miniSlope = 2.0;
  static const double normalRadius = 0.2;
  static const double miniRadius = 0.12;

  /// Spikes/saws use a smaller effective radius than walls — hazards feel
  /// "fair" when grazing a tip doesn't kill, same idea as the genre's
  /// forgiving hitboxes.
  static const double hazardRadiusFactor = 0.6;

  static double slopeFor(bool mini) => mini ? miniSlope : normalSlope;
  static double radiusFor(bool mini) => mini ? miniRadius : normalRadius;

  final double baseSpeed;
  final double startY;

  /// Finish line x. `double.infinity` for endless mode.
  double length;

  final List<Vec> floor = [];
  final List<Vec> ceiling = [];
  final List<Spike> spikes = [];
  final List<Saw> saws = [];
  final List<Portal> portals = [];

  /// Widest a single spike/saw can be in x — bounds the binary-search window.
  static const double maxHazardWidth = 3.0;

  LevelData({required this.baseSpeed, this.startY = worldHeight / 2, this.length = double.infinity});

  // ---------------------------------------------------------------- walls

  static double _interp(List<Vec> pts, double x) {
    if (pts.isEmpty) return double.nan;
    if (x <= pts.first.x) return pts.first.y;
    if (x >= pts.last.x) return pts.last.y;
    var lo = 0, hi = pts.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (pts[mid].x <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = pts[lo], b = pts[hi];
    final t = (x - a.x) / (b.x - a.x);
    return a.y + (b.y - a.y) * t;
  }

  double floorAt(double x) => floor.isEmpty ? 0 : _interp(floor, x);
  double ceilingAt(double x) => ceiling.isEmpty ? worldHeight : _interp(ceiling, x);

  /// Index of the first element whose x-key is >= [x].
  static int lowerBound<T>(List<T> list, double x, double Function(T) key) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (key(list[mid]) < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Wall polyline points with x in [x0, x1], plus one neighbour on each
  /// side so a caller drawing/checking them covers the full range.
  static Iterable<Vec> pointsInRange(List<Vec> pts, double x0, double x1) sync* {
    if (pts.isEmpty) return;
    var i = math.max(0, lowerBound<Vec>(pts, x0, (p) => p.x) - 1);
    for (; i < pts.length; i++) {
      yield pts[i];
      if (pts[i].x > x1) break;
    }
  }

  Iterable<Spike> spikesInRange(double x0, double x1) sync* {
    var i = lowerBound<Spike>(spikes, x0 - maxHazardWidth, (s) => s.minX);
    for (; i < spikes.length; i++) {
      final s = spikes[i];
      if (s.minX > x1) break;
      if (s.maxX >= x0) yield s;
    }
  }

  Iterable<Saw> sawsInRange(double x0, double x1) sync* {
    var i = lowerBound<Saw>(saws, x0 - maxHazardWidth, (s) => s.x);
    for (; i < saws.length; i++) {
      final s = saws[i];
      if (s.x - s.radius > x1) break;
      if (s.x + s.radius >= x0) yield s;
    }
  }

  // ---------------------------------------------------------------- modes

  ModeState modeAt(double x) {
    var m = ModeState.initial;
    for (final p in portals) {
      if (p.x > x) break;
      m = m.apply(p.kind);
    }
    return m;
  }

  // ------------------------------------------------------------ collision

  /// True if a wave of radius [r] centred at (x, y) touches anything deadly.
  bool collides(double x, double y, double r) {
    if (y - r < 0 || y + r > worldHeight) return true;

    // Walls: inside-the-wall test plus true distance to nearby segments, so
    // steep wall corners can't be clipped through between samples.
    if (y <= floorAt(x) || y >= ceilingAt(x)) return true;
    if (_nearPolyline(floor, x, y, r) || _nearPolyline(ceiling, x, y, r)) return true;

    final hr = r * hazardRadiusFactor;
    for (final s in spikesInRange(x - hr, x + hr)) {
      if (distanceToTriangle(x, y, s.a, s.b, s.c) < hr) return true;
    }
    for (final s in sawsInRange(x - hr, x + hr)) {
      final dx = x - s.x, dy = y - s.y;
      final rr = s.radius + hr;
      if (dx * dx + dy * dy < rr * rr) return true;
    }
    return false;
  }

  static bool _nearPolyline(List<Vec> pts, double x, double y, double r) {
    if (pts.length < 2) return false;
    var i = math.max(0, lowerBound<Vec>(pts, x - r, (p) => p.x) - 1);
    for (; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      if (a.x > x + r) break;
      if (distanceToSegment(x, y, a, b) < r) return true;
    }
    return false;
  }

  static double distanceToSegment(double px, double py, Vec a, Vec b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((px - a.x) * dx + (py - a.y) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = a.x + dx * t - px, cy = a.y + dy * t - py;
    return math.sqrt(cx * cx + cy * cy);
  }

  /// 0 when inside the triangle, otherwise distance to its nearest edge.
  static double distanceToTriangle(double px, double py, Vec a, Vec b, Vec c) {
    double sign(Vec p1, Vec p2) => (px - p2.x) * (p1.y - p2.y) - (p1.x - p2.x) * (py - p2.y);
    final d1 = sign(a, b), d2 = sign(b, c), d3 = sign(c, a);
    final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
    final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
    if (!(hasNeg && hasPos)) return 0;
    return math.min(
      distanceToSegment(px, py, a, b),
      math.min(distanceToSegment(px, py, b, c), distanceToSegment(px, py, c, a)),
    );
  }
}

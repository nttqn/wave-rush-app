import 'dart:math' as math;

import 'level_data.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

/// Tuning knobs derived from a single 0..1 difficulty value.
class Difficulty {
  final double t;
  const Difficulty(this.t);

  /// Vertical opening of zig-zag tunnels (normal wave; mini gets more).
  double get tunnelGap => _lerp(3.4, 1.75, t);

  /// Extra clearance between the guaranteed-safe path and any hazard,
  /// on top of the wave's own hitbox.
  double get margin => _lerp(0.9, 0.28, t);

  /// Shortest / longest straight run of the safe path, in seconds of flight.
  double get minSegTime => _lerp(0.42, 0.17, t);
  double get maxSegTime => _lerp(1.1, 0.5, t);

  /// Distance between consecutive hazards in rooms, in world units.
  double get hazardSpacing => _lerp(3.4, 1.5, t);
}

enum SectionType { runway, tunnel, spikeRoom, sawRoom, mixedRoom }

/// Builds level geometry section by section from a seed.
///
/// Every section first lays down a *safe path* — a zig-zag polyline whose
/// slopes are exactly the wave's own ±slope, so a player can always follow
/// it — and then places walls and hazards only where they keep a clearance
/// from that path. That makes every generated level beatable by
/// construction (and `LevelSolver` double-checks it in the tests).
///
/// Used both up front for fixed levels (`extendTo(length)` + `finish()`) and
/// lazily for endless mode (`extendTo(playerX + lookahead)` every frame).
class LevelBuilder {
  final LevelData level;
  final double Function(double x) difficultyAt;
  final bool allowSpeedPortals;
  final bool allowMiniPortals;
  final math.Random _rng;

  /// Everything with x < [generatedTo] exists.
  double generatedTo = 0;

  double _pathY;
  bool _up = true;
  ModeState _mode = ModeState.initial;
  int _sections = 0;
  SectionType? _lastType;

  /// Safe path of every section so far (tests draw/verify against it).
  final List<Vec> safePath = [];

  static const double _roomFloor = 0.5;
  static const double _roomCeiling = LevelData.worldHeight - 0.5;
  static const double _pathLo = 1.2;
  static const double _pathHi = LevelData.worldHeight - 1.2;

  /// Slack for the fixed-timestep wave not hitting path corners exactly.
  static const double _stepSlack = 0.18;

  LevelBuilder({
    required int seed,
    required this.level,
    required this.difficultyAt,
    this.allowSpeedPortals = true,
    this.allowMiniPortals = true,
  })  : _rng = math.Random(seed),
        _pathY = level.startY {
    // Open area behind the start so the camera never shows the void.
    level.floor.add(const Vec(-60, _roomFloor));
    level.ceiling.add(const Vec(-60, _roomCeiling));
    level.floor.add(const Vec(0, _roomFloor));
    level.ceiling.add(const Vec(0, _roomCeiling));
    safePath.add(Vec(0, _pathY));
  }

  double _rand(double a, double b) => a + (b - a) * _rng.nextDouble();

  void extendTo(double x) {
    while (generatedTo < x) {
      _addSection();
    }
  }

  /// Ends a fixed level: finish line shortly after the last section, then
  /// an empty stretch so the camera has something to show past it.
  void finish() {
    final x0 = generatedTo;
    level.length = x0 + 4;
    _addWalls(x0, x0 + 80, _roomFloor, _roomCeiling);
    generatedTo = x0 + 80;
  }

  void _addWalls(double x0, double x1, double floorY, double ceilY) {
    _addWallPoint(level.floor, Vec(x0, floorY));
    _addWallPoint(level.ceiling, Vec(x0, ceilY));
    _addWallPoint(level.floor, Vec(x1, floorY));
    _addWallPoint(level.ceiling, Vec(x1, ceilY));
  }

  /// Wall polylines must have strictly increasing x (interpolation divides
  /// by the x-gap), so a vertical step becomes a 1mm-wide near-vertical one.
  static void _addWallPoint(List<Vec> wall, Vec p) {
    if (wall.isNotEmpty && p.x <= wall.last.x) {
      if ((wall.last.y - p.y).abs() < 1e-9) return;
      p = Vec(wall.last.x + 0.001, p.y);
    }
    wall.add(p);
  }

  SectionType _pickType(Difficulty d) {
    if (_sections == 0) return SectionType.runway;
    final weights = <SectionType, double>{
      SectionType.tunnel: 1.0,
      SectionType.spikeRoom: 1.1,
      SectionType.sawRoom: _lerp(0.2, 0.8, d.t),
      SectionType.mixedRoom: _lerp(0.1, 0.9, d.t),
    };
    // Avoid the same section type twice in a row — keeps levels varied.
    weights.update(_lastType ?? SectionType.runway, (w) => w * 0.25, ifAbsent: () => 0);
    weights.remove(SectionType.runway);
    final total = weights.values.fold(0.0, (a, b) => a + b);
    var r = _rng.nextDouble() * total;
    for (final e in weights.entries) {
      r -= e.value;
      if (r <= 0) return e.key;
    }
    return SectionType.tunnel;
  }

  void _maybeAddPortals(double x0, Difficulty d) {
    if (_sections < 2) return;
    if (allowSpeedPortals && _rng.nextDouble() < 0.3) {
      final options = [
        PortalKind.speedSlow,
        PortalKind.speedNormal,
        PortalKind.speedFast,
        if (d.t > 0.45) PortalKind.speedVeryFast,
      ]..removeWhere((k) => k.speedMultiplier == _mode.speedMultiplier);
      final kind = options[_rng.nextInt(options.length)];
      level.portals.add(Portal(x0, kind));
      _mode = _mode.apply(kind);
    }
    if (allowMiniPortals && _rng.nextDouble() < (_mode.mini ? 0.55 : 0.25)) {
      final kind = _mode.mini ? PortalKind.miniOff : PortalKind.miniOn;
      level.portals.add(Portal(x0 + 0.01, kind));
      _mode = _mode.apply(kind);
    }
  }

  void _addSection() {
    final x0 = generatedTo;
    final d = Difficulty(difficultyAt(x0));
    _maybeAddPortals(x0, d);
    final type = _pickType(d);

    final mini = _mode.mini;
    final slope = LevelData.slopeFor(mini);
    final speed = level.baseSpeed * _mode.speedMultiplier;
    final radius = LevelData.radiusFor(mini);
    final length = type == SectionType.runway ? 12.0 : _rand(20, 34) * _mode.speedMultiplier;

    final gap = d.tunnelGap * (mini ? 1.35 : 1.0);
    final lo = type == SectionType.tunnel ? math.max(_pathLo, 0.9 + gap / 2) : _pathLo;
    final hi = type == SectionType.tunnel ? math.min(_pathHi, LevelData.worldHeight - 0.9 - gap / 2) : _pathHi;

    final path = _genPath(x0, x0 + length, lo, hi, slope, speed, d);
    final x1 = path.last.x;

    final clearance = radius * LevelData.hazardRadiusFactor + d.margin + _stepSlack;
    if (type == SectionType.tunnel) {
      _addFunnelledWall(level.floor, path, -gap / 2, slope);
      _addFunnelledWall(level.ceiling, path, gap / 2, slope);
      // Tunnel walls are slide surfaces, so the challenge in a tunnel is
      // the small spikes lining them.
      _placeWallSpikes(path, gap, clearance, d);
    } else {
      _addWalls(x0, x1, _roomFloor, _roomCeiling);
      if (type != SectionType.runway) {
        _placeHazards(type, path, x0, x1, clearance, d);
      }
    }

    safePath.addAll(path.skip(1));
    generatedTo = x1;
    _pathY = path.last.y;
    _lastType = type;
    _sections++;
  }

  /// Zig-zag path from (x0, _pathY) to at least x1, slopes exactly ±slope,
  /// every straight run at least `minSegTime` of flight long (reaction time).
  List<Vec> _genPath(double x0, double x1, double lo, double hi, double slope, double speed, Difficulty d) {
    final pts = <Vec>[Vec(x0, _pathY)];
    var x = x0, y = _pathY;
    // Cap segment lengths so the band [lo, hi] can always fit two of them.
    final band = math.max(0.5, hi - lo);
    final minSeg = math.min(d.minSegTime * speed, band / slope * 0.45);
    final maxSeg = math.max(minSeg, math.min(d.maxSegTime * speed, band / slope));

    var guard = 0;
    while (x < x1 && guard++ < 1000) {
      var up = !_up; // prefer a corner
      double room(bool goingUp) => goingUp ? (hi - y) / slope : (y - lo) / slope;
      if (y < lo) {
        up = true;
      } else if (y > hi) {
        up = false;
      } else if (room(up) < minSeg) {
        up = !up; // not enough space to turn this way: keep going straight
      }
      final maxLen = y < lo || y > hi ? maxSeg : math.max(minSeg, room(up));
      final len = math.min(_rand(minSeg, maxSeg), maxLen);
      x += len;
      y += (up ? 1 : -1) * slope * len;
      // Collinear continuation just extends the previous point.
      if (up == _up && pts.length > 1) pts.removeLast();
      pts.add(Vec(x, y));
      _up = up;
    }
    return pts;
  }

  /// Height of the guaranteed-safe path at [x] (binary search — the
  /// home-screen autopilot calls this every frame on an ever-growing path).
  double safePathYAt(double x) {
    final i = LevelData.lowerBound<Vec>(safePath, x, (p) => p.x);
    if (i <= 0) return safePath.first.y;
    if (i >= safePath.length) return safePath.last.y;
    final a = safePath[i - 1], b = safePath[i];
    return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
  }

  static double pathYAt(List<Vec> path, double x) {
    if (x <= path.first.x) return path.first.y;
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i], b = path[i + 1];
      if (x <= b.x) return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
    }
    return path.last.y;
  }

  /// Minimum distance from the safe path (sampled) within [xa, xb] to a
  /// shape given by [dist].
  double _pathClearance(List<Vec> path, double xa, double xb, double Function(double x, double y) dist) {
    var best = double.infinity;
    final from = math.max(xa, path.first.x), to = math.min(xb, path.last.x);
    for (var x = from; x <= to; x += 0.05) {
      best = math.min(best, dist(x, pathYAt(path, x)));
    }
    return best;
  }

  void _placeHazards(SectionType type, List<Vec> path, double x0, double x1, double clearance, Difficulty d) {
    final newSpikes = <Spike>[];
    final newSaws = <Saw>[];
    var onFloor = _rng.nextBool();
    var x = x0 + 2.0;
    while (x < x1 - 2.0) {
      final useSaw = switch (type) {
        SectionType.sawRoom => _rng.nextDouble() < 0.85,
        SectionType.mixedRoom => _rng.nextDouble() < 0.45,
        _ => false,
      };
      if (useSaw) {
        final saw = _tryPlaceSaw(path, x, clearance);
        if (saw != null) newSaws.add(saw);
      } else {
        final spike = _tryPlaceSpike(path, x, onFloor, clearance);
        if (spike != null) newSpikes.add(spike);
      }
      if (_rng.nextDouble() < 0.8) onFloor = !onFloor;
      x += d.hazardSpacing * _rand(0.8, 1.4);
    }
    newSpikes.sort((a, b) => a.minX.compareTo(b.minX));
    newSaws.sort((a, b) => a.x.compareTo(b.x));
    level.spikes.addAll(newSpikes);
    level.saws.addAll(newSaws);
  }

  /// Tunnel wall following the safe path at [offset], but entered through a
  /// funnel: from wherever the previous section's wall ended, it slopes
  /// toward the tunnel at the wave's own slope (a slide surface) instead of
  /// jumping there as a vertical cliff the wave would smash into. The
  /// funnel always stays on the outer side of the tunnel wall, so the safe
  /// path's clearance is untouched.
  void _addFunnelledWall(List<Vec> wall, List<Vec> path, double offset, double slope) {
    final ceiling = offset > 0;
    final x0 = path.first.x;
    double target(double x) => pathYAt(path, x) + offset;
    final start = wall.isEmpty ? target(x0) : wall.last.y;
    // Only funnel when the tunnel is narrower (wall moving inward);
    // widening is a harmless drop.
    final inward = ceiling ? start > target(x0) : start < target(x0);
    var from = 0;
    if (inward) {
      double ramp(double x) => start + (ceiling ? -1 : 1) * slope * (x - x0);
      bool reached(double x) => ceiling ? ramp(x) <= target(x) : ramp(x) >= target(x);
      var xm = x0;
      while (!reached(xm) && xm < path.last.x) {
        xm += 0.02;
      }
      _addWallPoint(wall, Vec(x0, start));
      _addWallPoint(wall, Vec(xm, target(xm)));
      while (from < path.length && path[from].x <= xm) {
        from++;
      }
    }
    for (var i = from; i < path.length; i++) {
      _addWallPoint(wall, Vec(path[i].x, path[i].y + offset));
    }
  }

  /// Small spikes standing perpendicular on a tunnel's floor/ceiling (which
  /// follow the safe path at ±gap/2), sized to keep clear of the path.
  void _placeWallSpikes(List<Vec> path, double gap, double clearance, Difficulty d) {
    final added = <Spike>[];
    var onFloor = _rng.nextBool();
    var x = path.first.x + 1.5;
    while (x < path.last.x - 1.5) {
      const w = 0.8;
      final side = onFloor ? -1.0 : 1.0;
      final a = Vec(x, pathYAt(path, x) + side * gap / 2);
      final b = Vec(x + w, pathYAt(path, x + w) + side * gap / 2);
      // Unit normal pointing into the corridor.
      final len = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
      var nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len;
      if (!onFloor) {
        nx = -nx;
        ny = -ny;
      }
      final mid = Vec((a.x + b.x) / 2, (a.y + b.y) / 2);
      for (var h = 0.9; h >= 0.4; h -= 0.1) {
        final c = Vec(mid.x + nx * h, mid.y + ny * h);
        final clear =
            _pathClearance(path, x - 2, x + w + 2, (px, py) => LevelData.distanceToTriangle(px, py, a, b, c));
        if (clear >= clearance) {
          added.add(onFloor ? Spike(a, b, c, fromCeiling: false) : Spike(b, a, c, fromCeiling: true));
          break;
        }
      }
      if (_rng.nextDouble() < 0.7) onFloor = !onFloor;
      x += d.hazardSpacing * _rand(1.0, 1.8);
    }
    added.sort((p, q) => p.minX.compareTo(q.minX));
    level.spikes.addAll(added);
  }

  Spike? _tryPlaceSpike(List<Vec> path, double x, bool onFloor, double clearance) {
    final w = _rand(1.0, 1.8);
    final baseY = onFloor ? _roomFloor : _roomCeiling;
    // Tallest spike the path's lowest (or highest) point above it allows.
    var pathExtreme = onFloor ? double.infinity : double.negativeInfinity;
    for (var sx = x; sx <= x + w; sx += 0.1) {
      final py = pathYAt(path, sx);
      pathExtreme = onFloor ? math.min(pathExtreme, py) : math.max(pathExtreme, py);
    }
    var h = ((pathExtreme - baseY).abs() - clearance) * _rand(0.8, 1.0);
    for (var attempt = 0; attempt < 10 && h >= 0.7; attempt++) {
      final tipY = onFloor ? baseY + h : baseY - h;
      final a = Vec(x, baseY), b = Vec(x + w, baseY), c = Vec(x + w / 2, tipY);
      final clear = _pathClearance(
          path, x - 2, x + w + 2, (px, py) => LevelData.distanceToTriangle(px, py, a, b, c));
      if (clear >= clearance) {
        return onFloor ? Spike(a, b, c, fromCeiling: false) : Spike(b, a, c, fromCeiling: true);
      }
      h *= 0.85;
    }
    return null;
  }

  Saw? _tryPlaceSaw(List<Vec> path, double x, double clearance) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final r = _rand(0.45, 1.0);
      final sx = x + r;
      final sy = _rand(_roomFloor + 0.2, _roomCeiling - 0.2);
      final clear = _pathClearance(path, sx - r - 2, sx + r + 2, (px, py) {
        final dx = px - sx, dy = py - sy;
        return math.sqrt(dx * dx + dy * dy) - r;
      });
      if (clear >= clearance) return Saw(sx, sy, r);
    }
    return null;
  }
}

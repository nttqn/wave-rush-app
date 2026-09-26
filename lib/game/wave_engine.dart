import 'dart:math' as math;

import 'level_data.dart';
import 'level_generator.dart';

enum RunState { ready, playing, dead, won }

class Particle {
  double x, y, vx, vy, life;
  final double maxLife;
  final double size;
  Particle(this.x, this.y, this.vx, this.vy, this.maxLife, this.size) : life = maxLife;
}

/// Game state + fixed-timestep simulation of one level (or endless run).
///
/// Pure Dart: the screen feeds it frame deltas and hold/release input, and
/// reads its public fields to paint. Physics always advances in [fixedDt]
/// steps — the exact same step `LevelSolver` uses — so "the solver says
/// it's beatable" means beatable in the real game too.
class WaveEngine {
  static const double fixedDt = 1 / 120;

  /// Pause between crashing and the automatic restart (levels only —
  /// endless shows a game-over panel instead).
  static const double restartDelay = 0.75;

  final LevelData level;
  final LevelBuilder? endlessBuilder;
  bool get endless => endlessBuilder != null;

  RunState state = RunState.ready;
  double x = 0;
  late double y = level.startY;
  bool holding = false;
  ModeState mode = ModeState.initial;
  int _nextPortal = 0;

  int attempts = 1;

  /// Total elapsed time (drives animations, keeps running while dead).
  double time = 0;

  /// Time spent flying in the current attempt.
  double runTime = 0;

  /// Time since the last death / win.
  double stateTimer = 0;

  /// Best progress (0..1) reached in any attempt this session.
  double bestProgress = 0;

  /// Corner points of the wave's zig-zag trail, oldest first. The current
  /// head (x, y) is not included.
  final List<Vec> trail = [];
  final List<Particle> particles = [];

  void Function()? onDeath;
  void Function()? onWin;
  void Function()? onRestart;
  void Function(PortalKind kind)? onPortal;

  final math.Random _fxRng = math.Random();
  double _acc = 0;

  WaveEngine({required this.level, this.endlessBuilder}) {
    _ensureGenerated();
  }

  double get speed => level.baseSpeed * mode.speedMultiplier;
  double get slope => LevelData.slopeFor(mode.mini);
  double get radius => LevelData.radiusFor(mode.mini);

  /// Vertical velocity sign right now (+1 rising, -1 falling).
  double get direction => holding ? 1 : -1;

  double get progress => endless ? 0 : (x / level.length).clamp(0.0, 1.0);

  /// Endless-mode score: metres flown.
  int get distance => x.floor();

  /// Angle the wave actually moved at in the last step (radians) — flat
  /// while sliding along the ground, the surface's angle on a slope.
  double heading = 0;

  /// True while pressed against a floor/ceiling slide surface.
  bool sliding = false;

  /// Vertical movement of the previous step; a change means a trail corner.
  double _lastDy = double.nan;

  void setHolding(bool value) {
    if (value == holding) return;
    holding = value;
    if (state == RunState.ready && value) {
      state = RunState.playing;
      trail.add(Vec(x, y));
    }
  }

  void update(double frameDt) {
    frameDt = math.min(frameDt, 0.05);
    time += frameDt;
    _updateParticles(frameDt);

    switch (state) {
      case RunState.ready:
        return;
      case RunState.playing:
        _acc += frameDt;
        while (_acc >= fixedDt && state == RunState.playing) {
          _acc -= fixedDt;
          _step();
        }
      case RunState.dead:
        stateTimer += frameDt;
        if (!endless && stateTimer >= restartDelay) restart();
      case RunState.won:
        stateTimer += frameDt;
    }
  }

  void _ensureGenerated() {
    endlessBuilder?.extendTo(x + 80);
  }

  void _step() {
    _ensureGenerated();
    final portals = level.portals;
    while (_nextPortal < portals.length && portals[_nextPortal].x <= x) {
      final p = portals[_nextPortal++];
      mode = mode.apply(p.kind);
      trail.add(Vec(x, y));
      onPortal?.call(p.kind);
    }

    runTime += fixedDt;
    final dx = speed * fixedDt;
    final wanted = direction * slope * dx;
    final ny = level.resolveStep(x + dx, y, wanted, dx, radius);
    x += dx;
    if (ny == null) {
      y += wanted;
      _die();
      return;
    }

    final actualDy = ny - y;
    // Record a trail corner wherever the real path bends (turns, landing
    // on or leaving a slide surface, slope changes while sliding).
    if (_lastDy.isNaN || (actualDy - _lastDy).abs() > 1e-6) trail.add(Vec(x - dx, y));
    _lastDy = actualDy;
    sliding = (actualDy - wanted).abs() > 1e-9;
    heading = math.atan2(actualDy, dx);
    y = ny;

    // Keep the trail bounded — only the last ~2 screens are ever drawn.
    if (trail.length > 2 && trail[1].x < x - 60) trail.removeAt(0);

    if (!endless) bestProgress = math.max(bestProgress, progress);

    if (x >= level.length) {
      state = RunState.won;
      stateTimer = 0;
      bestProgress = 1;
      _burst(40, 6, 1.4);
      onWin?.call();
    }
  }

  void _die() {
    state = RunState.dead;
    stateTimer = 0;
    _burst(28, 9, 0.9);
    onDeath?.call();
  }

  void _burst(int count, double power, double life) {
    for (var i = 0; i < count; i++) {
      final a = _fxRng.nextDouble() * math.pi * 2;
      final v = power * (0.3 + _fxRng.nextDouble() * 0.7);
      particles.add(Particle(x, y, math.cos(a) * v, math.sin(a) * v, life * (0.5 + _fxRng.nextDouble() * 0.5),
          0.08 + _fxRng.nextDouble() * 0.16));
    }
  }

  void _updateParticles(double dt) {
    for (final p in particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.96;
      p.vy *= 0.96;
    }
    particles.removeWhere((p) => p.life <= 0);
  }

  /// Instant restart from the beginning (levels) — also used by the pause
  /// menu and the endless "retry" button.
  void restart() {
    if (state != RunState.ready) attempts++;
    x = 0;
    y = level.startY;
    mode = ModeState.initial;
    _nextPortal = 0;
    runTime = 0;
    stateTimer = 0;
    _acc = 0;
    _lastDy = double.nan;
    heading = 0;
    sliding = false;
    trail.clear();
    // Keep flying if the player is still holding from before the crash —
    // that's what makes restarts feel instant.
    state = RunState.playing;
    onRestart?.call();
  }
}

class SolveResult {
  final bool solved;
  final double reachedX;
  const SolveResult(this.solved, this.reachedX);
}

/// Exhaustive reachability check: simulates every hold/release choice at
/// every fixed step (merging near-identical heights into buckets) and
/// reports whether any sequence reaches the finish line.
class LevelSolver {
  static SolveResult solve(LevelData level, {double? untilX, double bucket = 0.03}) {
    final end = untilX ?? level.length;
    var x = 0.0;
    var mode = ModeState.initial;
    var nextPortal = 0;
    var states = <int, double>{(level.startY / bucket).round(): level.startY};
    while (x < end) {
      while (nextPortal < level.portals.length && level.portals[nextPortal].x <= x) {
        mode = mode.apply(level.portals[nextPortal++].kind);
      }
      final speed = level.baseSpeed * mode.speedMultiplier;
      final dy = LevelData.slopeFor(mode.mini) * speed * WaveEngine.fixedDt;
      final r = LevelData.radiusFor(mode.mini);
      final nx = x + speed * WaveEngine.fixedDt;
      final next = <int, double>{};
      for (final y in states.values) {
        for (final move in [dy, -dy]) {
          final ny = level.resolveStep(nx, y, move, nx - x, r);
          if (ny == null) continue;
          next.putIfAbsent((ny / bucket).round(), () => ny);
        }
      }
      if (next.isEmpty) return SolveResult(false, x);
      states = next;
      x = nx;
    }
    return SolveResult(true, x);
  }
}

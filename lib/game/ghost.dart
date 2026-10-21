import 'level_data.dart';
import 'wave_engine.dart';

/// A recorded attempt: how far it got and the steps where the input
/// flipped (see [WaveEngine.inputLog]).
class GhostRecord {
  final double progress;
  final int steps;
  final List<int> toggles;
  const GhostRecord({required this.progress, required this.steps, required this.toggles});

  /// Better = got further, or finished in fewer steps.
  bool beats(GhostRecord? other) {
    if (other == null) return true;
    if (progress != other.progress) return progress > other.progress;
    return progress >= 1 && steps < other.steps;
  }

  Map<String, dynamic> toJson() => {'p': progress, 's': steps, 't': toggles};

  static GhostRecord? fromJson(Map<String, dynamic> j) {
    try {
      return GhostRecord(
        progress: (j['p'] as num).toDouble(),
        steps: (j['s'] as num).toInt(),
        toggles: [for (final t in j['t'] as List) (t as num).toInt()],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Replays a [GhostRecord] on its own engine, kept in lockstep with the
/// player's attempt by [advanceTo]. Physics is fixed-step and deterministic,
/// so the replay retraces the recorded run exactly.
class GhostRunner {
  final GhostRecord record;
  final WaveEngine engine;
  int _next = 0;

  GhostRunner(LevelData level, this.record) : engine = WaveEngine(level: level) {
    engine.state = RunState.playing;
    engine.trail.add(Vec(0, level.startY));
  }

  bool get active => engine.state == RunState.playing;

  /// Simulates until the ghost has taken [steps] fixed steps.
  void advanceTo(int steps) {
    while (engine.stepIndex < steps && engine.state == RunState.playing) {
      while (_next < record.toggles.length && record.toggles[_next] <= engine.stepIndex) {
        _next++;
      }
      engine.holding = _next.isOdd; // starts released; each toggle flips it
      engine.stepOnce();
    }
  }
}

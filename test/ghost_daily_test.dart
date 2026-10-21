import 'package:flutter_test/flutter_test.dart';
import 'package:wave_rush/game/daily.dart';
import 'package:wave_rush/game/ghost.dart';
import 'package:wave_rush/game/level_generator.dart';
import 'package:wave_rush/game/levels.dart';
import 'package:wave_rush/game/wave_engine.dart';

void main() {
  group('ghost', () {
    test('replaying the input log retraces the attempt exactly', () {
      // Fly level 13 by following its safe path with a frame-based input
      // (like a real player would), then replay the recorded log.
      final built = kLevels.firstWhere((d) => d.id == 13).buildWithPath();
      final e = WaveEngine(level: built.level);
      e.setHolding(true);
      for (var i = 0; i < 400 && e.state == RunState.playing; i++) {
        e.setHolding(LevelBuilder.pathYAt(built.safePath, e.x + 0.1) > e.y);
        e.update(1 / 60);
      }
      final record = GhostRecord(progress: e.progress, steps: e.stepIndex, toggles: List.of(e.inputLog));
      expect(record.toggles.length, greaterThan(5));

      final ghost = GhostRunner(built.level, record)..advanceTo(e.stepIndex);
      expect(ghost.engine.x, closeTo(e.x, 1e-9));
      expect(ghost.engine.y, closeTo(e.y, 1e-9));
    });

    test('a ghost of a crash stops where the crash happened', () {
      final level = kLevels.first.build();
      final e = WaveEngine(level: level);
      e.setHolding(true); // hold forever: slides on the ceiling into the level
      double? crashX;
      e.onDeath = () => crashX ??= e.x;
      for (var i = 0; i < 1200 && crashX == null; i++) {
        e.update(1 / 60);
      }
      expect(crashX, isNotNull);
      final record = GhostRecord(progress: e.progress, steps: e.stepIndex, toggles: List.of(e.inputLog));
      final ghost = GhostRunner(level, record)..advanceTo(record.steps + 500);
      expect(ghost.active, isFalse);
      expect(ghost.engine.x, closeTo(crashX!, 1e-9));
    });

    test('records compare by progress, then by finishing time', () {
      const a = GhostRecord(progress: 0.5, steps: 100, toggles: []);
      const b = GhostRecord(progress: 0.7, steps: 300, toggles: []);
      const fast = GhostRecord(progress: 1, steps: 900, toggles: []);
      const slow = GhostRecord(progress: 1, steps: 1000, toggles: []);
      expect(b.beats(a), isTrue);
      expect(a.beats(b), isFalse);
      expect(fast.beats(slow), isTrue);
      expect(slow.beats(fast), isFalse);
      expect(a.beats(null), isTrue);
    });

    test('JSON round trip', () {
      const r = GhostRecord(progress: 0.42, steps: 777, toggles: [0, 12, 40]);
      final back = GhostRecord.fromJson(r.toJson())!;
      expect(back.progress, 0.42);
      expect(back.steps, 777);
      expect(back.toggles, [0, 12, 40]);
      expect(GhostRecord.fromJson({'p': 'x'}), isNull);
    });
  });

  group('daily', () {
    test('same date gives the same level, different dates differ', () {
      final a = DailyChallenge(DateTime(2026, 10, 21)).def.build();
      final b = DailyChallenge(DateTime(2026, 10, 21, 23, 59)).def.build();
      final c = DailyChallenge(DateTime(2026, 10, 22)).def.build();
      expect(a.spikes.length, b.spikes.length);
      expect(a.floor.last.y, b.floor.last.y);
      expect(a.spikes.length == c.spikes.length && a.saws.length == c.saws.length, isFalse);
    });

    test('two weeks of dailies are all beatable', () {
      for (var i = 0; i < 14; i++) {
        final day = DailyChallenge(DateTime(2026, 10, 19 + i));
        final result = LevelSolver.solve(day.def.build());
        expect(result.solved, isTrue, reason: '${day.key} stuck at ${result.reachedX.toStringAsFixed(1)}');
      }
    });

    test('streak counts back from today, or from yesterday if today is not cleared', () {
      final today = DateTime(2026, 10, 21);
      expect(DailyChallenge.streak({}, today), 0);
      expect(DailyChallenge.streak({'20261021'}, today), 1);
      expect(DailyChallenge.streak({'20261019', '20261020'}, today), 2); // today still open
      expect(DailyChallenge.streak({'20261019', '20261020', '20261021'}, today), 3);
      expect(DailyChallenge.streak({'20261018', '20261020'}, today), 1); // gap on the 19th
      // Across a month boundary.
      expect(DailyChallenge.streak({'20261030', '20261031', '20261101'}, DateTime(2026, 11, 1)), 3);
    });
  });
}

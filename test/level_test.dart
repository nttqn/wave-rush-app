import 'package:flutter_test/flutter_test.dart';
import 'package:wave_rush/game/level_data.dart';
import 'package:wave_rush/game/levels.dart';
import 'package:wave_rush/game/wave_engine.dart';

void main() {
  group('generated levels', () {
    for (final def in kLevels) {
      test('level ${def.id} "${def.name}" is beatable', () {
        final level = def.build();
        expect(level.length.isFinite, isTrue);
        expect(level.spikes.length + level.saws.length, greaterThan(5));
        final result = LevelSolver.solve(level);
        expect(result.solved, isTrue, reason: 'stuck at x=${result.reachedX.toStringAsFixed(1)} of ${level.length}');
      });
    }

    test('same seed builds identical geometry', () {
      final a = kLevels[4].build(), b = kLevels[4].build();
      expect(a.spikes.length, b.spikes.length);
      expect(a.floor.length, b.floor.length);
      expect(a.floor.last.y, b.floor.last.y);
    });

    test('wall polylines have strictly increasing x', () {
      for (final def in kLevels) {
        final level = def.build();
        for (final wall in [level.floor, level.ceiling]) {
          for (var i = 1; i < wall.length; i++) {
            expect(wall[i].x, greaterThan(wall[i - 1].x), reason: 'level ${def.id}');
          }
        }
      }
    });

    for (final seed in [1, 2, 3]) {
      test('endless run seed $seed is beatable for 2500m', () {
        final builder = buildEndless(seed);
        builder.extendTo(2600);
        final result = LevelSolver.solve(builder.level, untilX: 2500);
        expect(result.solved, isTrue, reason: 'stuck at x=${result.reachedX.toStringAsFixed(1)}');
      });
    }
  });

  group('engine', () {
    LevelData openLevel() {
      final level = LevelData(baseSpeed: 8, length: 50);
      level.floor.addAll(const [Vec(-10, 0.5), Vec(100, 0.5)]);
      level.ceiling.addAll(const [Vec(-10, 9.5), Vec(100, 9.5)]);
      return level;
    }

    test('waits for the first touch, then flies diagonally', () {
      final e = WaveEngine(level: openLevel());
      e.update(0.5);
      expect(e.x, 0);
      e.setHolding(true);
      expect(e.state, RunState.playing);
      for (var i = 0; i < 12; i++) {
        e.update(1 / 60);
      }
      expect(e.x, closeTo(8 * 0.2, 0.05));
      expect(e.y - 5, closeTo(e.x, 0.01)); // 45° while holding
    });

    test('crashes into the floor when never holding, then auto-restarts', () {
      var deaths = 0;
      final e = WaveEngine(level: openLevel())..onDeath = () => deaths++;
      e.setHolding(true);
      e.setHolding(false);
      for (var i = 0; i < 60; i++) {
        e.update(1 / 60);
      }
      expect(deaths, 1);
      for (var i = 0; i < 60; i++) {
        e.update(1 / 60);
      }
      expect(e.attempts, 2);
      expect(e.state, isNot(RunState.ready));
    });

    test('reaches the finish by zig-zagging', () {
      var won = false;
      final e = WaveEngine(level: openLevel())..onWin = () => won = true;
      e.setHolding(true);
      var t = 0.0;
      while (!won && e.state != RunState.dead && t < 20) {
        e.setHolding(e.y < 5);
        e.update(1 / 60);
        t += 1 / 60;
      }
      expect(won, isTrue);
      expect(e.progress, 1.0);
    });

    test('speed and mini portals change flight', () {
      final level = openLevel()
        ..portals.addAll(const [Portal(2, PortalKind.speedFast), Portal(2.01, PortalKind.miniOn)]);
      final e = WaveEngine(level: level);
      e.setHolding(true);
      e.setHolding(false);
      e.setHolding(true);
      for (var i = 0; i < 30; i++) {
        e.setHolding(e.y < 5);
        e.update(1 / 60);
      }
      expect(e.mode.mini, isTrue);
      expect(e.speed, closeTo(10, 1e-9));
      expect(e.slope, LevelData.miniSlope);
    });
  });
}

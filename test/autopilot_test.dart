import 'package:flutter_test/flutter_test.dart';
import 'package:wave_rush/game/levels.dart';
import 'package:wave_rush/game/wave_engine.dart';

/// The home screen's background run is flown by an autopilot that follows
/// the generator's safe path. Endless now has FLIP portals, so the
/// autopilot must account for reversed controls (WaveEngine.holdToReach),
/// or it crashes at the first flip.
void main() {
  for (final seed in [7, 21, 99]) {
    test('home autopilot flies an endless course through flips and twins (seed $seed)', () {
      final builder = buildEndless(seed);
      final e = WaveEngine(level: builder.level, endlessBuilder: builder)..setHolding(true);
      var sawReverse = false, sawDual = false;
      for (var i = 0; i < 60 * 150 && e.state == RunState.playing && e.x < 1400; i++) {
        final lookahead = e.speed * WaveEngine.fixedDt;
        e.setHolding(e.holdToReach(builder.safePathYAt(e.x + lookahead)));
        e.update(1 / 60);
        sawReverse |= e.mode.reversed;
        sawDual |= e.mode.dual;
      }
      expect(e.state, RunState.playing, reason: 'crashed at x=${e.x.toStringAsFixed(1)}');
      expect(sawReverse && sawDual, isTrue, reason: 'course should exercise both new portals');
    });
  }
}

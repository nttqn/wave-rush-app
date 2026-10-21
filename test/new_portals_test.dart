import 'package:flutter_test/flutter_test.dart';
import 'package:wave_rush/game/level_data.dart';
import 'package:wave_rush/game/levels.dart';
import 'package:wave_rush/game/wave_engine.dart';

LevelData _open({List<Portal> portals = const [], List<Spike> spikes = const []}) {
  final level = LevelData(baseSpeed: 8, length: 60)
    ..floor.addAll(const [Vec(-10, 0.5), Vec(100, 0.5)])
    ..ceiling.addAll(const [Vec(-10, 9.5), Vec(100, 9.5)])
    ..portals.addAll(portals)
    ..spikes.addAll(spikes);
  return level;
}

void _fly(WaveEngine e, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    e.update(1 / 60);
  }
}

void main() {
  test('reverse portal makes holding dive', () {
    final e = WaveEngine(level: _open(portals: const [Portal(1, PortalKind.reverseOn)]));
    e.setHolding(true);
    _fly(e, 0.4); // past the portal, still holding
    final y0 = e.y;
    _fly(e, 0.2);
    expect(e.mode.reversed, isTrue);
    expect(e.y, lessThan(y0));
  });

  test('reverse off restores normal controls', () {
    final e = WaveEngine(
      level: _open(portals: const [Portal(1, PortalKind.reverseOn), Portal(3, PortalKind.reverseOff)]),
    );
    e.setHolding(true);
    _fly(e, 0.6);
    final y0 = e.y;
    _fly(e, 0.2);
    expect(e.mode.reversed, isFalse);
    expect(e.y, greaterThan(y0));
  });

  test('the dual twin is killed by a hazard on its mirrored side', () {
    // Spike only reachable by the twin: the real wave flies high (holding,
    // sliding on the ceiling), so its mirror skims the floor where the spike is.
    var deaths = 0;
    double? deathX;
    late final WaveEngine e;
    e = WaveEngine(
      level: _open(
        portals: const [Portal(1, PortalKind.dualOn)],
        spikes: [Spike(const Vec(8, 0.5), const Vec(9, 0.5), const Vec(8.5, 2.5), fromCeiling: false)],
      ),
    )..onDeath = () {
        deaths++;
        deathX ??= e.x; // read now: the level auto-restarts 0.75s later
      };
    e.setHolding(true);
    _fly(e, 1.5);
    expect(deaths, 1);
    expect(deathX, closeTo(8.4, 0.6));
  });

  test('without dual, the same spike is harmless to a wave flying high', () {
    var deaths = 0;
    final e = WaveEngine(
      level: _open(spikes: [Spike(const Vec(8, 0.5), const Vec(9, 0.5), const Vec(8.5, 2.5), fromCeiling: false)]),
    )..onDeath = () => deaths++;
    e.setHolding(true);
    _fly(e, 2.0);
    expect(deaths, 0);
  });

  test('dual corridor is the overlap of the real and mirrored corridors', () {
    // Floor raised to 3 → mirrored ceiling at 7: the real wave must stay below it.
    final level = LevelData(baseSpeed: 8, length: 60)
      ..floor.addAll(const [Vec(-10, 3), Vec(100, 3)])
      ..ceiling.addAll(const [Vec(-10, 9.5), Vec(100, 9.5)])
      ..portals.add(const Portal(0, PortalKind.dualOn));
    final e = WaveEngine(level: level);
    e.setHolding(true);
    _fly(e, 1.5);
    expect(e.state, RunState.playing);
    expect(e.y, closeTo(7 - LevelData.normalRadius, 1e-9));
  });

  test('levels 13-16 use the new portals, and the shipped 12 do not', () {
    bool has(LevelData l, Set<PortalKind> kinds) => l.portals.any((p) => kinds.contains(p.kind));
    const reverse = {PortalKind.reverseOn, PortalKind.reverseOff};
    const dual = {PortalKind.dualOn, PortalKind.dualOff};
    for (final d in kLevels) {
      final l = d.build();
      if (d.id <= 12) {
        expect(has(l, reverse) || has(l, dual), isFalse, reason: 'level ${d.id}');
      }
      if (d.reversePortals) expect(has(l, reverse), isTrue, reason: 'level ${d.id} should flip');
      if (d.dualPortals) expect(has(l, dual), isTrue, reason: 'level ${d.id} should have a twin');
    }
  });

  test('dual portals always come in on/off pairs inside one level', () {
    for (final d in kLevels.where((d) => d.dualPortals)) {
      var on = false;
      for (final p in d.build().portals) {
        if (p.kind == PortalKind.dualOn) {
          expect(on, isFalse);
          on = true;
        } else if (p.kind == PortalKind.dualOff) {
          expect(on, isTrue);
          on = false;
        }
      }
      expect(on, isFalse, reason: 'level ${d.id} ends with the twin still active');
    }
  });
}

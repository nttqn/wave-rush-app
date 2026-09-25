import 'package:flutter_test/flutter_test.dart';
import 'package:wave_rush/game/custom_level.dart';
import 'package:wave_rush/game/level_data.dart';
import 'package:wave_rush/game/wave_engine.dart';

void main() {
  CustomLevel sample() {
    final l = CustomLevel.blank('id1', 'Sample')..setLength(120);
    l.setWallPoint(ceiling: false, x: 20, y: 0.5);
    l.setWallPoint(ceiling: false, x: 25, y: 3);
    l.setWallPoint(ceiling: true, x: 25, y: 7);
    l.addSpike(40, 0.5, up: true, size: 1);
    l.addSpike(50, 9.5, up: false, size: 2);
    l.addSaw(60, 5, size: 0);
    l.addPortal(70, PortalKind.speedFast);
    l.addPortal(80, PortalKind.miniOn);
    return l;
  }

  test('blank level is an open corridor that is beatable', () {
    final l = CustomLevel.blank('a', 'Blank');
    expect(LevelSolver.solve(l.toLevelData()).solved, isTrue);
  });

  test('wall points are sorted, replaced at the same x, and never close the corridor', () {
    final l = CustomLevel.blank('a', 'W');
    l.setWallPoint(ceiling: false, x: 30, y: 2);
    l.setWallPoint(ceiling: false, x: 10, y: 1);
    l.setWallPoint(ceiling: false, x: 30, y: 3);
    expect(l.floorPoints.map((p) => p.x), [0, 10, 30]);
    expect(l.floorPoints.last.y, 3);

    l.setWallPoint(ceiling: true, x: 30, y: 2); // below the floor
    expect(l.ceilingAt(30), greaterThanOrEqualTo(l.floorAt(30) + CustomLevel.minWallGap));
  });

  test('toLevelData builds strictly increasing walls covering lead-in and run-out', () {
    final data = sample().toLevelData();
    for (final wall in [data.floor, data.ceiling]) {
      expect(wall.first.x, lessThan(0));
      expect(wall.last.x, greaterThan(data.length));
      for (var i = 1; i < wall.length; i++) {
        expect(wall[i].x, greaterThan(wall[i - 1].x));
      }
    }
    expect(data.spikes.length, 2);
    expect(data.saws.length, 1);
    expect(data.portals.length, 2);
    expect(data.floorAt(25), 3);
  });

  test('spikes point the right way', () {
    final data = sample().toLevelData();
    final up = data.spikes.firstWhere((s) => !s.fromCeiling);
    final down = data.spikes.firstWhere((s) => s.fromCeiling);
    expect(up.c.y, greaterThan(up.a.y));
    expect(down.c.y, lessThan(down.a.y));
  });

  test('erase removes the nearest object only', () {
    final l = sample();
    expect(l.eraseNear(60.3, 5.2), isTrue);
    expect(l.saws, isEmpty);
    expect(l.spikes.length, 2);
    expect(l.eraseNear(200, 5), isFalse);
    // The wall start point can't be erased.
    expect(l.eraseNear(0, 0.5), isFalse);
  });

  test('any edit clears the verified flag', () {
    final l = sample()..verified = true;
    l.addSaw(90, 5);
    expect(l.verified, isFalse);
  });

  test('shortening the level drops objects past the finish', () {
    final l = sample()..setLength(55);
    expect(l.saws, isEmpty);
    expect(l.portals, isEmpty);
    expect(l.spikes.length, 2);
  });

  test('JSON round trip keeps everything', () {
    final a = sample()..verified = true;
    final b = CustomLevel.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
  });

  test('share codes round trip and never carry the verified flag', () {
    final a = sample()..verified = true;
    final code = a.toShareCode();
    expect(code, startsWith(CustomLevel.sharePrefix));
    final b = CustomLevel.fromShareCode(code, newId: 'new')!;
    expect(b.id, 'new');
    expect(b.verified, isFalse);
    expect(b.name, 'Sample');
    expect(b.spikes.length, 2);
    expect(b.portals.map((p) => p.kind), [PortalKind.speedFast, PortalKind.miniOn]);
  });

  test('garbage share codes are rejected', () {
    expect(CustomLevel.fromShareCode('hello', newId: 'x'), isNull);
    expect(CustomLevel.fromShareCode('${CustomLevel.sharePrefix}!!!', newId: 'x'), isNull);
  });

  test('solver finds a fully blocked level impossible and reports where', () {
    final l = CustomLevel.blank('a', 'Wall');
    // A saw column filling the whole corridor at x = 30.
    for (var y = 1.0; y < 10; y += 1.5) {
      l.addSaw(30, y, size: 2);
    }
    final result = LevelSolver.solve(l.toLevelData());
    expect(result.solved, isFalse);
    expect(result.reachedX, closeTo(30, 2));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wave_rush/game/level_data.dart';
import 'package:wave_rush/game/levels.dart';

/// Hash of every wall point, hazard and portal of a level.
int fingerprint(LevelData l) {
  var h = 0;
  void add(double v) => h = (h * 31 + (v * 1000).round()) & 0x7fffffff;
  for (final p in [...l.floor, ...l.ceiling]) {
    add(p.x);
    add(p.y);
  }
  for (final s in l.spikes) {
    add(s.a.x);
    add(s.a.y);
    add(s.c.x);
    add(s.c.y);
  }
  for (final s in l.saws) {
    add(s.x);
    add(s.y);
    add(s.radius);
  }
  for (final p in l.portals) {
    add(p.x);
    add(p.kind.index.toDouble());
  }
  add(l.length);
  return h;
}

/// Players' saved best % refers to each level's exact geometry, so the 12
/// shipped levels must never change. New mechanics may only appear in new
/// levels, Daily and Endless. If this fails, a generator change leaked into
/// the original levels: gate it behind a LevelDef flag instead.
const _shipped = {
  1: 521405332,
  2: 1598471703,
  3: 681296612,
  4: 201234659,
  5: 1361390704,
  6: 43455499,
  7: 2031565444,
  8: 1827474571,
  9: 371379027,
  10: 1389997187,
  11: 142371106,
  12: 565400119,
};

void main() {
  for (final e in _shipped.entries) {
    test('shipped level ${e.key} geometry is unchanged', () {
      final def = kLevels.firstWhere((d) => d.id == e.key);
      expect(fingerprint(def.build()), e.value);
    });
  }
}

import 'level_data.dart';
import 'level_generator.dart';

/// One hand-tuned entry of the level list. Geometry itself is generated
/// from [seed], so the same level is identical on every device and run.
class LevelDef {
  final int id;
  final String name;
  final int seed;

  /// Difficulty at the start / end of the level (0..1), ramped linearly.
  final double difficultyFrom;
  final double difficultyTo;
  final double baseSpeed;

  /// Approximate flight time in seconds at base speed.
  final double seconds;
  final bool speedPortals;
  final bool miniPortals;
  final int palette;
  final int music;

  const LevelDef({
    required this.id,
    required this.name,
    required this.seed,
    required this.difficultyFrom,
    required this.difficultyTo,
    required this.baseSpeed,
    required this.seconds,
    required this.palette,
    required this.music,
    this.speedPortals = true,
    this.miniPortals = true,
  });

  /// 1..5 "stars" shown on the level card.
  int get stars => (1 + difficultyTo * 4.2).floor().clamp(1, 5);

  String get difficultyLabel => const ['Easy', 'Normal', 'Hard', 'Harder', 'Insane'][stars - 1];

  LevelData build() {
    final level = LevelData(baseSpeed: baseSpeed);
    final target = seconds * baseSpeed;
    final builder = LevelBuilder(
      seed: seed,
      level: level,
      difficultyAt: (x) => difficultyFrom + (difficultyTo - difficultyFrom) * (x / target).clamp(0.0, 1.0),
      allowSpeedPortals: speedPortals,
      allowMiniPortals: miniPortals,
    );
    builder.extendTo(target);
    builder.finish();
    return level;
  }
}

const List<LevelDef> kLevels = [
  LevelDef(id: 1, name: 'Neon Drift', seed: 1101, difficultyFrom: 0.0, difficultyTo: 0.12, baseSpeed: 7, seconds: 40, palette: 0, music: 0, speedPortals: false, miniPortals: false),
  LevelDef(id: 2, name: 'Pulse Canyon', seed: 2207, difficultyFrom: 0.08, difficultyTo: 0.22, baseSpeed: 7.5, seconds: 45, palette: 1, music: 1, miniPortals: false),
  LevelDef(id: 3, name: 'Static Stream', seed: 3313, difficultyFrom: 0.15, difficultyTo: 0.32, baseSpeed: 8, seconds: 48, palette: 2, music: 2),
  LevelDef(id: 4, name: 'Hyper Tide', seed: 4441, difficultyFrom: 0.22, difficultyTo: 0.42, baseSpeed: 8, seconds: 50, palette: 3, music: 0),
  LevelDef(id: 5, name: 'Prism Rift', seed: 5557, difficultyFrom: 0.3, difficultyTo: 0.5, baseSpeed: 8.5, seconds: 52, palette: 4, music: 1),
  LevelDef(id: 6, name: 'Voltage', seed: 6661, difficultyFrom: 0.38, difficultyTo: 0.58, baseSpeed: 8.5, seconds: 55, palette: 5, music: 2),
  LevelDef(id: 7, name: 'Echo Chamber', seed: 7703, difficultyFrom: 0.45, difficultyTo: 0.66, baseSpeed: 9, seconds: 58, palette: 0, music: 0),
  LevelDef(id: 8, name: 'Razor Wind', seed: 8819, difficultyFrom: 0.52, difficultyTo: 0.74, baseSpeed: 9, seconds: 60, palette: 1, music: 1),
  LevelDef(id: 9, name: 'Cyber Surge', seed: 9923, difficultyFrom: 0.6, difficultyTo: 0.82, baseSpeed: 9.5, seconds: 62, palette: 2, music: 2),
  LevelDef(id: 10, name: 'Quantum Zig', seed: 10037, difficultyFrom: 0.68, difficultyTo: 0.9, baseSpeed: 9.5, seconds: 65, palette: 3, music: 0),
  LevelDef(id: 11, name: 'Eclipse', seed: 11149, difficultyFrom: 0.76, difficultyTo: 0.96, baseSpeed: 10, seconds: 68, palette: 4, music: 1),
  LevelDef(id: 12, name: 'Singularity', seed: 12251, difficultyFrom: 0.85, difficultyTo: 1.0, baseSpeed: 10, seconds: 72, palette: 5, music: 2),
];

/// Endless mode: difficulty keeps climbing with distance, levels off at max.
LevelBuilder buildEndless(int seed) {
  final level = LevelData(baseSpeed: 8);
  return LevelBuilder(
    seed: seed,
    level: level,
    difficultyAt: (x) => (x / 1600).clamp(0.0, 1.0),
  );
}

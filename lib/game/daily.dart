import 'levels.dart';

/// One generated level per calendar day, the same for every player (the
/// seed is the local date). Difficulty climbs through the week: Monday is
/// the gentlest, Sunday the hardest. Uses every portal type, and like all
/// generated levels it is beatable by construction.
class DailyChallenge {
  final DateTime date;
  DailyChallenge(DateTime d) : date = DateTime(d.year, d.month, d.day);
  factory DailyChallenge.today() => DailyChallenge(DateTime.now());

  static String keyFor(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// yyyymmdd, used for saves and the ghost.
  String get key => keyFor(date);

  int get seed => (int.parse(key) * 7919) % 2147483647;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String get label => '${_months[date.month - 1]} ${date.day}';

  LevelDef get def {
    final w = date.weekday - 1; // 0 = Monday .. 6 = Sunday
    final from = 0.2 + 0.07 * w;
    return LevelDef(
      id: 0, // not a numbered level; GameScreen saves Daily progress separately
      name: 'Daily: $label',
      seed: seed,
      difficultyFrom: from,
      difficultyTo: from + 0.22,
      baseSpeed: 8 + 0.25 * w,
      seconds: 45,
      palette: date.day % 6,
      music: 0,
      reversePortals: true,
      dualPortals: true,
    );
  }

  /// Consecutive cleared days ending today, or ending yesterday if today
  /// isn't cleared yet (so the streak isn't shown as lost before the day
  /// is over).
  static int streak(Set<String> clearedKeys, DateTime today) {
    var d = DateTime(today.year, today.month, today.day);
    if (!clearedKeys.contains(keyFor(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (clearedKeys.contains(keyFor(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }
}

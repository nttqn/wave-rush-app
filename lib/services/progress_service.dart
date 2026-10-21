import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/daily.dart';

/// Local save data: best % per level, completions, endless best, skin.
/// Everything is loaded once at startup into memory ([load]) so screens can
/// read it synchronously; writes go straight through to shared_preferences.
class ProgressService extends ChangeNotifier {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  SharedPreferences? _prefs;
  final Map<int, int> _bestPercent = {};
  final Map<int, int> _attempts = {};
  int endlessBest = 0;
  int selectedSkin = 0;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    for (final key in p.getKeys()) {
      if (key.startsWith('best_')) _bestPercent[int.parse(key.substring(5))] = p.getInt(key) ?? 0;
      if (key.startsWith('attempts_')) _attempts[int.parse(key.substring(9))] = p.getInt(key) ?? 0;
    }
    endlessBest = p.getInt('endless_best') ?? 0;
    selectedSkin = p.getInt('skin') ?? 0;
    // Daily keys deliberately don't start with "best_"/"attempts_": the
    // loop above parses those suffixes as level ids.
    _dailyCleared.addAll(p.getStringList('daily_cleared') ?? const []);
    notifyListeners();
  }

  // ----------------------------------------------------------------- daily

  final Set<String> _dailyCleared = {};

  int dailyBest(String key) => _prefs?.getInt('daily_best_$key') ?? 0;
  bool dailyCleared(String key) => _dailyCleared.contains(key);
  int get dailyStreak => DailyChallenge.streak(_dailyCleared, DateTime.now());

  void recordDaily(String key, double progress) {
    final percent = (progress * 100).floor().clamp(0, 100);
    if (percent > dailyBest(key)) _prefs?.setInt('daily_best_$key', percent);
    if (percent >= 100 && _dailyCleared.add(key)) {
      _prefs?.setStringList('daily_cleared', _dailyCleared.toList());
    }
    notifyListeners();
  }

  int bestPercent(int levelId) => _bestPercent[levelId] ?? 0;
  bool isCompleted(int levelId) => bestPercent(levelId) >= 100;
  int attempts(int levelId) => _attempts[levelId] ?? 0;
  int get completedCount => _bestPercent.values.where((v) => v >= 100).length;

  void recordAttempt(int levelId, double progress) {
    final percent = (progress * 100).floor().clamp(0, 100);
    _attempts[levelId] = attempts(levelId) + 1;
    _prefs?.setInt('attempts_$levelId', _attempts[levelId]!);
    if (percent > bestPercent(levelId)) {
      _bestPercent[levelId] = percent;
      _prefs?.setInt('best_$levelId', percent);
    }
    notifyListeners();
  }

  /// Returns true if [distance] is a new record.
  bool recordEndless(int distance) {
    if (distance <= endlessBest) return false;
    endlessBest = distance;
    _prefs?.setInt('endless_best', distance);
    notifyListeners();
    return true;
  }

  void selectSkin(int index) {
    selectedSkin = index;
    _prefs?.setInt('skin', index);
    notifyListeners();
  }
}

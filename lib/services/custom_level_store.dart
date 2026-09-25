import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/custom_level.dart';

/// Player-made levels, persisted as one JSON list in shared_preferences,
/// plus the best % reached on each.
class CustomLevelStore extends ChangeNotifier {
  CustomLevelStore._();
  static final CustomLevelStore instance = CustomLevelStore._();

  static const _levelsKey = 'custom_levels';

  final List<CustomLevel> levels = [];
  final Map<String, int> _best = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    levels.clear();
    try {
      final list = jsonDecode(prefs.getString(_levelsKey) ?? '[]') as List;
      for (final j in list) {
        try {
          levels.add(CustomLevel.fromJson(j as Map<String, dynamic>));
        } catch (_) {
          // Skip a single corrupt entry rather than losing every level.
        }
      }
    } catch (_) {}
    for (final l in levels) {
      _best[l.id] = prefs.getInt('custom_best_${l.id}') ?? 0;
    }
    _loaded = true;
    notifyListeners();
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  int bestPercent(String id) => _best[id] ?? 0;

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_levelsKey, jsonEncode([for (final l in levels) l.toJson()]));
  }

  /// Inserts or replaces (by id) and saves.
  Future<void> save(CustomLevel level) async {
    final i = levels.indexWhere((l) => l.id == level.id);
    if (i >= 0) {
      levels[i] = level;
    } else {
      levels.insert(0, level);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    levels.removeWhere((l) => l.id == id);
    _best.remove(id);
    notifyListeners();
    await _persist();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_best_$id');
  }

  void recordProgress(String id, double progress) {
    final percent = (progress * 100).floor().clamp(0, 100);
    if (percent <= bestPercent(id)) return;
    _best[id] = percent;
    SharedPreferences.getInstance().then((p) => p.setInt('custom_best_$id', percent));
    notifyListeners();
  }
}

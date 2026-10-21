import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/ghost.dart';

/// The best recorded attempt per level, for the ghost replay. Keys:
/// `L<id>` built-in levels, `D<yyyymmdd>` dailies, `C<id>` player levels.
class GhostStore {
  GhostStore._();
  static final GhostStore instance = GhostStore._();

  Future<GhostRecord?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ghost_$key');
      if (raw == null) return null;
      return GhostRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key, GhostRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ghost_$key', jsonEncode(record.toJson()));
    } catch (_) {}
  }
}

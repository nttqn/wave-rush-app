import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SoundEffect { death, portal, win, click }

/// Music loops + one-shot effects via `flame_audio`.
///
/// `init()` is fired unawaited from `main()` (never awaited before
/// `runApp()`): a broken asset can leave `AudioPool` creation hanging on
/// web, which would otherwise block the first frame. Every call here is a
/// safe no-op if loading hasn't finished or the sound is switched off.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const _musicKey = 'music_enabled';
  static const _sfxKey = 'sfx_enabled';
  static const musicFiles = ['music_0.wav', 'music_1.wav', 'music_2.wav'];

  static const Map<SoundEffect, String> _files = {
    SoundEffect.death: 'sfx_death.wav',
    SoundEffect.portal: 'sfx_portal.wav',
    SoundEffect.win: 'sfx_win.wav',
    SoundEffect.click: 'sfx_click.wav',
  };

  final ValueNotifier<bool> musicEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> sfxEnabled = ValueNotifier<bool>(true);
  final Map<SoundEffect, AudioPool> _pools = {};
  bool _bgmInitialized = false;
  int? _currentTrack;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    musicEnabled.value = prefs.getBool(_musicKey) ?? true;
    sfxEnabled.value = prefs.getBool(_sfxKey) ?? true;
    try {
      FlameAudio.bgm.initialize();
      _bgmInitialized = true;
      await FlameAudio.audioCache.loadAll(musicFiles).timeout(const Duration(seconds: 8));
    } catch (_) {}
    for (final entry in _files.entries) {
      try {
        _pools[entry.key] =
            await FlameAudio.createPool(entry.value, minPlayers: 1, maxPlayers: 3).timeout(const Duration(seconds: 5));
      } catch (_) {
        // That one effect just stays silent.
      }
    }
  }

  void play(SoundEffect effect) {
    if (!sfxEnabled.value) return;
    _pools[effect]?.start();
  }

  /// Starts [track] from the beginning — called on every attempt so the
  /// music lines up with the level, like the genre does.
  void startMusic(int track) {
    _currentTrack = track;
    if (!musicEnabled.value || !_bgmInitialized) return;
    try {
      FlameAudio.bgm.play(musicFiles[track % musicFiles.length], volume: 0.55);
    } catch (_) {}
  }

  void stopMusic() {
    _currentTrack = null;
    if (!_bgmInitialized) return;
    try {
      FlameAudio.bgm.stop();
    } catch (_) {}
  }

  void pauseMusic() {
    if (!_bgmInitialized) return;
    try {
      FlameAudio.bgm.pause();
    } catch (_) {}
  }

  void resumeMusic() {
    if (!musicEnabled.value || !_bgmInitialized || _currentTrack == null) return;
    try {
      FlameAudio.bgm.resume();
    } catch (_) {}
  }

  Future<void> toggleMusic() async {
    musicEnabled.value = !musicEnabled.value;
    if (!musicEnabled.value) {
      final track = _currentTrack;
      stopMusic();
      _currentTrack = track;
    } else if (_currentTrack != null) {
      startMusic(_currentTrack!);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_musicKey, musicEnabled.value);
  }

  Future<void> toggleSfx() async {
    sfxEnabled.value = !sfxEnabled.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sfxKey, sfxEnabled.value);
  }
}

import 'dart:math' as math;

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SoundEffect { death, portal, win, click, back }

/// Music + one-shot effects via `flame_audio`.
///
/// Music: `m_title.mp3` loops on every menu screen; entering a run picks one
/// of `m_ig1..6.mp3` at random and restarts it with every attempt;
/// `m_win.mp3` plays once on a level clear (as an effect, so it isn't
/// cut off by the music being stopped).
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

  static const menuTrack = 'm_title.mp3';
  static const gameTracks = ['m_ig1.mp3', 'm_ig2.mp3', 'm_ig3.mp3', 'm_ig4.mp3', 'm_ig5.mp3', 'm_ig6.mp3'];

  static const Map<SoundEffect, String> _files = {
    SoundEffect.death: 'sfx_explosive.wav',
    SoundEffect.portal: 'sfx_portal.wav',
    SoundEffect.win: 'm_win.mp3',
    SoundEffect.click: 'sfx_menu_confirm.wav',
    SoundEffect.back: 'sfx_menu_back.wav',
  };

  final ValueNotifier<bool> musicEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> sfxEnabled = ValueNotifier<bool>(true);
  final Map<SoundEffect, AudioPool> _pools = {};
  final _rng = math.Random();
  bool _bgmReady = false;

  /// The track that *should* be playing (null = silence), even while music
  /// is switched off or still loading — so toggling music back on, or init
  /// finishing late, starts the right thing.
  String? _wanted;

  /// What bgm is actually playing right now.
  String? _playing;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    musicEnabled.value = prefs.getBool(_musicKey) ?? true;
    sfxEnabled.value = prefs.getBool(_sfxKey) ?? true;
    try {
      // Also makes bgm pause/resume with the app going to background.
      FlameAudio.bgm.initialize();
      _bgmReady = true;
      await FlameAudio.audioCache.loadAll([menuTrack, ...gameTracks]).timeout(const Duration(seconds: 10));
    } catch (_) {}
    for (final entry in _files.entries) {
      try {
        _pools[entry.key] =
            await FlameAudio.createPool(entry.value, minPlayers: 1, maxPlayers: 3).timeout(const Duration(seconds: 5));
      } catch (_) {
        // That one effect just stays silent.
      }
    }
    // A screen may have asked for music before loading finished.
    _apply(restart: true);
  }

  void play(SoundEffect effect) {
    if (!sfxEnabled.value) return;
    _pools[effect]?.start(volume: effect == SoundEffect.win ? 0.8 : 1.0);
  }

  /// A random in-game track, chosen once per run by the game screen.
  String pickGameTrack() => gameTracks[_rng.nextInt(gameTracks.length)];

  /// Menu screens call this; it keeps an already-playing title loop going
  /// instead of restarting it on every screen change.
  void playMenuMusic() {
    _wanted = menuTrack;
    _apply(restart: false);
  }

  /// Starts [track] from the beginning — called on every attempt so the
  /// music restarts with the level.
  void startGameMusic(String track) {
    _wanted = track;
    _apply(restart: true);
  }

  void stopMusic() {
    _wanted = null;
    _apply(restart: false);
  }

  void _apply({required bool restart}) {
    if (!_bgmReady) return;
    final target = musicEnabled.value ? _wanted : null;
    if (target == _playing && !restart) return;
    try {
      if (target == null) {
        FlameAudio.bgm.stop();
      } else {
        FlameAudio.bgm.play(target, volume: 0.55);
      }
      _playing = target;
    } catch (_) {}
  }

  void pauseMusic() {
    if (!_bgmReady || _playing == null) return;
    try {
      FlameAudio.bgm.pause();
    } catch (_) {}
  }

  void resumeMusic() {
    if (!_bgmReady || _playing == null) return;
    try {
      FlameAudio.bgm.resume();
    } catch (_) {}
  }

  Future<void> toggleMusic() async {
    musicEnabled.value = !musicEnabled.value;
    _apply(restart: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_musicKey, musicEnabled.value);
  }

  Future<void> toggleSfx() async {
    sfxEnabled.value = !sfxEnabled.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sfxKey, sfxEnabled.value);
  }
}

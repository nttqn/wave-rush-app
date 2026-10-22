import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/custom_level.dart';
import '../game/ghost.dart';
import '../game/level_data.dart';
import '../game/levels.dart';
import '../game/wave_engine.dart';
import '../services/ads_service.dart';
import '../services/custom_level_store.dart';
import '../services/ghost_store.dart';
import '../services/progress_service.dart';
import '../services/sound_service.dart';
import '../ui/game_painter.dart';
import '../ui/neon_widgets.dart';
import '../ui/palettes.dart';

/// Beat the background pulses to (the supplied mp3 tracks have no tempo
/// metadata, so this is a steady generic pulse rather than a synced one).
const _pulseBpm = 128.0;

/// Plays a built-in [level], a player-made [custom] level, or endless mode
/// when both are null. [testPlay] is the editor's "try it" run: no ads, no
/// saved progress, and the finish panel leads back to the editor.
class GameScreen extends StatefulWidget {
  final LevelDef? level;
  final CustomLevel? custom;
  final bool testPlay;

  /// Set for the Daily Challenge (yyyymmdd): [level] is then that day's
  /// generated level, and progress is saved as Daily, not as a level.
  final String? dailyKey;

  const GameScreen({super.key, required this.level, this.custom, this.testPlay = false, this.dailyKey});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final FocusNode _focus = FocusNode();
  Duration _last = Duration.zero;

  late WaveEngine _engine;
  final Set<int> _pointers = {};
  bool _keyHeld = false;
  bool _paused = false;
  bool _newRecord = false;

  bool get _endless => widget.level == null && widget.custom == null;
  bool get _daily => widget.dailyKey != null;

  // ------------------------------------------------------- ghost + hints

  /// Where this level's best attempt is stored; null when there's no
  /// ghost (endless courses differ every run; editor test runs don't count).
  String? get _ghostKey {
    if (widget.testPlay || _endless) return null;
    if (_daily) return 'D${widget.dailyKey}';
    if (widget.custom != null) return 'C${widget.custom!.id}';
    return 'L${widget.level!.id}';
  }

  GhostRecord? _bestGhost;
  GhostRunner? _ghost;

  /// Generator's safe path (built-in levels and Daily only).
  List<Vec>? _safePath;

  /// Where the player crashed this session, to spot a section they're stuck on.
  final List<double> _deathXs = [];

  /// Active hint: show the safe path over this x range until passed.
  double? _hintFrom, _hintTo;

  /// Seconds left to show the "hint" banner.
  double _hintBanner = 0;

  static const _hintAfterDeaths = 4;
  String get _title => widget.level?.name ?? widget.custom?.name ?? 'ENDLESS';
  /// One random in-game track per visit, restarted with every attempt.
  late final String _track = SoundService.instance.pickGameTrack();

  /// GameScreens alive right now: "NEXT" replaces one with another, and the
  /// outgoing one must not switch to menu music under the incoming one.
  static int _alive = 0;
  late final LevelPalette _palette =
      kPalettes[widget.level?.palette ?? widget.custom?.palette ?? math.Random().nextInt(kPalettes.length)];

  @override
  void initState() {
    super.initState();
    _alive++;
    // Silence until the first touch starts the run and its track.
    SoundService.instance.stopMusic();
    WidgetsBinding.instance.addObserver(this);
    _engine = _createEngine();
    _ticker = createTicker(_onTick)..start();
    final key = _ghostKey;
    if (key != null) {
      GhostStore.instance.load(key).then((record) {
        if (!mounted || record == null) return;
        // A record from this session may already be better.
        if (_bestGhost == null || record.beats(_bestGhost)) _bestGhost = record;
        _resetGhost();
        setState(() {});
      });
    }
  }

  void _resetGhost() {
    final g = _bestGhost;
    _ghost = g == null ? null : GhostRunner(_engine.level, g);
    _ghost?.advanceTo(_engine.stepIndex);
  }

  /// Keeps the attempt that just ended if it beats the stored best.
  void _maybeSaveGhost() {
    final key = _ghostKey;
    if (key == null) return;
    final record = GhostRecord(progress: _engine.progress, steps: _engine.stepIndex, toggles: List.of(_engine.inputLog));
    if (!record.beats(_bestGhost)) return;
    _bestGhost = record;
    GhostStore.instance.save(key, record);
  }

  /// Turns on a hint after several crashes around the same spot.
  void _noteDeath(double x) {
    if (_safePath == null || widget.testPlay) return;
    final nearby = _deathXs.where((d) => (d - x).abs() < 2.5).length;
    _deathXs.add(x);
    if (nearby + 1 >= _hintAfterDeaths && _hintTo == null) {
      _hintFrom = x - 7;
      _hintTo = x + 3;
      _hintBanner = 2.5;
    }
  }

  WaveEngine _createEngine() {
    final def = widget.level;
    final custom = widget.custom;
    final WaveEngine engine;
    if (custom != null) {
      engine = WaveEngine(level: custom.toLevelData());
    } else if (def == null) {
      final builder = buildEndless(math.Random().nextInt(1 << 30));
      engine = WaveEngine(level: builder.level, endlessBuilder: builder);
    } else {
      final built = def.buildWithPath();
      _safePath = built.safePath;
      engine = WaveEngine(level: built.level);
    }
    engine
      ..onDeath = _onDeath
      ..onWin = _onWin
      ..onRestart = () {
        SoundService.instance.startGameMusic(_track);
        _resetGhost();
      }
      ..onPortal = (_) {
        SoundService.instance.play(SoundEffect.portal);
      };
    return engine;
  }

  void _onDeath() {
    final sound = SoundService.instance;
    sound.stopMusic();
    sound.play(SoundEffect.death);
    if (_endless) {
      _newRecord = ProgressService.instance.recordEndless(_engine.distance);
    } else {
      _recordProgress(_engine.progress);
      _maybeSaveGhost();
      _noteDeath(_engine.x);
    }
  }

  void _onWin() {
    SoundService.instance.stopMusic();
    SoundService.instance.play(SoundEffect.win);
    _recordProgress(1.0);
    _maybeSaveGhost();
  }

  /// Saves the attempt's progress for built-in and player-made levels.
  /// Editor test runs don't count.
  void _recordProgress(double progress) {
    if (widget.testPlay) return;
    final def = widget.level, custom = widget.custom;
    if (_daily) {
      ProgressService.instance.recordDaily(widget.dailyKey!, progress);
      return;
    }
    if (def != null) ProgressService.instance.recordAttempt(def.id, progress);
    if (custom != null) CustomLevelStore.instance.recordProgress(custom.id, progress);
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_paused) return;
    final before = _engine.state;
    _engine.update(dt);
    _ghost?.advanceTo(_engine.stepIndex);
    if (_hintBanner > 0) _hintBanner -= dt;
    // Made it past the tricky bit: retire the hint and its crash history.
    final hintTo = _hintTo;
    if (hintTo != null && _engine.state == RunState.playing && _engine.x > hintTo + 1) {
      _deathXs.removeWhere((d) => d >= _hintFrom! && d <= hintTo);
      // The painter takes the hint range at build time: rebuild to drop it.
      if (mounted) setState(() => _hintFrom = _hintTo = null);
    }
    // Overlays (win / endless game over) appear after a short beat.
    if (before != _engine.state || _engine.state == RunState.won || _engine.state == RunState.dead) {
      if (mounted) setState(() {});
    }
    _frame.value++;
  }

  void _setHolding(bool holding) {
    if (_paused) return;
    final wasReady = _engine.state == RunState.ready;
    _engine.setHolding(holding);
    if (wasReady && _engine.state == RunState.playing) {
      SoundService.instance.startGameMusic(_track);
      setState(() {});
    }
  }

  void _updateHold() => _setHolding(_pointers.isNotEmpty || _keyHeld);

  // ------------------------------------------------------------- lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _engine.state == RunState.playing) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focus.dispose();
    if (--_alive == 0) SoundService.instance.playMenuMusic();
    super.dispose();
  }

  void _pause() {
    if (_paused) return;
    setState(() => _paused = true);
    _pointers.clear();
    _keyHeld = false;
    SoundService.instance.pauseMusic();
  }

  void _resume() {
    setState(() => _paused = false);
    _engine.setHolding(false);
    _last = Duration.zero;
    SoundService.instance.resumeMusic();
    _focus.requestFocus();
  }

  void _restart() {
    setState(() {
      _paused = false;
      _newRecord = false;
      if (_endless) {
        // Fresh random course every endless run.
        final attempts = _engine.attempts;
        _engine = _createEngine()..attempts = attempts + 1;
        SoundService.instance.stopMusic();
      } else {
        if (_engine.state == RunState.playing) _recordProgress(_engine.progress);
        _engine.restart();
        _engine.setHolding(false);
      }
    });
    _last = Duration.zero;
    _focus.requestFocus();
  }

  void _exit() {
    if (!_endless && _engine.state == RunState.playing) _recordProgress(_engine.progress);
    // Natural break: leaving a level after a real session, or after a win.
    // Never while bouncing between the editor and its test runs.
    if (!widget.testPlay && (_engine.attempts >= 3 || _engine.state == RunState.won || _endless)) {
      AdsService.instance.maybeShowInterstitial();
    }
    // Test runs report back whether the creator reached the finish — a
    // human clear counts as verification, same as the solver's.
    Navigator.of(context).pop(_engine.state == RunState.won);
  }

  void _nextLevel() {
    final idx = kLevels.indexOf(widget.level!);
    AdsService.instance.maybeShowInterstitial();
    if (idx + 1 < kLevels.length) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(level: kLevels[idx + 1])),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Android back: toggles pause during a run, never quits mid-attempt.
  void _onBack() {
    if (_engine.state == RunState.won || (_endless && _engine.state == RunState.dead)) {
      _exit();
    } else if (_paused) {
      SoundService.instance.play(SoundEffect.back);
      _resume();
    } else {
      SoundService.instance.play(SoundEffect.back);
      _pause();
    }
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final skin = kSkins[ProgressService.instance.selectedSkin.clamp(0, kSkins.length - 1)];
    final showWin = _engine.state == RunState.won && _engine.stateTimer > 0.8;
    final showOver = _endless && _engine.state == RunState.dead && _engine.stateTimer > 0.6;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: _palette.bgBottom,
        body: KeyboardListener(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (event) {
            final keys = {LogicalKeyboardKey.space, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW};
            if (!keys.contains(event.logicalKey)) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) _onBack();
              return;
            }
            if (event is KeyDownEvent) _keyHeld = true;
            if (event is KeyUpEvent) _keyHeld = false;
            _updateHold();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  _pointers.add(e.pointer);
                  _updateHold();
                },
                onPointerUp: (e) {
                  _pointers.remove(e.pointer);
                  _updateHold();
                },
                onPointerCancel: (e) {
                  _pointers.remove(e.pointer);
                  _updateHold();
                },
                child: CustomPaint(
                  painter: GamePainter(
                    engine: _engine,
                    palette: _palette,
                    skin: skin,
                    bpm: _pulseBpm,
                    repaint: _frame,
                    ghost: _engine.state == RunState.playing ? _ghost?.engine : null,
                    hintPath: _safePath,
                    hintFrom: _hintFrom ?? 0,
                    hintTo: _hintTo ?? 0,
                  ),
                ),
              ),
              _buildHud(),
              if (_hintTo != null && !_paused) _buildHintBanner(),
              if (_engine.state == RunState.ready && !_paused) _buildTapToStart(),
              if (_paused) _buildPauseMenu(),
              if (showWin) _buildWinPanel(),
              if (showOver) _buildGameOverPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 46),
            Expanded(
              child: IgnorePointer(
                child: ValueListenableBuilder<int>(
                  valueListenable: _frame,
                  builder: (context, _, _) => _endless ? _endlessHud() : _progressHud(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (!_paused && _engine.state != RunState.won)
              NeonIconButton(icon: Icons.pause, color: _palette.wallLine, onPressed: _pause)
            else
              const SizedBox(width: 46),
          ],
        ),
      ),
    );
  }

  Widget _progressHud() {
    final p = _engine.progress;
    return Column(
      children: [
        const SizedBox(height: 6),
        FractionallySizedBox(
          widthFactor: 0.6,
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white70, width: 1.5),
              color: Colors.black38,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: p,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: _palette.wallLine,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(p * 100).floor()}%',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white),
        ),
      ],
    );
  }

  Widget _endlessHud() {
    return Column(
      children: [
        Text(
          '${_engine.distance}m',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Colors.white),
        ),
        Text(
          'BEST ${ProgressService.instance.endlessBest}m',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white60),
        ),
      ],
    );
  }

  Widget _buildTapToStart() {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.55),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeonTitle(widget.testPlay ? 'TEST: $_title' : _title, size: 34, color: _palette.wallLine),
            const SizedBox(height: 8),
            const Text(
              'HOLD ANYWHERE TO START',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 3),
            ),
            if (_bestGhost != null) ...[
              const SizedBox(height: 6),
              Text(
                'Racing your ghost: best ${(_bestGhost!.progress * 100).floor()}%',
                style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHintBanner() {
    // Rebuilt every frame (the screen itself only rebuilds on state
    // changes), so the banner actually fades out while the player flies.
    return IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: _frame,
        builder: (context, _, child) => _hintBanner <= 0
            ? const SizedBox.shrink()
            : Align(
                alignment: const Alignment(0, -0.55),
                child: Opacity(opacity: _hintBanner.clamp(0.0, 1.0), child: child),
              ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _palette.accent),
          ),
          child: const Text(
            'HINT: follow the glowing dots',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
        ),
      ),
    );
  }

  Widget _panel({required List<Widget> children}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _buildPauseMenu() {
    final def = widget.level, custom = widget.custom;
    final best = def != null
        ? ProgressService.instance.bestPercent(def.id)
        : custom != null
            ? CustomLevelStore.instance.bestPercent(custom.id)
            : null;
    return _panel(children: [
      const NeonTitle('PAUSED', size: 40),
      if (!_endless) ...[
        const SizedBox(height: 6),
        Text(
          [
            _title,
            if (best != null && !widget.testPlay) 'Best $best%',
            'Attempt ${_engine.attempts}',
          ].join('  ·  '),
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
      ],
      const SizedBox(height: 18),
      Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          NeonButton(
            label: 'RESUME',
            icon: Icons.play_arrow_rounded,
            filled: true,
            width: 180,
            sound: SoundEffect.back,
            onPressed: _resume,
          ),
          NeonButton(label: 'RESTART', icon: Icons.replay, width: 180, onPressed: _restart),
          NeonButton(
            label: widget.testPlay ? 'EDITOR' : 'MENU',
            icon: widget.testPlay ? Icons.edit : Icons.home_rounded,
            sound: null,
            color: const Color(0xFFFF5CF0),
            width: 180,
            onPressed: _exit,
          ),
        ],
      ),
      const SizedBox(height: 16),
      const SoundToggles(),
    ]);
  }

  Widget _buildWinPanel() {
    final def = widget.level;
    final idx = def == null || _daily ? -1 : kLevels.indexOf(def);
    final hasNext = idx >= 0 && idx < kLevels.length - 1;
    final streak = ProgressService.instance.dailyStreak;
    return _panel(children: [
      NeonTitle(_daily ? 'DAILY CLEARED!' : 'LEVEL COMPLETE!', size: 40, color: const Color(0xFF4DFF9A)),
      if (_daily) ...[
        const SizedBox(height: 6),
        Text(
          streak > 1 ? '$streak-day streak! Come back tomorrow for a new one.' : 'Come back tomorrow for a new one.',
          style: const TextStyle(color: Color(0xFFFFD23F), fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        '$_title  ·  ${_engine.attempts} attempt${_engine.attempts == 1 ? '' : 's'}  ·  ${_engine.runTime.toStringAsFixed(1)}s',
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          NeonButton(
            label: widget.testPlay ? 'EDITOR' : 'MENU',
            icon: widget.testPlay ? Icons.edit : Icons.home_rounded,
            sound: null,
            width: 170,
            onPressed: _exit,
          ),
          NeonButton(label: 'REPLAY', icon: Icons.replay, width: 170, onPressed: _restart),
          if (hasNext)
            NeonButton(
              label: 'NEXT',
              icon: Icons.skip_next_rounded,
              color: const Color(0xFF4DFF9A),
              filled: true,
              width: 170,
              onPressed: _nextLevel,
            ),
        ],
      ),
    ]);
  }

  Widget _buildGameOverPanel() {
    return _panel(children: [
      NeonTitle(_newRecord ? 'NEW RECORD!' : 'CRASHED', size: 40, color: _newRecord ? const Color(0xFFFFD23F) : const Color(0xFFFF4F9A)),
      const SizedBox(height: 8),
      Text(
        '${_engine.distance}m   ·   Best ${ProgressService.instance.endlessBest}m',
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          NeonButton(label: 'MENU', icon: Icons.home_rounded, width: 170, sound: null, onPressed: _exit),
          NeonButton(
            label: 'RETRY',
            icon: Icons.replay,
            color: const Color(0xFFFF5CF0),
            filled: true,
            width: 170,
            onPressed: _restart,
          ),
        ],
      ),
    ]);
  }
}


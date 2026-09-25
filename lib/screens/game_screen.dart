import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/custom_level.dart';
import '../game/levels.dart';
import '../game/wave_engine.dart';
import '../services/ads_service.dart';
import '../services/custom_level_store.dart';
import '../services/progress_service.dart';
import '../services/sound_service.dart';
import '../ui/game_painter.dart';
import '../ui/neon_widgets.dart';
import '../ui/palettes.dart';

const _trackBpm = [128.0, 140.0, 150.0];

/// Plays a built-in [level], a player-made [custom] level, or endless mode
/// when both are null. [testPlay] is the editor's "try it" run: no ads, no
/// saved progress, and the finish panel leads back to the editor.
class GameScreen extends StatefulWidget {
  final LevelDef? level;
  final CustomLevel? custom;
  final bool testPlay;
  const GameScreen({super.key, required this.level, this.custom, this.testPlay = false});

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
  String get _title => widget.level?.name ?? widget.custom?.name ?? 'ENDLESS';
  late final int _track = widget.level?.music ?? widget.custom?.music ?? math.Random().nextInt(SoundService.musicFiles.length);
  late final LevelPalette _palette =
      kPalettes[widget.level?.palette ?? widget.custom?.palette ?? math.Random().nextInt(kPalettes.length)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = _createEngine();
    _ticker = createTicker(_onTick)..start();
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
      engine = WaveEngine(level: def.build());
    }
    engine
      ..onDeath = _onDeath
      ..onWin = _onWin
      ..onRestart = () {
        SoundService.instance.startMusic(_track);
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
    }
  }

  void _onWin() {
    SoundService.instance.stopMusic();
    SoundService.instance.play(SoundEffect.win);
    _recordProgress(1.0);
  }

  /// Saves the attempt's progress for built-in and player-made levels.
  /// Editor test runs don't count.
  void _recordProgress(double progress) {
    if (widget.testPlay) return;
    final def = widget.level, custom = widget.custom;
    if (def != null) ProgressService.instance.recordAttempt(def.id, progress);
    if (custom != null) CustomLevelStore.instance.recordProgress(custom.id, progress);
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_paused) return;
    final before = _engine.state;
    _engine.update(dt);
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
      SoundService.instance.startMusic(_track);
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
    SoundService.instance.stopMusic();
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
      _resume();
    } else {
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
                    bpm: _trackBpm[_track],
                    repaint: _frame,
                  ),
                ),
              ),
              _buildHud(),
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
          ],
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
          NeonButton(label: 'RESUME', icon: Icons.play_arrow_rounded, filled: true, width: 180, onPressed: _resume),
          NeonButton(label: 'RESTART', icon: Icons.replay, width: 180, onPressed: _restart),
          NeonButton(
            label: widget.testPlay ? 'EDITOR' : 'MENU',
            icon: widget.testPlay ? Icons.edit : Icons.home_rounded,
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
    final hasNext = def != null && kLevels.indexOf(def) < kLevels.length - 1;
    return _panel(children: [
      const NeonTitle('LEVEL COMPLETE!', size: 40, color: Color(0xFF4DFF9A)),
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
          NeonButton(label: 'MENU', icon: Icons.home_rounded, width: 170, onPressed: _exit),
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


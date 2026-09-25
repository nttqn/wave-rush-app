import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/custom_level.dart';
import '../game/level_data.dart';
import '../game/wave_engine.dart';
import '../services/custom_level_store.dart';
import '../services/progress_service.dart';
import '../ui/game_painter.dart';
import '../ui/neon_widgets.dart';
import '../ui/palettes.dart';
import 'game_screen.dart';

enum EditorTool { floor, ceiling, spikeUp, spikeDown, saw, portal, erase }

const _speedOptions = [(7.0, 'Slow'), (8.0, 'Normal'), (9.5, 'Fast'), (11.0, 'Very fast')];

/// Runs [LevelSolver] off the UI isolate (plain JSON in, plain list out).
List<double> _solveInBackground(Map<String, dynamic> json) {
  final result = LevelSolver.solve(CustomLevel.fromJson(json).toLevelData());
  return [result.solved ? 1 : 0, result.reachedX];
}

/// Level editor: tap to place with the selected tool, drag to scroll.
class EditorScreen extends StatefulWidget {
  final CustomLevel level;
  const EditorScreen({super.key, required this.level});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late CustomLevel _level = widget.level.copy();
  late LevelData _data;
  late WaveEngine _preview;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final List<String> _undo = [];

  EditorTool _tool = EditorTool.floor;
  int _spikeSize = 0;
  int _sawSize = 1;
  PortalKind _portalKind = PortalKind.speedFast;

  double _camX = -2;
  double _viewW = 20;

  /// Where the last failed verification got stuck (highlighted in red).
  double? _failX;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  void _rebuild() {
    _data = _level.toLevelData();
    _preview = WaveEngine(level: _data);
    _repaint.value++;
  }

  /// Every edit goes through here: snapshot for undo, apply, redraw.
  void _mutate(void Function() edit) {
    _undo.add(jsonEncode(_level.toJson()));
    if (_undo.length > 80) _undo.removeAt(0);
    setState(() {
      edit();
      _failX = null;
      _rebuild();
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _level = CustomLevel.fromJson(jsonDecode(_undo.removeLast()) as Map<String, dynamic>);
      _failX = null;
      _rebuild();
    });
  }

  Future<void> _save() => CustomLevelStore.instance.save(_level.copy());

  double get _maxCam => math.max(-2.0, _level.length - _viewW + 4);

  void _scrollTo(double worldX) {
    setState(() => _camX = (worldX - _viewW * 0.3).clamp(-2.0, _maxCam));
  }

  // ------------------------------------------------------------ placing

  static double _snap(double v) => (v * 2).roundToDouble() / 2;

  void _onTap(Offset local, Size size) {
    final s = size.height / LevelData.worldHeight;
    final wx = _snap(_camX + local.dx / s);
    var wy = _snap(LevelData.worldHeight - local.dy / s);
    if (wx < 0 || wx > _level.length) return;

    switch (_tool) {
      case EditorTool.floor:
        _mutate(() => _level.setWallPoint(ceiling: false, x: wx, y: wy));
      case EditorTool.ceiling:
        _mutate(() => _level.setWallPoint(ceiling: true, x: wx, y: wy));
      case EditorTool.spikeUp:
        // Near the floor? Sit exactly on it.
        final f = _level.floorAt(wx);
        if ((wy - f).abs() < 0.75) wy = f;
        _mutate(() => _level.addSpike(wx, wy, up: true, size: _spikeSize));
      case EditorTool.spikeDown:
        final c = _level.ceilingAt(wx);
        if ((wy - c).abs() < 0.75) wy = c;
        _mutate(() => _level.addSpike(wx, wy, up: false, size: _spikeSize));
      case EditorTool.saw:
        _mutate(() => _level.addSaw(wx, wy, size: _sawSize));
      case EditorTool.portal:
        _mutate(() => _level.addPortal(wx, _portalKind));
      case EditorTool.erase:
        final raw = LevelData.worldHeight - local.dy / s;
        final copy = _level.copy();
        if (copy.eraseNear(_camX + local.dx / s, raw)) {
          _mutate(() => _level.eraseNear(_camX + local.dx / s, raw));
        }
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _testPlay() async {
    await _save();
    if (!mounted) return;
    final won = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GameScreen(level: null, custom: _level.copy(), testPlay: true)),
    );
    if (won == true && mounted && !_level.verified) {
      setState(() => _level.verified = true);
      await _save();
      _toast('You beat it — level verified!', good: true);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _save();
    final result = await compute(_solveInBackground, _level.toJson());
    if (!mounted) return;
    final solved = result[0] == 1;
    setState(() {
      _busy = false;
      if (solved) {
        _level.verified = true;
        _failX = null;
      } else {
        _failX = result[1];
      }
    });
    if (solved) {
      await _save();
      _toast('Beatable! Level verified.', good: true);
    } else {
      final pct = (_failX! / _level.length * 100).clamp(0, 100).floor();
      _scrollTo(_failX!);
      _toast('Impossible at $pct% — no timing gets past the red line.');
    }
  }

  void _toast(String text, {bool good = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: good ? const Color(0xFF1B7F4B) : const Color(0xFF8A1F3A),
        duration: const Duration(seconds: 3),
      ));
  }

  Future<void> _leave() async {
    await _save();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    final nameCtrl = TextEditingController(text: _level.name);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          void apply(void Function() edit) {
            _mutate(edit);
            setLocal(() {});
          }

          final seconds = _level.length / _level.baseSpeed;
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1230),
            title: const Text('Level settings', style: TextStyle(fontWeight: FontWeight.w900)),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      maxLength: 24,
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (v) => _level.name = v.trim().isEmpty ? 'Untitled' : v.trim(),
                    ),
                    Text('Length: ${_level.length.round()}m  (~${seconds.round()}s)',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Slider(
                      min: CustomLevel.minLength,
                      max: CustomLevel.maxLength,
                      divisions: ((CustomLevel.maxLength - CustomLevel.minLength) / 10).round(),
                      value: _level.length,
                      onChanged: (v) => apply(() => _level.setLength(v)),
                    ),
                    const Text('Speed', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      for (final (v, label) in _speedOptions)
                        ChoiceChip(
                          label: Text(label),
                          selected: _level.baseSpeed == v,
                          onSelected: (_) => apply(() => _level.setSpeed(v)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    const Text('Colors', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 10, children: [
                      for (var i = 0; i < kPalettes.length; i++)
                        GestureDetector(
                          onTap: () => apply(() => _level.palette = i),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kPalettes[i].wallFill,
                              border: Border.all(
                                color: kPalettes[i].wallLine,
                                width: _level.palette == i ? 4 : 1.5,
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    const Text('Music', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      for (var i = 0; i < 3; i++)
                        ChoiceChip(
                          label: Text('Track ${i + 1}'),
                          selected: _level.music == i,
                          onSelected: (_) => apply(() => _level.music = i),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('DONE'))],
          );
        },
      ),
    );
    setState(() {});
    await _save();
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final palette = kPalettes[_level.palette.clamp(0, kPalettes.length - 1)];
    final skin = kSkins[ProgressService.instance.selectedSkin.clamp(0, kSkins.length - 1)];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: palette.bgBottom,
        body: SafeArea(
          child: Row(
            children: [
              _buildToolColumn(palette),
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(palette),
                    Expanded(
                      child: LayoutBuilder(builder: (context, c) {
                        final size = Size(c.maxWidth, c.maxHeight);
                        _viewW = size.width / (size.height / LevelData.worldHeight);
                        _camX = _camX.clamp(-2.0, _maxCam);
                        return ClipRect(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _onTap(d.localPosition, size),
                            onHorizontalDragUpdate: (d) => setState(() {
                              final s = size.height / LevelData.worldHeight;
                              _camX = (_camX - d.delta.dx / s).clamp(-2.0, _maxCam);
                            }),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomPaint(
                                  painter: GamePainter(
                                    engine: _preview,
                                    palette: palette,
                                    skin: skin,
                                    bpm: 128,
                                    repaint: _repaint,
                                    cameraLeft: _camX,
                                  ),
                                ),
                                CustomPaint(
                                  painter: _EditorOverlayPainter(
                                    level: _level,
                                    camX: _camX,
                                    palette: palette,
                                    skin: skin,
                                    failX: _failX,
                                  ),
                                ),
                                if (_busy)
                                  Container(
                                    color: Colors.black54,
                                    alignment: Alignment.center,
                                    child: const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 12),
                                        Text('Checking every possible run…',
                                            style: TextStyle(fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    _buildScrollBar(palette),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolColumn(LevelPalette palette) {
    Widget tool(EditorTool t, Widget icon, String tip) {
      final selected = _tool == t;
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => setState(() => _tool = t),
          child: Container(
            width: 50,
            height: 42,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: selected ? palette.wallLine.withValues(alpha: 0.25) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? palette.wallLine : Colors.white12, width: selected ? 2 : 1),
            ),
            child: IconTheme(
              data: IconThemeData(color: selected ? Colors.white : Colors.white60, size: 24),
              child: Center(child: icon),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 62,
      color: Colors.black26,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            tool(EditorTool.floor, const Icon(Icons.vertical_align_bottom), 'Floor point'),
            tool(EditorTool.ceiling, const Icon(Icons.vertical_align_top), 'Ceiling point'),
            tool(EditorTool.spikeUp, const Icon(Icons.change_history), 'Spike up'),
            tool(EditorTool.spikeDown, Transform.rotate(angle: math.pi, child: const Icon(Icons.change_history)),
                'Spike down'),
            tool(EditorTool.saw, const Icon(Icons.settings), 'Saw'),
            tool(EditorTool.portal, const Icon(Icons.adjust), 'Portal'),
            tool(EditorTool.erase, const Icon(Icons.delete_outline), 'Erase'),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(LevelPalette palette) {
    Widget chip(String label, bool selected, VoidCallback onTap, {Color? color}) {
      final c = color ?? palette.wallLine;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.withValues(alpha: 0.3) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? c : Colors.white24, width: selected ? 2 : 1),
            ),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: selected ? Colors.white : c)),
          ),
        ),
      );
    }

    final options = <Widget>[
      if (_tool == EditorTool.spikeUp || _tool == EditorTool.spikeDown)
        for (var i = 0; i < kSpikeSizes.length; i++)
          chip(const ['S', 'M', 'L'][i], _spikeSize == i, () => setState(() => _spikeSize = i)),
      if (_tool == EditorTool.saw)
        for (var i = 0; i < kSawSizes.length; i++)
          chip(const ['S', 'M', 'L'][i], _sawSize == i, () => setState(() => _sawSize = i)),
      if (_tool == EditorTool.portal)
        for (final k in PortalKind.values)
          chip(
            switch (k) {
              PortalKind.speedSlow => '0.8x',
              PortalKind.speedNormal => '1x',
              PortalKind.speedFast => '1.25x',
              PortalKind.speedVeryFast => '1.5x',
              PortalKind.miniOn => 'MINI',
              PortalKind.miniOff => 'BIG',
            },
            _portalKind == k,
            () => setState(() => _portalKind = k),
            color: GamePainter.portalColor(k),
          ),
      if (_tool == EditorTool.floor || _tool == EditorTool.ceiling)
        const Text('Tap to add/move a point', style: TextStyle(color: Colors.white54, fontSize: 12)),
      if (_tool == EditorTool.erase)
        const Text('Tap an object to remove it', style: TextStyle(color: Colors.white54, fontSize: 12)),
    ];

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 6),
          NeonIconButton(icon: Icons.arrow_back, size: 40, color: palette.wallLine, onPressed: _leave),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: GestureDetector(
              onTap: _openSettings,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_level.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text(
                    _level.verified ? '✓ Verified' : 'Not verified',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _level.verified ? const Color(0xFF4DFF9A) : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: options),
            ),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: _undo.isEmpty ? null : _undoLast,
            icon: const Icon(Icons.undo),
          ),
          IconButton(tooltip: 'Settings', onPressed: _openSettings, icon: const Icon(Icons.tune)),
          IconButton(
            tooltip: 'Verify',
            onPressed: _busy ? null : _verify,
            icon: Icon(Icons.verified_outlined, color: _level.verified ? const Color(0xFF4DFF9A) : null),
          ),
          const SizedBox(width: 4),
          NeonIconButton(
            icon: Icons.play_arrow_rounded,
            size: 40,
            color: const Color(0xFF4DFF9A),
            onPressed: _testPlay,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildScrollBar(LevelPalette palette) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Text('${math.max(0, _camX + _viewW * 0.3).round()}m',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70, fontSize: 12)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: palette.wallLine,
                thumbColor: palette.wallLine,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                min: -2,
                max: math.max(-1.99, _maxCam),
                value: _camX.clamp(-2.0, math.max(-1.99, _maxCam)),
                onChanged: (v) => setState(() => _camX = v),
              ),
            ),
          ),
          Text('${_level.length.round()}m',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// Editor-only marks on top of the normal game rendering: grid, wall
/// control points, start marker, out-of-bounds shading, failure line.
class _EditorOverlayPainter extends CustomPainter {
  final CustomLevel level;
  final double camX;
  final LevelPalette palette;
  final WaveSkin skin;
  final double? failX;

  _EditorOverlayPainter({
    required this.level,
    required this.camX,
    required this.palette,
    required this.skin,
    required this.failX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const h = LevelData.worldHeight;
    final s = size.height / h;
    final viewW = size.width / s;
    Offset toScreen(double x, double y) => Offset((x - camX) * s, (h - y) * s);

    // Grid: every unit, brighter every 5.
    final minor = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..strokeWidth = 1;
    for (var gx = camX.floorToDouble(); gx <= camX + viewW + 1; gx++) {
      final p = toScreen(gx, 0).dx;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), gx % 5 == 0 ? major : minor);
      if (gx % 10 == 0 && gx >= 0 && gx <= level.length) {
        final tp = TextPainter(
          text: TextSpan(text: '${gx.round()}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p + 3, size.height - 14));
      }
    }
    for (var gy = 0; gy <= h; gy++) {
      final p = toScreen(0, gy.toDouble()).dy;
      canvas.drawLine(Offset(0, p), Offset(size.width, p), gy % 5 == 0 ? major : minor);
    }

    // Outside the playable range.
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final startPx = toScreen(0, 0).dx, endPx = toScreen(level.length, 0).dx;
    if (startPx > 0) canvas.drawRect(Rect.fromLTRB(0, 0, startPx, size.height), shade);
    if (endPx < size.width) canvas.drawRect(Rect.fromLTRB(endPx, 0, size.width, size.height), shade);

    // Start marker: where (and which way) the wave begins.
    final start = toScreen(0, h / 2);
    final arrow = Path()
      ..moveTo(start.dx + 0.45 * s, start.dy)
      ..lineTo(start.dx - 0.3 * s, start.dy - 0.3 * s)
      ..lineTo(start.dx - 0.14 * s, start.dy)
      ..lineTo(start.dx - 0.3 * s, start.dy + 0.3 * s)
      ..close();
    canvas.drawPath(arrow, Paint()..color = skin.body);
    final label = TextPainter(
      text: const TextSpan(
          text: 'START', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, start + Offset(-label.width / 2, 0.45 * s));

    // Wall control points.
    for (final pts in [level.floorPoints, level.ceilingPoints]) {
      for (final p in pts) {
        final o = toScreen(p.x, p.y);
        if (o.dx < -10 || o.dx > size.width + 10) continue;
        canvas.drawCircle(o, 6, Paint()..color = Colors.white);
        canvas.drawCircle(
          o,
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = palette.wallLine,
        );
      }
    }

    if (failX != null) {
      final fx = toScreen(failX!, 0).dx;
      canvas.drawRect(
        Rect.fromLTWH(fx - 3, 0, 6, size.height),
        Paint()..color = const Color(0xFFFF3F5E).withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EditorOverlayPainter old) => true;
}

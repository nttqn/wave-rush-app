import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/level_data.dart';
import '../game/wave_engine.dart';
import 'palettes.dart';

/// Draws one frame of the game. World space is y-up (see [LevelData]); the
/// canvas is flipped once so all world geometry is drawn in world units.
class GamePainter extends CustomPainter {
  final WaveEngine engine;
  final LevelPalette palette;
  final WaveSkin skin;
  final double bpm;

  /// Editor: fixed camera (world x of the left screen edge) instead of
  /// following the wave, and no wave drawn.
  final double? cameraLeft;

  /// Where on screen (fraction of width) the wave sits horizontally.
  static const double playerScreenX = 0.3;

  GamePainter({
    required this.engine,
    required this.palette,
    required this.skin,
    required this.bpm,
    required Listenable repaint,
    this.cameraLeft,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    const h = LevelData.worldHeight;
    final s = size.height / h;
    final viewW = size.width / s;
    final camX = cameraLeft ?? engine.x - viewW * playerScreenX;
    final x0 = camX - 1, x1 = camX + viewW + 1;

    final beat = engine.state == RunState.playing ? (engine.runTime * bpm / 60) % 1.0 : 0.5;
    final pulse = math.pow(1 - beat, 3).toDouble();

    _drawBackground(canvas, size, camX, s, pulse);

    canvas.save();
    canvas.translate(0, size.height);
    canvas.scale(s, -s);
    canvas.translate(-camX, 0);

    _drawPortals(canvas, x0, x1);
    _drawFinish(canvas, x0, x1);
    _drawWalls(canvas, x0, x1, pulse);
    _drawHazards(canvas, x0, x1);
    if (cameraLeft == null) {
      _drawTrail(canvas, x0);
      if (engine.state != RunState.dead) _drawWave(canvas);
    }
    _drawParticles(canvas);

    canvas.restore();

    _drawAttemptLabel(canvas, size, camX, s);
  }

  // ------------------------------------------------------------ background

  void _drawBackground(Canvas canvas, Size size, double camX, double s, double pulse) {
    final rect = Offset.zero & size;
    final top = Color.lerp(palette.bgTop, palette.accent, 0.08 * pulse)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, palette.bgBottom],
        ).createShader(rect),
    );

    // Two layers of slowly scrolling outlined squares for parallax depth.
    for (final layer in const [(0.15, 3.2, 0.05), (0.35, 1.9, 0.07)]) {
      final (speed, cell, alpha) = layer;
      final px = cell * s;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.accent.withValues(alpha: alpha + 0.03 * pulse);
      final offset = (camX * s * speed) % (px * 2);
      for (var gx = -offset; gx < size.width + px; gx += px * 2) {
        for (var gy = 0.0; gy < size.height + px; gy += px * 2) {
          final stagger = ((gy / (px * 2)).round().isOdd) ? px : 0;
          canvas.drawRect(Rect.fromLTWH(gx + stagger, gy, px * 0.9, px * 0.9), paint);
        }
      }
    }
  }

  // ------------------------------------------------------------------ walls

  void _drawWalls(Canvas canvas, double x0, double x1, double pulse) {
    const h = LevelData.worldHeight;
    final floorPts = LevelData.pointsInRange(engine.level.floor, x0, x1).toList();
    final ceilPts = LevelData.pointsInRange(engine.level.ceiling, x0, x1).toList();
    if (floorPts.isEmpty || ceilPts.isEmpty) return;

    final fill = Path()..moveTo(floorPts.first.x, -1);
    final floorEdge = Path()..moveTo(floorPts.first.x, floorPts.first.y);
    for (final p in floorPts) {
      fill.lineTo(p.x, p.y);
      floorEdge.lineTo(p.x, p.y);
    }
    fill
      ..lineTo(floorPts.last.x, -1)
      ..close()
      ..moveTo(ceilPts.first.x, h + 1);
    final ceilEdge = Path()..moveTo(ceilPts.first.x, ceilPts.first.y);
    for (final p in ceilPts) {
      fill.lineTo(p.x, p.y);
      ceilEdge.lineTo(p.x, p.y);
    }
    fill
      ..lineTo(ceilPts.last.x, h + 1)
      ..close();

    canvas.drawPath(fill, Paint()..color = palette.wallFill);

    // Faint block grid inside the walls.
    canvas.save();
    canvas.clipPath(fill);
    final grid = Paint()
      ..color = palette.wallLine.withValues(alpha: 0.13)
      ..strokeWidth = 0.04;
    for (var gx = x0.floorToDouble(); gx <= x1; gx += 1) {
      canvas.drawLine(Offset(gx, -1), Offset(gx, h + 1), grid);
    }
    for (var gy = 0.0; gy <= h; gy += 1) {
      canvas.drawLine(Offset(x0, gy), Offset(x1, gy), grid);
    }
    canvas.restore();

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.22 + 0.12 * pulse
      ..color = palette.wallLine.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.12)
      ..strokeJoin = StrokeJoin.round;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.08
      ..color = palette.wallLine
      ..strokeJoin = StrokeJoin.round;
    for (final edge in [floorEdge, ceilEdge]) {
      canvas.drawPath(edge, glow);
      canvas.drawPath(edge, line);
    }
  }

  // ---------------------------------------------------------------- hazards

  void _drawHazards(Canvas canvas, double x0, double x1) {
    final fill = Paint()..color = Color.lerp(palette.bgBottom, Colors.black, 0.4)!;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.2
      ..color = palette.hazard.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.1);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..strokeJoin = StrokeJoin.round
      ..color = palette.hazard;

    for (final spike in engine.level.spikesInRange(x0, x1)) {
      final path = Path()
        ..moveTo(spike.a.x, spike.a.y)
        ..lineTo(spike.c.x, spike.c.y)
        ..lineTo(spike.b.x, spike.b.y)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }

    for (final saw in engine.level.sawsInRange(x0, x1)) {
      final teeth = math.max(8, (saw.radius * 14).round());
      final angle = engine.time * 5 * (saw.x.floor().isEven ? 1 : -1);
      final path = Path();
      for (var i = 0; i <= teeth * 2; i++) {
        final a = angle + i * math.pi / teeth;
        final r = i.isEven ? saw.radius : saw.radius * 0.78;
        final p = Offset(saw.x + math.cos(a) * r, saw.y + math.sin(a) * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
      canvas.drawCircle(Offset(saw.x, saw.y), saw.radius * 0.3, line);
    }
  }

  // --------------------------------------------------------- portals/finish

  static Color portalColor(PortalKind kind) => switch (kind) {
        PortalKind.speedSlow => const Color(0xFFFFB13F),
        PortalKind.speedNormal => const Color(0xFF3FA9FF),
        PortalKind.speedFast => const Color(0xFF4DFF9A),
        PortalKind.speedVeryFast => const Color(0xFFFF5CF0),
        PortalKind.miniOn => const Color(0xFFFF4FD8),
        PortalKind.miniOff => const Color(0xFF4DFF6A),
      };

  void _drawPortals(Canvas canvas, double x0, double x1) {
    for (final p in engine.level.portals) {
      if (p.x < x0 - 1) continue;
      if (p.x > x1 + 1) break;
      final floor = engine.level.floorAt(p.x), ceil = engine.level.ceilingAt(p.x);
      final cy = (floor + ceil) / 2;
      final hh = math.min(2.2, (ceil - floor) / 2 - 0.1);
      final color = portalColor(p.kind);
      final rect = Rect.fromCenter(center: Offset(p.x, cy), width: 0.7, height: hh * 2);
      canvas.drawOval(
        rect,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3),
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.14
          ..color = color,
      );

      final icon = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;
      if (p.kind.isSpeed) {
        final n = p.kind.index + 1; // 1..4 chevrons
        for (var i = 0; i < n; i++) {
          final cx = p.x - 0.2 * (n - 1) + i * 0.4;
          final y = cy + hh + 0.5;
          canvas.drawPath(
            Path()
              ..moveTo(cx - 0.12, y - 0.2)
              ..lineTo(cx + 0.12, y)
              ..lineTo(cx - 0.12, y + 0.2),
            icon,
          );
        }
      } else {
        final big = p.kind == PortalKind.miniOff;
        final sz = big ? 0.35 : 0.18;
        final y = cy + hh + 0.5;
        canvas.drawPath(
          Path()
            ..moveTo(p.x + sz, y)
            ..lineTo(p.x - sz, y + sz)
            ..lineTo(p.x - sz, y - sz)
            ..close(),
          icon,
        );
      }
    }
  }

  void _drawFinish(Canvas canvas, double x0, double x1) {
    final fx = engine.level.length;
    if (!fx.isFinite || fx < x0 || fx > x1) return;
    final light = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.6);
    const sq = 0.5;
    for (var i = 0; i * sq < LevelData.worldHeight; i++) {
      for (var j = 0; j < 2; j++) {
        canvas.drawRect(Rect.fromLTWH(fx + j * sq, i * sq, sq, sq), (i + j).isEven ? light : dark);
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(fx - 0.5, 0, 2, LevelData.worldHeight),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
  }

  // ------------------------------------------------------------------ wave

  void _drawTrail(Canvas canvas, double x0) {
    final pts = engine.trail;
    if (pts.isEmpty) return;
    var start = 0;
    while (start < pts.length - 1 && pts[start + 1].x < x0) {
      start++;
    }
    final path = Path()..moveTo(pts[start].x, pts[start].y);
    for (var i = start + 1; i < pts.length; i++) {
      path.lineTo(pts[i].x, pts[i].y);
    }
    path.lineTo(engine.x, engine.y);

    final w = engine.mode.mini ? 0.13 : 0.22;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 2.6
        ..strokeJoin = StrokeJoin.miter
        ..color = skin.trail.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.15),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeJoin = StrokeJoin.miter
        ..color = skin.trail,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.35
        ..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  void _drawWave(Canvas canvas) {
    final angle = math.atan(engine.direction * engine.slope);
    canvas.save();
    canvas.translate(engine.x, engine.y);
    canvas.rotate(angle);
    final k = engine.mode.mini ? 0.62 : 1.0;
    canvas.scale(k, k);
    final arrow = Path()
      ..moveTo(0.45, 0)
      ..lineTo(-0.32, 0.32)
      ..lineTo(-0.15, 0)
      ..lineTo(-0.32, -0.32)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = skin.body.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.2),
    );
    canvas.drawPath(arrow, Paint()..color = skin.body);
    canvas.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.restore();
  }

  void _drawParticles(Canvas canvas) {
    for (final p in engine.particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(p.x, p.y), width: p.size, height: p.size),
        Paint()..color = (engine.state == RunState.won ? palette.accent : skin.body).withValues(alpha: a),
      );
    }
  }

  void _drawAttemptLabel(Canvas canvas, Size size, double camX, double s) {
    if (engine.endless || cameraLeft != null) return;
    const labelX = 3.0;
    final sx = (labelX - camX) * s;
    if (sx < -size.width) return;
    final tp = TextPainter(
      text: TextSpan(
        text: 'Attempt ${engine.attempts}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: size.height * 0.08,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(sx, size.height * 0.2));
  }

  @override
  bool shouldRepaint(covariant GamePainter old) =>
      old.engine != engine || old.palette != palette || old.skin != skin || old.cameraLeft != cameraLeft;
}

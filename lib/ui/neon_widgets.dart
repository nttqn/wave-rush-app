import 'package:flutter/material.dart';

import '../services/sound_service.dart';

/// Glowing outlined button used across menus.
class NeonButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback onPressed;
  final double width;
  final bool filled;

  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = const Color(0xFF3FE0FF),
    this.width = 220,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 16)],
        ),
        child: Material(
          color: filled ? color : const Color(0xFF0A1230),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color, width: 2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              SoundService.instance.play(SoundEffect.click);
              onPressed();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: filled ? Colors.black : color, size: 22),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button with a neon ring.
class NeonIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final double size;

  const NeonIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = const Color(0xFF3FE0FF),
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: const Color(0xAA0A1230),
        shape: CircleBorder(side: BorderSide(color: color, width: 2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            SoundService.instance.play(SoundEffect.click);
            onPressed();
          },
          child: Icon(icon, color: color, size: size * 0.5),
        ),
      ),
    );
  }
}

/// Music + SFX toggles, reacting to SoundService's notifiers.
class SoundToggles extends StatelessWidget {
  const SoundToggles({super.key});

  @override
  Widget build(BuildContext context) {
    final sound = SoundService.instance;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: sound.musicEnabled,
          builder: (context, on, _) => NeonIconButton(
            icon: on ? Icons.music_note : Icons.music_off,
            color: on ? const Color(0xFF3FE0FF) : Colors.white38,
            onPressed: sound.toggleMusic,
          ),
        ),
        const SizedBox(width: 12),
        ValueListenableBuilder<bool>(
          valueListenable: sound.sfxEnabled,
          builder: (context, on, _) => NeonIconButton(
            icon: on ? Icons.volume_up : Icons.volume_off,
            color: on ? const Color(0xFF3FE0FF) : Colors.white38,
            onPressed: sound.toggleSfx,
          ),
        ),
      ],
    );
  }
}

/// Big glowing title text.
class NeonTitle extends StatelessWidget {
  final String text;
  final double size;
  final Color color;

  const NeonTitle(this.text, {super.key, this.size = 52, this.color = const Color(0xFF3FE0FF)});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        letterSpacing: 3,
        color: Colors.white,
        shadows: [
          Shadow(color: color, blurRadius: 18),
          Shadow(color: color, blurRadius: 4),
        ],
      ),
    );
  }
}

/// Draws the wave's arrow on its own (skin previews, logo).
class ArrowGlyph extends StatelessWidget {
  final Color color;
  final double size;
  final double angle;

  const ArrowGlyph({super.key, required this.color, this.size = 48, this.angle = -0.785});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ArrowPainter(color, angle)),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  final double angle;
  _ArrowPainter(this.color, this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 1.0;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    canvas.scale(s, s);
    final arrow = Path()
      ..moveTo(0.42, 0)
      ..lineTo(-0.3, 0.3)
      ..lineTo(-0.14, 0)
      ..lineTo(-0.3, -0.3)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08),
    );
    canvas.drawPath(arrow, Paint()..color = color);
    canvas.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.color != color || old.angle != angle;
}

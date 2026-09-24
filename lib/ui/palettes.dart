import 'package:flutter/material.dart';

/// Per-level colour scheme for the neon look.
class LevelPalette {
  final Color bgTop;
  final Color bgBottom;
  final Color wallFill;
  final Color wallLine;
  final Color hazard;
  final Color accent;

  const LevelPalette({
    required this.bgTop,
    required this.bgBottom,
    required this.wallFill,
    required this.wallLine,
    required this.hazard,
    required this.accent,
  });
}

const List<LevelPalette> kPalettes = [
  // 0 electric blue
  LevelPalette(
    bgTop: Color(0xFF0B1B4D),
    bgBottom: Color(0xFF050A1F),
    wallFill: Color(0xFF0E2A6B),
    wallLine: Color(0xFF3FA9FF),
    hazard: Color(0xFFFF4F9A),
    accent: Color(0xFF3FA9FF),
  ),
  // 1 magenta
  LevelPalette(
    bgTop: Color(0xFF3D0B4D),
    bgBottom: Color(0xFF14041C),
    wallFill: Color(0xFF5A1470),
    wallLine: Color(0xFFFF5CF0),
    hazard: Color(0xFFFFD23F),
    accent: Color(0xFFFF5CF0),
  ),
  // 2 toxic green
  LevelPalette(
    bgTop: Color(0xFF0B3D25),
    bgBottom: Color(0xFF03140C),
    wallFill: Color(0xFF0F5634),
    wallLine: Color(0xFF4DFF9A),
    hazard: Color(0xFFFF5A4D),
    accent: Color(0xFF4DFF9A),
  ),
  // 3 sunset orange
  LevelPalette(
    bgTop: Color(0xFF4D1F0B),
    bgBottom: Color(0xFF1C0904),
    wallFill: Color(0xFF6B2E0E),
    wallLine: Color(0xFFFF9A3F),
    hazard: Color(0xFF3FE0FF),
    accent: Color(0xFFFF9A3F),
  ),
  // 4 violet
  LevelPalette(
    bgTop: Color(0xFF200B4D),
    bgBottom: Color(0xFF09041C),
    wallFill: Color(0xFF2E1470),
    wallLine: Color(0xFFA77BFF),
    hazard: Color(0xFF4DFFD8),
    accent: Color(0xFFA77BFF),
  ),
  // 5 crimson
  LevelPalette(
    bgTop: Color(0xFF4D0B18),
    bgBottom: Color(0xFF1C0409),
    wallFill: Color(0xFF6B0E22),
    wallLine: Color(0xFFFF3F5E),
    hazard: Color(0xFFFFFFFF),
    accent: Color(0xFFFF3F5E),
  ),
];

class WaveSkin {
  final String name;
  final Color body;
  final Color trail;

  /// Levels that must be completed to unlock this skin.
  final int unlockAt;

  const WaveSkin(this.name, this.body, this.trail, this.unlockAt);
}

const List<WaveSkin> kSkins = [
  WaveSkin('Classic', Color(0xFF3FE0FF), Color(0xFF3FE0FF), 0),
  WaveSkin('Lime', Color(0xFFB6FF3F), Color(0xFF7DFF3F), 1),
  WaveSkin('Rose', Color(0xFFFF5C9E), Color(0xFFFF2E7E), 2),
  WaveSkin('Gold', Color(0xFFFFD23F), Color(0xFFFFA83F), 3),
  WaveSkin('Violet', Color(0xFFB98CFF), Color(0xFF8A4DFF), 5),
  WaveSkin('Ember', Color(0xFFFF7A3F), Color(0xFFFF3F3F), 7),
  WaveSkin('Ghost', Color(0xFFFFFFFF), Color(0xFFBFD7FF), 9),
  WaveSkin('Prism', Color(0xFF4DFFD8), Color(0xFFFF5CF0), 12),
];

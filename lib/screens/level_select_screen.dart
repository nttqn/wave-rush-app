import 'package:flutter/material.dart';

import '../game/levels.dart';
import '../services/progress_service.dart';
import '../ui/neon_widgets.dart';
import '../ui/palettes.dart';
import 'game_screen.dart';

/// Swipeable level cards (all levels open from the start, like the genre —
/// the best % bar is the progression).
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  late final PageController _pages;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Start on the first level not yet beaten.
    final progress = ProgressService.instance;
    _index = kLevels.indexWhere((l) => !progress.isCompleted(l.id));
    if (_index < 0) _index = 0;
    _pages = PageController(initialPage: _index, viewportFraction: 0.62);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _play(LevelDef def) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(level: def)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  NeonIconButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop()),
                  const Expanded(child: NeonTitle('SELECT LEVEL', size: 30)),
                  const SizedBox(width: 46),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: kLevels.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => AnimatedScale(
                  scale: i == _index ? 1.0 : 0.86,
                  duration: const Duration(milliseconds: 200),
                  child: _LevelCard(def: kLevels[i], onPlay: () => _play(kLevels[i])),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < kLevels.length; i++)
                    Container(
                      width: i == _index ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: ProgressService.instance.isCompleted(kLevels[i].id)
                            ? const Color(0xFF4DFF9A)
                            : Colors.white.withValues(alpha: i == _index ? 0.9 : 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final LevelDef def;
  final VoidCallback onPlay;

  const _LevelCard({required this.def, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final palette = kPalettes[def.palette];
    final progress = ProgressService.instance;
    final best = progress.bestPercent(def.id);
    final done = best >= 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        onTap: onPlay,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.bgTop, palette.bgBottom],
            ),
            border: Border.all(color: palette.wallLine, width: 2.5),
            boxShadow: [BoxShadow(color: palette.wallLine.withValues(alpha: 0.4), blurRadius: 20)],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('LEVEL ${def.id}',
                          style: TextStyle(color: palette.wallLine, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const Spacer(),
                      if (done) const Icon(Icons.check_circle, color: Color(0xFF4DFF9A)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    def.name,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var s = 0; s < 5; s++)
                        Icon(s < def.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: s < def.stars ? palette.hazard : Colors.white24, size: 22),
                      const SizedBox(width: 8),
                      Text(def.difficultyLabel,
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Container(height: 18, color: Colors.black38),
                        FractionallySizedBox(
                          widthFactor: best / 100,
                          child: Container(height: 18, color: done ? const Color(0xFF4DFF9A) : palette.wallLine),
                        ),
                        SizedBox(
                          height: 18,
                          child: Center(
                            child: Text('$best%',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Attempts: ${progress.attempts(def.id)}', style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 10),
                  NeonButton(
                    label: 'PLAY',
                    icon: Icons.play_arrow_rounded,
                    color: palette.wallLine,
                    filled: true,
                    width: 180,
                    onPressed: onPlay,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

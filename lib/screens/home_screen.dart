import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../game/level_generator.dart';
import '../game/levels.dart';
import '../game/wave_engine.dart';
import '../services/ads_service.dart';
import '../services/progress_service.dart';
import '../ui/game_painter.dart';
import '../ui/neon_widgets.dart';
import '../ui/palettes.dart';
import 'game_screen.dart';
import 'level_select_screen.dart';
import 'my_levels_screen.dart';
import 'skins_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration _last = Duration.zero;
  late LevelBuilder _demoBuilder;
  late WaveEngine _demo;
  BannerAd? _banner;
  bool _bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _newDemo();
    _ticker = createTicker(_onTick)..start();
    _banner = AdsService.instance.createBannerAd(onLoaded: () {
      if (mounted) setState(() => _bannerLoaded = true);
    });
  }

  /// Background "attract mode": an endless run flown by an autopilot that
  /// just follows the generator's guaranteed-safe path.
  void _newDemo() {
    _demoBuilder = buildEndless(math.Random().nextInt(1 << 30));
    _demo = WaveEngine(level: _demoBuilder.level, endlessBuilder: _demoBuilder);
    _demo.setHolding(true);
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_demo.state == RunState.dead || _demo.x > 1400) _newDemo();
    final lookahead = _demo.speed * WaveEngine.fixedDt;
    _demo.setHolding(_demoBuilder.safePathYAt(_demo.x + lookahead) > _demo.y);
    _demo.update(dt);
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _banner?.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    _ticker.stop();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    _last = Duration.zero;
    _ticker.start();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final skin = kSkins[progress.selectedSkin.clamp(0, kSkins.length - 1)];
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: GamePainter(
              engine: _demo,
              palette: kPalettes[0],
              skin: skin,
              bpm: 128,
              repaint: _frame,
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.45)),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ArrowGlyph(color: skin.body, size: 56),
                              const SizedBox(width: 10),
                              const NeonTitle('WAVE RUSH'),
                            ],
                          ),
                          const Text(
                            'HOLD TO RISE  ·  RELEASE TO FALL',
                            style: TextStyle(color: Colors.white70, letterSpacing: 3, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              NeonButton(
                                label: 'PLAY',
                                icon: Icons.play_arrow_rounded,
                                filled: true,
                                width: 180,
                                onPressed: () => _open(const LevelSelectScreen()),
                              ),
                              NeonButton(
                                label: 'ENDLESS',
                                icon: Icons.all_inclusive,
                                color: const Color(0xFFFF5CF0),
                                width: 180,
                                onPressed: () => _open(const GameScreen(level: null)),
                              ),
                              NeonButton(
                                label: 'SKINS',
                                icon: Icons.palette_outlined,
                                color: const Color(0xFFFFD23F),
                                width: 180,
                                onPressed: () => _open(const SkinsScreen()),
                              ),
                              NeonButton(
                                label: 'CREATE',
                                icon: Icons.construction_rounded,
                                color: const Color(0xFF4DFF9A),
                                width: 180,
                                onPressed: () => _open(const MyLevelsScreen()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Levels ${progress.completedCount}/${kLevels.length}   ·   Endless best ${progress.endlessBest}m',
                            style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),
                          const SoundToggles(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_banner != null && _bannerLoaded)
                  SizedBox(
                    width: _banner!.size.width.toDouble(),
                    height: _banner!.size.height.toDouble(),
                    child: AdWidget(ad: _banner!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

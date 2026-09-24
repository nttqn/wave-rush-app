import 'package:flutter/material.dart';

import '../services/progress_service.dart';
import '../ui/neon_widgets.dart';
import '../ui/palettes.dart';

/// Wave colours, unlocked by completing levels.
class SkinsScreen extends StatefulWidget {
  const SkinsScreen({super.key});

  @override
  State<SkinsScreen> createState() => _SkinsScreenState();
}

class _SkinsScreenState extends State<SkinsScreen> {
  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final completed = progress.completedCount;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  NeonIconButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop()),
                  const Expanded(child: NeonTitle('SKINS', size: 30, color: Color(0xFFFFD23F))),
                  const SizedBox(width: 46),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.05,
                ),
                itemCount: kSkins.length,
                itemBuilder: (context, i) {
                  final skin = kSkins[i];
                  final unlocked = completed >= skin.unlockAt;
                  final selected = progress.selectedSkin == i;
                  return GestureDetector(
                    onTap: unlocked ? () => setState(() => progress.selectSkin(i)) : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1230),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? skin.body : Colors.white12,
                          width: selected ? 3 : 1.5,
                        ),
                        boxShadow: selected ? [BoxShadow(color: skin.body.withValues(alpha: 0.5), blurRadius: 14)] : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Opacity(
                            opacity: unlocked ? 1 : 0.25,
                            child: ArrowGlyph(color: skin.body, size: 64),
                          ),
                          const SizedBox(height: 6),
                          Text(skin.name,
                              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 2),
                          if (!unlocked)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock, size: 14, color: Colors.white54),
                                const SizedBox(width: 4),
                                Text('Beat ${skin.unlockAt} levels',
                                    style: const TextStyle(fontSize: 12, color: Colors.white54)),
                              ],
                            )
                          else if (selected)
                            Text('SELECTED',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: skin.body))
                          else
                            const Text('Tap to use', style: TextStyle(fontSize: 12, color: Colors.white54)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/custom_level.dart';
import '../services/custom_level_store.dart';
import '../ui/neon_widgets.dart';
import '../ui/palettes.dart';
import 'editor_screen.dart';
import 'game_screen.dart';

/// The player's own levels: create, edit, play, share and import.
class MyLevelsScreen extends StatefulWidget {
  const MyLevelsScreen({super.key});

  @override
  State<MyLevelsScreen> createState() => _MyLevelsScreenState();
}

class _MyLevelsScreenState extends State<MyLevelsScreen> {
  final _store = CustomLevelStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toast(String text, {bool good = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: good ? const Color(0xFF1B7F4B) : const Color(0xFF8A1F3A),
      ));
  }

  Future<void> _create() async {
    final level = CustomLevel.blank(_store.newId(), 'My Level ${_store.levels.length + 1}');
    await _store.save(level);
    await _edit(level);
  }

  Future<void> _edit(CustomLevel level) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(level: level)));
  }

  Future<void> _play(CustomLevel level) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(level: null, custom: level)));
  }

  Future<void> _share(CustomLevel level) async {
    if (!level.verified) {
      _toast('Verify it first: beat it in a test run, or tap ✓ in the editor.', good: false);
      return;
    }
    await Clipboard.setData(ClipboardData(text: level.toShareCode()));
    _toast('Level code copied — paste it to a friend!');
  }

  Future<void> _delete(CustomLevel level) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A1230),
        title: Text('Delete "${level.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE', style: TextStyle(color: Color(0xFFFF4F9A))),
          ),
        ],
      ),
    );
    if (ok == true) await _store.delete(level.id);
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A1230),
        title: const Text('Import level'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '${CustomLevel.sharePrefix}…',
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) ctrl.text = data!.text!;
                },
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('IMPORT')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    final level = CustomLevel.fromShareCode(code, newId: _store.newId());
    if (level == null) {
      _toast('That is not a valid level code.', good: false);
      return;
    }
    await _store.save(level);
    _toast('Imported "${level.name}"!');
  }

  @override
  Widget build(BuildContext context) {
    final levels = _store.levels;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  NeonIconButton(icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop()),
                  const Expanded(child: NeonTitle('MY LEVELS', size: 30, color: Color(0xFF4DFF9A))),
                  NeonButton(
                    label: 'IMPORT',
                    icon: Icons.download_rounded,
                    width: 130,
                    color: const Color(0xFFFFD23F),
                    onPressed: _import,
                  ),
                  const SizedBox(width: 10),
                  NeonButton(
                    label: 'NEW',
                    icon: Icons.add,
                    width: 110,
                    filled: true,
                    color: const Color(0xFF4DFF9A),
                    onPressed: _create,
                  ),
                ],
              ),
            ),
            Expanded(
              child: levels.isEmpty
                  ? const Center(
                      child: Text(
                        'No levels yet.\nTap NEW to build your first stage, or IMPORT a friend\'s code.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 16, height: 1.5),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: levels.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _LevelRow(
                        level: levels[i],
                        best: _store.bestPercent(levels[i].id),
                        onPlay: () => _play(levels[i]),
                        onEdit: () => _edit(levels[i]),
                        onShare: () => _share(levels[i]),
                        onDelete: () => _delete(levels[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  final CustomLevel level;
  final int best;
  final VoidCallback onPlay, onEdit, onShare, onDelete;

  const _LevelRow({
    required this.level,
    required this.best,
    required this.onPlay,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = kPalettes[level.palette.clamp(0, kPalettes.length - 1)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [palette.bgTop, palette.bgBottom]),
        border: Border.all(color: palette.wallLine, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: level.verified ? '✓ Verified' : 'Not verified',
                      style: TextStyle(
                        color: level.verified ? const Color(0xFF4DFF9A) : Colors.white54,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: '   ${level.length.round()}m  ·  ${level.objectCount} objects  ·  Best $best%',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ]),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Delete', onPressed: onDelete, icon: const Icon(Icons.delete_outline, color: Colors.white54)),
          IconButton(tooltip: 'Share code', onPressed: onShare, icon: const Icon(Icons.share, color: Colors.white70)),
          IconButton(tooltip: 'Edit', onPressed: onEdit, icon: Icon(Icons.edit, color: palette.wallLine)),
          const SizedBox(width: 4),
          NeonIconButton(icon: Icons.play_arrow_rounded, color: const Color(0xFF4DFF9A), onPressed: onPlay),
        ],
      ),
    );
  }
}

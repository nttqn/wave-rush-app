import 'dart:convert';
import 'dart:math' as math;

import 'level_data.dart';

/// Spike sizes offered by the editor: (base width, height).
const List<(double, double)> kSpikeSizes = [(1.0, 1.2), (1.2, 2.2), (1.5, 3.6)];

/// Saw radii offered by the editor.
const List<double> kSawSizes = [0.5, 0.8, 1.2];

/// A spike as the editor stores it: base centre + direction + size index.
class EditorSpike {
  final double x;
  final double y;
  final bool up;
  final int size;
  const EditorSpike(this.x, this.y, this.up, this.size);

  Spike toSpike() {
    final (w, h) = kSpikeSizes[size.clamp(0, kSpikeSizes.length - 1)];
    final a = Vec(x - w / 2, y), b = Vec(x + w / 2, y);
    final c = Vec(x, up ? y + h : y - h);
    return up ? Spike(a, b, c, fromCeiling: false) : Spike(b, a, c, fromCeiling: true);
  }

  List<num> toJson() => [_r(x), _r(y), up ? 1 : 0, size];
  static EditorSpike fromJson(List<dynamic> j) =>
      EditorSpike((j[0] as num).toDouble(), (j[1] as num).toDouble(), j[2] == 1, (j[3] as num).toInt());
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// A player-made level. Pure Dart — the editor screen only calls the
/// editing methods here, so everything about editing is unit-testable.
///
/// Walls are stored as *control points* in `0..length`; [toLevelData] adds
/// the lead-in behind the start and the run-out after the finish.
class CustomLevel {
  static const double minWallGap = 1.0;
  static const double wallMargin = 0.2;
  static const double minLength = 40;
  static const double maxLength = 1500;

  String id;
  String name;
  double length;
  double baseSpeed;
  int palette;
  int music;

  /// Set when [LevelSolver] proved the current layout beatable; any edit
  /// clears it.
  bool verified;

  final List<Vec> floorPoints;
  final List<Vec> ceilingPoints;
  final List<EditorSpike> spikes;
  final List<Saw> saws;
  final List<Portal> portals;

  CustomLevel({
    required this.id,
    required this.name,
    this.length = 200,
    this.baseSpeed = 8,
    this.palette = 0,
    this.music = 0,
    this.verified = false,
    List<Vec>? floorPoints,
    List<Vec>? ceilingPoints,
    List<EditorSpike>? spikes,
    List<Saw>? saws,
    List<Portal>? portals,
  })  : floorPoints = floorPoints ?? [const Vec(0, 0.5)],
        ceilingPoints = ceilingPoints ?? [const Vec(0, LevelData.worldHeight - 0.5)],
        spikes = spikes ?? [],
        saws = saws ?? [],
        portals = portals ?? [];

  factory CustomLevel.blank(String id, String name) => CustomLevel(id: id, name: name);

  int get objectCount => spikes.length + saws.length + portals.length;

  // --------------------------------------------------------------- geometry

  static double _wallAt(List<Vec> pts, double x) {
    if (x <= pts.first.x) return pts.first.y;
    if (x >= pts.last.x) return pts.last.y;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      if (x <= b.x) return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
    }
    return pts.last.y;
  }

  double floorAt(double x) => _wallAt(floorPoints, x);
  double ceilingAt(double x) => _wallAt(ceilingPoints, x);

  LevelData toLevelData() {
    final level = LevelData(baseSpeed: baseSpeed, length: length);
    void wall(List<Vec> out, List<Vec> pts) {
      out.add(Vec(-60, pts.first.y));
      for (final p in pts) {
        if (p.x > out.last.x) out.add(p);
      }
      final endY = _wallAt(pts, length);
      if (length > out.last.x) out.add(Vec(length, endY));
      out.add(Vec(length + 80, endY));
    }

    wall(level.floor, floorPoints);
    wall(level.ceiling, ceilingPoints);
    level.spikes.addAll(spikes.map((s) => s.toSpike()).toList()..sort((a, b) => a.minX.compareTo(b.minX)));
    level.saws.addAll([...saws]..sort((a, b) => a.x.compareTo(b.x)));
    level.portals.addAll([...portals]..sort((a, b) => a.x.compareTo(b.x)));
    return level;
  }

  // ---------------------------------------------------------------- editing

  void _changed() => verified = false;

  /// Adds (or moves) a floor/ceiling control point at [x]. The height is
  /// clamped so the corridor never closes completely.
  void setWallPoint({required bool ceiling, required double x, required double y}) {
    x = x.clamp(0.0, length);
    final pts = ceiling ? ceilingPoints : floorPoints;
    if (ceiling) {
      y = y.clamp(floorAt(x) + minWallGap, LevelData.worldHeight - wallMargin);
    } else {
      y = y.clamp(wallMargin, ceilingAt(x) - minWallGap);
    }
    pts.removeWhere((p) => (p.x - x).abs() < 0.01);
    pts.add(Vec(x, y));
    pts.sort((a, b) => a.x.compareTo(b.x));
    _changed();
  }

  void addSpike(double x, double y, {required bool up, int size = 0}) {
    spikes.removeWhere((s) => (s.x - x).abs() < 0.01 && (s.y - y).abs() < 0.01);
    spikes.add(EditorSpike(x, y, up, size));
    _changed();
  }

  void addSaw(double x, double y, {int size = 1}) {
    saws.removeWhere((s) => (s.x - x).abs() < 0.01 && (s.y - y).abs() < 0.01);
    saws.add(Saw(x, y, kSawSizes[size.clamp(0, kSawSizes.length - 1)]));
    _changed();
  }

  void addPortal(double x, PortalKind kind) {
    x = x.clamp(0.0, length);
    portals.removeWhere((p) => (p.x - x).abs() < 0.3);
    portals.add(Portal(x, kind));
    portals.sort((a, b) => a.x.compareTo(b.x));
    _changed();
  }

  /// Removes the object nearest to (x, y) within [radius]. Wall control
  /// points count too, except the one at x = 0 (the wall's start).
  /// Returns true if anything was removed.
  bool eraseNear(double x, double y, {double radius = 0.9}) {
    double best = radius;
    void Function()? remove;
    void consider(double d, void Function() action) {
      if (d < best) {
        best = d;
        remove = action;
      }
    }

    double dist(double ax, double ay) => math.sqrt((ax - x) * (ax - x) + (ay - y) * (ay - y));
    for (final s in spikes) {
      final (_, h) = kSpikeSizes[s.size.clamp(0, kSpikeSizes.length - 1)];
      consider(dist(s.x, s.y + (s.up ? h / 2 : -h / 2)), () => spikes.remove(s));
    }
    for (final s in saws) {
      consider(math.max(0, dist(s.x, s.y) - s.radius), () => saws.remove(s));
    }
    for (final p in portals) {
      consider((p.x - x).abs() * 1.5, () => portals.remove(p));
    }
    for (final pts in [floorPoints, ceilingPoints]) {
      for (final p in pts) {
        if (p.x <= 0) continue;
        consider(dist(p.x, p.y), () => pts.remove(p));
      }
    }
    if (remove == null) return false;
    remove!();
    _changed();
    return true;
  }

  /// Changes the level length, dropping anything beyond the new finish.
  void setLength(double value) {
    length = value.clamp(minLength, maxLength);
    floorPoints.removeWhere((p) => p.x > length);
    ceilingPoints.removeWhere((p) => p.x > length);
    spikes.removeWhere((s) => s.x > length);
    saws.removeWhere((s) => s.x > length);
    portals.removeWhere((p) => p.x > length);
    _changed();
  }

  void setSpeed(double value) {
    baseSpeed = value;
    _changed();
  }

  // ---------------------------------------------------------- serialization

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'name': name,
        'len': _r(length),
        'spd': _r(baseSpeed),
        'pal': palette,
        'mus': music,
        'ok': verified,
        'fl': [for (final p in floorPoints) [_r(p.x), _r(p.y)]],
        'cl': [for (final p in ceilingPoints) [_r(p.x), _r(p.y)]],
        'sp': [for (final s in spikes) s.toJson()],
        'sw': [for (final s in saws) [_r(s.x), _r(s.y), _r(s.radius)]],
        'pt': [for (final p in portals) [_r(p.x), p.kind.index]],
      };

  static CustomLevel fromJson(Map<String, dynamic> j) {
    List<Vec> pts(String key) => [
          for (final p in (j[key] as List? ?? const []))
            Vec(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
        ];
    final floor = pts('fl'), ceiling = pts('cl');
    return CustomLevel(
      id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: j['name'] as String? ?? 'Untitled',
      length: ((j['len'] as num?) ?? 200).toDouble().clamp(minLength, maxLength),
      baseSpeed: ((j['spd'] as num?) ?? 8).toDouble(),
      palette: (j['pal'] as num?)?.toInt() ?? 0,
      music: (j['mus'] as num?)?.toInt() ?? 0,
      verified: j['ok'] == true,
      floorPoints: floor.isEmpty ? null : floor,
      ceilingPoints: ceiling.isEmpty ? null : ceiling,
      spikes: [for (final s in (j['sp'] as List? ?? const [])) EditorSpike.fromJson(s as List)],
      saws: [
        for (final s in (j['sw'] as List? ?? const []))
          Saw(((s as List)[0] as num).toDouble(), (s[1] as num).toDouble(), (s[2] as num).toDouble()),
      ],
      portals: [
        for (final p in (j['pt'] as List? ?? const []))
          Portal(((p as List)[0] as num).toDouble(),
              PortalKind.values[(p[1] as num).toInt().clamp(0, PortalKind.values.length - 1)]),
      ],
    );
  }

  CustomLevel copy() => fromJson(toJson());

  // ------------------------------------------------------------ share codes

  static const String sharePrefix = 'WAVE1:';

  /// Compact text code players can paste to each other. The verified flag
  /// is deliberately not trusted from a code — imports get re-verified.
  String toShareCode() {
    final j = toJson()
      ..remove('id')
      ..remove('ok');
    return sharePrefix + base64Url.encode(utf8.encode(jsonEncode(j)));
  }

  /// Returns null if [code] isn't a valid level code.
  static CustomLevel? fromShareCode(String code, {required String newId}) {
    try {
      var body = code.trim();
      if (!body.startsWith(sharePrefix)) return null;
      body = body.substring(sharePrefix.length).replaceAll(RegExp(r'\s'), '');
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(body)))) as Map<String, dynamic>;
      return fromJson(j
        ..['id'] = newId
        ..['ok'] = false);
    } catch (_) {
      return null;
    }
  }
}

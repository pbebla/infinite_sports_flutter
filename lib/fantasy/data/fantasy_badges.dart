// Infinite Fantasy achievement badges — the PURE fan-side contract (spec
// docs/superpowers/specs/2026-10-30-fantasy-badges-design.md §3/§5). No
// Flutter/Firebase imports; unit-tested in test/fantasy/fantasy_badges_test.dart.
// FantasyService wraps these in onValue streams; the shelf / sheet / count
// chip (hub/badge_shelf.dart) render them.
//
// NODES (server-written — functions/src/lib/fantasy/badges.ts is the twin):
//
//   Fantasy/BadgeCatalog/<badgeId>  (GLOBAL, all sports/seasons) =
//     { Name, Description, Icon, ImageUrl?, Kind:'auto'|'manual',
//       Rule?, Repeatable, Order, Active }
//   Fantasy/<sport>/<season>/Badges/<uid>/<awardId> =
//     { Badge, Gw?, At, Source:'auto'|'manual', Note?, By? }
//
// The catalog read mirrors the server's catalogOf: the stored entries OVER
// the starter set, a missing field of a starter id falling back to the
// starter's value (any other id: the generic manual defaults). Entries are
// never deleted (Active:false hides one from the Manager's give list) — an
// EARNED badge always shows, active or not. An award whose badge is not in
// the catalog at all renders as the generic badge.
//
// `BadgeCatalog` sits next to the sport keys under `Fantasy/` — it is never a
// sport (see kFantasyReservedRootKeys and the season resolver's guard).

/// Keys directly under `Fantasy/` that are NOT sports.
const Set<String> kFantasyReservedRootKeys = {'BadgeCatalog'};

/// The Material icon key used when a catalog entry names none (and for an
/// unknown badge).
const String kDefaultBadgeIcon = 'military_tech';

/// The name an award shows when its badge id is not in the catalog.
const String kGenericBadgeName = 'Badge';

/// The sheet's attribution line on an owner-given (manual) badge.
const String kBadgeGivenByCopy = 'Given by Infinite Sports';

/// The Infinite profile's empty shelf.
const String kNoBadgesCopy = "No badges yet — they're earned every gameweek.";

enum FantasyBadgeKind { auto, manual }

/// One `Fantasy/BadgeCatalog/<badgeId>` entry.
class FantasyBadgeCatalogEntry {
  const FantasyBadgeCatalogEntry({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = kDefaultBadgeIcon,
    this.imageUrl,
    this.kind = FantasyBadgeKind.manual,
    this.rule,
    this.repeatable = true,
    this.order = 1000,
    this.active = true,
  });

  final String id;
  final String name;
  final String description;

  /// A curated Material icon key (hub/badge_shelf.dart maps it).
  final String icon;

  /// An uploaded picture (Storage download URL) — wins over [icon].
  final String? imageUrl;
  final FantasyBadgeKind kind;

  /// The engine rule key of an auto badge (one of the starter ids).
  final String? rule;
  final bool repeatable;

  /// Display order (ascending).
  final int order;

  /// false = hidden from the Manager's give list; earned ones still show.
  final bool active;

  FantasyBadgeCatalogEntry _copyWith({
    String? name,
    String? description,
    String? icon,
    String? imageUrl,
    FantasyBadgeKind? kind,
    String? rule,
    bool clearRule = false,
    bool? repeatable,
    int? order,
    bool? active,
  }) =>
      FantasyBadgeCatalogEntry(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        icon: icon ?? this.icon,
        imageUrl: imageUrl,
        kind: kind ?? this.kind,
        rule: clearRule ? null : (rule ?? this.rule),
        repeatable: repeatable ?? this.repeatable,
        order: order ?? this.order,
        active: active ?? this.active,
      );
}

/// badgeId → catalog entry.
typedef FantasyBadgeCatalog = Map<String, FantasyBadgeCatalogEntry>;

const Set<String> _weeklyRules = {
  'captainGenius',
  'crystalBall',
  'benchBoss',
  'hiddenGem',
  'topOfTheWeek',
};

FantasyBadgeCatalogEntry _starter(String rule, String name,
        String description, String icon, int order) =>
    FantasyBadgeCatalogEntry(
      id: rule,
      name: name,
      description: description,
      icon: icon,
      kind: FantasyBadgeKind.auto,
      rule: rule,
      repeatable: _weeklyRules.contains(rule),
      order: order,
    );

/// The starter set — a copy of the server's STARTER_CATALOG (badges.ts), so
/// an award that outruns the first catalog seeding still reads right.
final FantasyBadgeCatalog kStarterBadgeCatalog = {
  for (final e in [
    _starter('captainGenius', 'Captain Genius',
        'Your captain outscored (or tied) every other starter in your team that gameweek.',
        'military_tech', 10),
    _starter('crystalBall', 'Crystal Ball',
        'At least 3 of the Team of the Week were in your squad.',
        'auto_awesome', 20),
    _starter('benchBoss', 'Bench Boss',
        'Nobody on your bench outscored a starter in the same position (not in a Bench Boost week).',
        'event_seat', 30),
    _starter('hiddenGem', 'Hidden Gem',
        'One of your starters scored 10+ points while fewer than 10% of managers owned him.',
        'diamond', 40),
    _starter('topOfTheWeek', 'Top of the Week',
        'Highest score of the gameweek.', 'emoji_events', 50),
    _starter('everPresent', 'Ever Present',
        'You had a team in every gameweek of the season.',
        'calendar_month', 60),
    _starter('champion', 'Champion', 'Finished the season 1st overall.',
        'workspace_premium', 70),
    _starter('runnerUp', 'Runner-up', 'Finished the season 2nd overall.',
        'looks_two', 80),
    _starter('thirdPlace', 'Third place', 'Finished the season 3rd overall.',
        'looks_3', 90),
  ])
    e.id: e,
};

int? _optInt(Object? raw) => raw is num
    ? (raw.isFinite ? raw.toInt() : null)
    : int.tryParse(raw?.toString().trim() ?? '');

String _text(Object? raw) => raw is String ? raw.trim() : '';

/// `{key: child}` pairs of a Map, or of a list-coerced node (index = key,
/// holes skipped).
Iterable<MapEntry<String, Object?>> _children(Object? node) sync* {
  if (node is Map) {
    for (final e in node.entries) {
      yield MapEntry(e.key.toString(), e.value);
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      if (node[i] != null) yield MapEntry('$i', node[i]);
    }
  }
}

/// One stored catalog entry (server parseCatalogEntry's rules): null for a
/// non-map. A field missing from a starter id's entry falls back to the
/// starter value, from any other id to the generic defaults (Name = the id,
/// manual, repeatable, active). An empty ImageUrl is no picture.
FantasyBadgeCatalogEntry? badgeCatalogEntryFromNode(String id, Object? node) {
  if (node is! Map) return null;
  final base = kStarterBadgeCatalog[id] ??
      FantasyBadgeCatalogEntry(id: id, name: id);
  final rawRule = node['Rule'];
  final String? storedRule =
      rawRule is String && kStarterBadgeCatalog.containsKey(rawRule)
          ? rawRule
          : null;
  final kind = switch (node['Kind']) {
    'auto' => FantasyBadgeKind.auto,
    'manual' => FantasyBadgeKind.manual,
    _ => base.kind,
  };
  final image = _text(node['ImageUrl']);
  final description = node['Description'];
  final repeatable = node['Repeatable'];
  final active = node['Active'];
  return base._copyWith(
    name: _text(node['Name']).isNotEmpty ? _text(node['Name']) : base.name,
    description:
        description is String ? description.trim() : base.description,
    icon: _text(node['Icon']).isNotEmpty ? _text(node['Icon']) : base.icon,
    imageUrl: image.isEmpty ? null : image,
    kind: kind,
    rule: storedRule,
    // A stored Rule that is not an engine rule key reads as none.
    clearRule: node.containsKey('Rule') && storedRule == null,
    repeatable: repeatable is bool ? repeatable : base.repeatable,
    order: _optInt(node['Order']) ?? base.order,
    active: active is bool ? active : base.active,
  );
}

/// The whole `Fantasy/BadgeCatalog` node → the effective catalog: the stored
/// entries over the starter set (absent node = the starter set). Junk
/// children are skipped, never a crash.
FantasyBadgeCatalog badgeCatalogFromNode(Object? node) {
  final out = <String, FantasyBadgeCatalogEntry>{...kStarterBadgeCatalog};
  for (final e in _children(node)) {
    final entry = badgeCatalogEntryFromNode(e.key, e.value);
    if (entry != null) out[e.key] = entry;
  }
  return out;
}

enum FantasyBadgeSource { auto, manual }

/// One `Badges/<uid>/<awardId>` row.
class FantasyBadgeAward {
  const FantasyBadgeAward({
    required this.id,
    required this.badgeId,
    this.gw,
    this.atMs = 0,
    this.source = FantasyBadgeSource.auto,
    this.note,
    this.by,
  });

  /// `<badgeId>_gw<N>` / `<badgeId>_season` (auto) or a push id (manual).
  final String id;
  final String badgeId;

  /// The gameweek it was earned in; null = season-wide (season-end awards,
  /// a manual award given without a week).
  final int? gw;
  final int atMs;
  final FantasyBadgeSource source;

  /// The owner's note on a manual award.
  final String? note;

  /// The admin uid that gave a manual award.
  final String? by;

  bool get isManual => source == FantasyBadgeSource.manual;
}

/// One award row; null when unusable (not a map, no Badge).
FantasyBadgeAward? badgeAwardFromNode(String id, Object? node) {
  if (node is! Map) return null;
  final badge = _text(node['Badge']);
  if (badge.isEmpty) return null;
  final gw = _optInt(node['Gw']);
  final note = _text(node['Note']);
  final by = _text(node['By']);
  return FantasyBadgeAward(
    id: id,
    badgeId: badge,
    gw: (gw == null || gw <= 0) ? null : gw,
    atMs: _optInt(node['At']) ?? 0,
    source: node['Source'] == 'manual'
        ? FantasyBadgeSource.manual
        : FantasyBadgeSource.auto,
    note: note.isEmpty ? null : note,
    by: by.isEmpty ? null : by,
  );
}

/// One manager's `Badges/<uid>` node → awards, oldest first (At, then week,
/// then id). Empty when absent/malformed.
List<FantasyBadgeAward> badgeAwardsFromNode(Object? node) {
  final out = [
    for (final e in _children(node))
      if (badgeAwardFromNode(e.key, e.value) case final award?) award,
  ];
  out.sort((a, b) {
    final byAt = a.atMs.compareTo(b.atMs);
    if (byAt != 0) return byAt;
    final byGw = (a.gw ?? 1 << 30).compareTo(b.gw ?? 1 << 30);
    return byGw != 0 ? byGw : a.id.compareTo(b.id);
  });
  return out;
}

/// The whole season `Badges` node → uid → awards (the leaderboard's counts).
/// A uid with nothing usable is absent.
Map<String, List<FantasyBadgeAward>> badgesByUidFromNode(Object? node) {
  final out = <String, List<FantasyBadgeAward>>{};
  for (final e in _children(node)) {
    final awards = badgeAwardsFromNode(e.value);
    if (awards.isNotEmpty) out[e.key] = awards;
  }
  return out;
}

/// One badge on a manager's shelf: every award of it, oldest first.
class FantasyBadgeGroup {
  FantasyBadgeGroup({
    required this.badgeId,
    required this.entry,
    required this.awards,
  });

  final String badgeId;

  /// null = the id is not in the catalog → the generic badge.
  final FantasyBadgeCatalogEntry? entry;
  final List<FantasyBadgeAward> awards;

  int get count => awards.length;
  String get name => entry?.name ?? kGenericBadgeName;
  String get description => entry?.description ?? '';

  /// The gameweeks it was earned in, ascending and distinct.
  late final List<int> weeks = ({
    for (final a in awards)
      if (a.gw != null) a.gw!,
  }.toList()
    ..sort());

  /// At least one award without a week (season-end / season-wide).
  bool get seasonWide => awards.any((a) => a.gw == null);

  bool get hasManual => awards.any((a) => a.isManual);

  /// The owner's notes on the manual awards, oldest first.
  List<String> get notes => [
        for (final a in awards)
          if (a.isManual && a.note != null) a.note!,
      ];
}

/// Awards → one group per badge, in catalog order (Order, then name, then
/// id; unknown ids last). Inactive catalog entries still group (earned
/// badges always show).
List<FantasyBadgeGroup> groupBadgeAwards(
    List<FantasyBadgeAward> awards, FantasyBadgeCatalog catalog) {
  final byBadge = <String, List<FantasyBadgeAward>>{};
  for (final a in awards) {
    byBadge.putIfAbsent(a.badgeId, () => []).add(a);
  }
  final groups = [
    for (final e in byBadge.entries)
      FantasyBadgeGroup(
        badgeId: e.key,
        entry: catalog[e.key],
        awards: [...e.value]..sort((a, b) => a.atMs.compareTo(b.atMs)),
      ),
  ];
  groups.sort((a, b) {
    final byOrder = (a.entry?.order ?? 1 << 30)
        .compareTo(b.entry?.order ?? 1 << 30);
    if (byOrder != 0) return byOrder;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.badgeId.compareTo(b.badgeId);
  });
  return groups;
}

/// When a badge was earned: "GW3, GW7, GW9", "Season 15", or both joined
/// ("GW4 · Season 15").
String badgeEarnedLine(FantasyBadgeGroup group, {required String season}) {
  final s = season.trim();
  return [
    if (group.weeks.isNotEmpty) group.weeks.map((w) => 'GW$w').join(', '),
    if (group.seasonWide) s.isEmpty ? 'This season' : 'Season $s',
  ].join(' · ');
}

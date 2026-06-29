// Pure helpers for the player profile. No Flutter imports.

/// A single competition the player took part in (league season or tournament).
class ParticipationStint {
  final String sport;       // 'Futsal' | 'Basketball' | 'Flag Football' | 'AFC San Jose' | 'Soccer'
  final String label;       // display year/season, e.g. '2026' or 'Season 5'
  final int sortKey;        // for ordering (year or season number; higher = newer)
  final String team;
  final String position;    // raw position string from data
  final bool isActive;      // season/tournament not finished
  final bool isTournament;
  final String scopeId;     // tournamentId or sport key (for tap-to-detail)

  ParticipationStint({
    required this.sport, required this.label, required this.sortKey,
    required this.team, required this.position, required this.isActive,
    this.isTournament = false, this.scopeId = '',
  });
}

/// Normalize a raw position string into a coarse group used for stat ordering.
String positionGroup(String sport, String position) {
  final p = position.toLowerCase().trim();
  final s = sport.toLowerCase();
  if (s.contains('basket')) {
    if (p.startsWith('g') || p.contains('guard')) return 'GUARD';
    return 'BIG'; // forward/center
  }
  if (s.contains('flag')) {
    if (p.contains('qb') || p.contains('quarter')) return 'QB';
    if (p.contains('wr') || p.contains('rb') || p.contains('recei') || p.contains('rush')) return 'SKILL';
    if (p.contains('def') || p.contains('db') || p.contains('lb')) return 'DEF';
    return 'SKILL';
  }
  // soccer / futsal
  if (p.contains('gk') || p.contains('keep') || p.contains('goalie')) return 'GK';
  if (p.contains('def') || p.contains('back')) return 'DEF';
  if (p.contains('mid')) return 'MID';
  return 'ATT';
}

const Map<String, Map<String, List<String>>> _priority = {
  'Futsal': {
    'GK': ['games', 'cleanSheets', 'saves', 'dpl'],
    'DEF': ['games', 'dpl', 'assists', 'goals'],
    'MID': ['games', 'goals', 'assists', 'dpl'],
    'ATT': ['games', 'goals', 'assists', 'dpl'],
  },
  'Basketball': {
    'GUARD': ['points', 'threePointers', 'rebounds', 'twoPointers', 'freeThrows'],
    'BIG': ['points', 'rebounds', 'threePointers', 'twoPointers', 'freeThrows'],
  },
  'Flag Football': {
    'QB': ['passTouchdowns', 'receptions', 'interceptions', 'flagPulls', 'sacks'],
    'SKILL': ['receivingTouchdowns', 'receptions', 'flagPulls', 'interceptions', 'sacks'],
    'DEF': ['interceptions', 'flagPulls', 'sacks', 'passBreakups'],
  },
};

/// Soccer/AFC + Tournament reuse the Futsal table (same stat vocabulary).
List<String> profileStatPriority(String sport, String group) {
  final table = _priority[sport] ?? _priority['Futsal']!;
  return table[group] ?? table.values.first;
}

/// True if the player should be treated as a keeper.
bool detectKeeper(Map<String, num> stats, String position) {
  if (positionGroup('Futsal', position) == 'GK') return true;
  final saves = stats['saves'] ?? 0;
  final cleanSheets = stats['cleanSheets'] ?? 0;
  final goals = stats['goals'] ?? 0;
  return (saves + cleanSheets) > goals && (saves + cleanSheets) > 0;
}

/// The player's current stint: an active one (highest sortKey), else the most
/// recent of any.
ParticipationStint? currentParticipation(List<ParticipationStint> stints) {
  if (stints.isEmpty) return null;
  final active = stints.where((s) => s.isActive).toList()
    ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  if (active.isNotEmpty) return active.first;
  final all = [...stints]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return all.first;
}

/// All stints newest-first.
List<ParticipationStint> careerHistory(List<ParticipationStint> stints) {
  final out = [...stints]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return out;
}

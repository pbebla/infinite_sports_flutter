class Award {
  final String id;
  final String trophyId;
  final String name;
  final String icon;
  final String iconType;
  final String tier;
  final String sport;
  final String scopeType; // 'tournament' | 'league'
  final String scopeId;
  final String season;
  final String edition;
  final String context;
  final String date; // MMDDYYYY
  final String source; // 'auto' | 'manual'

  const Award({
    required this.id,
    required this.trophyId,
    required this.name,
    required this.icon,
    required this.iconType,
    required this.tier,
    required this.sport,
    required this.scopeType,
    required this.scopeId,
    required this.season,
    required this.edition,
    required this.context,
    required this.date,
    required this.source,
  });

  factory Award.fromMap(String id, Map<dynamic, dynamic> m) => Award(
        id: id,
        trophyId: (m['TrophyId'] ?? '').toString(),
        name: (m['Name'] ?? '').toString(),
        icon: (m['Icon'] ?? 'trophy_gold').toString(),
        iconType: (m['IconType'] ?? 'builtin').toString(),
        tier: (m['Tier'] ?? 'gold').toString(),
        sport: (m['Sport'] ?? '').toString(),
        scopeType: (m['ScopeType'] ?? '').toString(),
        scopeId: (m['ScopeId'] ?? '').toString(),
        season: (m['Season'] ?? '').toString(),
        edition: (m['Edition'] ?? '').toString(),
        context: (m['Context'] ?? '').toString(),
        date: (m['Date'] ?? '').toString(),
        source: (m['Source'] ?? 'manual').toString(),
      );

  Map<String, dynamic> toFirebaseMap() => {
        'TrophyId': trophyId,
        'Name': name,
        'Icon': icon,
        'IconType': iconType,
        'Tier': tier,
        'Sport': sport,
        'ScopeType': scopeType,
        'ScopeId': scopeId,
        'Season': season,
        'Edition': edition,
        'Context': context,
        'Date': date,
        'Source': source,
      };
}

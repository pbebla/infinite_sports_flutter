import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';
import 'package:infinite_sports_flutter/misc/share_profile_service.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart'
    show catchPercentage;
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/flagfootballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/profile/career_tab.dart';
import 'package:infinite_sports_flutter/profile/profile_hero.dart';
import 'package:infinite_sports_flutter/profile/profile_tab.dart';
import 'package:infinite_sports_flutter/profile/stats_tab.dart';
import 'package:infinite_sports_flutter/widgets/share_profile_card.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

// ─── Human-readable labels for stat keys (shared across ProfileTab + StatsTab) ─
const Map<String, String> _statLabel = {
  'games': 'Games',
  'goals': 'Goals',
  'assists': 'Assists',
  'saves': 'Saves',
  'cleanSheets': 'Clean Sheets',
  'dpl': 'DPL',
  'points': 'Points',
  'rebounds': 'Rebounds',
  'threePointers': '3PM',
  'twoPointers': '2PM',
  'freeThrows': 'FTM',
  'passTouchdowns': 'Pass TDs',
  'receivingTouchdowns': 'Rec TDs',
  'receptions': 'Receptions',
  'catchPercentage': 'Catch %',
  'interceptions': 'INTs',
  'flagPulls': 'Flag Pulls',
  'sacks': 'Sacks',
  'passBreakups': 'PBUs',
};

/// Profile stat values render as plain counts except Catch % (L6.1),
/// which carries a % suffix.
String formatProfileStatValue(String key, num value) =>
    key == 'catchPercentage' ? '$value%' : value.toString();

/// The full tabbed player profile page.
///
/// Loads data from Firebase via [getProfileData] (mirrors the old
/// PlayerPage.getPlayerData logic, extended with tournament history).
///
/// Callers that previously used `PlayerPage(uid: uid)` now get this page
/// via the thin `PlayerPage` wrapper in playerpage.dart.
///
/// For players without a linked account, use [ProfilePage.limited].
class ProfilePage extends StatefulWidget {
  final String uid;

  /// When true, this instance was constructed via [ProfilePage.limited].
  /// Only a name is available — no Firebase load is performed.
  final bool _isLimited;
  final String _limitedName;

  const ProfilePage({super.key, required this.uid})
      : _isLimited = false,
        _limitedName = '';

  /// Stub for Task 8: renders just the name with "not linked" message.
  const ProfilePage.limited({super.key, required String name})
      : uid = '',
        _isLimited = true,
        _limitedName = name;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Raw loaded data ──────────────────────────────────────────────────────
  String _firstName = '';
  String _lastName = '';
  String _profileUrl = '';
  Map<dynamic, dynamic> _information = {};
  List<Award> _awards = [];

  // ── Share state ──────────────────────────────────────────────────────────
  /// Tracks which competition is currently selected in the Stats tab, so the
  /// Share button on that tab knows which card to build.
  int _selectedStatsIndex = 0;

  // sport → seasonNum → (teamName, teamColor, Player)
  final Map<String, Map<String, (String, Color, Player)>> _tableEntries = {};
  final Map<String, String> _sportPositions = {};

  // ── Built data structures ───────────────────────────────────────────────
  List<ParticipationStint> _stints = [];
  List<CompetitionStats> _competitions = [];
  List<CareerRow> _careerRows = [];
  ParticipationStint? _current;
  Color? _teamColor;
  List<({String label, String value})> _headlineStats = [];
  String? _currentTeamNumber;
  String? _currentStatsLabel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Helper: extract league player stats ───────────────────────────────

  Future<(String, Color, Player)> _extractHelper(
      String sport, String season, String team) async {
    await getAllTeamLogo();
    // Color extraction is deferred — we only decode the CURRENT stint's logo
    // once, after _current is determined. Use a placeholder here so we don't
    // download + decode every logo for every season.
    const Color placeholder = Color(0xFFD00000);
    (String, Color, Player) data;
    if (sport == 'Basketball') {
      data = ('', placeholder, BasketballPlayer());
      final entries = basketballLineups[season]?[team]?.entries;
      if (entries != null) {
        for (final entry in entries) {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final logoUrl =
                (teamLogos[sport]?[season]?[team])?.toString() ?? '';
            info.teamPath = logoUrl;
            if (_firstName.isEmpty && info.name.contains(' ')) {
              _firstName = info.name.split(' ')[0];
              _lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, placeholder, info);
            break;
          }
        }
      }
    } else if (sport == 'Futsal') {
      data = ('', placeholder, FutsalPlayer());
      final entries = futsalLineups[season]?[team]?.entries;
      if (entries != null) {
        for (final entry in entries) {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final logoUrl =
                (teamLogos[sport]?[season]?[team])?.toString() ?? '';
            info.teamPath = logoUrl;
            if (_firstName.isEmpty && info.name.contains(' ')) {
              _firstName = info.name.split(' ')[0];
              _lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, placeholder, info);
            break;
          }
        }
      }
    } else {
      // Flag Football
      data = ('', placeholder, FlagFootballPlayer());
      final entries = flagFootballLineups[season]?[team]?.entries;
      if (entries != null) {
        for (final entry in entries) {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final logoUrl =
                (teamLogos[sport]?[season]?[team])?.toString() ?? '';
            info.teamPath = logoUrl;
            if (_firstName.isEmpty && info.name.contains(' ')) {
              _firstName = info.name.split(' ')[0];
              _lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, placeholder, info);
            break;
          }
        }
      }
    }
    return data;
  }

  Future<(String, Color, Player)> _extractPlayerStats(
      String sport, String season, String team) async {
    var val = await _extractHelper(sport, season, team);
    if (val.$1 != '') return val;

    // Try other teams in case player transferred
    if (sport == 'Basketball') {
      for (final other in (basketballLineups[season] ?? {}).keys) {
        if (other == team) continue;
        val = await _extractHelper(sport, season, other);
        if (val.$1 != '') return val;
      }
    } else if (sport == 'Futsal') {
      for (final other in (futsalLineups[season] ?? {}).keys) {
        if (other == team) continue;
        val = await _extractHelper(sport, season, other);
        if (val.$1 != '') return val;
      }
    } else if (sport == 'Flag Football') {
      for (final other in (flagFootballLineups[season] ?? {}).keys) {
        if (other == team) continue;
        val = await _extractHelper(sport, season, other);
        if (val.$1 != '') return val;
      }
    }
    return val;
  }

  Future<void> _extractAFCStats() async {
    try {
      final seasons = await getSoccerSeasons('AFC San Jose');
      await Future.forEach(seasons, (season) async {
        final roster = await getSoccerRoster('AFC San Jose', season);
        roster.forEach((name, info) {
          if (info.uid == widget.uid) {
            _tableEntries['AFC San Jose'] ??= {};
            _tableEntries['AFC San Jose']![season] =
                (season, Colors.white, info);
          }
        });
      });
    } catch (_) {}
  }

  // ─── Stat map builders ──────────────────────────────────────────────────

  Map<String, num> _futsalStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int goals = 0, assists = 0, saves = 0;
    for (final e in seasons.values) {
      final p = e.$3 as FutsalPlayer;
      goals += p.goals;
      assists += p.assists;
      saves += p.saves;
    }
    return {'goals': goals, 'assists': assists, 'saves': saves};
  }

  Map<String, num> _basketballStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int points = 0, rebounds = 0, threePointers = 0, twoPointers = 0,
        freeThrows = 0;
    for (final e in seasons.values) {
      final p = e.$3 as BasketballPlayer;
      points += p.total;
      rebounds += p.rebounds;
      threePointers += p.threePoints;
      twoPointers += p.twoPoints;
      freeThrows += p.onePoint;
    }
    return {
      'points': points,
      'rebounds': rebounds,
      'threePointers': threePointers,
      'twoPointers': twoPointers,
      'freeThrows': freeThrows,
    };
  }

  Map<String, num> _flagFootballStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int receptions = 0, receptionMisses = 0, receivingTDs = 0, passTDs = 0,
        interceptions = 0, flagPulls = 0, sacks = 0, passBreakups = 0;
    for (final e in seasons.values) {
      final p = e.$3 as FlagFootballPlayer;
      receptions += p.receptions;
      receptionMisses += p.receptionMisses;
      receivingTDs += p.receivingTouchdowns;
      passTDs += p.passingTouchdowns;
      interceptions += p.interceptions;
      flagPulls += p.flagPulls;
      sacks += p.sacks;
      passBreakups += p.passBreakups;
    }
    // Career Catch % (L6.1) from career REC/RECMiss. No minTargets gate —
    // the player's own profile shows their real rate; null (zero targets)
    // omits the row entirely instead of showing a misleading 0%.
    final catchPct = catchPercentage(receptions, receptionMisses);
    return {
      'receptions': receptions,
      if (catchPct != null) 'catchPercentage': catchPct,
      'receivingTouchdowns': receivingTDs,
      'passTouchdowns': passTDs,
      'interceptions': interceptions,
      'flagPulls': flagPulls,
      'sacks': sacks,
      'passBreakups': passBreakups,
    };
  }

  Map<String, num> _soccerStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int goals = 0, assists = 0, saves = 0;
    for (final e in seasons.values) {
      final p = e.$3 as SoccerPlayer;
      goals += p.goals;
      assists += p.assists;
      saves += p.saves;
    }
    return {'goals': goals, 'assists': assists, 'saves': saves};
  }

  Map<String, num> _tournamentPlayerStatMap(TournamentPlayer p) {
    final m = <String, num>{};
    if (p.goals > 0) m['goals'] = p.goals;
    if (p.assists > 0) m['assists'] = p.assists;
    if (p.saves > 0) m['saves'] = p.saves;
    if (p.cleanSheets > 0) m['cleanSheets'] = p.cleanSheets;
    if (p.dpl > 0) m['dpl'] = p.dpl;
    return m;
  }

  // ─── Career row summary strings ─────────────────────────────────────────

  String _futsalSummary(Map<String, num> stats) {
    final parts = <String>[];
    if ((stats['goals'] ?? 0) > 0) parts.add('${stats['goals']}G');
    if ((stats['assists'] ?? 0) > 0) parts.add('${stats['assists']}A');
    if ((stats['saves'] ?? 0) > 0) parts.add('${stats['saves']} saves');
    return parts.join(' · ');
  }

  String _basketballSummary(Map<String, num> stats) {
    final pts = stats['points'] ?? 0;
    final reb = stats['rebounds'] ?? 0;
    final parts = <String>[];
    if (pts > 0) parts.add('${pts}pts');
    if (reb > 0) parts.add('${reb}reb');
    return parts.join(' · ');
  }

  String _flagFootballSummary(Map<String, num> stats) {
    final parts = <String>[];
    final tds = (stats['receivingTouchdowns'] ?? 0) +
        (stats['passTouchdowns'] ?? 0);
    if (tds > 0) parts.add('${tds}TD');
    if ((stats['receptions'] ?? 0) > 0) {
      parts.add('${stats['receptions']}rec');
    }
    return parts.join(' · ');
  }

  String _soccerSummary(Map<String, num> stats) => _futsalSummary(stats);

  String _tournamentSummary(Map<String, num> stats) {
    final parts = <String>[];
    if ((stats['goals'] ?? 0) > 0) parts.add('${stats['goals']}G');
    if ((stats['assists'] ?? 0) > 0) parts.add('${stats['assists']}A');
    if ((stats['saves'] ?? 0) > 0) parts.add('${stats['saves']} saves');
    return parts.join(' · ');
  }

  // ─── Award matching ──────────────────────────────────────────────────────

  bool _awardMatchesStint(Award award, ParticipationStint stint) {
    if (stint.isTournament) {
      return award.scopeType == 'tournament' &&
          award.scopeId == stint.scopeId;
    } else {
      final sportKey = stint.sport.replaceAll(' ', '').toLowerCase();
      final scopeMatch = award.scopeId.toLowerCase().contains(sportKey) ||
          award.sport.toLowerCase().contains(stint.sport.toLowerCase()) ||
          award.sport == stint.sport;
      final seasonMatch = award.season == stint.label ||
          award.season == 'Season ${stint.label}';
      return award.scopeType == 'league' && scopeMatch && seasonMatch;
    }
  }

  // ─── Team logo URL helper ────────────────────────────────────────────────

  String _teamLogoUrl(String sport, String season, String team) {
    try {
      if (sport == 'AFC San Jose') {
        final afcVal = teamLogos['AFC San Jose'];
        if (afcVal is String) return afcVal;
        return '';
      }
      final url = teamLogos[sport]?[season]?[team];
      return url?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ─── Main data load ──────────────────────────────────────────────────────

  List<({String label, String value})> _buildHeadlineStats() {
    if (_current == null) return [];

    Map<String, num> statMap;
    String sport;
    String position;

    if (_current!.isTournament) {
      final ta = _findTournamentAppearance(_current!.scopeId);
      if (ta == null) return [];
      statMap = _tournamentPlayerStatMap(ta.player);
      sport = ta.sport;
      position = ta.position;
    } else {
      sport = _current!.sport;
      position = _current!.position;
      final seasons = _tableEntries[sport];
      if (seasons == null || seasons.isEmpty) return [];
      // Show only the current season stats, not career totals
      final currentSeasonEntry = seasons[_current!.label];
      if (currentSeasonEntry != null) {
        statMap = _buildStatMapForSingleEntry(sport, currentSeasonEntry.$3);
      } else {
        statMap = _buildStatMapForSport(sport, seasons);
      }
    }

    final group = positionGroup(sport, position);
    final priority = profileStatPriority(sport, group);

    final result = <({String label, String value})>[];
    for (final key in priority) {
      if (statMap.containsKey(key)) {
        result.add((
          label: _statLabel[key] ?? key,
          value: formatProfileStatValue(key, statMap[key]!),
        ));
        if (result.length == 3) break;
      }
    }

    // Pad to 3 if fewer than 3 keys are present
    while (result.length < 3) {
      result.add((label: '—', value: '—'));
    }

    return result;
  }

  /// Build stat map from a single Player entry (for current season card).
  Map<String, num> _buildStatMapForSingleEntry(String sport, Player player) {
    switch (sport) {
      case 'Futsal':
        final p = player as FutsalPlayer;
        return {'goals': p.goals, 'assists': p.assists, 'saves': p.saves};
      case 'Basketball':
        final p = player as BasketballPlayer;
        return {
          'points': p.total,
          'rebounds': p.rebounds,
          'threePointers': p.threePoints,
          'twoPointers': p.twoPoints,
          'freeThrows': p.onePoint,
        };
      case 'Flag Football':
        final p = player as FlagFootballPlayer;
        // Season Catch % (L6.1) — same no-gate/no-data semantics as the
        // career map above.
        final catchPct = catchPercentage(p.receptions, p.receptionMisses);
        return {
          'receptions': p.receptions,
          if (catchPct != null) 'catchPercentage': catchPct,
          'receivingTouchdowns': p.receivingTouchdowns,
          'passTouchdowns': p.passingTouchdowns,
          'interceptions': p.interceptions,
          'flagPulls': p.flagPulls,
          'sacks': p.sacks,
          'passBreakups': p.passBreakups,
        };
      case 'AFC San Jose':
        final p = player as SoccerPlayer;
        return {'goals': p.goals, 'assists': p.assists, 'saves': p.saves};
      default:
        return {};
    }
  }

  Map<String, num> _buildStatMapForSport(
      String sport, Map<String, (String, Color, Player)> seasons) {
    switch (sport) {
      case 'Futsal':
        return _futsalStatMap(seasons);
      case 'Basketball':
        return _basketballStatMap(seasons);
      case 'Flag Football':
        return _flagFootballStatMap(seasons);
      case 'AFC San Jose':
        return _soccerStatMap(seasons);
      default:
        return _futsalStatMap(seasons);
    }
  }

  List<CareerRow> _buildCareerRows() {
    final history = careerHistory(_stints);
    final rows = <CareerRow>[];

    for (final stint in history) {
      if (stint.isTournament) {
        final ta = _findTournamentAppearance(stint.scopeId);
        final stats = ta != null ? _tournamentPlayerStatMap(ta.player) : {};
        final stintTrophies = _awards
            .where((a) => _awardMatchesStint(a, stint))
            .map((a) => (name: a.name, icon: a.icon))
            .toList();
        rows.add(CareerRow(
          teamLogoUrl: ta?.logoUrl ?? '',
          title: '${stint.sport} · ${ta?.tournamentName ?? stint.label}',
          summary: _tournamentSummary(Map<String, num>.from(stats)),
          trophies: stintTrophies,
          onTap: null,
        ));
      } else {
        final sport = stint.sport;
        final season = stint.label;
        final team = stint.team;
        final seasons = _tableEntries[sport];
        // Per-season stats for THIS row (not the sport's career aggregate).
        final seasonEntry = seasons?[season];
        final Map<String, num> stats = seasonEntry != null
            ? _buildStatMapForSingleEntry(sport, seasonEntry.$3)
            : {};
        final stintTrophies = _awards
            .where((a) => _awardMatchesStint(a, stint))
            .map((a) => (name: a.name, icon: a.icon))
            .toList();
        final logoUrl = _teamLogoUrl(sport, season, team);

        String summary;
        switch (sport) {
          case 'Futsal':
            summary = _futsalSummary(stats);
          case 'Basketball':
            summary = _basketballSummary(stats);
          case 'Flag Football':
            summary = _flagFootballSummary(stats);
          case 'AFC San Jose':
            summary = _soccerSummary(stats);
          default:
            summary = '';
        }

        rows.add(CareerRow(
          teamLogoUrl: logoUrl,
          title: '$sport · Season $season',
          summary: summary,
          trophies: stintTrophies,
          onTap: null,
        ));
      }
    }

    return rows;
  }

  _TournamentAppearance? _findTournamentAppearance(String tournamentId) {
    return _tournamentAppearancesCache
        .where((ta) => ta.tournamentId == tournamentId)
        .firstOrNull;
  }

  // Cache set during getProfileData so _buildCareerRows can reference it.
  final List<_TournamentAppearance> _tournamentAppearancesCache = [];

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ── Limited (no-account) state ────────────────────────────────────────
    if (widget._isLimited) {
      return Scaffold(
        appBar: _appBar(context),
        body: Column(
          children: [
            ProfileHero(
              photoUrl: '',
              fullName: widget._limitedName,
              teamColor: null,
            ),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    "This player isn't linked to an account yet.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Full profile ─────────────────────────────────────────────────────
    return Scaffold(
      appBar: _appBar(context),
      body: FutureBuilder<int>(
        future: _loadOnce(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _ProfileSkeleton();
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Could not load profile. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            );
          }

          final fullName =
              '$_firstName $_lastName'.trim().isNotEmpty
                  ? '$_firstName $_lastName'.trim()
                  : 'Player';

          return Column(
            children: [
              // Fixed hero above the tabs
              ProfileHero(
                photoUrl: _profileUrl,
                fullName: fullName,
                teamColor: _teamColor,
              ),
              // Tab bar
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Profile'),
                  Tab(text: 'Stats'),
                  Tab(text: 'Career'),
                ],
              ),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ProfileTab(
                      information: _information,
                      awards: _awards,
                      current: _current,
                      currentTeamNumber: _currentTeamNumber,
                      currentStatsLabel: _currentStatsLabel,
                      currentStats: _headlineStats,
                    ),
                    StatsTab(
                      competitions: _competitions,
                      initialIndex: _selectedStatsIndex,
                      onCompetitionChanged: (i) =>
                          setState(() => _selectedStatsIndex = i),
                    ),
                    CareerTab(rows: _careerRows),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  AppBar _appBar(BuildContext context) {
    return AppBar(
      centerTitle: true,
      title: const Text('Profile'),
      actions: widget._isLimited
          ? null
          : [
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Share',
                onPressed: () => _onShareTap(context),
              ),
            ],
    );
  }

  /// Builds and shares the appropriate profile card for the active tab.
  Future<void> _onShareTap(BuildContext context) async {
    final fullName =
        '$_firstName $_lastName'.trim().isNotEmpty
            ? '$_firstName $_lastName'.trim()
            : 'Player';

    final tab = _tabController.index;

    if (tab == 0) {
      // ── Profile tab → Trophy Cabinet card ──────────────────────────────
      final currentLabel = _current != null
          ? '${_current!.team} · ${_current!.sport}'
          : '';
      final n = _awards.length;
      await shareProfileCard(
        context,
        ShareProfileCabinetCard(
          name: fullName,
          photoUrl: _profileUrl,
          currentLabel: currentLabel,
          awards: _awards,
        ),
        shareText:
            "$fullName's trophy cabinet — $n ${n == 1 ? 'trophy' : 'trophies'}"
            ' on Infinite Sports',
      );
    } else if (tab == 1) {
      // ── Stats tab → Stats card for currently selected competition ───────
      if (_competitions.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('No stats to share yet.')),
        );
        return;
      }
      final idx = _selectedStatsIndex.clamp(0, _competitions.length - 1);
      final comp = _competitions[idx];

      // Build ordered stat rows the same way StatsTab does.
      final group = positionGroup(comp.sport, comp.position);
      final priority = profileStatPriority(comp.sport, group);
      final orderedKeys = <String>[
        for (final k in priority)
          if (comp.stats.containsKey(k)) k,
        for (final k in comp.stats.keys)
          if (!priority.contains(k)) k,
      ];
      final statRows = orderedKeys
          .take(5)
          .map((k) => (
                label: _statLabel[k] ?? k,
                value: formatProfileStatValue(k, comp.stats[k]!),
              ))
          .toList();

      await shareProfileCard(
        context,
        ShareProfileStatsCard(
          name: fullName,
          photoUrl: _profileUrl,
          competitionLabel: comp.label,
          stats: statRows,
        ),
        shareText:
            "$fullName · ${comp.label} — Infinite Sports",
      );
    } else {
      // ── Career tab → Career card ─────────────────────────────────────────
      // Compute career headline totals.
      final distinctSports = <String>{
        for (final c in _competitions) c.sport,
      };
      final sportsPlayed = distinctSports.length;

      // Total goals across all league/tournament stats.
      int totalGoals = 0;
      for (final c in _competitions) {
        totalGoals += (c.stats['goals'] ?? 0).toInt();
      }

      final trophies = _awards.length;

      final headlineTotals = <({String label, String value})>[
        (label: 'Sports Played', value: '$sportsPlayed'),
        if (totalGoals > 0) (label: 'Goals', value: '$totalGoals'),
        (label: 'Trophies', value: '$trophies'),
        (label: 'Seasons', value: '${_competitions.length}'),
      ];

      await shareProfileCard(
        context,
        ShareProfileCareerCard(
          name: fullName,
          photoUrl: _profileUrl,
          headlineTotals: headlineTotals,
        ),
        shareText: "$fullName's career on Infinite Sports",
      );
    }
  }

  // Ensure getProfileData runs only once even if FutureBuilder rebuilds.
  Future<int>? _loadFuture;
  Future<int> _loadOnce() {
    _loadFuture ??= _doLoad();
    return _loadFuture!;
  }

  Future<int> _doLoad() async {
    _tournamentAppearancesCache.clear();
    return _getProfileDataWithCache();
  }

  Future<int> _getProfileDataWithCache() async {
    // ── 1. Load Users/{uid} ──────────────────────────────────────────────
    final ref = FirebaseDatabase.instance.ref();
    Map rawUser = {};
    try {
      final userSnap = await ref.child('Users/${widget.uid}').get();
      rawUser = userSnap.value as Map? ?? {};
    } catch (_) {}

    _firstName = (rawUser['First Name'] ?? '').toString();
    _lastName = (rawUser['Last Name'] ?? '').toString();
    _profileUrl = (rawUser['ProfileUrl'] ?? '').toString();
    _information = (rawUser['Information'] is Map)
        ? rawUser['Information'] as Map
        : {};

    // ── 2. Load league appearances ───────────────────────────────────────
    try {
      if (rawUser['Played'] is Map) {
        await Future.forEach(
            (rawUser['Played'] as Map).entries, (entry) async {
          final sport = entry.key.toString();
          final seasons = entry.value;
          if (seasons is! Map) return;
          await Future.forEach(seasons.entries, (entry2) async {
            final seasonRaw = entry2.key.toString();
            final team = entry2.value.toString();
            final parts = seasonRaw.split(' ');
            final seasonNum = parts.last;

            if (sport == 'Futsal') {
              _sportPositions[sport] =
                  (_information['${sport}Position'] ?? '').toString();
              await getAllFutsalLineUps(seasonNum);
              _tableEntries['Futsal'] ??= {};
              _tableEntries['Futsal']![seasonNum] =
                  await _extractPlayerStats(sport, seasonNum, team);
            } else if (sport == 'Basketball') {
              _sportPositions[sport] =
                  (_information['${sport}Position'] ?? '').toString();
              await getAllBasketballLineUps(seasonNum);
              _tableEntries['Basketball'] ??= {};
              _tableEntries['Basketball']![seasonNum] =
                  await _extractPlayerStats(sport, seasonNum, team);
            } else if (sport == 'Flag Football') {
              _sportPositions[sport] =
                  (_information['${sport}Position'] ?? '').toString();
              await getAllFlagFootballLineUps(seasonNum);
              _tableEntries['Flag Football'] ??= {};
              _tableEntries['Flag Football']![seasonNum] =
                  await _extractPlayerStats(sport, seasonNum, team);
            }
          });
        });
      }
    } catch (_) {}

    // ── 3. AFC San Jose ──────────────────────────────────────────────────
    try {
      await _extractAFCStats();
    } catch (_) {}

    // ── 4. Awards ────────────────────────────────────────────────────────
    try {
      final awardsSnap =
          await ref.child('Users/${widget.uid}/Awards').get();
      if (awardsSnap.value is Map) {
        _awards = (awardsSnap.value as Map)
            .entries
            .where((e) => e.value is Map)
            .map((e) => Award.fromMap(
                  e.key.toString(),
                  Map<dynamic, dynamic>.from(e.value as Map),
                ))
            .toList();
      }
    } catch (_) {
      _awards = [];
    }

    // ── 5. Tournament appearances ────────────────────────────────────────
    try {
      final tournaments = await TournamentService.getAllTournaments();
      // Run all tournament lookups concurrently for speed.
      await Future.wait(tournaments.map((tournament) async {
        try {
          final teams = await TournamentService.getTeams(tournament.id);
          final rosters =
              await TournamentService.getRosters(tournament.id, teams);
          for (final entry in rosters.entries) {
            for (final player in entry.value) {
              if (player.uid == widget.uid) {
                _tournamentAppearancesCache.add(_TournamentAppearance(
                  tournamentId: tournament.id,
                  tournamentName: tournament.name,
                  sport: tournament.sport,
                  edition: tournament.edition,
                  finished: tournament.finished,
                  logoUrl: tournament.logoUrl ?? '',
                  teamName: player.teamName,
                  position: player.position ?? '',
                  number: player.number ?? '',
                  player: player,
                ));
                break;
              }
            }
          }
        } catch (_) {}
      }));
    } catch (_) {}

    // ── 6. Build stints ──────────────────────────────────────────────────
    final stints = <ParticipationStint>[];

    // Memoize getCurrentSeason results — avoids one await per (sport × season).
    final Map<String, String> cachedCurrentSeason = {};

    for (final sportEntry in _tableEntries.entries) {
      final sport = sportEntry.key;

      // Fetch current season ONCE per sport.
      if (!cachedCurrentSeason.containsKey(sport)) {
        try {
          cachedCurrentSeason[sport] = sport == 'AFC San Jose'
              ? await getAFCCurrentSeason()
              : await getCurrentSeason(sport);
        } catch (_) {
          cachedCurrentSeason[sport] = '';
        }
      }
      final currentSeasonForSport = cachedCurrentSeason[sport] ?? '';

      for (final seasonEntry in sportEntry.value.entries) {
        final seasonNum = seasonEntry.key;
        final info = seasonEntry.value;
        if (info.$1.isEmpty) continue;

        final sortKey = int.tryParse(seasonNum) ?? 0;
        bool isActive = false;
        // Only run the finished-check for the one matching season, not all.
        if (currentSeasonForSport == seasonNum) {
          try {
            isActive = sport == 'AFC San Jose'
                ? !(await isAFCSeasonFinished(seasonNum))
                : !(await isSeasonFinished(sport, seasonNum));
          } catch (_) {}
        }

        final position = _sportPositions[sport] ??
            (sport == 'AFC San Jose'
                ? (_information['SoccerPosition'] ?? '').toString()
                : (_information['${sport}Position'] ?? '').toString());

        stints.add(ParticipationStint(
          sport: sport,
          label: seasonNum,
          sortKey: sortKey,
          team: info.$1,
          position: position,
          isActive: isActive,
        ));
      }
    }

    for (final ta in _tournamentAppearancesCache) {
      final sortKey =
          int.tryParse(ta.edition.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      stints.add(ParticipationStint(
        sport: ta.sport,
        label: ta.edition,
        sortKey: sortKey,
        team: ta.teamName,
        position: ta.position,
        isActive: !ta.finished,
        isTournament: true,
        scopeId: ta.tournamentId,
      ));
    }

    _stints = stints;
    _current = currentParticipation(_stints);

    // ── 7. Team color ────────────────────────────────────────────────────
    // Decode the logo image ONCE — only for the current stint.
    // All _extractHelper calls above stored a placeholder color; we now
    // replace it here with a single real ColorScheme decode.
    if (_current != null && !_current!.isTournament) {
      final entry = _tableEntries[_current!.sport]?[_current!.label];
      if (entry != null && entry.$1.isNotEmpty) {
        final logoUrl = entry.$3 is FutsalPlayer
            ? (entry.$3 as FutsalPlayer).teamPath
            : entry.$3 is BasketballPlayer
                ? (entry.$3 as BasketballPlayer).teamPath
                : entry.$3 is FlagFootballPlayer
                    ? (entry.$3 as FlagFootballPlayer).teamPath
                    : entry.$3 is SoccerPlayer
                        ? (entry.$3 as SoccerPlayer).teamPath
                        : '';
        if (logoUrl.isNotEmpty) {
          try {
            final cs = await ColorScheme.fromImageProvider(
                provider: NetworkImage(logoUrl));
            _teamColor = cs.primary;
          } catch (_) {
            _teamColor = const Color(0xFFD00000);
          }
        } else {
          _teamColor = const Color(0xFFD00000);
        }
      }
    }

    // ── 8. Jersey number for current team ────────────────────────────────
    if (_current != null) {
      if (_current!.isTournament) {
        final ta = _findTournamentAppearance(_current!.scopeId);
        if (ta != null && ta.number.isNotEmpty) {
          _currentTeamNumber = ta.number;
        }
      } else {
        // League players all have a `number` field on the Player model.
        final entry =
            _tableEntries[_current!.sport]?[_current!.label];
        if (entry != null && entry.$1.isNotEmpty) {
          final player = entry.$3;
          // All league player models implement Player which has `number`.
          if (player is FutsalPlayer && player.number.isNotEmpty) {
            _currentTeamNumber = player.number;
          } else if (player is BasketballPlayer && player.number.isNotEmpty) {
            _currentTeamNumber = player.number;
          } else if (player is FlagFootballPlayer &&
              player.number.isNotEmpty) {
            _currentTeamNumber = player.number;
          } else if (player is SoccerPlayer && player.number.isNotEmpty) {
            _currentTeamNumber = player.number;
          }
        }
      }
    }

    // ── 9. CompetitionStats (per-season + per-tournament, latest first) ────
    final competitions = <CompetitionStats>[];

    // League seasons — one entry per season per sport.
    for (final sportEntry in _tableEntries.entries) {
      final sport = sportEntry.key;
      final seasonMap = sportEntry.value;
      final position = sport == 'AFC San Jose'
          ? (_information['SoccerPosition'] ?? '').toString()
          : (_sportPositions[sport] ?? '');

      for (final seasonEntry in seasonMap.entries) {
        final seasonNum = seasonEntry.key;
        final player = seasonEntry.value.$3;
        final sortKey = int.tryParse(seasonNum) ?? 0;

        final String label;
        if (sport == 'AFC San Jose') {
          label = 'AFC San Jose · Season $seasonNum';
        } else {
          label = '$sport · Season $seasonNum';
        }

        competitions.add(CompetitionStats(
          label: label,
          sport: sport,
          position: position,
          stats: _buildStatMapForSingleEntry(sport, player),
          sortKey: sortKey,
        ));
      }
    }

    // Tournament appearances — one entry per appearance.
    for (final ta in _tournamentAppearancesCache) {
      final sortKey =
          int.tryParse(ta.edition.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      competitions.add(CompetitionStats(
        label: ta.tournamentName,
        sport: ta.sport,
        position: ta.position,
        stats: _tournamentPlayerStatMap(ta.player),
        sortKey: sortKey,
      ));
    }

    // Sort latest first.
    competitions.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    _competitions = competitions;

    // ── 10. Current-season stats label + headline stats ───────────────────
    if (_current != null) {
      if (_current!.isTournament) {
        final ta = _findTournamentAppearance(_current!.scopeId);
        _currentStatsLabel = ta?.tournamentName ?? _current!.label;
      } else {
        final sport = _current!.sport;
        final seasonNum = _current!.label;
        if (sport == 'AFC San Jose') {
          _currentStatsLabel = 'AFC San Jose Season $seasonNum';
        } else {
          _currentStatsLabel = '$sport League Season $seasonNum';
        }
      }
    }
    _headlineStats = _buildHeadlineStats();

    // ── 11. CareerRows ───────────────────────────────────────────────────
    _careerRows = _buildCareerRows();

    return 1;
  }
}

// ─── Skeleton placeholder shown while the profile loads ──────────────────────

class _ProfileSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Hero block
        Container(
          width: double.infinity,
          height: 180,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 64, height: 64, radius: 32),
              SizedBox(height: 12),
              SkeletonBox(width: 160, height: 18),
              SizedBox(height: 8),
              SkeletonBox(width: 100, height: 12),
            ],
          ),
        ),
        // Tab bar placeholder
        const SizedBox(height: 48),
        // Card blocks
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: const [
              SkeletonBox(width: double.infinity, height: 80),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 80),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 80),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Internal data holder for tournament appearances ─────────────────────────

class _TournamentAppearance {
  final String tournamentId;
  final String tournamentName;
  final String sport;
  final String edition;
  final bool finished;
  final String logoUrl;
  final String teamName;
  final String position;
  final String number;
  final TournamentPlayer player;

  _TournamentAppearance({
    required this.tournamentId,
    required this.tournamentName,
    required this.sport,
    required this.edition,
    required this.finished,
    required this.logoUrl,
    required this.teamName,
    required this.position,
    required this.number,
    required this.player,
  });
}

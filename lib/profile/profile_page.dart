import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';
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

// ─── Human-readable labels for stat keys (shared across hero + StatsTab) ──────
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
  'interceptions': 'INTs',
  'flagPulls': 'Flag Pulls',
  'sacks': 'Sacks',
  'passBreakups': 'PBUs',
};

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
  bool _isKeeper = false;

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
    (String, Color, Player) data;
    if (sport == 'Basketball') {
      data = ('', Colors.black, BasketballPlayer());
      final entries = basketballLineups[season]?[team]?.entries;
      if (entries != null) {
        await Future.forEach(entries, (entry) async {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final color = await ColorScheme.fromImageProvider(
                provider: NetworkImage(teamLogos[sport][season][team]));
            info.teamPath = teamLogos[sport][season][team];
            if (_firstName.isEmpty && info.name.contains(' ')) {
              _firstName = info.name.split(' ')[0];
              _lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, color.primary, info);
          }
        });
      }
    } else if (sport == 'Futsal') {
      data = ('', Colors.black, FutsalPlayer());
      final entries = futsalLineups[season]?[team]?.entries;
      if (entries != null) {
        await Future.forEach(entries, (entry) async {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final color = await ColorScheme.fromImageProvider(
                provider: NetworkImage(teamLogos[sport][season][team]));
            info.teamPath = teamLogos[sport][season][team];
            if (_firstName.isEmpty && info.name.contains(' ')) {
              _firstName = info.name.split(' ')[0];
              _lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, color.primary, info);
          }
        });
      }
    } else {
      // Flag Football
      data = ('', Colors.black, FlagFootballPlayer());
      final entries = flagFootballLineups[season]?[team]?.entries;
      if (entries != null) {
        await Future.forEach(entries, (entry) async {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final color = await ColorScheme.fromImageProvider(
                provider: NetworkImage(teamLogos[sport][season][team]));
            info.teamPath = teamLogos[sport][season][team];
            if (_firstName.isEmpty && info.name.contains(' ')) {
              _firstName = info.name.split(' ')[0];
              _lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, color.primary, info);
          }
        });
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
    int receptions = 0, receivingTDs = 0, passTDs = 0, interceptions = 0,
        flagPulls = 0, sacks = 0, passBreakups = 0;
    for (final e in seasons.values) {
      final p = e.$3 as FlagFootballPlayer;
      receptions += p.receptions;
      receivingTDs += p.receivingTouchdowns;
      passTDs += p.passingTouchdowns;
      interceptions += p.interceptions;
      flagPulls += p.flagPulls;
      sacks += p.sacks;
      passBreakups += p.passBreakups;
    }
    return {
      'receptions': receptions,
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
      // League: sport key in scopeId OR sport match, plus season match
      final sportKey = stint.sport.replaceAll(' ', '').toLowerCase();
      final scopeMatch = award.scopeId.toLowerCase().contains(sportKey) ||
          award.sport.toLowerCase().contains(stint.sport.toLowerCase()) ||
          award.sport == stint.sport;
      final seasonMatch = award.season == stint.label ||
          award.season.contains(stint.label);
      return award.scopeType == 'league' && scopeMatch && seasonMatch;
    }
  }

  // ─── Team logo URL helper ────────────────────────────────────────────────

  String _teamLogoUrl(String sport, String season, String team) {
    try {
      if (sport == 'AFC San Jose') {
        // AFC San Jose teamLogos value is a single String (the league logo)
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
      // Find the tournament appearance
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
      statMap = _buildStatMapForSport(sport, seasons);
    }

    final group = positionGroup(sport, position);
    final priority = profileStatPriority(sport, group);

    final result = <({String label, String value})>[];
    for (final key in priority) {
      if (statMap.containsKey(key)) {
        result.add((
          label: _statLabel[key] ?? key,
          value: statMap[key].toString(),
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
        final hasTrophy =
            _awards.any((a) => _awardMatchesStint(a, stint));
        rows.add(CareerRow(
          teamLogoUrl: ta?.logoUrl ?? '',
          title: '${stint.sport} · ${ta?.tournamentName ?? stint.label}',
          summary: _tournamentSummary(Map<String, num>.from(stats)),
          hasTrophy: hasTrophy,
          onTap: null, // Task 8 wires navigation
        ));
      } else {
        final sport = stint.sport;
        final season = stint.label;
        final team = stint.team;
        final seasons = _tableEntries[sport];
        final Map<String, num> stats = seasons != null
            ? _buildStatMapForSport(sport, seasons)
            : {};
        final hasTrophy =
            _awards.any((a) => _awardMatchesStint(a, stint));
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
          hasTrophy: hasTrophy,
          onTap: null,
        ));
      }
    }

    return rows;
  }

  _TournamentAppearance? _findTournamentAppearance(String tournamentId) {
    // We need to keep a reference to the tournament appearances list built
    // during getProfileData. We store it as a field for this helper.
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
              current: null,
              teamColor: null,
              headlineStats: const [
                (label: '—', value: '—'),
                (label: '—', value: '—'),
                (label: '—', value: '—'),
              ],
              trophyCount: 0,
              isKeeper: false,
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
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            );
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
                current: _current,
                teamColor: _teamColor,
                headlineStats: _headlineStats.length >= 3
                    ? _headlineStats.take(3).toList()
                    : [
                        ..._headlineStats,
                        for (int i = _headlineStats.length; i < 3; i++)
                          (label: '—', value: '—'),
                      ],
                trophyCount: _awards.length,
                isKeeper: _isKeeper,
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
                    ),
                    StatsTab(competitions: _competitions),
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
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
    );
  }

  // Ensure getProfileData runs only once even if FutureBuilder rebuilds.
  Future<int>? _loadFuture;
  Future<int> _loadOnce() {
    _loadFuture ??= _doLoad();
    return _loadFuture!;
  }

  Future<int> _doLoad() async {
    // Rebuild the tournament appearances cache reference before loading.
    _tournamentAppearancesCache.clear();

    // We need to store tournament appearances in the cache as we build them.
    // Refactor getProfileData to populate the cache directly.
    return _getProfileDataWithCache();
  }

  Future<int> _getProfileDataWithCache() async {
    // ── 1. Load Users/{uid} ──────────────────────────────────────────────
    final ref = FirebaseDatabase.instance.ref();
    final userSnap = await ref.child('Users/${widget.uid}').get();
    final rawUser = userSnap.value as Map? ?? {};

    _firstName = (rawUser['First Name'] ?? '').toString();
    _lastName = (rawUser['Last Name'] ?? '').toString();
    _profileUrl = (rawUser['ProfileUrl'] ?? '').toString();
    _information = (rawUser['Information'] is Map)
        ? rawUser['Information'] as Map
        : {};

    // ── 2. Load league appearances ───────────────────────────────────────
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

    // ── 3. AFC San Jose ──────────────────────────────────────────────────
    await _extractAFCStats();

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
      await Future.forEach(tournaments, (tournament) async {
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
                  player: player,
                ));
                break;
              }
            }
          }
        } catch (_) {}
      });
    } catch (_) {}

    // ── 6. Build stints ──────────────────────────────────────────────────
    final stints = <ParticipationStint>[];

    for (final sportEntry in _tableEntries.entries) {
      final sport = sportEntry.key;
      for (final seasonEntry in sportEntry.value.entries) {
        final seasonNum = seasonEntry.key;
        final info = seasonEntry.value;
        if (info.$1.isEmpty) continue;

        final sortKey = int.tryParse(seasonNum) ?? 0;
        bool isActive = false;
        try {
          final currentSeason = await getCurrentSeason(
              sport == 'AFC San Jose' ? 'AFC San Jose' : sport);
          if (currentSeason == seasonNum) {
            isActive = sport == 'AFC San Jose'
                ? !(await isAFCSeasonFinished(seasonNum))
                : !(await isSeasonFinished(sport, seasonNum));
          }
        } catch (_) {}

        final position = _sportPositions[sport] ??
            (_information['${sport}Position'] ?? '').toString();

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
    if (_current != null && !_current!.isTournament) {
      final entry = _tableEntries[_current!.sport]?[_current!.label];
      if (entry != null && entry.$1.isNotEmpty) {
        _teamColor = entry.$2;
      }
    }

    // ── 8. CompetitionStats ──────────────────────────────────────────────
    final competitions = <CompetitionStats>[];

    if (_tableEntries.containsKey('Futsal')) {
      competitions.add(CompetitionStats(
        label: 'Futsal (Career)',
        sport: 'Futsal',
        position: _sportPositions['Futsal'] ?? '',
        stats: _futsalStatMap(_tableEntries['Futsal']!),
      ));
    }
    if (_tableEntries.containsKey('Basketball')) {
      competitions.add(CompetitionStats(
        label: 'Basketball (Career)',
        sport: 'Basketball',
        position: _sportPositions['Basketball'] ?? '',
        stats: _basketballStatMap(_tableEntries['Basketball']!),
      ));
    }
    if (_tableEntries.containsKey('Flag Football')) {
      competitions.add(CompetitionStats(
        label: 'Flag Football (Career)',
        sport: 'Flag Football',
        position: _sportPositions['Flag Football'] ?? '',
        stats: _flagFootballStatMap(_tableEntries['Flag Football']!),
      ));
    }
    if (_tableEntries.containsKey('AFC San Jose')) {
      competitions.add(CompetitionStats(
        label: 'AFC San Jose (Career)',
        sport: 'AFC San Jose',
        position: (_information['SoccerPosition'] ?? '').toString(),
        stats: _soccerStatMap(_tableEntries['AFC San Jose']!),
      ));
    }
    for (final ta in _tournamentAppearancesCache) {
      competitions.add(CompetitionStats(
        label: ta.tournamentName,
        sport: ta.sport,
        position: ta.position,
        stats: _tournamentPlayerStatMap(ta.player),
      ));
    }
    _competitions = competitions;

    // ── 9. Hero headline stats ────────────────────────────────────────────
    _headlineStats = _buildHeadlineStats();

    // ── 10. isKeeper ─────────────────────────────────────────────────────
    final currentStatMap =
        _competitions.isNotEmpty ? _competitions.first.stats : <String, num>{};
    _isKeeper = detectKeeper(
      Map<String, num>.from(currentStatMap),
      _current?.position ?? '',
    );

    // ── 11. CareerRows ───────────────────────────────────────────────────
    _careerRows = _buildCareerRows();

    return 1;
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
    required this.player,
  });
}

// Pure adapters: league RTDB shapes -> the tournament view models that the
// reused tournament widgets (FixturesTab, KnockoutTab, MatchFactsTab,
// ShareMatchCard, ...) render. League Experience P2.
// NO Flutter/Firebase imports — unit-tested in test/league_adapters_test.dart.
// (dart:ui Color only, same as the TournamentTeam model itself.)
//
// Conventions:
// - League teams are keyed by NAME everywhere, so TournamentTeam.id and
//   TournamentPlayer.teamId carry the team name.
// - Game identity is the RTDB pair the game node lives under:
//   '{MMDDYYYY}#{index}' (leagueGameId / parseLeagueGameId).
// - Team metadata (P2.1 Task A3) read contract, maintained by the Manager
//   app: `{sport}/{season}/Teams/{team}/Captain|Color|Coach` — ALL optional
//   strings. Color/Coach ride on TournamentTeam (homeColor/coachName);
//   Captain has no TournamentTeam field, so it travels via the
//   leagueCaptainsFromTeamsNode side-channel.

import 'dart:ui' show Color;

import 'package:infinite_sports_flutter/misc/match_clock.dart';
import 'package:infinite_sports_flutter/misc/match_location.dart';
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';
import 'package:infinite_sports_flutter/misc/schedule_display.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart'
    show catchPercentage;
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

/// The sports served by the NEW league experience (LeagueDetailPage /
/// LeagueMatchDetailPage). AFC San Jose and anything unknown stay on the
/// legacy pages.
const Set<String> leagueEngineSports = {
  'Futsal',
  'Basketball',
  'Flag Football',
};

bool isLeagueEngineSport(String sport) =>
    leagueEngineSports.contains(sport.trim());

/// Stable id for a league game: the (date, index) pair its RTDB path needs.
String leagueGameId(String dateKey, int index) => '$dateKey#$index';

/// Inverse of [leagueGameId]. Returns null when [id] is not a league game id.
({String dateKey, int index})? parseLeagueGameId(String id) {
  final at = id.lastIndexOf('#');
  if (at <= 0) return null;
  final index = int.tryParse(id.substring(at + 1));
  if (index == null) return null;
  return (dateKey: id.substring(0, at), index: index);
}

/// Path-safe storage key for one league game's predictions ('#' is ILLEGAL
/// in RTDB keys, so the in-memory '{date}#{index}' id cannot be a path):
/// answers live at '{sport}/{season}/Predictions/{dateKey}_{index}'.
/// MUST stay in parity with functions/src/league_watch.ts leagueMatchKey.
String leaguePredictionMatchKey(String dateKey, int index) =>
    '${dateKey}_$index';

/// One league game node -> [TournamentMatch].
///
/// - Scores tolerate the legacy string/int + casing mix
///   (`team1score`/`team1Score`).
/// - `time` is ALWAYS non-null: stored 'HH:mm' renders 12h via
///   [gameTimeText]; absent falls back to the exact legacy text
///   `'{startHour + index}:00PM'` so old seasons look unchanged.
/// - `stage`/`label`: regular season -> 'League'; staged games keep the raw
///   stage (so TournamentStage bracket grouping works) and label via
///   [stageDisplayName] ('Semifinal', 'Championship', 'Friendly', ...).
/// - `Clock` (P1) and `Location` (spec §6, render side) parse when present.
TournamentMatch leagueMatchFromGameMap({
  required String dateKey,
  required int index,
  required Map<dynamic, dynamic> raw,
  int startHour = 0,
}) {
  // Minute-keyed activity buckets arrive as Maps, or as Lists when Firebase
  // collapses small integer-ish keys; normalize to the Map<String, dynamic>
  // shape MatchFactsTab._parseActivity handles (it deals with List and
  // index-keyed-Map BUCKETS itself).
  Map<String, dynamic>? activity(dynamic v) {
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    if (v is List) {
      final out = <String, dynamic>{};
      for (var i = 0; i < v.length; i++) {
        if (v[i] != null) out['$i'] = v[i];
      }
      return out.isEmpty ? null : out;
    }
    return null;
  }

  String? str(dynamic v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  final stage = (raw['Stage'] ?? '').toString();
  final stageLabel = stageDisplayName(stage);
  final storedTime = (raw['Time'] ?? '').toString();

  return TournamentMatch(
    id: leagueGameId(dateKey, index),
    stage: stage.isEmpty ? 'League' : stage,
    label: stageLabel.isEmpty ? 'League' : stageLabel,
    date: dateKey,
    time: gameTimeText(storedTime, startHour + index),
    team1Id: (raw['team1'] ?? '').toString(),
    team2Id: (raw['team2'] ?? '').toString(),
    team1Score: parseInt(raw['team1score'] ?? raw['team1Score']),
    team2Score: parseInt(raw['team2score'] ?? raw['team2Score']),
    status: parseInt(raw['status']),
    clock: MatchClock.fromMap(raw['Clock']),
    team1Activity: activity(raw['team1activity']),
    team2Activity: activity(raw['team2activity']),
    link: str(raw['link']),
    locationInfo:
        MatchLocationInfo.fromMatch(location: raw['Location'], legacyString: null),
    team1Keeper: str(raw['team1keeper']),
    team2Keeper: str(raw['team2keeper']),
    bracketPosition: index,
  );
}

/// The whole `/{sport}/{season}/Date` node -> flat match list.
/// Dates hold Lists (normal) or index-keyed Maps (Firebase hole collapsing);
/// either way the ORIGINAL index is preserved so ids stay addressable.
List<TournamentMatch> leagueMatchesFromDateNode(dynamic dateNode,
    {int startHour = 0}) {
  final out = <TournamentMatch>[];
  if (dateNode is! Map) return out;
  dateNode.forEach((dateKey, games) {
    void add(int index, dynamic raw) {
      if (raw is Map) {
        out.add(leagueMatchFromGameMap(
          dateKey: dateKey.toString(),
          index: index,
          raw: raw,
          startHour: startHour,
        ));
      }
    }

    if (games is List) {
      for (var i = 0; i < games.length; i++) {
        add(i, games[i]);
      }
    } else if (games is Map) {
      games.forEach((k, v) {
        final i = int.tryParse(k.toString());
        if (i != null) add(i, v);
      });
    }
  });
  return out;
}

/// League jersey `Color` string -> [Color]. Accepts the formats tournament
/// teams already use PLUS plain hex: optional `#` or `0x` prefix, 6 hex
/// digits (RGB, alpha forced opaque) or 8 (ARGB). Anything else -> null,
/// so callers fail gracefully by hiding the jersey row.
Color? parseLeagueTeamColor(dynamic value) {
  if (value == null) return null;
  var clean = value.toString().trim();
  if (clean.startsWith('#')) clean = clean.substring(1);
  if (clean.toLowerCase().startsWith('0x')) clean = clean.substring(2);
  if (clean.length == 6) clean = 'FF$clean';
  if (clean.length != 8) return null;
  final intValue = int.tryParse(clean, radix: 16);
  if (intValue == null) return null;
  return Color(intValue);
}

/// Logo-only team (name + crest, zeroed standings) for teams that are not
/// (yet) in the Teams node — e.g. match pages before standings exist.
/// [color]/[coach] let callers that already hold the season metadata keep
/// carrying it on the stub (homeColor/coachName, the tournament fields).
TournamentTeam leagueTeamStub(String name, String? logoUrl,
        {Color? color, String? coach}) =>
    TournamentTeam(
      id: name,
      name: name,
      logoUrl: logoUrl,
      qualification: '',
      gp: 0,
      wins: 0,
      draws: 0,
      losses: 0,
      gs: 0,
      gc: 0,
      gd: 0,
      points: 0,
      homeColor: color,
      coachName: (coach == null || coach.trim().isEmpty) ? null : coach,
    );

/// Per-sport standings sort — EXACT parity with the Manager's playoff
/// seeding (schedule_playoffs.dart seedOrder), so the table order always
/// agrees with bracket seeds:
///   Futsal:        Points desc, GD desc, GS desc
///   Basketball:    Points desc, PD desc, PPG desc
///   Flag Football: Wins desc, PF-PA desc, PF desc
/// Name tie-break last for stability.
void sortLeagueStandings(String sport, List<TournamentTeam> rows) {
  List<num> keysOf(TournamentTeam t) {
    switch (sport) {
      case 'Basketball':
        return [
          t.points,
          t.leagueStats['PD'] ?? 0,
          t.leagueStats['PPG'] ?? 0,
        ];
      case 'Flag Football':
        return [
          t.wins,
          (t.leagueStats['PF'] ?? 0) - (t.leagueStats['PA'] ?? 0),
          t.leagueStats['PF'] ?? 0,
        ];
      default: // Futsal
        return [t.points, t.gd, t.gs];
    }
  }

  rows.sort((a, b) {
    final ka = keysOf(a), kb = keysOf(b);
    for (var i = 0; i < 3; i++) {
      final v = kb[i].compareTo(ka[i]);
      if (v != 0) return v;
    }
    return a.name.compareTo(b.name);
  });
}

/// The `/{sport}/{season}/Teams` node -> SORTED standings rows.
/// The Manager maintains this node and already skips staged (playoff /
/// friendly) games at finalize time — nothing to exclude here.
/// Futsal reads the classic table keys; basketball and flag football
/// (P4) read their finalize-flow keys, with the per-sport numbers on
/// [TournamentTeam.leagueStats].
List<TournamentTeam> leagueStandingsFromTeamsNode(
    String sport, dynamic teamsNode, Map<String, String> logoUrls) {
  final out = <TournamentTeam>[];
  if (teamsNode is! Map) return out;
  teamsNode.forEach((name, v) {
    if (v is! Map) return;
    final wins = parseInt(v['Wins']);
    final losses = parseInt(v['Losses']);
    final draws = parseInt(v['Draws']);
    final coach = v['Coach']?.toString();

    num numOf(String key) {
      final raw = v[key];
      if (raw is num) return raw;
      return num.tryParse(raw?.toString() ?? '') ?? 0;
    }

    final leagueStats = <String, num>{
      if (sport == 'Basketball') ...{
        'PPG': numOf('PPG'),
        'PCPG': numOf('PCPG'),
        'PD': numOf('PD'),
      },
      if (sport == 'Flag Football') ...{
        'PF': parseInt(v['PF']),
        'PA': parseInt(v['PA']),
        'PD': parseInt(v['PF']) - parseInt(v['PA']),
      },
    };

    out.add(TournamentTeam(
      id: name.toString(),
      name: name.toString(),
      logoUrl: logoUrls[name.toString()],
      qualification: '',
      gp: parseInt(v['GP'], defaultValue: wins + draws + losses),
      wins: wins,
      draws: draws,
      losses: losses,
      gs: parseInt(v['GS']),
      gc: parseInt(v['GC']),
      gd: parseInt(v['GD']),
      points: parseInt(v['Points']),
      // Optional Manager-maintained metadata (P2.1 Task A3 read contract).
      homeColor: parseLeagueTeamColor(v['Color']),
      coachName: (coach == null || coach.trim().isEmpty) ? null : coach,
      leagueStats: leagueStats,
    ));
  });
  sortLeagueStandings(sport, out);
  return out;
}

/// Captain side-channel for the `{sport}/{season}/Teams/{team}/Captain`
/// key (TournamentTeam has no captain field): team name -> captain player
/// name. Teams without a (non-empty) Captain are simply absent.
Map<String, String> leagueCaptainsFromTeamsNode(dynamic teamsNode) {
  final out = <String, String>{};
  if (teamsNode is! Map) return out;
  teamsNode.forEach((name, v) {
    if (v is! Map) return;
    final captain = v['Captain']?.toString().trim();
    if (captain != null && captain.isNotEmpty) {
      out[name.toString()] = captain;
    }
  });
  return out;
}

/// Standings rows + the season logo map -> the `Map<teamId, team>` the
/// tournament widgets take. Teams with a logo but no standings row (fresh
/// seasons) get stubs so crests still render everywhere.
Map<String, TournamentTeam> leagueTeamsById(
    List<TournamentTeam> standings, Map<String, String> logoUrls) {
  final out = <String, TournamentTeam>{
    for (final t in standings) t.id: t,
  };
  logoUrls.forEach((name, url) {
    final existing = out[name];
    if (existing == null) {
      out[name] = leagueTeamStub(name, url);
    } else if (existing.logoUrl == null) {
      // Backfill the crest onto an existing standings row built without a
      // logo map (e.g. a caller passed standings + logos separately).
      out[name] = TournamentTeam(
        id: existing.id,
        name: existing.name,
        logoUrl: url,
        seed: existing.seed,
        qualification: existing.qualification,
        group: existing.group,
        gp: existing.gp,
        wins: existing.wins,
        draws: existing.draws,
        losses: existing.losses,
        gs: existing.gs,
        gc: existing.gc,
        gd: existing.gd,
        points: existing.points,
        homeColor: existing.homeColor,
        awayColor: existing.awayColor,
        overrideColor: existing.overrideColor,
        coachName: existing.coachName,
        coachPhotoUrl: existing.coachPhotoUrl,
        cityState: existing.cityState,
        established: existing.established,
        leagueStats: existing.leagueStats,
      );
    }
  });
  return out;
}

/// One Line Ups player node -> [TournamentPlayer], per sport (P4).
/// Futsal: the classic mapping (Goals/Assists/Saves/DPL/CleanSheets,
/// Yellow -> yellowCards, Red -> redCards). Basketball/flag football:
/// the Manager's short stat keys land on [TournamentPlayer.extraStats]
/// under the fan statByName vocabulary; basketball ALSO fills the core
/// assists field (statByName('assists') is an existing switch case).
/// Legacy UID '0' (and empty) means UNLINKED -> uid null.
TournamentPlayer leaguePlayerFromLineup({
  required String sport,
  required String name,
  required String teamName,
  required Map<dynamic, dynamic> raw,
}) {
  String? uid = raw['UID']?.toString();
  if (uid == null || uid.trim().isEmpty || uid.trim() == '0') uid = null;
  String? number = (raw['number'] ?? raw['Number'])?.toString();
  if (number != null && number.isEmpty) number = null;

  int i(String key) => parseInt(raw[key]);

  Map<String, int> extraStats = const {};
  var assists = 0;
  var goals = 0, saves = 0, dpl = 0, cleanSheets = 0;
  var yellowCards = 0, redCards = 0;

  switch (sport) {
    case 'Basketball':
      assists = i('Assists');
      final storedTotal = raw['Total'];
      final points = storedTotal is num
          ? storedTotal.toInt()
          : i('OnePoint') + 2 * i('TwoPoints') + 3 * i('ThreePoints');
      extraStats = {
        'points': points,
        'freeThrows': i('OnePoint'),
        'twoPointers': i('TwoPoints'),
        'threePointers': i('ThreePoints'),
        'misses': i('Misses'),
        'rebounds': i('Rebounds'),
        'steals': i('Steals'),
        'blocks': i('Blocks'),
        'fouls': i('Fouls'),
        'turnovers': i('Turnovers'),
      };
    case 'Flag Football':
      extraStats = {
        // The L6 "Most TDs" definition: TDs a player SCORED (not threw).
        'touchdowns': i('RECTD') + i('RushTD') + i('INTTD'),
        'receivingTouchdowns': i('RECTD'),
        'rushingTouchdowns': i('RushTD'),
        'interceptionTouchdowns': i('INTTD'),
        'passTouchdowns': i('PassTD'),
        'receptions': i('REC'),
        'interceptions': i('INT'),
        'flagPulls': i('FP'),
        'sacks': i('Sack'),
        'passBreakups': i('PBU'),
        // L6.1 Catch % — RECMiss's ONLY surfaced value (the raw drop count
        // stays a timeline marker, never a stat row). Gated to >=3 targets
        // because this feeds the season leaders board; below the gate (or
        // no targets) -> 0, which sortedLeagueLeaders' "> 0" filter drops.
        'catchPercentage':
            catchPercentage(i('REC'), i('RECMiss'), minTargets: 3) ?? 0,
      };
    default: // Futsal
      goals = i('Goals');
      assists = i('Assists');
      saves = i('Saves');
      dpl = i('DPL');
      cleanSheets = i('CleanSheets');
      yellowCards = i('Yellow');
      redCards = i('Red');
  }

  return TournamentPlayer(
    name: name,
    teamId: teamName,
    teamName: teamName,
    uid: uid,
    number: number,
    goals: goals,
    assists: assists,
    saves: saves,
    dpl: dpl,
    cleanSheets: cleanSheets,
    yellowCards: yellowCards,
    redCards: redCards,
    extraStats: extraStats,
  );
}

/// The whole `/{sport}/{season}/Line Ups` node -> rosters keyed by team
/// name, each roster sorted by shirt number (non-numeric numbers last).
Map<String, List<TournamentPlayer>> leagueRostersFromLineupsNode(
    String sport, dynamic lineupsNode) {
  final out = <String, List<TournamentPlayer>>{};
  if (lineupsNode is! Map) return out;
  lineupsNode.forEach((team, lineup) {
    if (lineup is! Map) return;
    final players = <TournamentPlayer>[];
    lineup.forEach((player, info) {
      if (info is Map) {
        players.add(leaguePlayerFromLineup(
          sport: sport,
          name: player.toString(),
          teamName: team.toString(),
          raw: info,
        ));
      }
    });
    players.sort((a, b) => (int.tryParse(a.number ?? '') ?? 999)
        .compareTo(int.tryParse(b.number ?? '') ?? 999));
    out[team.toString()] = players;
  });
  return out;
}

/// Season leaders for one statByName key ('goals', 'assists', 'saves',
/// 'dpl', 'cleanSheets', 'yellowCards', 'redCards'): zero counts excluded,
/// sorted desc, ties broken alphabetically. Drives the Player Stats tab.
List<TournamentPlayer> sortedLeagueLeaders(
    Map<String, List<TournamentPlayer>> rosters, String stat) {
  final all = <TournamentPlayer>[
    for (final players in rosters.values) ...players,
  ];
  final filtered =
      all.where((p) => p.statByName(stat) > 0).toList()
        ..sort((a, b) {
          final v = b.statByName(stat).compareTo(a.statByName(stat));
          return v != 0 ? v : a.name.compareTo(b.name);
        });
  return filtered;
}

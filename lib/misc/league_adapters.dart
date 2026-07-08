// Pure adapters: league RTDB shapes -> the tournament view models that the
// reused tournament widgets (FixturesTab, KnockoutTab, MatchFactsTab,
// ShareMatchCard, ...) render. League Experience P2.
// NO Flutter/Firebase imports — unit-tested in test/league_adapters_test.dart.
//
// Conventions:
// - League teams are keyed by NAME everywhere, so TournamentTeam.id and
//   TournamentPlayer.teamId carry the team name.
// - Game identity is the RTDB pair the game node lives under:
//   '{MMDDYYYY}#{index}' (leagueGameId / parseLeagueGameId).

import 'package:infinite_sports_flutter/misc/match_clock.dart';
import 'package:infinite_sports_flutter/misc/match_location.dart';
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';
import 'package:infinite_sports_flutter/misc/schedule_display.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

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

/// Logo-only team (name + crest, zeroed standings) for teams that are not
/// (yet) in the Teams node — e.g. match pages before standings exist.
TournamentTeam leagueTeamStub(String name, String? logoUrl) => TournamentTeam(
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
    );

/// Futsal standings sort (exact table.dart parity):
/// Points desc, GD desc, GS desc, then name for stability.
void sortLeagueStandings(List<TournamentTeam> rows) {
  rows.sort((a, b) {
    var v = b.points.compareTo(a.points);
    if (v == 0) v = b.gd.compareTo(a.gd);
    if (v == 0) v = b.gs.compareTo(a.gs);
    if (v == 0) v = a.name.compareTo(b.name);
    return v;
  });
}

/// The `/{sport}/{season}/Teams` node -> SORTED standings rows.
/// The Manager maintains this node and already skips staged (playoff /
/// friendly) games at finalize time — nothing to exclude here.
List<TournamentTeam> leagueStandingsFromTeamsNode(
    dynamic teamsNode, Map<String, String> logoUrls) {
  final out = <TournamentTeam>[];
  if (teamsNode is! Map) return out;
  teamsNode.forEach((name, v) {
    if (v is! Map) return;
    final wins = parseInt(v['Wins']);
    final draws = parseInt(v['Draws']);
    final losses = parseInt(v['Losses']);
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
    ));
  });
  sortLeagueStandings(out);
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
      );
    }
  });
  return out;
}

/// One Line Ups player node -> [TournamentPlayer]. League stat keys map onto
/// the statByName vocabulary: Goals/Assists/Saves/DPL/CleanSheets plus the
/// league card keys Yellow -> yellowCards, Red -> redCards.
/// Legacy UID '0' (and empty) means UNLINKED -> uid null, so profile taps
/// open the limited profile instead of a bogus uid lookup.
TournamentPlayer leaguePlayerFromLineup({
  required String name,
  required String teamName,
  required Map<dynamic, dynamic> raw,
}) {
  String? uid = raw['UID']?.toString();
  if (uid == null || uid.trim().isEmpty || uid.trim() == '0') uid = null;
  String? number = (raw['number'] ?? raw['Number'])?.toString();
  if (number != null && number.isEmpty) number = null;
  return TournamentPlayer(
    name: name,
    teamId: teamName,
    teamName: teamName,
    uid: uid,
    number: number,
    goals: parseInt(raw['Goals']),
    assists: parseInt(raw['Assists']),
    saves: parseInt(raw['Saves']),
    dpl: parseInt(raw['DPL']),
    cleanSheets: parseInt(raw['CleanSheets']),
    yellowCards: parseInt(raw['Yellow']),
    redCards: parseInt(raw['Red']),
  );
}

/// The whole `/{sport}/{season}/Line Ups` node -> rosters keyed by team
/// name, each roster sorted by shirt number (non-numeric numbers last).
Map<String, List<TournamentPlayer>> leagueRostersFromLineupsNode(
    dynamic lineupsNode) {
  final out = <String, List<TournamentPlayer>>{};
  if (lineupsNode is! Map) return out;
  lineupsNode.forEach((team, lineup) {
    if (lineup is! Map) return;
    final players = <TournamentPlayer>[];
    lineup.forEach((player, info) {
      if (info is Map) {
        players.add(leaguePlayerFromLineup(
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

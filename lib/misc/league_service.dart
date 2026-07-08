// Thin live-stream layer over the league RTDB paths (League Experience P2)
// — the league mirror of TournamentService.watch* (lib/misc/
// tournament_service.dart:153-205): onValue streams + pure mapping, no
// logic. Firebase-touching: no unit tests (repo convention — logic lives
// pure in league_adapters.dart / league_playoffs_view.dart).

import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

class LeagueService {
  static DatabaseReference _ref(String path) =>
      FirebaseDatabase.instance.ref(path);

  /// Legacy derived-time seed: `/{sport}/{season}/Start Time`. Returns 0
  /// when absent — the same value getSeasonStartTime uses for a null node,
  /// so the adapter's `'{startHour + index}:00PM'` fallback matches the
  /// legacy rendering exactly.
  static Future<int> getStartHour(String sport, String season) async {
    try {
      final snap = await _ref('/$sport/$season/Start Time').get();
      final v = snap.value;
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Season logo urls (team name → url) via the cached global Logo Urls map
  /// (utility.getAllTeamLogo caches on first call; shape
  /// teamLogos[sport][season][team]).
  static Future<Map<String, String>> leagueLogoUrls(
      String sport, String season) async {
    try {
      await getAllTeamLogo();
      final bySport = teamLogos[sport];
      if (bySport is! Map) return {};
      final bySeason = bySport[season];
      if (bySeason is! Map) return {};
      return {
        for (final e in bySeason.entries)
          if (e.value != null) e.key.toString(): e.value.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Live stream of the season's WHOLE schedule (every date), adapted to
  /// TournamentMatch. Emits from RTDB's disk cache first, then on every
  /// change — scores, clocks, playoff advancement all arrive here.
  static Stream<List<TournamentMatch>> watchGames(String sport, String season,
      {int startHour = 0}) {
    return _ref('/$sport/$season/Date').onValue.map((event) =>
        leagueMatchesFromDateNode(event.snapshot.value,
            startHour: startHour));
  }

  /// Live stream of ONE game node. null while the node is missing.
  static Stream<TournamentMatch?> watchGame(
      String sport, String season, String dateKey, int gameIndex,
      {int startHour = 0}) {
    return _ref('/$sport/$season/Date/$dateKey/$gameIndex')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return null;
      return leagueMatchFromGameMap(
        dateKey: dateKey,
        index: gameIndex,
        raw: v,
        startHour: startHour,
      );
    });
  }

  /// Live SORTED standings from the Manager-maintained Teams node (staged
  /// games are already excluded at finalize time by L3 — render as-is).
  static Stream<List<TournamentTeam>> watchStandings(
      String sport, String season, Map<String, String> logoUrls) {
    return _ref('/$sport/$season/Teams').onValue.map((event) =>
        leagueStandingsFromTeamsNode(event.snapshot.value, logoUrls));
  }

  /// Live rosters (season-total player stats) from Line Ups.
  static Stream<Map<String, List<TournamentPlayer>>> watchRosters(
      String sport, String season) {
    return _ref('/$sport/$season/Line Ups')
        .onValue
        .map((event) => leagueRostersFromLineupsNode(event.snapshot.value));
  }

  /// Live playoffs node. null until playoffs are generated.
  static Stream<LeaguePlayoffs?> watchPlayoffs(String sport, String season) {
    return _ref('/$sport/$season/Playoffs')
        .onValue
        .map((event) => LeaguePlayoffs.fromNode(event.snapshot.value));
  }
}

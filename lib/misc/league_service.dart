// Thin live-stream layer over the league RTDB paths (League Experience P2)
// — the league mirror of TournamentService.watch* (lib/misc/
// tournament_service.dart:153-205): onValue streams + pure mapping, no
// logic. Firebase-touching: no unit tests (repo convention — logic lives
// pure in league_adapters.dart / league_playoffs_view.dart).

import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
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

  /// Live stream of ONE date's games (P2.1: the Matches-tab league day view
  /// watches just its date node instead of the whole season schedule).
  /// Reuses the whole-node adapter by wrapping the single date.
  static Stream<List<TournamentMatch>> watchDateGames(
      String sport, String season, String dateKey,
      {int startHour = 0}) {
    return _ref('/$sport/$season/Date/$dateKey').onValue.map((event) =>
        leagueMatchesFromDateNode({dateKey: event.snapshot.value},
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

  /// Live captain map (team name -> Captain player name) from the same
  /// Manager-maintained Teams node (P2.1 Task A3 side-channel — Captain has
  /// no TournamentTeam field to ride on).
  static Stream<Map<String, String>> watchCaptains(
      String sport, String season) {
    return _ref('/$sport/$season/Teams')
        .onValue
        .map((event) => leagueCaptainsFromTeamsNode(event.snapshot.value));
  }

  /// Session-scoped cache of /Users/{uid}/ProfileUrl values (uid -> url,
  /// '' = known-absent) — the league mirror of TournamentService's cache,
  /// so squad avatars resolve once per player per session.
  static final Map<String, String> _profileUrlCache = {};

  /// Clears the in-memory ProfileUrl cache (rare — e.g. after sign-out).
  static void clearProfileUrlCache() => _profileUrlCache.clear();

  /// Live rosters (season-total player stats) from Line Ups, with each
  /// linked player's profile photo attached (P2.2: squad-row avatars).
  static Stream<Map<String, List<TournamentPlayer>>> watchRosters(
      String sport, String season) {
    return _ref('/$sport/$season/Line Ups').onValue.asyncMap((event) =>
        _withProfileUrls(leagueRostersFromLineupsNode(event.snapshot.value)));
  }

  /// The exact photo-enrichment approach of TournamentService.getRosters
  /// (tournament_service.dart): collect linked uids still missing a photo,
  /// fetch /Users/{uid}/ProfileUrl for all of them in PARALLEL (cached per
  /// session), then substitute via copyWith. Unlinked players (uid null —
  /// the adapter already normalizes '0'/empty) keep photoUrl null, so the
  /// UI's neutral person icon renders.
  static Future<Map<String, List<TournamentPlayer>>> _withProfileUrls(
      Map<String, List<TournamentPlayer>> rosters) async {
    final uidsToFetch = <String>{};
    for (final players in rosters.values) {
      for (final p in players) {
        final uid = p.uid;
        if (uid != null &&
            uid.isNotEmpty &&
            (p.photoUrl == null || p.photoUrl!.isEmpty) &&
            !_profileUrlCache.containsKey(uid)) {
          uidsToFetch.add(uid);
        }
      }
    }
    if (uidsToFetch.isNotEmpty) {
      await Future.wait(uidsToFetch.map((uid) async {
        try {
          final snap = await _ref('/Users/$uid/ProfileUrl').get();
          _profileUrlCache[uid] = snap.value?.toString() ?? '';
        } catch (_) {
          _profileUrlCache[uid] = '';
        }
      }));
    }
    rosters.forEach((team, players) {
      for (var i = 0; i < players.length; i++) {
        final p = players[i];
        if (p.uid == null || p.uid!.isEmpty) continue;
        if (p.photoUrl != null && p.photoUrl!.isNotEmpty) continue;
        final cached = _profileUrlCache[p.uid!];
        if (cached != null && cached.isNotEmpty) {
          players[i] = p.copyWith(photoUrl: cached);
        }
      }
    });
    return rosters;
  }

  /// Live playoffs node. null until playoffs are generated.
  static Stream<LeaguePlayoffs?> watchPlayoffs(String sport, String season) {
    return _ref('/$sport/$season/Playoffs')
        .onValue
        .map((event) => LeaguePlayoffs.fromNode(event.snapshot.value));
  }

  // ── Predictions (League Experience P3) ─────────────────────────────────
  // League mirror of TournamentService's prediction methods; paths sit
  // under the league-season node, per-game questions/results ride ON the
  // game node, and answers are keyed by leaguePredictionMatchKey.

  /// League PredictionConfig. ABSENT NODE = CLOSED — legacy seasons must
  /// not grow a Predict tab (the tournament parse defaults OPEN, so the
  /// null check must happen here, before PredictionConfig.fromFirebase).
  static Stream<PredictionConfig> watchPredictionConfig(
      String sport, String season) {
    return _ref('/$sport/$season/PredictionConfig').onValue.map((event) {
      final v = event.snapshot.value;
      if (v == null) {
        return const PredictionConfig(
            open: false, matchWinnerPoints: 1, exactScorePoints: 3);
      }
      return PredictionConfig.fromFirebase(v);
    });
  }

  static List<PredictionQuestion> _parseQuestions(dynamic value) {
    final out = <PredictionQuestion>[];
    if (value is Map) {
      value.forEach((qid, q) =>
          out.add(PredictionQuestion.fromFirebase(qid.toString(), q)));
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }

  /// Season-wide default questions (tournament-level equivalent).
  static Stream<List<PredictionQuestion>> watchSeasonQuestions(
      String sport, String season) {
    return _ref('/$sport/$season/PredictionQuestions')
        .onValue
        .map((event) => _parseQuestions(event.snapshot.value));
  }

  /// Per-game extra questions — ON the game node (tournament-match parity;
  /// they travel with Schedule Manager moves/compaction).
  static Stream<List<PredictionQuestion>> watchGameQuestions(
      String sport, String season, String dateKey, int index) {
    return _ref('/$sport/$season/Date/$dateKey/$index/PredictionQuestions')
        .onValue
        .map((event) => _parseQuestions(event.snapshot.value));
  }

  /// Owner-resolved results for custom questions: {qid: optionId}.
  static Stream<Map<String, String>> watchGameResults(
      String sport, String season, String dateKey, int index) {
    return _ref('/$sport/$season/Date/$dateKey/$index/PredictionResults')
        .onValue
        .map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return const <String, String>{};
      return {
        for (final e in v.entries) e.key.toString(): e.value.toString(),
      };
    });
  }

  /// My answers for one game: {qid: QuestionAnswer}.
  static Stream<Map<String, QuestionAnswer>> watchMyGameAnswers(
      String sport, String season, String dateKey, int index, String uid) {
    final key = leaguePredictionMatchKey(dateKey, index);
    return _ref('/$sport/$season/Predictions/$key/$uid').onValue.map((event) {
      final v = event.snapshot.value;
      final out = <String, QuestionAnswer>{};
      if (v is Map) {
        v.forEach((qid, raw) {
          final a = QuestionAnswer.fromFirebase(raw);
          if (a != null) out[qid.toString()] = a;
        });
      }
      return out;
    });
  }

  /// Writes one answer (same {Answer, UpdatedAt} leaf the scorer reads;
  /// UpdatedAt must predate Clock/StartedAt to count — functions fairness).
  static Future<void> submitAnswer(String sport, String season, String dateKey,
      int index, String uid, String qid, String value, int nowMs) {
    final key = leaguePredictionMatchKey(dateKey, index);
    return _ref('/$sport/$season/Predictions/$key/$uid/$qid')
        .set(QuestionAnswer(value: value, updatedAt: nowMs).toFirebase());
  }

  /// Functions-maintained league leaderboard, sorted for display.
  static Stream<List<LeaderboardEntry>> watchLeaderboard(
      String sport, String season) {
    return _ref('/$sport/$season/Leaderboard').onValue.map((event) {
      final v = event.snapshot.value;
      final out = <LeaderboardEntry>[];
      if (v is Map) {
        v.forEach((uid, raw) =>
            out.add(LeaderboardEntry.fromFirebase(uid.toString(), raw)));
      }
      out.sort(compareLeaderboard);
      return out;
    });
  }
}

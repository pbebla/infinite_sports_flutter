import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

/// ONE-SHOT READS UNDER /Tournaments USE once(), NEVER get() (iOS bug):
/// FrontPage keeps a PERMANENT onValue listener on the whole /Tournaments
/// node ([TournamentService.watchAllTournaments], for live tournament-tab
/// discovery), and firebase-ios-sdk's one-shot get() returns the WRONG NODE
/// (an ancestor's cached value) when a listener is active at an
/// overlapping/ancestor path — every get('/Tournaments/...') came back with
/// the /Tournaments ROOT map, whose tournament children (each carrying a
/// 'Name') then parsed as "teams" on iOS. once() rides the listener
/// mechanism (observeSingleEvent) and does not share the defect; onValue
/// listeners are unaffected. Non-/Tournaments paths keep get(): no
/// root-level listener exists for them, so the collision can't happen.
class TournamentService {
  /// Session-scoped cache of /Users/{uid}/ProfileUrl values.
  /// Keyed by uid. Cleared by [clearProfileUrlCache] if needed.
  static final Map<String, String> _profileUrlCache = {};

  /// Clears the in-memory ProfileUrl cache. Call after a sign-out or when
  /// you need fresh user photos (rare).
  static void clearProfileUrlCache() => _profileUrlCache.clear();

  /// Parses the raw /Tournaments node into a sorted tournament list: active
  /// (not finished) first, then historical sorted by edition descending.
  /// Skips the "Current Tournament" pointer key and any non-map entries
  /// without throwing. Pure — shared by [getAllTournaments] (one-shot) and
  /// [watchAllTournaments] (live) so both stay in sync by construction.
  static List<Tournament> parseTournaments(dynamic value) {
    if (value is! Map) return [];
    final List<Tournament> tournaments = [];
    value.forEach((key, v) {
      // Skip the "Current Tournament" key which is a plain string pointer
      if (key.toString() == 'Current Tournament') return;
      if (v is Map) {
        try {
          tournaments.add(Tournament.fromFirebase(key.toString(), v));
        } catch (_) {}
      }
    });
    // Sort: active (not finished) first, then finished sorted by edition desc
    tournaments.sort((a, b) {
      if (!a.finished && b.finished) return -1;
      if (a.finished && !b.finished) return 1;
      return b.edition.compareTo(a.edition);
    });
    return tournaments;
  }

  /// Returns list of all tournaments sorted: active first, then historical newest-first.
  static Future<List<Tournament>> getAllTournaments() async {
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref('/Tournaments');
      final event = await ref.once();
      return parseTournaments(event.snapshot.value);
    } catch (_) {
      return [];
    }
  }

  /// Live stream of all tournaments, sorted the same way as
  /// [getAllTournaments] (active first, then historical newest-first).
  /// Emits on every /Tournaments change, so a newly created tournament (or a
  /// status flip) appears without restarting the app.
  static Stream<List<Tournament>> watchAllTournaments() {
    return FirebaseDatabase.instance
        .ref('/Tournaments')
        .onValue
        .map((event) => parseTournaments(event.snapshot.value));
  }

  /// Sorted ids of the tournaments in [tournaments] that are NOT finished.
  /// Pure — used to detect when the SET of active tournaments changes (one
  /// is created, finishes, or un-finishes) without reacting to routine
  /// in-tournament updates (score changes, roster edits, ...) that fire the
  /// same /Tournaments stream but don't change which tournaments are active.
  /// See FrontPage's live tournament-tab discovery.
  static List<String> activeTournamentIds(List<Tournament> tournaments) {
    final ids = tournaments.where((t) => !t.finished).map((t) => t.id).toList();
    ids.sort();
    return ids;
  }

  /// Returns the id string of the current active tournament.
  static Future<String?> getCurrentTournamentId() async {
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref('/Tournaments');
      final event = await ref.child('Current Tournament').once();
      final value = event.snapshot.value;
      if (value == null) return null;
      return value.toString();
    } catch (_) {
      return null;
    }
  }

  /// Returns headers for all tournaments whose Finished flag is false.
  /// Order follows getAllTournaments (active-first, newest edition first).
  static Future<List<Tournament>> getActiveTournaments() async {
    final all = await getAllTournaments();
    return all.where((t) => !t.finished).toList();
  }

  /// Returns the Tournament header object (top-level fields only).
  static Future<Tournament?> getTournamentHeader(String tournamentId) async {
    try {
      DatabaseReference ref =
          FirebaseDatabase.instance.ref('/Tournaments/$tournamentId');
      final event = await ref.once();
      final value = event.snapshot.value;
      if (value == null) return null;
      final data = value as Map;
      return Tournament.fromFirebase(tournamentId, data);
    } catch (e) {
      debugPrint('TournamentService.getTournamentHeader error: $e');
      return null;
    }
  }

  /// Pure parse of a whole `/Tournaments/<id>` snapshot into everything the
  /// tournament detail page needs. Reuses the exact per-node parsers
  /// ([Tournament.fromFirebase], [parseTeams], [parseMatches],
  /// [parseRosters], [PredictionConfig.fromFirebase]) so the bundle path can
  /// never drift from what the separate per-node calls produce.
  ///
  /// Returns null when the snapshot is UNUSABLE — null/garbage input, or a
  /// payload shaped like the /Tournaments ROOT instead of a single
  /// tournament (the iOS wrong-node get() symptom, see the class comment).
  /// Callers keep their previous state instead of rendering garbage.
  static TournamentBundle? parseTournamentBundle(
      String tournamentId, Object? raw) {
    if (raw is! Map) return null;
    if (_looksLikeTournamentsRoot(raw)) {
      debugPrint(
          'TournamentService.parseTournamentBundle($tournamentId): snapshot '
          'is shaped like the /Tournaments ROOT, not a single tournament '
          '(keys: ${raw.keys.take(8).join(', ')}). Refusing to parse — '
          'this is the iOS root-listener/get() wrong-node symptom; the '
          'caller keeps its previous state instead of rendering '
          'tournaments as teams.');
      return null;
    }
    Tournament? tournament;
    try {
      tournament = Tournament.fromFirebase(tournamentId, raw);
    } catch (_) {}
    final teams = parseTeams(raw['Teams'], raw['Table']);
    return TournamentBundle(
      tournament: tournament,
      teams: teams,
      matches: parseMatches(raw['Matches']),
      config: PredictionConfig.fromFirebase(raw['PredictionConfig']),
      rosters: parseRosters(raw['Rosters'], teams),
    );
  }

  /// Shape guard (defense in depth for the iOS wrong-node get() incident):
  /// true when [raw] is the /Tournaments ROOT map rather than one tournament
  /// node. The root carries the 'Current Tournament' string pointer, and its
  /// map children are tournaments (each with a Teams/Matches child) — while
  /// a single tournament's map children (Teams, Table, Matches, Rosters,
  /// PredictionConfig) never themselves contain a Teams/Matches child.
  /// Majority-of-values so one malformed sibling can't flip the verdict.
  static bool _looksLikeTournamentsRoot(Map raw) {
    if (raw.containsKey('Current Tournament')) return true;
    var tournamentShaped = 0;
    for (final v in raw.values) {
      if (v is Map && (v.containsKey('Teams') || v.containsKey('Matches'))) {
        tournamentShaped++;
      }
    }
    return tournamentShaped > 0 && tournamentShaped * 2 > raw.length;
  }

  /// ONE once() read of `/Tournaments/<id>` + [parseTournamentBundle]. The
  /// detail page used to fire five get()s in parallel; now nothing under
  /// /Tournaments reads via get() at all (class comment: get() returns an
  /// ancestor's cached value on iOS while the permanent /Tournaments root
  /// listener is up). An unusable snapshot degrades to the empty bundle so
  /// one-shot callers keep their existing graceful-defaults behavior.
  static Future<TournamentBundle> getTournamentBundle(
      String tournamentId) async {
    try {
      final event = await FirebaseDatabase.instance
          .ref('/Tournaments/$tournamentId')
          .once();
      return parseTournamentBundle(tournamentId, event.snapshot.value) ??
          TournamentBundle.empty();
    } catch (e) {
      debugPrint('TournamentService.getTournamentBundle error: $e');
      return TournamentBundle.empty();
    }
  }

  /// Live stream of the whole `/Tournaments/<id>` node, parsed. The detail
  /// page's single source of truth — the same one-listener architecture the
  /// league pages use (listeners never hit the iOS wrong-node get() defect),
  /// and everything (header, teams, table, matches, rosters, prediction
  /// config) updates in place. A null emission means the snapshot was
  /// unusable (missing node, or [parseTournamentBundle]'s root-shape guard
  /// fired): subscribers keep their previous state rather than blanking.
  static Stream<TournamentBundle?> watchTournamentBundle(String tournamentId) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId')
        .onValue
        .map((event) =>
            parseTournamentBundle(tournamentId, event.snapshot.value));
  }

  /// Pure Teams+Table merge shared by [getTeams] and [parseTournamentBundle]
  /// — one source of truth so both paths merge table rows identically.
  static Map<String, TournamentTeam> parseTeams(
      Object? teamsRaw, Object? tableRaw) {
    if (teamsRaw is! Map) return {};
    final tableData =
        tableRaw is Map ? tableRaw : <dynamic, dynamic>{};

    final Map<String, TournamentTeam> result = {};
    teamsRaw.forEach((key, value) {
      if (value is Map) {
        final teamId = key.toString();
        final Map<dynamic, dynamic> rowData =
            tableData.containsKey(key) && tableData[key] is Map
                ? tableData[key] as Map
                : {};
        try {
          result[teamId] = TournamentTeam.fromFirebase(teamId, value, rowData);
        } catch (_) {}
      }
    });
    return result;
  }

  /// Returns map of teams keyed by team id, merged with table data.
  /// Teams and Table queries run in parallel via Future.wait.
  static Future<Map<String, TournamentTeam>> getTeams(String tournamentId) async {
    try {
      final ref = FirebaseDatabase.instance.ref('/Tournaments/$tournamentId');
      final events = await Future.wait([
        ref.child('Teams').once(),
        ref.child('Table').once(),
      ]);
      return parseTeams(events[0].snapshot.value, events[1].snapshot.value);
    } catch (e) {
      debugPrint('TournamentService.getTeams error: $e');
      return {};
    }
  }

  /// Pure per-child match parse + sort (date, then bracketPosition) shared
  /// by [getMatches], [watchMatches] and [parseTournamentBundle].
  static List<TournamentMatch> parseMatches(Object? raw) {
    if (raw is! Map) return [];
    final List<TournamentMatch> matches = [];
    raw.forEach((key, value) {
      if (value is Map) {
        try {
          matches.add(TournamentMatch.fromFirebase(key.toString(), value));
        } catch (_) {}
      }
    });
    matches.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.bracketPosition.compareTo(b.bracketPosition);
    });
    return matches;
  }

  /// Returns list of all matches sorted by date then bracketPosition.
  static Future<List<TournamentMatch>> getMatches(String tournamentId) async {
    try {
      DatabaseReference ref =
          FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Matches');
      final event = await ref.once();
      return parseMatches(event.snapshot.value);
    } catch (e) {
      debugPrint('TournamentService.getMatches error: $e');
      return [];
    }
  }

  /// Live stream of all matches in a tournament. Emits immediately from
  /// RTDB's local cache (if any) then on every change.
  /// Matches are sorted by date then bracketPosition, mirroring [getMatches].
  static Stream<List<TournamentMatch>> watchMatches(String tournamentId) {
    final ref = FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/Matches');
    return ref.onValue.map((event) => parseMatches(event.snapshot.value));
  }

  /// Live stream of one match.
  static Stream<TournamentMatch?> watchMatch(
      String tournamentId, String matchId) {
    final ref = FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/Matches/$matchId');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      try {
        return TournamentMatch.fromFirebase(matchId, value);
      } catch (_) {
        return null;
      }
    });
  }

  /// Live stream of the tournament header (status/champion/etc.).
  static Stream<Tournament?> watchTournament(String tournamentId) {
    final ref =
        FirebaseDatabase.instance.ref('/Tournaments/$tournamentId');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      try {
        return Tournament.fromFirebase(tournamentId, value);
      } catch (_) {
        return null;
      }
    });
  }

  /// Returns map of teamId -> list of TournamentPlayer.
  /// Also tries to load profileUrl from /Users/{uid}/ProfileUrl if uid exists
  /// and the player record doesn't already have a photoUrl.
  ///
  /// Composition of [getRostersNode] + [parseRosters] + [enrichRosterPhotos]
  /// — callers that must not let avatar round-trips gate first paint (the
  /// tournament detail page) use the pieces individually instead.
  static Future<Map<String, List<TournamentPlayer>>> getRosters(
    String tournamentId,
    Map<String, TournamentTeam> teams,
  ) async {
    final rosters = parseRosters(await getRostersNode(tournamentId), teams);
    return enrichRosterPhotos(rosters);
  }

  /// Raw /Rosters node fetch — split out so callers can run it in the same
  /// Future.wait wave as the teams fetch its parsing depends on.
  static Future<Object?> getRostersNode(String tournamentId) async {
    try {
      final event = await FirebaseDatabase.instance
          .ref('/Tournaments/$tournamentId/Rosters')
          .once();
      return event.snapshot.value;
    } catch (e) {
      debugPrint('TournamentService.getRostersNode error: $e');
      return null;
    }
  }

  /// Pure parse + session-cached photo substitution — NO network. Photos
  /// for linked players not yet in the session cache stay null here;
  /// [enrichRosterPhotos] fills them behind the first paint (perceived-perf
  /// rule: avatar fetches never gate stats).
  static Map<String, List<TournamentPlayer>> parseRosters(
    Object? raw,
    Map<String, TournamentTeam> teams,
  ) {
    if (raw is! Map) return {};
    final Map<String, List<TournamentPlayer>> result = {};
    raw.forEach((teamKey, teamValue) {
      if (teamValue is! Map) return;
      final teamId = teamKey.toString();
      final teamName = teams[teamId]?.name ?? teamId;
      final List<TournamentPlayer> players = [];
      teamValue.forEach((playerKey, playerValue) {
        if (playerValue is! Map) return;
        players.add(TournamentPlayer.fromFirebase(
          playerKey.toString(),
          teamId,
          teamName,
          playerValue,
        ));
      });
      result[teamId] = players;
    });
    _substituteCachedRosterPhotos(result);
    return result;
  }

  /// Fetches ProfileUrls for linked players still missing a photo — in
  /// PARALLEL, session-cached, so subsequent renders are instant (before
  /// the cache this was N+1 sequential reads, ~120 round trips for a
  /// 12-team x 10-player tournament) — then substitutes them in.
  static Future<Map<String, List<TournamentPlayer>>> enrichRosterPhotos(
    Map<String, List<TournamentPlayer>> rosters,
  ) async {
    final Set<String> uidsToFetch = {};
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
          final urlSnap = await FirebaseDatabase.instance
              .ref('/Users/$uid/ProfileUrl')
              .get();
          _profileUrlCache[uid] = urlSnap.value?.toString() ?? '';
        } catch (_) {
          _profileUrlCache[uid] = '';
        }
      }));
    }
    _substituteCachedRosterPhotos(rosters);
    return rosters;
  }

  /// True when [enrichRosterPhotos] would actually do network work: some
  /// linked player still lacks a photo AND its ProfileUrl is not in the
  /// session cache. Lets the live bundle stream skip the follow-up
  /// enrichment pass (and its setState) on the many events where nothing
  /// is missing — e.g. every live score tick.
  static bool rosterPhotosPending(
    Map<String, List<TournamentPlayer>> rosters,
  ) {
    for (final players in rosters.values) {
      for (final p in players) {
        final uid = p.uid;
        if (uid != null &&
            uid.isNotEmpty &&
            (p.photoUrl == null || p.photoUrl!.isEmpty) &&
            !_profileUrlCache.containsKey(uid)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Applies already-cached ProfileUrls in place (no network).
  static void _substituteCachedRosterPhotos(
    Map<String, List<TournamentPlayer>> rosters,
  ) {
    rosters.forEach((teamId, players) {
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
  }

  /// Returns a flat list of all players across all teams for leaderboard use.
  static List<TournamentPlayer> getAllPlayers(
    Map<String, List<TournamentPlayer>> rosters,
  ) {
    final List<TournamentPlayer> all = [];
    for (final playerList in rosters.values) {
      all.addAll(playerList);
    }
    return all;
  }

  /// Returns all matches between team1Id and team2Id across ALL tournaments,
  /// sorted by date descending. Each match is annotated with its tournament name.
  static Future<List<Map<String, dynamic>>> getH2HMatches(String team1Id, String team2Id) async {
    try {
      final ref = FirebaseDatabase.instance.ref('/Tournaments');
      final event = await ref.once();
      final value = event.snapshot.value;
      if (value == null) return [];
      final data = value as Map;
      final List<Map<String, dynamic>> results = [];

      data.forEach((tourneyKey, tourneyValue) {
        if (tourneyKey.toString() == 'Current Tournament') return;
        if (tourneyValue is! Map) return;
        final tourneyName = tourneyValue['Name']?.toString() ?? tourneyKey.toString();
        final matchesNode = tourneyValue['Matches'];
        if (matchesNode is! Map) return;
        matchesNode.forEach((matchKey, matchValue) {
          if (matchValue is! Map) return;
          final t1 = matchValue['Team1Id']?.toString();
          final t2 = matchValue['Team2Id']?.toString();
          if ((t1 == team1Id && t2 == team2Id) || (t1 == team2Id && t2 == team1Id)) {
            try {
              final match = TournamentMatch.fromFirebase(matchKey.toString(), matchValue);
              results.add({'match': match, 'tournamentName': tourneyName, 'tournamentId': tourneyKey.toString()});
            } catch (_) {}
          }
        });
      });

      results.sort((a, b) {
        final ma = a['match'] as TournamentMatch;
        final mb = b['match'] as TournamentMatch;
        return mb.date.compareTo(ma.date);
      });
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Returns teams for any tournament (alias for getTeams, used by H2H navigation).
  static Future<Map<String, TournamentTeam>> getTeamsForTournament(String tournamentId) async {
    return getTeams(tournamentId);
  }

  /// Reads PredictionConfig once (defaults applied when absent).
  static Future<PredictionConfig> getPredictionConfig(String tournamentId) async {
    try {
      final event = await FirebaseDatabase.instance
          .ref('/Tournaments/$tournamentId/PredictionConfig')
          .once();
      return PredictionConfig.fromFirebase(event.snapshot.value);
    } catch (e) {
      debugPrint('TournamentService.getPredictionConfig error: $e');
      return PredictionConfig.fromFirebase(const {});
    }
  }

  static Stream<PredictionConfig> watchPredictionConfig(String tournamentId) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/PredictionConfig')
        .onValue
        .map((e) => PredictionConfig.fromFirebase(e.snapshot.value));
  }

  /// Writes the signed-in user's prediction for one match.
  static Future<void> submitPrediction(
    String tournamentId,
    String matchId,
    String uid,
    int team1,
    int team2,
    int nowMs,
  ) async {
    final pred = MatchPrediction(team1: team1, team2: team2, updatedAt: nowMs);
    await FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/Predictions/$matchId/$uid')
        .set(pred.toFirebase());
  }

  /// Streams the signed-in user's predictions across the tournament, keyed by matchId.
  static Stream<Map<String, MatchPrediction>> watchMyPredictions(
      String tournamentId, String uid) {
    final ref =
        FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Predictions');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      final out = <String, MatchPrediction>{};
      if (value is Map) {
        value.forEach((matchId, byUser) {
          if (byUser is Map && byUser[uid] is Map) {
            final p = MatchPrediction.fromFirebase(byUser[uid]);
            if (p != null) out[matchId.toString()] = p;
          }
        });
      }
      return out;
    });
  }

  /// Streams the tournament leaderboard, already sorted.
  static Stream<List<LeaderboardEntry>> watchLeaderboard(String tournamentId) {
    final ref =
        FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Leaderboard');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      final out = <LeaderboardEntry>[];
      if (value is Map) {
        value.forEach((uid, v) {
          out.add(LeaderboardEntry.fromFirebase(uid.toString(), v));
        });
      }
      out.sort(compareLeaderboard);
      return out;
    });
  }

  /// Tournament-wide default questions.
  static Stream<List<PredictionQuestion>> watchTournamentQuestions(String tid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/PredictionQuestions')
        .onValue
        .map((e) => _parseQuestions(e.snapshot.value));
  }

  /// Per-match extra questions.
  static Stream<List<PredictionQuestion>> watchMatchQuestions(String tid, String mid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Matches/$mid/PredictionQuestions')
        .onValue
        .map((e) => _parseQuestions(e.snapshot.value));
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

  /// The signed-in user's answers for one match, keyed by questionId.
  static Stream<Map<String, QuestionAnswer>> watchMyMatchAnswers(
      String tid, String mid, String uid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Predictions/$mid/$uid')
        .onValue
        .map((e) {
      final out = <String, QuestionAnswer>{};
      final v = e.snapshot.value;
      if (v is Map) {
        v.forEach((qid, raw) {
          final a = QuestionAnswer.fromFirebase(raw);
          if (a != null) out[qid.toString()] = a;
        });
      }
      return out;
    });
  }

  static Future<void> submitAnswer(
      String tid, String mid, String uid, String qid, String value, int nowMs) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Predictions/$mid/$uid/$qid')
        .set({'Answer': value, 'UpdatedAt': nowMs});
  }

  /// Owner-set correct option for custom questions (read by the room to show results).
  static Stream<Map<String, String>> watchMatchResults(String tid, String mid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Matches/$mid/PredictionResults')
        .onValue
        .map((e) {
      final out = <String, String>{};
      final v = e.snapshot.value;
      if (v is Map) v.forEach((qid, opt) => out[qid.toString()] = opt.toString());
      return out;
    });
  }

  /// Count of a user's answered questions for a match (for the hub progress chip).
  static Stream<int> watchMyAnswerCount(String tid, String mid, String uid) =>
      watchMyMatchAnswers(tid, mid, uid).map((m) => m.length);

  /// Returns participation history for a team across all tournaments.
  /// Returns list of {tournamentName, tournamentId, furthestStage, isChampion, isRunnerUp, wins, draws, losses, points}
  static Future<List<Map<String, dynamic>>> getTeamTournamentHistory(String teamId) async {
    try {
      final ref = FirebaseDatabase.instance.ref('/Tournaments');
      final event = await ref.once();
      final value = event.snapshot.value;
      if (value == null) return [];
      final data = value as Map;
      final List<Map<String, dynamic>> results = [];

      data.forEach((tourneyKey, tourneyValue) {
        if (tourneyKey.toString() == 'Current Tournament') return;
        if (tourneyValue is! Map) return;
        final tourneyName =
            tourneyValue['Name']?.toString() ?? tourneyKey.toString();

        // Check if team is in this tournament
        final teamsNode = tourneyValue['Teams'];
        if (teamsNode is! Map) return;
        if (!teamsNode.containsKey(teamId)) return;

        // Get table data
        final tableNode = tourneyValue['Table'];
        final tableData =
            (tableNode is Map && tableNode.containsKey(teamId))
                ? tableNode[teamId] as Map
                : <dynamic, dynamic>{};

        // Get furthest stage reached
        final matchesNode = tourneyValue['Matches'];
        String furthestStage = 'Group Stage';
        bool isChampion = false;
        bool isRunnerUp = false;

        if (matchesNode is Map) {
          int maxOrder = 0;

          matchesNode.forEach((mKey, mValue) {
            if (mValue is! Map) return;
            final t1 = mValue['Team1Id']?.toString();
            final t2 = mValue['Team2Id']?.toString();
            if (t1 != teamId && t2 != teamId) return;
            final rawStage = mValue['Stage']?.toString() ?? '';
            final stage = TournamentStage.fromString(rawStage);
            final order = stage.sortOrder;
            if (order > maxOrder && order != TournamentStage.unknown.sortOrder) {
              maxOrder = order;
              furthestStage = rawStage.isNotEmpty ? rawStage : 'Group Stage';
            }
            // Check if champion or runner-up (only if the match was the final and finished)
            if (stage == TournamentStage.finalStage &&
                (mValue['Status'] as num?)?.toInt() == 2) {
              final score1 =
                  (mValue['Team1Score'] as num?)?.toInt() ?? 0;
              final score2 =
                  (mValue['Team2Score'] as num?)?.toInt() ?? 0;
              if (t1 == teamId && score1 > score2) isChampion = true;
              if (t2 == teamId && score2 > score1) isChampion = true;
              if (t1 == teamId && score1 < score2) isRunnerUp = true;
              if (t2 == teamId && score2 < score1) isRunnerUp = true;
            }
          });
        }

        results.add({
          'tournamentName': tourneyName,
          'tournamentId': tourneyKey.toString(),
          'furthestStage': furthestStage,
          'isChampion': isChampion,
          'isRunnerUp': isRunnerUp,
          'wins': (tableData['W'] as num?)?.toInt() ?? 0,
          'draws': (tableData['D'] as num?)?.toInt() ?? 0,
          'losses': (tableData['L'] as num?)?.toInt() ?? 0,
          'points': (tableData['Pts'] as num?)?.toInt() ?? 0,
        });
      });

      return results;
    } catch (_) {
      return [];
    }
  }
}

/// Everything one `/Tournaments/<id>` snapshot yields, parsed — see
/// [TournamentService.parseTournamentBundle]. [rosters] carries only
/// session-cached photos (parseRosters does no network): callers run
/// TournamentService.enrichRosterPhotos(bundle.rosters) behind the first
/// paint so avatar round-trips never gate stats.
class TournamentBundle {
  final Tournament? tournament;
  final Map<String, TournamentTeam> teams;
  final List<TournamentMatch> matches;
  final PredictionConfig config;
  final Map<String, List<TournamentPlayer>> rosters;

  const TournamentBundle({
    required this.tournament,
    required this.teams,
    required this.matches,
    required this.config,
    required this.rosters,
  });

  /// Missing/unreadable tournament: null header, empty collections, default
  /// config — the same graceful defaults the separate per-node calls produce.
  factory TournamentBundle.empty() => TournamentBundle(
        tournament: null,
        teams: {},
        matches: [],
        config: PredictionConfig.fromFirebase(const {}),
        rosters: {},
      );
}

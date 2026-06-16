import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

class TournamentService {
  /// Session-scoped cache of /Users/{uid}/ProfileUrl values.
  /// Keyed by uid. Cleared by [clearProfileUrlCache] if needed.
  static final Map<String, String> _profileUrlCache = {};

  /// Clears the in-memory ProfileUrl cache. Call after a sign-out or when
  /// you need fresh user photos (rare).
  static void clearProfileUrlCache() => _profileUrlCache.clear();

  /// Returns list of all tournaments sorted: active first, then historical newest-first.
  static Future<List<Tournament>> getAllTournaments() async {
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref('/Tournaments');
      var snap = await ref.get();
      if (snap.value == null) return [];
      final data = snap.value as Map;
      final List<Tournament> tournaments = [];
      data.forEach((key, value) {
        // Skip the "Current Tournament" key which is a plain string pointer
        if (key.toString() == 'Current Tournament') return;
        if (value is Map) {
          try {
            tournaments.add(Tournament.fromFirebase(key.toString(), value));
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
    } catch (_) {
      return [];
    }
  }

  /// Returns the id string of the current active tournament.
  static Future<String?> getCurrentTournamentId() async {
    try {
      DatabaseReference ref = FirebaseDatabase.instance.ref('/Tournaments');
      var snap = await ref.child('Current Tournament').get();
      if (snap.value == null) return null;
      return snap.value.toString();
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
      var snap = await ref.get();
      if (snap.value == null) return null;
      final data = snap.value as Map;
      return Tournament.fromFirebase(tournamentId, data);
    } catch (_) {
      return null;
    }
  }

  /// Returns map of teams keyed by team id, merged with table data.
  /// Teams and Table queries run in parallel via Future.wait.
  static Future<Map<String, TournamentTeam>> getTeams(String tournamentId) async {
    try {
      final ref = FirebaseDatabase.instance.ref('/Tournaments/$tournamentId');
      final snaps = await Future.wait([
        ref.child('Teams').get(),
        ref.child('Table').get(),
      ]);
      final teamsSnap = snaps[0];
      final tableSnap = snaps[1];

      if (teamsSnap.value == null) return {};

      final teamsData = teamsSnap.value as Map;
      final tableData = tableSnap.value is Map
          ? tableSnap.value as Map
          : <dynamic, dynamic>{};

      final Map<String, TournamentTeam> result = {};
      teamsData.forEach((key, value) {
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
    } catch (e) {
      debugPrint('TournamentService.getTeams error: $e');
      return {};
    }
  }

  /// Returns list of all matches sorted by date then bracketPosition.
  static Future<List<TournamentMatch>> getMatches(String tournamentId) async {
    try {
      DatabaseReference ref =
          FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Matches');
      var snap = await ref.get();
      if (snap.value == null) return [];
      final data = snap.value as Map;
      final List<TournamentMatch> matches = [];
      data.forEach((key, value) {
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
    } catch (_) {
      return [];
    }
  }

  /// Live stream of all matches in a tournament. Emits immediately from
  /// RTDB's local cache (if any) then on every change.
  /// Matches are sorted by date then bracketPosition, mirroring [getMatches].
  static Stream<List<TournamentMatch>> watchMatches(String tournamentId) {
    final ref = FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/Matches');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <TournamentMatch>[];
      final out = <TournamentMatch>[];
      value.forEach((key, v) {
        if (v is Map) {
          try {
            out.add(TournamentMatch.fromFirebase(key.toString(), v));
          } catch (_) {}
        }
      });
      out.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.bracketPosition.compareTo(b.bracketPosition);
      });
      return out;
    });
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
  /// Profile-photo URLs are fetched in PARALLEL via Future.wait and cached
  /// in a session-scoped Map keyed by uid, so subsequent renders are instant.
  /// Previously this was N+1 sequential per-player reads — ~120 round trips
  /// for a 12-team x 10-player tournament before this page could render.
  static Future<Map<String, List<TournamentPlayer>>> getRosters(
    String tournamentId,
    Map<String, TournamentTeam> teams,
  ) async {
    try {
      final ref =
          FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Rosters');
      final snap = await ref.get();
      if (snap.value == null) return {};
      final data = snap.value as Map;

      // First pass: build all TournamentPlayer instances and collect the
      // set of uids whose ProfileUrl we still need to fetch.
      final Map<String, List<TournamentPlayer>> result = {};
      final Set<String> uidsToFetch = {};

      data.forEach((teamKey, teamValue) {
        if (teamValue is! Map) return;
        final teamId = teamKey.toString();
        final teamName = teams[teamId]?.name ?? teamId;
        final List<TournamentPlayer> players = [];

        teamValue.forEach((playerKey, playerValue) {
          if (playerValue is! Map) return;
          final player = TournamentPlayer.fromFirebase(
            playerKey.toString(),
            teamId,
            teamName,
            playerValue,
          );
          players.add(player);

          final uid = player.uid;
          if (uid != null &&
              uid.isNotEmpty &&
              (player.photoUrl == null || player.photoUrl!.isEmpty) &&
              !_profileUrlCache.containsKey(uid)) {
            uidsToFetch.add(uid);
          }
        });

        result[teamId] = players;
      });

      // Second pass: fetch all missing ProfileUrls in parallel.
      if (uidsToFetch.isNotEmpty) {
        await Future.wait(uidsToFetch.map((uid) async {
          try {
            final urlSnap = await FirebaseDatabase.instance
                .ref('/Users/$uid/ProfileUrl')
                .get();
            _profileUrlCache[uid] =
                urlSnap.value?.toString() ?? '';
          } catch (_) {
            _profileUrlCache[uid] = '';
          }
        }));
      }

      // Third pass: substitute cached photoUrls into players where needed.
      result.forEach((teamId, players) {
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

      return result;
    } catch (_) {
      return {};
    }
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
      final snap = await ref.get();
      if (snap.value == null) return [];
      final data = snap.value as Map;
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
      final snap = await FirebaseDatabase.instance
          .ref('/Tournaments/$tournamentId/PredictionConfig')
          .get();
      return PredictionConfig.fromFirebase(snap.value);
    } catch (_) {
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

  /// Returns participation history for a team across all tournaments.
  /// Returns list of {tournamentName, tournamentId, furthestStage, isChampion, isRunnerUp, wins, draws, losses, points}
  static Future<List<Map<String, dynamic>>> getTeamTournamentHistory(String teamId) async {
    try {
      final ref = FirebaseDatabase.instance.ref('/Tournaments');
      final snap = await ref.get();
      if (snap.value == null) return [];
      final data = snap.value as Map;
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

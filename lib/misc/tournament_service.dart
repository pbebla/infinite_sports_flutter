import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

class TournamentService {
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
  static Future<Map<String, TournamentTeam>> getTeams(String tournamentId) async {
    try {
      DatabaseReference ref =
          FirebaseDatabase.instance.ref('/Tournaments/$tournamentId');
      final teamsSnap = await ref.child('Teams').get();
      final tableSnap = await ref.child('Table').get();

      if (teamsSnap.value == null) return {};

      final teamsData = teamsSnap.value as Map;
      final tableData = tableSnap.value != null
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
    } catch (_) {
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

  /// Returns map of teamId -> list of TournamentPlayer.
  /// Also tries to load profileUrl from Users/{uid}/ProfileUrl if uid exists.
  static Future<Map<String, List<TournamentPlayer>>> getRosters(
    String tournamentId,
    Map<String, TournamentTeam> teams,
  ) async {
    try {
      DatabaseReference ref =
          FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Rosters');
      var snap = await ref.get();
      if (snap.value == null) return {};
      final data = snap.value as Map;

      final Map<String, List<TournamentPlayer>> result = {};

      for (final teamEntry in data.entries) {
        final teamId = teamEntry.key.toString();
        final teamName = teams[teamId]?.name ?? teamId;
        if (teamEntry.value is! Map) continue;
        final playersData = teamEntry.value as Map;
        final List<TournamentPlayer> players = [];

        for (final playerEntry in playersData.entries) {
          if (playerEntry.value is! Map) continue;
          final playerName = playerEntry.key.toString();
          var player = TournamentPlayer.fromFirebase(
            playerName,
            teamId,
            teamName,
            playerEntry.value as Map,
          );

          // Try to load profile photo from Users/{uid}/ProfileUrl
          if (player.uid != null && player.uid!.isNotEmpty && player.photoUrl == null) {
            try {
              DatabaseReference userRef =
                  FirebaseDatabase.instance.ref('/Users/${player.uid}/ProfileUrl');
              var urlSnap = await userRef.get();
              if (urlSnap.value != null) {
                player = player.copyWith(photoUrl: urlSnap.value.toString());
              }
            } catch (_) {}
          }

          players.add(player);
        }

        result[teamId] = players;
      }

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
          const stageOrder = {
            'group stage': 0,
            'quarterfinal': 1,
            'quarterfinals': 1,
            'semifinal': 2,
            'semifinals': 2,
            'final': 3,
            'championship': 3,
          };
          int maxOrder = 0;

          matchesNode.forEach((mKey, mValue) {
            if (mValue is! Map) return;
            final t1 = mValue['Team1Id']?.toString();
            final t2 = mValue['Team2Id']?.toString();
            if (t1 != teamId && t2 != teamId) return;
            final stage =
                (mValue['Stage']?.toString() ?? '').toLowerCase();
            final order = stageOrder[stage] ?? 0;
            if (order > maxOrder) {
              maxOrder = order;
              furthestStage =
                  mValue['Stage']?.toString() ?? 'Group Stage';
            }
            // Check if champion or runner-up
            if ((stage == 'final' || stage == 'championship') &&
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

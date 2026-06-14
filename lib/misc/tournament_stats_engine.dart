import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

/// Canonical event-type strings written to a match timeline. Kept in sync with
/// the Manager app's tournament_stats_engine.dart and the user-app icons.
class TournamentEvents {
  static const String goal = 'goal';
  static const String assist = 'assist';
  static const String save = 'save';
  static const String dpl = 'dpl';
  static const String yellowCard = 'yellow card';
  static const String redCard = 'red card';
  static const String secondYellow = 'second yellow';
  static const String ownGoal = 'own goal';
  static const String penaltyGoal = 'penalty goal';
  static const String penaltySaved = 'penalty saved';
  static const String penaltyMissed = 'penalty missed';
  static const String foul = 'foul';
  static const String substitution = 'substitution';
}

/// One team's standings row.
class TeamStanding {
  int gp = 0, w = 0, d = 0, l = 0, gs = 0, gc = 0, pts = 0;
  int get gd => gs - gc;
}

/// One player's counters.
class PlayerCounters {
  int goals = 0, assists = 0, saves = 0, dpl = 0, cleanSheets = 0,
      yellowCards = 0, redCards = 0;
}

/// Result of a recompute, with convenience accessors for the UI.
class ComputedTournamentStats {
  final Map<String, TeamStanding> standings; // teamId -> row
  final Map<String, Map<String, PlayerCounters>> players; // teamId -> name -> counters
  final Set<String> unknownPlayers;

  const ComputedTournamentStats({
    required this.standings,
    required this.players,
    required this.unknownPlayers,
  });

  /// Standing for a team, or a zero row if the team has no counted matches.
  TeamStanding standingFor(String teamId) =>
      standings[teamId] ?? TeamStanding();

  /// Derived stat value for a player by stat name (mirrors
  /// TournamentPlayer.statByName), reading the computed counters. 0 if unknown.
  int statByName(String teamId, String playerName, String stat) {
    final c = players[teamId]?[playerName];
    if (c == null) return 0;
    switch (stat) {
      case 'goals':
        return c.goals;
      case 'assists':
        return c.assists;
      case 'saves':
        return c.saves;
      case 'dpl':
        return c.dpl;
      case 'cleanSheets':
        return c.cleanSheets;
      case 'yellowCards':
        return c.yellowCards;
      case 'redCards':
        return c.redCards;
      case 'goalsAndAssists':
        return c.goals + c.assists;
      default:
        return 0;
    }
  }
}

/// Recomputes standings + player counters from LIVE (status 1) and FINISHED
/// (status 2) matches — so in-progress scores feed the table and leaders.
/// Upcoming (status 0) matches are ignored. Pure: no Firebase access.
ComputedTournamentStats computeTournamentStats({
  required List<TournamentMatch> matches,
  required Map<String, List<TournamentPlayer>> rosters,
}) {
  final standings = <String, TeamStanding>{};
  final players = <String, Map<String, PlayerCounters>>{};
  final unknown = <String>{};

  rosters.forEach((teamId, list) {
    standings.putIfAbsent(teamId, () => TeamStanding());
    final byName = players.putIfAbsent(teamId, () => {});
    for (final p in list) {
      byName.putIfAbsent(p.name, () => PlayerCounters());
    }
  });

  PlayerCounters? counterFor(String? teamId, String playerName) {
    if (teamId == null) return null;
    final byName = players[teamId];
    if (byName == null) {
      unknown.add('$teamId/$playerName');
      return null;
    }
    final c = byName[playerName];
    if (c == null) {
      unknown.add('$teamId/$playerName');
      return null;
    }
    return c;
  }

  void applyEvent(String? teamId, String type, String playerName) {
    final c = counterFor(teamId, playerName);
    if (c == null) return;
    switch (type.toLowerCase().trim()) {
      case TournamentEvents.goal:
      case TournamentEvents.penaltyGoal:
        c.goals++;
        break;
      case TournamentEvents.assist:
        c.assists++;
        break;
      case TournamentEvents.save:
      case TournamentEvents.penaltySaved:
        c.saves++;
        break;
      case TournamentEvents.dpl:
        c.dpl++;
        break;
      case TournamentEvents.yellowCard:
        c.yellowCards++;
        break;
      case TournamentEvents.redCard:
      case TournamentEvents.secondYellow:
        c.redCards++;
        break;
      // own goal, penalty missed, foul, substitution: timeline-only, no counter.
      default:
        break;
    }
  }

  for (final m in matches) {
    // KEY FAN DIFFERENCE vs Manager: include live (1) AND finished (2).
    if (m.status != 1 && m.status != 2) continue;
    final t1 = m.team1Id;
    final t2 = m.team2Id;
    if (t1 == null || t2 == null) continue;

    final st1 = standings.putIfAbsent(t1, () => TeamStanding());
    final st2 = standings.putIfAbsent(t2, () => TeamStanding());
    final s1 = m.team1Score;
    final s2 = m.team2Score;

    st1.gp++;
    st2.gp++;
    st1.gs += s1;
    st1.gc += s2;
    st2.gs += s2;
    st2.gc += s1;
    if (s1 > s2) {
      st1.w++;
      st1.pts += 3;
      st2.l++;
    } else if (s2 > s1) {
      st2.w++;
      st2.pts += 3;
      st1.l++;
    } else {
      st1.d++;
      st2.d++;
      st1.pts += 1;
      st2.pts += 1;
    }

    for (final e in _eventsFromActivity(m.team1Activity)) {
      applyEvent(t1, e.type, e.player);
    }
    for (final e in _eventsFromActivity(m.team2Activity)) {
      applyEvent(t2, e.type, e.player);
    }

    if (s2 == 0 && m.team1Keeper != null) {
      counterFor(t1, m.team1Keeper!)?.cleanSheets++;
    }
    if (s1 == 0 && m.team2Keeper != null) {
      counterFor(t2, m.team2Keeper!)?.cleanSheets++;
    }
  }

  return ComputedTournamentStats(
    standings: standings,
    players: players,
    unknownPlayers: unknown,
  );
}

/// Flattens a Team{N}Activity map into (type, player) records. Buckets may be
/// a List or an index-keyed Map; entries are {type: playerName}.
List<({String type, String player})> _eventsFromActivity(
    Map<String, dynamic>? activity) {
  final out = <({String type, String player})>[];
  if (activity == null) return out;

  void addFromEntry(dynamic entry) {
    if (entry is Map) {
      entry.forEach((k, v) {
        out.add((type: k.toString(), player: v.toString()));
      });
    }
  }

  activity.forEach((_, bucket) {
    if (bucket is List) {
      for (final entry in bucket) {
        addFromEntry(entry);
      }
    } else if (bucket is Map) {
      bucket.forEach((_, entry) => addFromEntry(entry));
    }
  });

  return out;
}

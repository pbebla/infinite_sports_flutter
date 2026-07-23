import 'package:infinite_sports_flutter/misc/league_sport_config.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart'
    show catchPercentage;
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

/// A single player's counters, generalized (P1) to a per-sport key→value
/// map so any sport in [LeagueSportConfig] gets tournament stat tracking
/// for free. Soccer/futsal keep their EXACT legacy RTDB key names
/// (Goals/Assists/Saves/DPL/CleanSheets/YellowCards/RedCards, via the
/// getters below) so existing consumers (TournamentPlayer, award_engine,
/// the fan app) keep reading the same fields unchanged. Basketball/Flag
/// Football write their [LeagueSportConfig.statCatalog] key names
/// directly (OnePoint/TwoPoints/.../QBComp/REC/...).
class PlayerCounters {
  final Map<String, int> _byKey = {};

  void bump(String key, [int by = 1]) =>
      _byKey[key] = (_byKey[key] ?? 0) + by;

  /// Zero-initializes every key in [keys] so a re-finalize always clears a
  /// stale value that no longer applies (the self-healing behavior the
  /// original fixed-field toMap() had for free).
  void seedZero(Iterable<String> keys) {
    for (final k in keys) {
      _byKey.putIfAbsent(k, () => 0);
    }
  }

  int byKey(String key) => _byKey[key] ?? 0;

  // ---- Legacy soccer/futsal getters — UNCHANGED key names ----
  int get goals => byKey('Goals');
  int get assists => byKey('Assists');
  int get saves => byKey('Saves');
  int get dpl => byKey('DPL');
  int get cleanSheets => byKey('CleanSheets');
  int get yellowCards => byKey('YellowCards');
  int get redCards => byKey('RedCards');

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_byKey);
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
      // P3 basketball/flag football derived stats (raw catalog keys live
      // on PlayerCounters directly via byKey; these are the UI-facing
      // combinations PlayerStatsTab/TeamDetail read).
      case 'points':
        return c.byKey('OnePoint') + 2 * c.byKey('TwoPoints') + 3 * c.byKey('ThreePoints');
      case 'freeThrows':
        return c.byKey('OnePoint');
      case 'twoPointers':
        return c.byKey('TwoPoints');
      case 'threePointers':
        return c.byKey('ThreePoints');
      case 'misses':
        return c.byKey('Misses');
      case 'rebounds':
        return c.byKey('Rebounds');
      case 'steals':
        return c.byKey('Steals');
      case 'blocks':
        return c.byKey('Blocks');
      case 'fouls':
        return c.byKey('Fouls');
      case 'turnovers':
        return c.byKey('Turnovers');
      case 'touchdowns':
        return c.byKey('RECTD') + c.byKey('RushTD') + c.byKey('INTTD');
      case 'receivingTouchdowns':
        return c.byKey('RECTD');
      case 'rushingTouchdowns':
        return c.byKey('RushTD');
      case 'interceptionTouchdowns':
        return c.byKey('INTTD');
      case 'passTouchdowns':
        return c.byKey('PassTD');
      case 'receptions':
        return c.byKey('REC');
      case 'interceptions':
        return c.byKey('INT');
      case 'flagPulls':
        return c.byKey('FP');
      case 'sacks':
        return c.byKey('Sack');
      case 'passBreakups':
        return c.byKey('PBU');
      case 'catchPercentage':
        return catchPercentage(c.byKey('REC'), c.byKey('RECMiss'), minTargets: 3) ?? 0;
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
  // Defaults to 'Soccer' so every existing call site (and every existing
  // test) keeps compiling and behaving identically without modification.
  String sport = 'Soccer',
}) {
  final standings = <String, TeamStanding>{};
  final players = <String, Map<String, PlayerCounters>>{};
  final unknown = <String>{};

  // P1: the zero-init key set is sport-specific — soccer/futsal keep the
  // exact legacy 7 keys (no 'Fouls' counter for tournaments — out of scope,
  // unchanged from today); basketball/flag football zero-init their full
  // stat catalog so a fix that removes an event always clears the stale
  // value.
  const legacySoccerKeys = [
    'Goals',
    'Assists',
    'Saves',
    'DPL',
    'CleanSheets',
    'YellowCards',
    'RedCards',
  ];
  final config = configForSport(sport);
  final zeroKeys = (sport == 'Basketball' || sport == 'Flag Football')
      ? (config?.statCatalog.map((s) => s.key).toList() ?? const <String>[])
      : legacySoccerKeys;

  rosters.forEach((teamId, list) {
    standings.putIfAbsent(teamId, () => TeamStanding());
    final byName = players.putIfAbsent(teamId, () => {});
    for (final p in list) {
      byName.putIfAbsent(p.name, () => PlayerCounters()..seedZero(zeroKeys));
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

  void applyEvent(String? teamId, String rawType, String playerName) {
    final c = counterFor(teamId, playerName);
    if (c == null) return;
    final canonical = canonicalEventType(sport, rawType);

    if (sport == 'Basketball' || sport == 'Flag Football') {
      // P1: fully config-driven — any sport added to LeagueSportConfig
      // gets tournament counters for free, no new switch case here.
      final event = config?.eventForActivity(canonical);
      if (event == null) return; // unknown/legacy: timeline-only
      for (final key in event.statKeys) {
        c.bump(key);
      }
      return;
    }

    // Soccer/Futsal — EXACT legacy mapping, now keyed off the canonical
    // type so both old and new spellings resolve identically.
    switch (canonical) {
      case 'Goal':
      case 'PenGoal':
        c.bump('Goals');
        break;
      case 'Assist':
        c.bump('Assists');
        break;
      case 'Save':
      case 'PenSaved':
        c.bump('Saves');
        break;
      case 'DPL':
        c.bump('DPL');
        break;
      case 'Yellow':
        c.bump('YellowCards');
        break;
      case 'Red':
      case 'SecondYellow':
        c.bump('RedCards');
        break;
      // OwnGoal, PenMissed, Foul, Substitution: timeline-only, no counter.
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

    // Clean sheets: keeper of a team that conceded zero gets +1 — only for
    // sports with a clean-sheet concept (config-driven via
    // cleanSheetStatKey, empty for basketball/flag football).
    final cleanSheetKey = config?.cleanSheetStatKey ?? '';
    if (cleanSheetKey.isNotEmpty) {
      if (s2 == 0 && m.team1Keeper != null) {
        counterFor(t1, m.team1Keeper!)?.bump(cleanSheetKey);
      }
      if (s1 == 0 && m.team2Keeper != null) {
        counterFor(t2, m.team2Keeper!)?.bump(cleanSheetKey);
      }
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

/// Standings display mode for [sport] — a pure function so adding a future
/// sport is a one-line switch case, not a screen-by-screen decision.
/// 'drawsAllowed' (soccer/futsal): W/D/L/GS/GC/GD/Pts. 'winsOnly'
/// (basketball/flag football, and any future sport not listed): W/L/PF/PA/
/// Diff — no D or Pts column. The underlying [TeamStanding] computation is
/// identical for every sport (see computeTournamentStats): a sport that
/// never draws sorts identically whether you rank by Pts or by wins, so
/// this only changes what the fan TableTab RENDERS, never what is computed.
String standingsModeFor(String sport) {
  switch (sport) {
    case 'Soccer':
    case 'Futsal':
      return 'drawsAllowed';
    default:
      return 'winsOnly';
  }
}

// Pure sport-config engine for the League Experience epic (L4+L5) — P1
// covers futsal capture. NO Flutter/Firebase imports: unit-tested
// directly, and designed to be duplicated byte-for-byte into the fan repo
// in P2 (same convention as registration_models).
//
// One capture screen (Manager) and one set of league screens (fan) are
// parameterized by a per-sport LeagueSportConfig: adding a future league
// sport = writing a config instance here, not building screens (spec §1).
// Basketball and flag football configs are pure additions in P4.

import 'package:infinite_sports_flutter/misc/match_clock.dart';

// ---------------------------------------------------------------------------
// Stat catalog
// ---------------------------------------------------------------------------

/// One stat in a sport's catalog: the RTDB player-stat key (under
/// `{sport}/{season}/Line Ups/{team}/{player}/`), its display name, and
/// the stat-icon id fan timelines/leaders render it with (P2 maps ids to
/// the bundled stat icons; the Manager only carries them).
class LeagueStatDef {
  final String key;
  final String label;
  final String iconId;

  const LeagueStatDef({
    required this.key,
    required this.label,
    required this.iconId,
  });
}

// ---------------------------------------------------------------------------
// Capture events
// ---------------------------------------------------------------------------

/// Chained follow-up prompts a capture event can trigger once the player
/// is known (spec §3 "chained two-player capture"). Config data — the
/// capture screen switches on this. P4 adds flag football's
/// receiver→thrower chain as a new value here.
enum LeagueChainedPrompt {
  none,

  /// Goal → "Assisted by?" (teammates + Guest + Skip).
  assistedBy,
}

/// One capture button: what it writes to the timeline, which player stats
/// it increments, and what it does to the score.
class LeagueEventDef {
  /// Activity type written under `team{n}activity/{minute}'` — also the
  /// event's identity in [LeagueSportConfig.eventForActivity]. Never
  /// empty in the futsal config; '' is reserved for future silent
  /// counters (spec §2 "timeline events vs. silent counters").
  final String activityType;

  /// Compact label for player-row buttons ('G', 'SV').
  final String shortLabel;

  /// Full label for top-bar buttons, pickers, and toasts ('⚽ Goal').
  final String label;

  /// Player-stat keys incremented once per tap, in order — every write
  /// goes through LineupService.incrementPlayerStatForGame so the
  /// StatLog journal (and therefore Reset) always sees it. Multiple keys
  /// express paired credits: PenGoal also bumps the scorer's Goals,
  /// PenSaved also bumps the keeper's Saves, SecondYellow also bumps Red.
  /// Empty = timeline/score only (Guest taps are forced to this at the
  /// call site).
  final List<String> statKeys;

  /// Score points added when recorded (0 = none).
  final int scorePoints;

  /// true → [scorePoints] go to the OPPOSING team (own goal). The
  /// timeline entry still lands on the tapped player's own team.
  final bool scoresOpponent;

  final LeagueChainedPrompt chained;

  const LeagueEventDef({
    required this.activityType,
    required this.shortLabel,
    required this.label,
    this.statKeys = const [],
    this.scorePoints = 0,
    this.scoresOpponent = false,
    this.chained = LeagueChainedPrompt.none,
  });

  bool get isTimelineEvent => activityType.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Per-sport config
// ---------------------------------------------------------------------------

/// Everything sport-specific the capture screen (and, in P2, the fan
/// league screens) needs.
class LeagueSportConfig {
  /// League root key in RTDB ('Futsal').
  final String sportKey;

  final List<LeagueStatDef> statCatalog;

  /// Buttons rendered on every player row, in order (1 tap = 1 event).
  final List<LeagueEventDef> rowEvents;

  /// Rare events in the top action bar (tap → player picker).
  final List<LeagueEventDef> topBarEvents;

  /// Stat key auto-credited to a team's picked keeper at Final when the
  /// team concedes 0 ('' = sport has no keeper/clean-sheet concept).
  final String cleanSheetStatKey;

  const LeagueSportConfig({
    required this.sportKey,
    required this.statCatalog,
    required this.rowEvents,
    required this.topBarEvents,
    this.cleanSheetStatKey = '',
  });

  /// The event that writes [activityType], searching row then top-bar
  /// events. null for legacy/unknown types (e.g. the retired league
  /// 'Blue') — callers treat those as timeline-only.
  LeagueEventDef? eventForActivity(String activityType) {
    for (final e in rowEvents) {
      if (e.activityType == activityType) return e;
    }
    for (final e in topBarEvents) {
      if (e.activityType == activityType) return e;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Futsal (P1) — owner-approved layout, spec §3 table
// ---------------------------------------------------------------------------

/// Futsal activity/stat vocabulary. Legacy types kept verbatim ('Goal',
/// 'Assist', 'Yellow', 'Red', 'Foul'); new types are additive and spelled
/// exactly like their stat keys. League 'Blue' is retired for NEW capture
/// — legacy Blue data still renders on fan and still reverses on reset.
class FutsalLeagueEvents {
  static const String goal = 'Goal';
  static const String assist = 'Assist';
  static const String save = 'Save';
  static const String dpl = 'DPL';
  static const String foul = 'Foul';
  static const String penGoal = 'PenGoal';
  static const String penMissed = 'PenMissed';
  static const String penSaved = 'PenSaved';
  static const String ownGoal = 'OwnGoal';
  static const String yellow = 'Yellow';
  static const String secondYellow = 'SecondYellow';
  static const String red = 'Red';
}

const LeagueSportConfig futsalLeagueConfig = LeagueSportConfig(
  sportKey: 'Futsal',
  cleanSheetStatKey: 'CleanSheets',
  statCatalog: [
    LeagueStatDef(key: 'Goals', label: 'Goals', iconId: 'goal'),
    LeagueStatDef(key: 'Assists', label: 'Assists', iconId: 'assist'),
    LeagueStatDef(key: 'Saves', label: 'Saves', iconId: 'save'),
    LeagueStatDef(key: 'DPL', label: 'Defensive Plays', iconId: 'dpl'),
    LeagueStatDef(key: 'Fouls', label: 'Fouls', iconId: 'foul'),
    LeagueStatDef(
        key: 'PenGoal', label: 'Penalty Goals', iconId: 'pen_goal'),
    LeagueStatDef(
        key: 'PenMissed', label: 'Penalties Missed', iconId: 'pen_missed'),
    LeagueStatDef(
        key: 'PenSaved', label: 'Penalties Saved', iconId: 'pen_saved'),
    LeagueStatDef(key: 'OwnGoal', label: 'Own Goals', iconId: 'own_goal'),
    LeagueStatDef(key: 'Yellow', label: 'Yellow Cards', iconId: 'yellow'),
    LeagueStatDef(
        key: 'SecondYellow', label: '2nd Yellows', iconId: 'second_yellow'),
    LeagueStatDef(key: 'Red', label: 'Red Cards', iconId: 'red'),
    LeagueStatDef(
        key: 'CleanSheets', label: 'Clean Sheets', iconId: 'clean_sheet'),
  ],
  rowEvents: [
    LeagueEventDef(
      activityType: FutsalLeagueEvents.goal,
      shortLabel: 'G',
      label: '⚽ Goal',
      statKeys: ['Goals'],
      scorePoints: 1,
      chained: LeagueChainedPrompt.assistedBy,
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.assist,
      shortLabel: 'A',
      label: '🅰 Assist',
      statKeys: ['Assists'],
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.save,
      shortLabel: 'SV',
      label: '🧤 Save',
      statKeys: ['Saves'],
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.dpl,
      shortLabel: 'DP',
      label: '🛡 DPL',
      statKeys: ['DPL'],
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.foul,
      shortLabel: 'F',
      label: '🦶 Foul',
      statKeys: ['Fouls'],
    ),
  ],
  topBarEvents: [
    LeagueEventDef(
      activityType: FutsalLeagueEvents.penGoal,
      shortLabel: 'PG',
      label: '⚽ Pen Goal',
      // Paired credit (amendment, verified against tournament behavior):
      // a penalty goal also counts into the scorer's Goals, exactly like
      // PenSaved's ['PenSaved', 'Saves'] pairing below — tournaments
      // tally 'penalty goal' into goals.
      statKeys: ['PenGoal', 'Goals'],
      scorePoints: 1,
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.penMissed,
      shortLabel: 'PM',
      label: '❌ Pen Missed',
      statKeys: ['PenMissed'],
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.penSaved,
      shortLabel: 'PS',
      label: '🧤 Pen Saved',
      statKeys: ['PenSaved', 'Saves'],
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.ownGoal,
      shortLabel: 'OG',
      label: '😬 Own Goal',
      statKeys: ['OwnGoal'],
      scorePoints: 1,
      scoresOpponent: true,
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.yellow,
      shortLabel: 'Y',
      label: '🟨 Yellow',
      statKeys: ['Yellow'],
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.secondYellow,
      shortLabel: '2Y',
      label: '🟨🟥 2nd Yellow',
      statKeys: ['SecondYellow', 'Red'],
    ),
    LeagueEventDef(
      activityType: FutsalLeagueEvents.red,
      shortLabel: 'R',
      label: '🟥 Red',
      statKeys: ['Red'],
    ),
  ],
);

// ---------------------------------------------------------------------------
// Capture helpers (pure): minute stamping, 2nd-yellow detect, recent
// events, undo score math
// ---------------------------------------------------------------------------

/// Match minute stamped on a recorded event: 1-based elapsed minute from
/// the persisted clock (tournament convention — 0:00–0:59 is minute 1),
/// or 0 when the clock was never started. There is NO time picker
/// anywhere (spec §3): stamped minutes always chain from the clock.
int captureMinute(MatchClock? clock, int nowMs) {
  if (clock == null) return 0;
  return clock.elapsedAt(nowMs).inMinutes + 1;
}

/// True when [activity] (one team's `team{n}activity` node) already holds
/// an [activityType] event for [playerName] — the league mirror of the
/// tournament's playerHasYellowCard (services/second_yellow_detector.dart,
/// which matches the TOURNAMENT type 'yellow card' and therefore cannot be
/// reused for league types like 'Yellow'). Types match case-insensitively
/// (trimmed); player names match trimmed. Buckets may be Lists or
/// index-keyed Maps (Firebase array collapsing).
bool playerHasLeagueActivity(
    Map<String, dynamic>? activity, String activityType, String playerName) {
  if (activity == null) return false;
  final wantedType = activityType.toLowerCase().trim();
  final wantedPlayer = playerName.trim();

  bool entryMatches(Map<String, dynamic> entry) {
    for (final e in entry.entries) {
      if (e.key.toLowerCase().trim() == wantedType &&
          e.value.toString().trim() == wantedPlayer) {
        return true;
      }
    }
    return false;
  }

  for (final bucket in activity.values) {
    for (final entry in _flattenBucket(bucket)) {
      if (entryMatches(entry)) return true;
    }
  }
  return false;
}

/// One recorded timeline event, located precisely enough to undo it
/// (same role as the tournament's RecordedStat in match_activity_editor).
class LeagueRecordedEvent {
  final int teamTag;

  /// Raw minute key as stored, e.g. "7'".
  final String minuteKey;

  /// Position within the minute bucket AFTER flattening (null holes
  /// skipped) — GameService.removeActivityAt flattens the same way, so
  /// display and removal always agree.
  final int index;

  final String activityType;
  final String player;

  const LeagueRecordedEvent({
    required this.teamTag,
    required this.minuteKey,
    required this.index,
    required this.activityType,
    required this.player,
  });
}

/// Normalizes one minute bucket (List OR index-keyed Map) into an ordered
/// list of `{activityType: player}` maps, skipping null holes — the
/// single source of truth for in-bucket ordering (mirrors the
/// tournament's flattenActivityBucket).
List<Map<String, dynamic>> _flattenBucket(dynamic bucket) {
  final out = <Map<String, dynamic>>[];
  void add(dynamic entry) {
    if (entry is Map) {
      out.add(entry.map((k, v) => MapEntry(k.toString(), v)));
    }
  }

  if (bucket is List) {
    for (final entry in bucket) {
      add(entry);
    }
  } else if (bucket is Map) {
    final keys = bucket.keys.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a.toString());
        final bi = int.tryParse(b.toString());
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.toString().compareTo(b.toString());
      });
    for (final k in keys) {
      add(bucket[k]);
    }
  }
  return out;
}

int _minuteOf(String minuteKey) =>
    int.tryParse(minuteKey.replaceAll("'", '').trim()) ?? 0;

/// Both teams' timelines flattened newest-first: highest minute first,
/// later-recorded first within a minute, team1 before team2 on exact
/// ties. Drives the pinned Recent-events undo strip (callers `.take(5)`).
List<LeagueRecordedEvent> recentLeagueEvents({
  required Map<String, dynamic>? team1Activity,
  required Map<String, dynamic>? team2Activity,
}) {
  final out = <LeagueRecordedEvent>[];

  void collect(int teamTag, Map<String, dynamic>? activity) {
    if (activity == null) return;
    activity.forEach((minuteKey, bucket) {
      final events = _flattenBucket(bucket);
      for (var i = 0; i < events.length; i++) {
        final e = events[i];
        if (e.isEmpty) continue;
        out.add(LeagueRecordedEvent(
          teamTag: teamTag,
          minuteKey: minuteKey.toString(),
          index: i,
          activityType: e.keys.first,
          player: e[e.keys.first].toString(),
        ));
      }
    });
  }

  collect(0, team1Activity);
  collect(1, team2Activity);

  out.sort((a, b) {
    final byMinute =
        _minuteOf(b.minuteKey).compareTo(_minuteOf(a.minuteKey));
    if (byMinute != 0) return byMinute;
    final byIndex = b.index.compareTo(a.index); // later-recorded first
    if (byIndex != 0) return byIndex;
    return a.teamTag.compareTo(b.teamTag);
  });
  return out;
}

/// The score change that undoes [activityType] recorded for [teamTag] —
/// the exact mirror of the event's forward scorePoints/scoresOpponent.
/// null when the event never scored (or is unknown/legacy, e.g. 'Blue').
({int teamTag, int delta})? undoScoreEffect(
    LeagueSportConfig config, String activityType, int teamTag) {
  final event = config.eventForActivity(activityType);
  if (event == null || event.scorePoints == 0) return null;
  final target = event.scoresOpponent ? 1 - teamTag : teamTag;
  return (teamTag: target, delta: -event.scorePoints);
}

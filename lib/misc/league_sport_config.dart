// Pure sport-config engine for the League Experience epic (L4+L5) — P1
// covers futsal capture. NO Flutter/Firebase imports: unit-tested
// directly, and designed to be duplicated byte-for-byte into the fan repo
// in P2 (same convention as registration_models).
//
// One capture screen (Manager) and one set of league screens (fan) are
// parameterized by a per-sport LeagueSportConfig: adding a future league
// sport = writing a config instance here, not building screens (spec §1).
// Basketball and flag football configs are pure additions in P4.

import 'package:infinite_sports_flutter/misc/activity_entry.dart';
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

  /// FF Rec TD → "Thrown by?" (the receiver's teammates + Skip; no Guest
  /// — a Guest QB earns no stats and the pairing would be noise). The
  /// capture page records the sport's chained-only 'Pass TD' event for
  /// the chosen QB at the SAME minute (P4).
  thrownBy,
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

  /// Events with NO button of their own — recorded only by a chained
  /// prompt (FF 'Pass TD') or present only in legacy data (FF 'Pass
  /// INT'). Kept resolvable so the undo strip / event editor / score
  /// math treat them like any other event (P4).
  final List<LeagueEventDef> chainedOnlyEvents;

  /// Stat key auto-credited to a team's picked keeper at Final when the
  /// team concedes 0 ('' = sport has no keeper/clean-sheet concept).
  final String cleanSheetStatKey;

  const LeagueSportConfig({
    required this.sportKey,
    required this.statCatalog,
    required this.rowEvents,
    required this.topBarEvents,
    this.chainedOnlyEvents = const [],
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
    for (final e in chainedOnlyEvents) {
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
// Basketball (P4) — owner-approved layout, spec §3 table
// ---------------------------------------------------------------------------

/// Basketball activity/stat vocabulary. Legacy types kept verbatim
/// ('OnePointer', 'TwoPointer', 'ThreePointer', 'Rebound', 'Foul'); new
/// types are additive singular event names with explicit stat keys.
/// 'Foul' was activity-only before P4 — it now counts into the NEW
/// 'Fouls' stat key (legacy pre-journal games clamp an absent counter at
/// 0 on reset, the futsal Fouls precedent).
class BasketballLeagueEvents {
  static const String onePointer = 'OnePointer';
  static const String twoPointer = 'TwoPointer';
  static const String threePointer = 'ThreePointer';
  static const String miss = 'Miss';
  static const String rebound = 'Rebound';
  static const String assist = 'Assist';
  static const String steal = 'Steal';
  static const String block = 'Block';
  static const String foul = 'Foul';
  static const String turnover = 'Turnover';
}

const LeagueSportConfig basketballLeagueConfig = LeagueSportConfig(
  sportKey: 'Basketball',
  statCatalog: [
    LeagueStatDef(
        key: 'OnePoint', label: 'Free Throws Made', iconId: 'onepointer'),
    LeagueStatDef(key: 'TwoPoints', label: '2-Pointers', iconId: 'twopointer'),
    LeagueStatDef(
        key: 'ThreePoints', label: '3-Pointers', iconId: 'threepointer'),
    LeagueStatDef(key: 'Misses', label: 'Misses', iconId: 'miss'),
    LeagueStatDef(key: 'Rebounds', label: 'Rebounds', iconId: 'rebound'),
    LeagueStatDef(key: 'Assists', label: 'Assists', iconId: 'assist'),
    LeagueStatDef(key: 'Steals', label: 'Steals', iconId: 'steal'),
    LeagueStatDef(key: 'Blocks', label: 'Blocks', iconId: 'block'),
    LeagueStatDef(key: 'Fouls', label: 'Fouls', iconId: 'foul'),
    LeagueStatDef(key: 'Turnovers', label: 'Turnovers', iconId: 'turnover'),
  ],
  rowEvents: [
    LeagueEventDef(
      activityType: BasketballLeagueEvents.onePointer,
      shortLabel: '+1',
      label: '🏀 Free Throw Made',
      statKeys: ['OnePoint'],
      scorePoints: 1,
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.twoPointer,
      shortLabel: '+2',
      label: '🏀 2-Pointer',
      statKeys: ['TwoPoints'],
      scorePoints: 2,
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.threePointer,
      shortLabel: '+3',
      label: '🏀 3-Pointer',
      statKeys: ['ThreePoints'],
      scorePoints: 3,
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.miss,
      shortLabel: 'M',
      label: '❌ Miss',
      statKeys: ['Misses'],
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.rebound,
      shortLabel: 'RB',
      label: '🔁 Rebound',
      statKeys: ['Rebounds'],
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.assist,
      shortLabel: 'A',
      label: '🅰 Assist',
      statKeys: ['Assists'],
    ),
  ],
  topBarEvents: [
    LeagueEventDef(
      activityType: BasketballLeagueEvents.steal,
      shortLabel: 'ST',
      label: '🖐 Steal',
      statKeys: ['Steals'],
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.block,
      shortLabel: 'BK',
      label: '🚫 Block',
      statKeys: ['Blocks'],
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.foul,
      shortLabel: 'F',
      label: '🦶 Foul',
      statKeys: ['Fouls'],
    ),
    LeagueEventDef(
      activityType: BasketballLeagueEvents.turnover,
      shortLabel: 'TO',
      label: '↪ Turnover',
      statKeys: ['Turnovers'],
    ),
  ],
);

// ---------------------------------------------------------------------------
// Flag Football (P4) — owner-approved layout, spec §3 table
// ---------------------------------------------------------------------------

/// Flag football activity/stat vocabulary. Legacy activity types kept
/// verbatim ('Pass TD', 'Pass INT', 'Receiving TD', 'Interception',
/// 'Sack', 'Rushing TD', 'INT TD'); new types are additive and spelled
/// exactly like their stat keys. All 17 legacy stat keys survive.
/// 'Pass INT' has NO button in the owner-locked layout — it lives in
/// chainedOnlyEvents so LEGACY entries still undo/reassign correctly.
class FlagFootballLeagueEvents {
  static const String qbComp = 'QBComp';
  static const String qbInc = 'QBInc';
  static const String rec = 'REC';
  static const String recMiss = 'RECMiss';
  static const String flagPull = 'FP';
  static const String recTd = 'Receiving TD';
  static const String rushTd = 'Rushing TD';
  static const String intTd = 'INT TD';
  static const String interception = 'Interception';
  static const String sack = 'Sack';
  static const String pbu = 'PBU';
  static const String pat1 = 'PAT1';
  static const String pat1Miss = 'PAT1Miss';
  static const String twoPt = 'TwoPT';
  static const String twoPtMiss = 'TwoPTMiss';
  static const String passTd = 'Pass TD';
  static const String passInt = 'Pass INT';
}

const LeagueSportConfig flagFootballLeagueConfig = LeagueSportConfig(
  sportKey: 'Flag Football',
  statCatalog: [
    LeagueStatDef(key: 'QBComp', label: 'Completions', iconId: 'qb_comp'),
    LeagueStatDef(key: 'QBInc', label: 'Incompletions', iconId: 'qb_inc'),
    LeagueStatDef(key: 'PassTD', label: 'Pass TDs', iconId: 'pass_td'),
    LeagueStatDef(
        key: 'PassINT', label: 'Pass INTs Thrown', iconId: 'pass_int'),
    LeagueStatDef(key: 'REC', label: 'Receptions', iconId: 'rec'),
    LeagueStatDef(key: 'RECMiss', label: 'Drops', iconId: 'rec_miss'),
    LeagueStatDef(key: 'RECTD', label: 'Receiving TDs', iconId: 'rec_td'),
    LeagueStatDef(key: 'INT', label: 'Interceptions', iconId: 'int'),
    LeagueStatDef(key: 'FP', label: 'Flag Pulls', iconId: 'flag_pull'),
    LeagueStatDef(key: 'Sack', label: 'Sacks', iconId: 'sack'),
    LeagueStatDef(key: 'PBU', label: 'Pass Breakups', iconId: 'pbu'),
    LeagueStatDef(key: 'RushTD', label: 'Rushing TDs', iconId: 'rush_td'),
    LeagueStatDef(key: 'INTTD', label: 'Pick-Sixes', iconId: 'int_td'),
    LeagueStatDef(key: 'PAT1', label: 'PAT Makes', iconId: 'pat'),
    LeagueStatDef(key: 'PAT1Miss', label: 'PAT Misses', iconId: 'pat_miss'),
    LeagueStatDef(key: 'TwoPT', label: '2PT Makes', iconId: 'two_pt'),
    LeagueStatDef(
        key: 'TwoPTMiss', label: '2PT Misses', iconId: 'two_pt_miss'),
  ],
  rowEvents: [
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.qbComp,
      shortLabel: 'CP',
      label: '🏈 Completion',
      statKeys: ['QBComp'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.qbInc,
      shortLabel: 'IC',
      label: '❌ Incompletion',
      statKeys: ['QBInc'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.rec,
      shortLabel: 'RC',
      label: '🙌 Reception',
      statKeys: ['REC'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.recMiss,
      shortLabel: 'DR',
      label: '😬 Drop',
      statKeys: ['RECMiss'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.flagPull,
      shortLabel: 'FP',
      label: '🚩 Flag Pull',
      statKeys: ['FP'],
    ),
  ],
  topBarEvents: [
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.recTd,
      shortLabel: 'RTD',
      label: '🏈 Rec TD',
      statKeys: ['RECTD'],
      scorePoints: 6,
      chained: LeagueChainedPrompt.thrownBy,
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.rushTd,
      shortLabel: 'RUTD',
      label: '🏃 Rush TD',
      statKeys: ['RushTD'],
      scorePoints: 6,
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.intTd,
      shortLabel: 'ITD',
      label: '🔄 INT TD',
      statKeys: ['INTTD'],
      scorePoints: 6,
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.interception,
      shortLabel: 'INT',
      label: '🖐 Interception',
      statKeys: ['INT'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.sack,
      shortLabel: 'SK',
      label: '💥 Sack',
      statKeys: ['Sack'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.pbu,
      shortLabel: 'PBU',
      label: '🛡 Pass Breakup',
      statKeys: ['PBU'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.pat1,
      shortLabel: 'PAT',
      label: '✅ PAT Made',
      statKeys: ['PAT1'],
      scorePoints: 1,
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.pat1Miss,
      shortLabel: 'PATx',
      label: '❌ PAT Missed',
      statKeys: ['PAT1Miss'],
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.twoPt,
      shortLabel: '2PT',
      label: '✅ 2PT Made',
      statKeys: ['TwoPT'],
      scorePoints: 2,
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.twoPtMiss,
      shortLabel: '2PTx',
      label: '❌ 2PT Missed',
      statKeys: ['TwoPTMiss'],
    ),
  ],
  chainedOnlyEvents: [
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.passTd,
      shortLabel: 'PTD',
      label: '🎯 Pass TD',
      statKeys: ['PassTD'],
      // The +6 rode on the Rec TD that chained here — never double-score.
    ),
    LeagueEventDef(
      activityType: FlagFootballLeagueEvents.passInt,
      shortLabel: 'PINT',
      label: '🎯 Pass INT',
      statKeys: ['PassINT'],
      // No button in the owner-locked P4 layout; resolvable for LEGACY
      // 'Pass INT' entries (undo/reassign parity with the reset fallback).
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
      if (isActivityMetadataKey(e.key)) continue; // `_t` stamps (P2.1)
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

  /// Insertion stamp (`_t`, epoch ms) carried by events recorded since
  /// P2.1 — orders same-minute events across teams in true record order.
  /// null for legacy entries.
  final int? tsMs;

  const LeagueRecordedEvent({
    required this.teamTag,
    required this.minuteKey,
    required this.index,
    required this.activityType,
    required this.player,
    this.tsMs,
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
/// later-recorded first within a minute (by `_t` insertion stamp when
/// both events carry one — the only ordering that sees ACROSS teams —
/// else by in-bucket index), team1 before team2 on exact ties. Drives
/// the pinned Recent-events undo strip (callers `.take(5)`).
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
        final event = activityEventOf(e);
        if (event == null) continue; // empty or metadata-only leaf
        final ts = e['_t'];
        out.add(LeagueRecordedEvent(
          teamTag: teamTag,
          minuteKey: minuteKey.toString(),
          index: i,
          activityType: event.key,
          player: event.value.toString(),
          tsMs: ts is num ? ts.toInt() : null,
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
    // `_t` stamps (P2.1) give true record order across teams; legacy
    // entries without one fall back to index/team order.
    final at = a.tsMs, bt = b.tsMs;
    if (at != null && bt != null && at != bt) {
      return bt.compareTo(at); // later-recorded first
    }
    final byIndex = b.index.compareTo(a.index); // later-recorded first
    if (byIndex != 0) return byIndex;
    return a.teamTag.compareTo(b.teamTag);
  });
  return out;
}

/// One stat mutation in a reassign plan: apply [delta] (-1 take from the
/// old player, +1 give to the new player) to [statKey] for [player].
typedef LeagueStatMove = ({String player, String statKey, int delta});

/// The stat moves that re-credit an [activityType] event from [oldPlayer]
/// to [newPlayer] on the SAME team (the full event editor's Reassign,
/// P2.1 Task B3): all of the event's statKeys are decremented for the old
/// player, then incremented for the new one — paired credits (PenGoal's
/// Goals, SecondYellow's Red) follow statKeys automatically. The score is
/// never part of the plan: the event stays on the same team.
///
/// Gating mirrors capture/undo exactly:
/// - friendly games never accrue stats → empty plan;
/// - Guest never holds stats → reassigning TO Guest only decrements the
///   old player, FROM Guest only increments the new one;
/// - unknown/legacy types (e.g. 'Blue') are timeline-only → empty plan;
/// - same-player reassigns are no-ops.
List<LeagueStatMove> reassignStatMoves(
  LeagueSportConfig config,
  String activityType,
  String oldPlayer,
  String newPlayer, {
  required bool isFriendly,
}) {
  if (isFriendly || oldPlayer == newPlayer) return const [];
  final event = config.eventForActivity(activityType);
  if (event == null) return const [];
  return [
    if (oldPlayer != 'Guest')
      for (final k in event.statKeys)
        (player: oldPlayer, statKey: k, delta: -1),
    if (newPlayer != 'Guest')
      for (final k in event.statKeys)
        (player: newPlayer, statKey: k, delta: 1),
  ];
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

// ---------------------------------------------------------------------------
// Tournament sport-config resolution + spelling bridge (Tournaments-for-All-
// Sports epic, P1). Additive to this twin file (kept byte-identical except
// imports) — the file is no longer frozen the way L6 froze it, because this
// epic's whole point is teaching tournaments to read the SAME per-sport
// config leagues already use.
// ---------------------------------------------------------------------------

/// Resolves a Tournament's sport string to its [LeagueSportConfig]. 'Soccer'
/// shares Futsal's vocabulary (identical ruleset family — tournaments have
/// always treated them the same way NotificationsMeta/vocab-wise). Unknown
/// sports (e.g. a future Volleyball before its config lands) return null so
/// callers fall back to legacy/unconfigured behavior instead of crashing.
LeagueSportConfig? configForSport(String sport) {
  switch (sport) {
    case 'Futsal':
    case 'Soccer':
      return futsalLeagueConfig;
    case 'Basketball':
      return basketballLeagueConfig;
    case 'Flag Football':
      return flagFootballLeagueConfig;
    default:
      return null;
  }
}

/// Legacy TOURNAMENT activity spellings (spaced, lowercase — written by the
/// pre-unification pick-stat capture flow) -> the canonical league spelling
/// used by [LeagueSportConfig] going forward. Basketball/Flag Football have
/// no legacy tournament data (tournaments never supported them before this
/// epic), so they need no entries here — canonicalEventType folds their
/// case via the config scan below instead.
const Map<String, String> _legacyTournamentEventSpellings = {
  'goal': 'Goal',
  'penalty goal': 'PenGoal',
  'penalty saved': 'PenSaved',
  'penalty missed': 'PenMissed',
  'own goal': 'OwnGoal',
  'yellow card': 'Yellow',
  'second yellow': 'SecondYellow',
  'red card': 'Red',
  'assist': 'Assist',
  'save': 'Save',
  'dpl': 'DPL',
  'foul': 'Foul',
  'substitution': 'Substitution',
};

/// Normalizes a raw activity-type string (as read off Firebase, in either
/// its legacy tournament spelling OR its canonical league spelling, in any
/// case) to the canonical [LeagueSportConfig] spelling for [sport]. Every
/// consumer that used to switch on hardcoded tournament spellings
/// (engines, icons, undo, second-yellow detection, notification watchers)
/// should run raw types through this FIRST so old and new data behave
/// identically. Unknown/legacy-only types (e.g. the retired league 'Blue')
/// pass through trimmed but otherwise unchanged — callers that need to
/// know "is this a real event" still call [LeagueSportConfig.eventForActivity]
/// on the result and get null, exactly as today. Pure — no Firebase.
String canonicalEventType(String sport, String raw) {
  final trimmed = raw.trim();
  final lower = trimmed.toLowerCase();

  final config = configForSport(sport);
  if (config != null) {
    for (final e in [
      ...config.rowEvents,
      ...config.topBarEvents,
      ...config.chainedOnlyEvents,
    ]) {
      if (e.activityType.toLowerCase() == lower) return e.activityType;
    }
  }

  final legacy = _legacyTournamentEventSpellings[lower];
  if (legacy != null) return legacy;

  return trimmed;
}

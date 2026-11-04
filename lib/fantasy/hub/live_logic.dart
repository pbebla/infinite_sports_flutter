// The locked My Team's pure logic (live everywhere, Task 5) — no Flutter, no
// Firebase calls, unit-tested in test/fantasy/live_logic_test.dart.
//
// While a gameweek is locked, My Team swaps its edit header for a strip that
// says what the week is doing, and every court chip carries that player's
// counted points. Everything the screen shows comes from [resolveLockedWeek],
// over the four small sources of the locked week:
//
//   LIVE (the week is being played):   Live/Squads/<uid> (the squad's points
//     and one counted row per pick) + the live feed's Players (a status per
//     player) and Board (the Overall rank and movement).
//   SETTLED (finalize has run, until editing reopens): History/<gw>/<uid> (net
//     tenths + the same per-pick rows) + the official Overall rank.
//   Never `Squads/<uid>` for points — that is what the manager SAVED, not
//   what the week scored.
//
// "Voided" comes from the Voided set (what the server reads) or the History
// mirror — never from a live record: in a voided week the live per-player
// record reads "not voided, GP 0" (Task 4 review).
//
// THE COPY is the plan's, verbatim (live_logic_test.dart pins every string).
// When nothing is known yet (before the first game started, or no feed has
// answered), the honest default is "Locked · waiting for kickoff" — a
// number is never made up.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart'
    show movementLabel;
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart'
    show squadEditable;

// ── The strip ──────────────────────────────────────────────────────────────

/// What a locked week is doing for this manager.
enum LockedWeekKind {
  /// Nothing known yet: before the first game started.
  waiting,

  /// Games are being played; the numbers are provisional.
  live,

  /// Finalize has run; the numbers are the official ones.
  settled,

  /// The owner voided the week: it counts 0.
  voided,

  /// The squad was judged illegal at the lock: it scored 0.
  invalid,
}

/// The strip's content for one locked week.
class LockedWeekView {
  const LockedWeekView._(this.kind,
      {this.weekPoints, this.rank, this.movement});

  const LockedWeekView.waiting() : this._(LockedWeekKind.waiting);

  /// [weekPoints] the squad's whole points so far, [rank] the Overall rank
  /// with them and [movement] the places climbed (null/0 = not shown).
  const LockedWeekView.live({required int weekPoints, int? rank, int? movement})
      : this._(LockedWeekKind.live,
            weekPoints: weekPoints, rank: rank, movement: movement);

  /// The official numbers: [weekPoints] the net whole points, [rank] the
  /// Overall rank (the settled copy has no movement).
  const LockedWeekView.settled(
      {required int weekPoints, int? rank, int? movement})
      : this._(LockedWeekKind.settled,
            weekPoints: weekPoints, rank: rank, movement: movement);

  const LockedWeekView.voided() : this._(LockedWeekKind.voided);

  const LockedWeekView.invalid() : this._(LockedWeekKind.invalid);

  final LockedWeekKind kind;
  final int? weekPoints;
  final int? rank;
  final int? movement;

  /// The LIVE pill shows only while the numbers are live.
  bool get isLive => kind == LockedWeekKind.live;
}

/// The strip text split so the screen can colour the movement: [main] and,
/// only for a live week whose rank moved, [movement] ("▲2" / "▼1" — the
/// leaderboard's own [movementLabel]).
({String main, String? movement}) lockedStripParts(LockedWeekView v) {
  final rank = v.rank == null ? '' : ' · #${v.rank}';
  switch (v.kind) {
    case LockedWeekKind.waiting:
      return (main: 'Locked · waiting for kickoff', movement: null);
    case LockedWeekKind.live:
      final m = v.movement;
      return (
        main: '${v.weekPoints} pts$rank',
        movement: m == null || m == 0 ? null : movementLabel(m),
      );
    case LockedWeekKind.settled:
      return (main: 'Final · ${v.weekPoints} pts$rank', movement: null);
    case LockedWeekKind.voided:
      return (main: 'Voided · this week counts 0', movement: null);
    case LockedWeekKind.invalid:
      return (main: "0 pts · this week didn't count", movement: null);
  }
}

/// The strip's whole text (see the file header for every case):
/// `Locked · waiting for kickoff` · `34 pts · #5 ▲2` (live; the pill renders
/// separately) · `Final · 34 pts · #5` · `Voided · this week counts 0` ·
/// `0 pts · this week didn't count`.
String lockedStripText(LockedWeekView v) {
  final parts = lockedStripParts(v);
  return parts.movement == null
      ? parts.main
      : '${parts.main} ${parts.movement}';
}

// ── The chip ───────────────────────────────────────────────────────────────

/// Tenths of a point → "8", "2.5", "-0.5": one decimal only when not whole
/// (a bench player's half points).
String _points(int tenths) =>
    tenths % 10 == 0 ? '${tenths ~/ 10}' : (tenths / 10).toStringAsFixed(1);

/// A court chip's week line for one player: `Not started` · `{pts} pts · live`
/// · `{pts} pts` · `Out`. [slot] is his counted row (the captain's multiplier,
/// the bench factor and any auto-sub already applied); null (he is not in the
/// squad's rows) → no text.
String? chipWeekText(LiveSlot? slot, LivePlayerStatus st) {
  if (slot == null) return null;
  return switch (st) {
    LivePlayerStatus.pending => 'Not started',
    LivePlayerStatus.live => '${_points(slot.countedTenths)} pts · live',
    LivePlayerStatus.done => '${_points(slot.countedTenths)} pts',
    LivePlayerStatus.out => 'Out',
  };
}

// ── The sources → the view ─────────────────────────────────────────────────

/// What the locked week's feed holds right now (everything optional: a
/// source that has not answered, or has nothing, is simply absent).
class LockedWeekSources {
  const LockedWeekSources({
    this.live = FantasyLiveState.none,
    this.liveSquad,
    this.history,
    this.overall,
  });

  /// The season's live gameweek (Meta + Board + Players).
  final FantasyLiveState live;

  /// The manager's own `Live/Squads/<uid>`.
  final LiveSquad? liveSquad;

  /// The manager's own settled `History/<gw>/<uid>`.
  final HistoryWeek? history;

  /// The manager's official `Leaderboards/Overall/<uid>` row.
  final OverallStanding? overall;
}

/// What the locked My Team shows: the strip's [view] and each pick's chip
/// text by player id (empty when nothing counts yet or the week is void).
class LockedWeekModel {
  const LockedWeekModel({required this.view, this.chipTexts = const {}});

  final LockedWeekView view;
  final Map<String, String> chipTexts;

  String? chipTextFor(String playerId) => chipTexts[playerId];
}

/// The ONE place the locked week's numbers are decided, in this order:
///
/// 1. Voided — the `Voided` set ([voidedWeeks]) or History's own flag: it
///    counts 0, so no chip shows points.
/// 2. Live — the live meta is this week's AND still `live` ([liveAppliesTo];
///    a settled tombstone overlays nothing) and the manager has a live squad:
///    its points, the live board's rank and movement, a chip text per pick
///    from that player's live status. A live squad with no rows is an invalid
///    squad (a valid one always has its picks).
/// 3. Settled — `History/<gw>/<uid>` with its net tenths: Final, the official
///    rank, every chip "done". Invalid by History's marker.
/// 4. Otherwise nothing is known: waiting.
LockedWeekModel resolveLockedWeek({
  required int week,
  required String? uid,
  required Set<int> voidedWeeks,
  required LockedWeekSources sources,
}) {
  final history = sources.history;
  if (voidedWeeks.contains(week) || (history?.voided ?? false)) {
    return const LockedWeekModel(view: LockedWeekView.voided());
  }

  final live = sources.live;
  final squad = sources.liveSquad;
  if (squad != null && liveAppliesTo(meta: live.meta, week: week)) {
    if (squad.slots.isEmpty) {
      return const LockedWeekModel(view: LockedWeekView.invalid());
    }
    final row = uid == null ? null : live.board[uid];
    return LockedWeekModel(
      view: LockedWeekView.live(
          weekPoints: squad.week, rank: row?.r, movement: row?.m),
      chipTexts: _chipTexts(
          squad.slots, (id) => live.players[id]?.st ?? LivePlayerStatus.done),
    );
  }

  if (history != null) {
    if (history.invalid) {
      return const LockedWeekModel(view: LockedWeekView.invalid());
    }
    final tenths = history.totalTenths;
    if (tenths != null) {
      return LockedWeekModel(
        // Whole points truncate toward zero, like the server's wholePoints.
        view: LockedWeekView.settled(
            weekPoints: tenths ~/ 10, rank: sources.overall?.rank),
        chipTexts: _chipTexts(history.slots, (_) => LivePlayerStatus.done),
      );
    }
  }

  return const LockedWeekModel(view: LockedWeekView.waiting());
}

Map<String, String> _chipTexts(
    List<LiveSlot> slots, LivePlayerStatus Function(String id) statusOf) {
  final out = <String, String>{};
  for (final slot in slots) {
    final text = chipWeekText(slot, statusOf(slot.playerId));
    if (text != null) out[slot.playerId] = text;
  }
  return out;
}

// ── Which week is locked, and when that changes ────────────────────────────

/// The gameweek My Team is locked on — the one the builder shows while it
/// cannot be edited ([squadEditable] false: the owner's lock override, or the
/// current gameweek past its lock). That is the current gameweek (from its
/// lock to the end of its lock day) and, with the season over, the last one
/// (final). null = editing is open, or the schedule is not known yet (never
/// guessed).
int? lockedWeekNumber({
  required FantasyLockOverride lockOverride,
  required List<Gameweek>? gameweeks,
  required DateTime nowUtc,
}) {
  if (gameweeks == null || gameweeks.isEmpty) return null;
  if (squadEditable(
      lockOverride: lockOverride, gameweeks: gameweeks, nowUtc: nowUtc)) {
    return null;
  }
  return (currentGameweek(gameweeks, nowUtc) ?? gameweeks.last).number;
}

/// The next instant the clock alone moves the locked week: the current
/// gameweek's lock while it is open, the end of its lock day (editing
/// reopens on the next gameweek) once it has locked. null = never (season
/// over, or no schedule).
DateTime? nextLockTransition(List<Gameweek> gameweeks, DateTime nowUtc) {
  final current = currentGameweek(gameweeks, nowUtc);
  if (current == null) return null;
  return nowUtc.isBefore(current.lockUtc)
      ? current.lockUtc
      : current.lockUtc.add(const Duration(hours: 24));
}

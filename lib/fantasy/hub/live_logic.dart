// The locked My Team's pure logic (live everywhere, Task 5) — no Flutter, no
// Firebase calls, unit-tested in test/fantasy/live_logic_test.dart.
//
// While a gameweek is locked, My Team swaps its edit header for a strip that
// says what the week is doing, and every court chip carries that player's
// counted points. Everything the screen shows comes from [resolveLockedWeek],
// over the small sources of the locked week:
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
// THE COURT is the squad that was LOCKED, never `Squads/<uid>`: the server
// rewrites that after finalize (the spent chip switched off, so a Triple
// Captain week would read ×2 beside a tripled total; a Free Hit manager's
// squad restored to last week's) and it keeps a chip the lock voided. Live →
// `PublishedPicks/<gw>/<uid>` (the lock's snapshot); settled →
// `History/<gw>/<uid>`'s own squad. The armband and the nameplate multiplier
// come from it too, and a chip line is only ever shown for a player IN it —
// with no locked squad loaded the court falls back to the draft's and shows
// no lines.
//
// THE COPY is the plan's, verbatim (live_logic_test.dart pins every string).
// "Locked · waiting for kickoff" is said ONLY for the genuine before-kickoff
// state: every stream answered cleanly and nothing says a game has started.
// A failed or unknown load, or a started week we cannot read, says exactly
// "Locked". A number is never made up.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart'
    show movementLabel;
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart'
    show squadEditable;

// ── The strip ──────────────────────────────────────────────────────────────

/// What a locked week is doing for this manager.
enum LockedWeekKind {
  /// Before the first game started: everything was read and nothing is on.
  waiting,

  /// We cannot say more than "locked": a load failed or has not answered, or
  /// a game has started and the week cannot be read (no squad, no History).
  unknown,

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

  const LockedWeekView.unknown() : this._(LockedWeekKind.unknown);

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
    case LockedWeekKind.unknown:
      return (main: 'Locked', movement: null);
    case LockedWeekKind.live:
      final m = v.movement;
      return (
        main: '${pointsText(v.weekPoints!)}$rank',
        movement: m == null || m == 0 ? null : movementLabel(m),
      );
    case LockedWeekKind.settled:
      return (
        main: 'Final · ${pointsText(v.weekPoints!)}$rank',
        movement: null
      );
    case LockedWeekKind.voided:
      return (main: 'Voided · this week counts 0', movement: null);
    case LockedWeekKind.invalid:
      return (main: "0 pts · this week didn't count", movement: null);
  }
}

/// The strip's whole text (see the file header for every case):
/// `Locked · waiting for kickoff` · `Locked` (a week we cannot read) ·
/// `34 pts · #5 ▲2` (live; the pill renders separately) ·
/// `Final · 34 pts · #5` · `Voided · this week counts 0` ·
/// `0 pts · this week didn't count`.
String lockedStripText(LockedWeekView v) {
  final parts = lockedStripParts(v);
  return parts.movement == null
      ? parts.main
      : '${parts.main} ${parts.movement}';
}

/// The manager squad viewer's week line (Task 7) for the same [LockedWeekView]:
/// `{W} pts` while the week is live (the pill renders beside it), `Final · {W}
/// pts` once settled, and My Team's own copy for a voided or invalid week. No
/// rank or movement — the viewer is about the squad, not the table. null = a
/// week we cannot read yet, or before kickoff: no line at all.
({String text, bool live})? viewerWeekStrip(LockedWeekView v) {
  switch (v.kind) {
    case LockedWeekKind.live:
      return (text: pointsText(v.weekPoints!), live: true);
    case LockedWeekKind.settled:
      return (text: 'Final · ${pointsText(v.weekPoints!)}', live: false);
    case LockedWeekKind.voided:
    case LockedWeekKind.invalid:
      return (text: lockedStripText(v), live: false);
    case LockedWeekKind.waiting:
    case LockedWeekKind.unknown:
      return null;
  }
}

// ── The banners ────────────────────────────────────────────────────────────

/// The hub banner's and the front page banner's live line, verbatim from the
/// plan: `GW{n} live · {W} pts · #{R}` — the live week, this manager's whole
/// points so far and his Overall rank with them, both from HIS row of the live
/// board. null in every other case, and the banner then stays exactly as it
/// was: no live week (none, another week's tombstone), nobody signed in, no
/// row for him, or no points this week (`W` absent = no squad scored this
/// week; a real 0 is a number and shows). A week the owner VOIDED counts 0
/// for everyone (the live board says 0 pts · #1 for all): the Voided set
/// ([voidedWeeks], never the live record) takes the line away, like the My
/// Team strip's "Voided · this week counts 0".
String? liveBannerLine({
  required FantasyLiveState live,
  required String? uid,
  Set<int> voidedWeeks = const {},
}) {
  final week = live.liveWeek;
  if (week == null || uid == null || uid.isEmpty) return null;
  if (voidedWeeks.contains(week)) return null;
  final row = live.board[uid];
  final points = row?.w;
  if (row == null || points == null) return null;
  return 'GW$week live · ${pointsText(points)} · #${row.r}';
}

/// The front page banner's line once the locked [week] has SETTLED (owner
/// 2026-11-04): `GW{n} final · {W} pts · #{R}` — exactly My Team's settled
/// strip ([resolveLockedWeek] decides): his own `History/<gw>/<uid>` net
/// points and his official Overall rank (left off when unknown). null — the
/// banner keeps its locked line — before finalize (no History), for a week
/// the owner voided (the Voided set or History's own flag) or a squad judged
/// invalid: both count 0 and My Team says why.
String? finalBannerLine({
  required int week,
  required String? uid,
  required HistoryWeek? history,
  required OverallStanding? overall,
  required Set<int> voidedWeeks,
}) {
  final view = resolveLockedWeek(
    week: week,
    uid: uid,
    voidedWeeks: voidedWeeks,
    sources: LockedWeekSources(history: history, overall: overall),
  ).view;
  if (view.kind != LockedWeekKind.settled) return null;
  final rank = view.rank == null ? '' : ' · #${view.rank}';
  return 'GW$week final · ${pointsText(view.weekPoints!)}$rank';
}

/// The match tab's line under its header, verbatim from the plan: `Your
/// gameweek so far: {W} pts · #{R}` — this manager's whole points so far this
/// gameweek and his Overall rank with them, both from HIS row of the live
/// board. Only while THIS game's gameweek ([week]) is the live one
/// ([liveAppliesTo]: no live node, another week or the settled tombstone say
/// nothing); null otherwise, and also for nobody signed in, no row for him, no
/// points this week (`W` absent = no squad scored; a real 0 is a number and
/// shows), a week the owner VOIDED (the live board says 0 pts · #1 for all of
/// them — the Voided set, never the live record, decides) and an UNKNOWN Voided
/// set ([voidedWeeks] null: its feed failed or has not answered — never read
/// as "none voided").
String? matchWeekStrip({
  required FantasyLiveState live,
  required int? week,
  required String? uid,
  required Set<int>? voidedWeeks,
}) {
  if (week == null || uid == null || uid.isEmpty) return null;
  if (voidedWeeks == null || voidedWeeks.contains(week)) return null;
  if (!liveAppliesTo(meta: live.meta, week: week)) return null;
  final row = live.board[uid];
  final points = row?.w;
  if (row == null || points == null) return null;
  return 'Your gameweek so far: ${pointsText(points)} · #${row.r}';
}

// ── The chip ───────────────────────────────────────────────────────────────

/// A court chip's week line for one player: `Not started` · `{pts} pts · live`
/// · `{pts} pts` · `Out` — the unit agrees with the count (`1 pt`; a bench
/// player's half points stay `2.5 pts`, fantasy_format.pointsTenthsText). [slot] is his counted row (the captain's multiplier,
/// the bench factor and any auto-sub already applied); null (he is not in the
/// squad's rows) → no text.
String? chipWeekText(LiveSlot? slot, LivePlayerStatus st) {
  if (slot == null) return null;
  return switch (st) {
    LivePlayerStatus.pending => 'Not started',
    LivePlayerStatus.live => '${pointsTenthsText(slot.countedTenths)} · live',
    LivePlayerStatus.done => pointsTenthsText(slot.countedTenths),
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
    this.published,
    this.overall,
    this.complete = true,
  });

  /// The season's live gameweek (Meta + Board + Players).
  final FantasyLiveState live;

  /// The manager's own `Live/Squads/<uid>`.
  final LiveSquad? liveSquad;

  /// The manager's own settled `History/<gw>/<uid>`.
  final HistoryWeek? history;

  /// The squad that was LOCKED: his `PublishedPicks/<gw>/<uid>`.
  final FantasySquad? published;

  /// The manager's official `Leaderboards/Overall/<uid>` row.
  final OverallStanding? overall;

  /// Every stream answered and none failed: what is absent really is absent.
  /// false = a load failed or has not answered, so an empty source says
  /// nothing (the strip then says only "Locked").
  final bool complete;
}

/// What the locked My Team shows: the strip's [view], the squad to draw the
/// court from ([squad]: the one that was LOCKED — null until it has loaded, the
/// court then falls back to the draft's) and each pick's chip text by player
/// id (empty when nothing counts yet, the week is void, or no locked squad is
/// known to own the lines).
class LockedWeekModel {
  const LockedWeekModel({
    required this.view,
    this.chipTexts = const {},
    this.squad,
  });

  final LockedWeekView view;
  final Map<String, String> chipTexts;

  /// The squad that was locked for the week (PublishedPicks while live,
  /// History once settled): the court's picks, armband and chip.
  final FantasySquad? squad;

  String? chipTextFor(String playerId) => chipTexts[playerId];
}

/// The ONE place the locked week's numbers are decided, in this order:
///
/// 1. Voided — the `Voided` set ([voidedWeeks]) or History's own flag: it
///    counts 0, so no chip shows points.
/// 2. Live — the live meta is this week's AND still `live` ([liveAppliesTo];
///    a settled tombstone overlays nothing) and the manager has a live squad:
///    its points, the live board's rank and movement, a chip text per pick
///    from that player's live status (a player whose status is unknown shows
///    no line — never a defaulted "0 pts"). A live squad with no rows is an
///    invalid squad (a valid one always has its picks).
/// 3. Settled — `History/<gw>/<uid>` with its net tenths: Final, the official
///    rank, every chip "done". Invalid by History's marker.
/// 4. Otherwise: "waiting for kickoff" only when every stream answered cleanly
///    ([LockedWeekSources.complete]) and nothing says a game of this week has
///    started (no live meta of this week, no History, no live squad of his
///    beside an unreadable live meta); else exactly "Locked".
///
/// The court's squad is the one that was LOCKED — PublishedPicks while the
/// week is live, History's own squad once it has settled, each falling back
/// to the other — and the chip lines are filtered to the players in it; with
/// none loaded there is no squad and no line.
LockedWeekModel resolveLockedWeek({
  required int week,
  required String? uid,
  required Set<int> voidedWeeks,
  required LockedWeekSources sources,
}) {
  final history = sources.history;
  final live = sources.live;
  final liveApplies = liveAppliesTo(meta: live.meta, week: week);
  final locked = liveApplies
      ? (sources.published ?? history?.squad)
      : (history?.squad ?? sources.published);

  LockedWeekModel model(LockedWeekView view,
      [Map<String, String> texts = const {}]) {
    // A line only belongs to a player in the squad on screen.
    final ids = {
      for (final p in locked?.picks ?? const <SquadPick>[]) p.playerId
    };
    return LockedWeekModel(
      view: view,
      squad: locked,
      chipTexts: {
        for (final e in texts.entries)
          if (ids.contains(e.key)) e.key: e.value,
      },
    );
  }

  if (voidedWeeks.contains(week) || (history?.voided ?? false)) {
    return model(const LockedWeekView.voided());
  }

  final squad = sources.liveSquad;
  if (squad != null && liveApplies) {
    if (squad.slots.isEmpty) return model(const LockedWeekView.invalid());
    final row = uid == null ? null : live.board[uid];
    return model(
      LockedWeekView.live(
          weekPoints: squad.week, rank: row?.r, movement: row?.m),
      _chipTexts(squad.slots, (id) => live.players[id]?.st),
    );
  }

  if (history != null) {
    if (history.invalid) return model(const LockedWeekView.invalid());
    final tenths = history.totalTenths;
    if (tenths != null) {
      return model(
        // Whole points truncate toward zero, like the server's wholePoints.
        LockedWeekView.settled(
            weekPoints: tenths ~/ 10, rank: sources.overall?.rank),
        _chipTexts(history.slots, (_) => LivePlayerStatus.done),
      );
    }
  }

  // Nothing readable. Before kickoff only if everything was read and nothing
  // says a game has started; otherwise all we know is that it is locked. His
  // own live squad with NO live meta (the live feed failed — it then answers
  // "no live week", not an error) says a week is being played: never "waiting
  // for kickoff" during games. With another week's meta known, the live squad
  // is that week's and says nothing about this one.
  final started = live.meta?.gw == week ||
      history != null ||
      (live.meta == null && sources.liveSquad != null);
  return model(sources.complete && !started
      ? const LockedWeekView.waiting()
      : const LockedWeekView.unknown());
}

/// A chip text per slot; a player whose status is unknown ([statusOf] null)
/// gets none.
Map<String, String> _chipTexts(
    List<LiveSlot> slots, LivePlayerStatus? Function(String id) statusOf) {
  final out = <String, String>{};
  for (final slot in slots) {
    final status = statusOf(slot.playerId);
    if (status == null) continue;
    final text = chipWeekText(slot, status);
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

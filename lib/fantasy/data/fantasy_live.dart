// The fan's live gameweek (live everywhere, Task 4): models + parsers for
// `Fantasy/<sport>/<season>/Live`, the ONE overlay rule, the pure overlays
// and the four-child feed.
//
// THE NODE (functions/src/lib/fantasy/live_core.ts, NODE SHAPES — functions-
// written while a gameweek is being played, readable by any signed-in user):
//
//   Live/Meta       = { Gw, State:'live'|'settled', ReadAt, UpdatedAt,
//                       Games:{<gameKey>:{S:0|1|2, T1, T2}} }
//   Live/Board/<uid>    = { O, R, M?, W?, WR? }   O/R/M the Overall points,
//                       rank and movement, W/WR this week's points and rank
//   Live/Players/<name> = { Pts, St:'pending'|'live'|'done'|'out', Lines?:
//                       {key:{N,P}}, BonusProv?:true, Total, Form, Ppg,
//                       Games, Own }
//   Live/Squads/<uid>   = { T (net tenths), W, Slots:[{p, c, x, s?:true}] }
//   Live/TeamOfWeek     = [{name, position, points}]
//
// Optional fields are OMITTED (never null) and RTDB drops empty maps/lists
// and list-coerces small-int-keyed ones, so every parser is tolerant like
// fantasy_parsers.dart's. When finalize settles the week it writes every
// official node FIRST and then replaces `Live` with a Meta-only TOMBSTONE
// `{ Meta: { Gw, State:'settled', UpdatedAt } }` — no Board, Players, Squads
// or TeamOfWeek — which overlays nothing. A phone receives those writes in
// that order on its one connection, so live numbers hand over to the official
// ones with no gap. (`LiveBase` is server-only: never read.)
//
// THE OVERLAY RULE is one function, [liveAppliesTo]; every overlay below goes
// through it. The `mergeLive…` overlays are pure (unit-tested in
// test/fantasy/fantasy_live_test.dart): the FantasyService wrappers just join
// the official stream with [FantasyLiveFeed] through [combineLatest2]. A feed
// error means NO live (the official numbers keep showing) — never an empty
// board and never a made-up number.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';

export 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart'
    show LiveSlot;

// ── Models ─────────────────────────────────────────────────────────────────

/// `Live/Meta.State`: a gameweek in progress, or the tombstone finalize
/// leaves behind.
enum LiveState { live, settled }

/// One game of the day in `Live/Meta.Games`.
class LiveGame {
  const LiveGame({
    required this.status,
    required this.team1,
    required this.team2,
  });

  /// 0 not started, 1 live, 2 Final.
  final int status;
  final String team1;
  final String team2;
}

/// `Live/Meta`. A settled tombstone carries only [gw], [state] and
/// [updatedAt] (the rest default: [readAt] 0, no [games]).
class LiveMeta {
  const LiveMeta({
    required this.gw,
    required this.state,
    this.readAt = 0,
    this.updatedAt = 0,
    this.games = const {},
  });

  /// The gameweek being played.
  final int gw;
  final LiveState state;

  /// When the server read the games (epoch ms).
  final int readAt;

  /// When the server last wrote the node (epoch ms).
  final int updatedAt;

  /// The day's games by game key.
  final Map<String, LiveGame> games;
}

/// One manager's row of `Live/Board`: Overall points [o], rank [r] and
/// movement [m] (places climbed; null for a manager new this week), and this
/// week's whole points [w] with their rank [wr] (null for a manager not scored
/// this week).
class LiveBoardRow {
  const LiveBoardRow({
    required this.o,
    required this.r,
    this.m,
    this.w,
    this.wr,
  });

  final int o;
  final int r;
  final int? m;
  final int? w;
  final int? wr;
}

/// `Live/Players/<name>.St`.
enum LivePlayerStatus {
  /// His team has a game still to come and he has not played yet.
  pending,

  /// On the court in a game being played now.
  live,

  /// Played (his game is over or he is off the court).
  done,

  /// Not playing this week (no game, or absent with nothing to come).
  out,
}

/// One market player's row of `Live/Players`: this week's provisional points
/// and lines plus his season totals as they stand with them.
class LivePlayer {
  const LivePlayer({
    required this.pts,
    required this.st,
    this.lines = const {},
    this.bonusProv = false,
    required this.total,
    required this.form,
    required this.ppg,
    required this.games,
    required this.own,
  });

  /// This week's bonus-inclusive points so far.
  final int pts;
  final LivePlayerStatus st;

  /// This week's points by source key (`PlayerWeekStats.Lines`): count `n`,
  /// points `p`. Empty when nothing was scored.
  final Map<String, ({int n, int p})> lines;

  /// [pts] includes a bonus from a game that is not Final yet.
  final bool bonusProv;

  /// Season points with this week counted.
  final int total;

  /// Form in tenths (mean of the 3-week window).
  final int form;

  /// Points per game in tenths.
  final int ppg;

  /// Season games played with this week counted.
  final int games;

  /// Ownership, whole percent (0–100).
  final int own;
}

/// One manager's `Live/Squads/<uid>`: the squad's net tenths this week,
/// its whole points and one slot per pick (empty for an invalid squad).
class LiveSquad {
  const LiveSquad({
    required this.totalTenths,
    required this.week,
    required this.slots,
  });

  /// Net tenths this week (transfer hits taken off) — History `TotalTenths`.
  final int totalTenths;

  /// The week's whole points (the server's `W`: [totalTenths] truncated to
  /// whole points).
  final int week;

  /// One slot per pick in pick order — the live History `Breakdown`.
  final List<LiveSlot> slots;
}

/// What [FantasyLiveFeed] streams: the four children it listens to, parsed.
/// Everything empty / null = no live gameweek.
class FantasyLiveState {
  const FantasyLiveState({
    this.meta,
    this.board = const {},
    this.players = const {},
    this.teamOfWeek,
  });

  /// No Live node (or the feed failed): every overlay is a no-op.
  static const FantasyLiveState none = FantasyLiveState();

  final LiveMeta? meta;

  /// uid → live board row.
  final Map<String, LiveBoardRow> board;

  /// Market player name → live row.
  final Map<String, LivePlayer> players;

  /// The Team of the Week so far; null when empty (voided week, nobody
  /// played yet).
  final FantasyDreamTeam? teamOfWeek;

  /// The gameweek the live numbers belong to while they apply, else null.
  int? get liveWeek => liveWeekOf(meta);
}

// ── THE overlay rule ───────────────────────────────────────────────────────

/// Do the live numbers stand in for the official ones of gameweek [week]?
/// Only when [meta] is the live meta OF that week: no Live node, another
/// week, or the settled tombstone all mean the official nodes. Every overlay
/// in this file (and every screen that must decide) asks this one function.
bool liveAppliesTo({required LiveMeta? meta, required int week}) =>
    meta != null && meta.gw == week && meta.state == LiveState.live;

/// The gameweek [meta] overlays right now — [meta]'s own week when
/// [liveAppliesTo] says it applies, else null.
int? liveWeekOf(LiveMeta? meta) =>
    meta != null && liveAppliesTo(meta: meta, week: meta.gw) ? meta.gw : null;

// ── Parsers ────────────────────────────────────────────────────────────────

/// `Live/Meta`; null when absent or unusable (no/invalid gameweek or state —
/// never a fake live week).
LiveMeta? liveMetaFromNode(Object? node) {
  if (node is! Map) return null;
  final gw = optInt(node['Gw']);
  if (gw == null || gw < 1) return null;
  final state = switch (node['State']?.toString()) {
    'live' => LiveState.live,
    'settled' => LiveState.settled,
    _ => null,
  };
  if (state == null) return null;
  return LiveMeta(
    gw: gw,
    state: state,
    readAt: optInt(node['ReadAt']) ?? 0,
    updatedAt: optInt(node['UpdatedAt']) ?? 0,
    games: _liveGamesFromNode(node['Games']),
  );
}

/// `Meta.Games`: game key → game. The keys are game indexes, so RTDB may hand
/// the map back as a List (index = key, holes null).
Map<String, LiveGame> _liveGamesFromNode(Object? node) {
  final out = <String, LiveGame>{};
  void put(String key, Object? raw) {
    if (raw is! Map) return;
    final status = optInt(raw['S']);
    if (status == null || status < 0 || status > 2) return;
    out[key] = LiveGame(
      status: status,
      team1: raw['T1']?.toString() ?? '',
      team2: raw['T2']?.toString() ?? '',
    );
  }

  if (node is Map) {
    node.forEach((key, raw) => put(key.toString(), raw));
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      put('$i', node[i]);
    }
  }
  return out;
}

/// `Live/Board`: uid → row. A row without its Overall points or rank is
/// skipped (never defaulted to 0); anything else absent is null.
Map<String, LiveBoardRow> liveBoardFromNode(Object? node) {
  final out = <String, LiveBoardRow>{};
  if (node is! Map) return out;
  node.forEach((uid, raw) {
    if (raw is! Map) return;
    final o = optInt(raw['O']);
    final r = optInt(raw['R']);
    if (o == null || r == null) return;
    out[uid.toString()] = LiveBoardRow(
      o: o,
      r: r,
      m: optInt(raw['M']),
      w: optInt(raw['W']),
      wr: optInt(raw['WR']),
    );
  });
  return out;
}

/// `Live/Players`: name → row. The server writes every field for every
/// market player, so a row missing one (or with an unknown status) is skipped
/// — that player simply keeps his official numbers, never a defaulted 0.
Map<String, LivePlayer> livePlayersFromNode(Object? node) {
  final out = <String, LivePlayer>{};
  if (node is! Map) return out;
  node.forEach((name, raw) {
    if (raw is! Map) return;
    final st = switch (raw['St']?.toString()) {
      'pending' => LivePlayerStatus.pending,
      'live' => LivePlayerStatus.live,
      'done' => LivePlayerStatus.done,
      'out' => LivePlayerStatus.out,
      _ => null,
    };
    final pts = optInt(raw['Pts']);
    final total = optInt(raw['Total']);
    final form = optInt(raw['Form']);
    final ppg = optInt(raw['Ppg']);
    final games = optInt(raw['Games']);
    final own = optInt(raw['Own']);
    if (st == null ||
        pts == null ||
        total == null ||
        form == null ||
        ppg == null ||
        games == null ||
        own == null) {
      return;
    }
    final lines = <String, ({int n, int p})>{};
    final rawLines = raw['Lines'];
    if (rawLines is Map) {
      rawLines.forEach((key, line) {
        if (line is! Map) return;
        lines[key.toString()] =
            (n: optInt(line['N']) ?? 0, p: optInt(line['P']) ?? 0);
      });
    }
    out[name.toString()] = LivePlayer(
      pts: pts,
      st: st,
      lines: lines,
      bonusProv: raw['BonusProv'] == true,
      total: total,
      form: form,
      ppg: ppg,
      games: games,
      own: own,
    );
  });
  return out;
}

/// `Live/TeamOfWeek` (a `[{name, position, points}]` list, GK then DEF then
/// ATT) → the team; null when empty or absent. Reads like a DreamTeam week's
/// `Players`, so the same tolerance applies (index-keyed map, junk slots
/// skipped).
FantasyDreamTeam? liveTeamOfWeekFromNode(Object? node) =>
    dreamTeamFromNode({'Players': node});

/// `Live/Squads/<uid>`; null when absent or without its net tenths. A missing
/// `W` is derived from `T` (whole points, truncated); a missing `Slots` is an
/// empty list (RTDB drops it for an invalid squad).
LiveSquad? liveSquadFromNode(Object? node) {
  if (node is! Map) return null;
  final total = optInt(node['T']);
  if (total == null) return null;
  return LiveSquad(
    totalTenths: total,
    week: optInt(node['W']) ?? total ~/ 10,
    slots: liveSlotsFromNode(node['Slots']),
  );
}

/// The four children as RTDB handed them back → [FantasyLiveState]. Null /
/// junk children parse to their empty value: the tombstone is just a meta.
FantasyLiveState liveStateFromNodes({
  Object? meta,
  Object? board,
  Object? players,
  Object? teamOfWeek,
}) =>
    FantasyLiveState(
      meta: liveMetaFromNode(meta),
      board: liveBoardFromNode(board),
      players: livePlayersFromNode(players),
      teamOfWeek: liveTeamOfWeekFromNode(teamOfWeek),
    );

// ── Overlays (pure) ────────────────────────────────────────────────────────
//
// Each returns its [official] argument UNCHANGED (the same instance) when the
// live numbers do not apply or carry nothing for it, and otherwise a copy —
// the official value is never mutated (it is the session cache's).

/// `Leaderboards` ⊕ live: while a gameweek is live,
/// - the Overall rows ARE the live board (`o/r/m`, `live: true`) — the server
///   ranks every manager in the base or scored this week, so the board is the
///   whole Overall;
/// - that gameweek's rows are the managers scored this week (`w/wr`);
/// - `rankHistory[uid][gw]` is the live rank, flagged live
///   ([FantasyLeaderboards.isLiveRankPoint]).
/// Every other week and every other history point is the official one. An
/// empty live board overlays nothing.
FantasyLeaderboards mergeLiveLeaderboards(
    FantasyLeaderboards official, FantasyLiveState live) {
  final gw = live.liveWeek;
  if (gw == null || live.board.isEmpty) return official;

  final overall = sortLeaderboardEntries([
    for (final e in live.board.entries)
      FantasyLeaderboardEntry(
        uid: e.key,
        points: e.value.o,
        rank: e.value.r,
        movement: e.value.m,
        live: true,
      ),
  ]);
  final week = sortLeaderboardEntries([
    for (final e in live.board.entries)
      if (e.value.w case final points?)
        FantasyLeaderboardEntry(
          uid: e.key,
          points: points,
          rank: e.value.wr,
          live: true,
        ),
  ]);

  final byWeek = {...official.byWeek};
  if (week.isNotEmpty) byWeek[gw] = week;

  final history = {...official.rankHistory};
  final liveRankPoints = <String, Set<int>>{};
  for (final e in live.board.entries) {
    history[e.key] = {...?history[e.key], gw: e.value.r};
    liveRankPoints[e.key] = {gw};
  }

  return FantasyLeaderboards(
    overall: overall,
    byWeek: byWeek,
    rankHistory: history,
    liveRankPoints: liveRankPoints,
  );
}

/// `PlayerTotals` ⊕ live: each live player's points / form / ppg / games /
/// ownership are his live `Total / Form / Ppg / Games / Own` (`live: true`);
/// a player the live feed does not carry keeps his official row. The first
/// live week of a season has no official node (null): the live rows then
/// stand alone. No live players overlays nothing.
Map<String, FantasyPlayerTotals>? mergeLivePlayerTotals(
    Map<String, FantasyPlayerTotals>? official, FantasyLiveState live) {
  if (live.liveWeek == null || live.players.isEmpty) return official;
  return {
    ...?official,
    for (final e in live.players.entries)
      e.key: FantasyPlayerTotals(
        points: e.value.total,
        ownershipPct: e.value.own.toDouble(),
        formTenths: e.value.form,
        ppgTenths: e.value.ppg,
        games: e.value.games,
        live: true,
      ),
  };
}

/// `DreamTeam` ⊕ live: the live gameweek's Team of the Week is the live one
/// (`live: true`, computed at the live meta's `UpdatedAt`); every other week
/// is official. No live team (a voided week, nobody played yet) overlays
/// nothing.
Map<int, FantasyDreamTeam> mergeLiveDreamTeams(
    Map<int, FantasyDreamTeam> official, FantasyLiveState live) {
  final gw = live.liveWeek;
  final team = live.teamOfWeek;
  if (gw == null || team == null) return official;
  return {
    ...official,
    gw: FantasyDreamTeam(
      players: team.players,
      computedAtMs: live.meta?.updatedAt,
      live: true,
    ),
  };
}

/// One player's `PlayerWeekStats` by week ⊕ live: for each requested week in
/// [weeks] that [liveAppliesTo], the record is built from his live row —
/// `Pts`, `Lines`, `GP` (= the `plays` line's count), `Played` (on the court
/// now or already played: st done / live), `live: true` and the provisional-
/// bonus flag. The team's schedule (`games`) and the voided flag are not in
/// the live node: an official record for that week (a re-run) keeps them,
/// else no games / not voided. Other weeks, and a player the live feed does
/// not carry, stay official; a week not in [weeks] is not added.
Map<int, PlayerWeekStats> mergeLivePlayerWeekStats(
  Map<int, PlayerWeekStats> official,
  FantasyLiveState live, {
  required String name,
  required Iterable<int> weeks,
}) {
  final player = live.players[name];
  if (player == null) return official;
  Map<int, PlayerWeekStats>? merged;
  for (final week in weeks) {
    if (!liveAppliesTo(meta: live.meta, week: week)) continue;
    final base = official[week];
    (merged ??= {...official})[week] = PlayerWeekStats(
      points: player.pts,
      played: player.st == LivePlayerStatus.done ||
          player.st == LivePlayerStatus.live,
      gamesPlayed: player.lines['plays']?.n ?? 0,
      games: base?.games ?? const [],
      lines: {
        for (final e in player.lines.entries)
          e.key: ScoreSourceLine(count: e.value.n, points: e.value.p),
      },
      voided: base?.voided ?? false,
      live: true,
      bonusProvisional: player.bonusProv,
    );
  }
  return merged ?? official;
}

// ── Joining official ⊕ live ────────────────────────────────────────────────

/// Combines the latest value of [a] and [b] with [combine]: nothing is
/// emitted until BOTH have answered (the screen never paints official numbers
/// and then pops live ones in), then every change of either re-emits. Errors
/// of either side are forwarded; the stream completes when both complete;
/// cancelling cancels both.
Stream<R> combineLatest2<A, B, R>(
    Stream<A> a, Stream<B> b, R Function(A a, B b) combine) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  var done = 0;

  void emit() {
    if (!hasA || !hasB) return;
    try {
      controller.add(combine(lastA as A, lastB as B));
    } catch (e, s) {
      controller.addError(e, s);
    }
  }

  void sideDone() {
    if (++done == 2) controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        hasA = true;
        emit();
      }, onError: controller.addError, onDone: sideDone);
      subB = b.listen((v) {
        lastB = v;
        hasB = true;
        emit();
      }, onError: controller.addError, onDone: sideDone);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

// ── The feed ───────────────────────────────────────────────────────────────

/// The live gameweek as one stream per `<sport>/<season>`.
///
/// Listens to FOUR children of `Live` — Meta, Board, Players and TeamOfWeek —
/// and never the whole node: a phone must not download every manager's
/// `Squads` (those are read one uid at a time, FantasyService.watchLiveSquad).
/// Streams only (RTDB `.get()` is banned). The first state is emitted once
/// all four have answered (no piecemeal frame — a live meta with a not-yet-
/// arrived board would otherwise read as an empty board), then on every
/// change.
///
/// A stream error — or a stream that cannot even be created (no Firebase app
/// in a widget test) — yields [FantasyLiveState.none] ("no live": the official
/// numbers keep showing) once, drops the session seed and stops listening;
/// the next subscription retries. The feed itself never errors.
///
/// The last real state is session-cached per `<sport>/<season>` and seeds a
/// revisit's first frame (stale-while-refresh, like the other fantasy feeds);
/// cleared on sign-out by [clearSessionCache] (fantasy_session.dart).
class FantasyLiveFeed {
  FantasyLiveFeed._();

  /// The `Live` children this feed listens to — exactly these, never `Live`
  /// itself.
  static const List<String> children = [
    'Meta',
    'Board',
    'Players',
    'TeamOfWeek',
  ];

  static final Map<String, FantasyLiveState> _session = {};

  /// Clears the session cache (sign-out hygiene, tests).
  static void clearSessionCache() => _session.clear();

  /// The seed a revisit would paint (null: none) — for tests.
  @visibleForTesting
  static FantasyLiveState? cachedState(String sport, String season) =>
      _session['$sport/$season'];

  /// See the class doc. [childStream] is the test seam replacing the RTDB
  /// listener of one `Live` child (its raw snapshot values).
  static Stream<FantasyLiveState> watch(
    String sport,
    String season, {
    Stream<Object?> Function(String child)? childStream,
  }) {
    final key = '$sport/$season';
    final open = childStream ??
        (String child) => FirebaseDatabase.instance
            .ref('Fantasy/$sport/$season/Live/$child')
            .onValue
            .map((event) => event.snapshot.value);

    final subs = <StreamSubscription<Object?>>[];
    final raw = <String, Object?>{};
    late final StreamController<FantasyLiveState> controller;
    var failed = false;

    void fail(String what, Object error) {
      debugPrint('FantasyLiveFeed: $what failed: $error');
      if (failed) return;
      failed = true;
      _session.remove(key); // a broken feed must not seed the next visit
      for (final s in subs) {
        unawaited(s.cancel());
      }
      if (!controller.isClosed) controller.add(FantasyLiveState.none);
    }

    void onChild(String child, Object? value) {
      if (failed) return;
      raw[child] = value;
      if (raw.length < children.length) return; // not every child answered
      try {
        final state = liveStateFromNodes(
          meta: raw['Meta'],
          board: raw['Board'],
          players: raw['Players'],
          teamOfWeek: raw['TeamOfWeek'],
        );
        _session[key] = state;
        controller.add(state);
      } catch (e) {
        fail('parse', e);
      }
    }

    controller = StreamController<FantasyLiveState>(
      onListen: () {
        final seed = _session[key];
        if (seed != null) controller.add(seed);
        for (final child in children) {
          try {
            subs.add(open(child).listen(
              (value) => onChild(child, value),
              onError: (Object e) => fail('$child feed', e),
            ));
          } catch (e) {
            fail('$child feed', e);
            return;
          }
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }
}

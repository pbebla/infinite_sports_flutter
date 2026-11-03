// Live gameweek math (live design 2026-11-03, docs/superpowers/specs/
// 2026-11-03-fantasy-live-design.md §2 provisional rules, §5 node shapes) —
// the pure heart the live trigger and the sweep backstop call. No firebase
// imports; vitest covers it without emulators (live_core.test.ts).
//
// THE CONTRACT (pinned by live_core.test.ts): when every game of the day
// is Final (status 2) and no team is still to kick off, computeLiveWeek
// publishes EXACTLY what computeGameweekFinalize then writes for gw, uid
// for uid and player for player:
//   Board.W/WR == Leaderboards/Gameweek; Board.O/R/M == Leaderboards/
//   Overall (points/rank/movement); Players.Pts/Lines == PlayerWeekStats;
//   Players.Total/Form/Ppg/Games/Own == PlayerTotals (points/form/ppg/
//   games/ownershipPct); TeamOfWeek == DreamTeam.Players; Squads.T ==
//   History TotalTenths and Squads.Slots == History Breakdown.
// So the hand-off from live to official numbers never jumps. Both engines
// share the scoring stages (scoreWeekCore) and every rounding helper
// (wholePoints, competitionRanks, roundTenths, pickDreamTeam); the only new
// math here is resumming against a small settled base instead of re-reading
// every past week. Anything that changes finalize's stages 5–7 must change
// here too — the contract test fails otherwise.
//
// PROVISIONAL RULES (spec §2; while games are still to come):
// - Counted games: today's started non-friendly games (status 1 live, 2
//   Final). A status-0 game counts nothing, even if a caller hands one in.
// - Pending teams = every team with at least one status-0 game in the day's
//   status table (gameStatus). Their market players who have not played yet
//   are PENDING: team scoring counts them as playing, 0 so far (no auto-sub,
//   a captain keeps the armband, a bench player stays on the bench —
//   scoreWeekCore's pending rule). On a double-game day a player marked
//   absent in an earlier game is still pending while his team has a game to
//   come (controller ruling, Task 1).
// - A pending player keeps his SETTLED numbers: Pts 0, Total = base P,
//   Games = base G, Form over the base weeks only (his official form), Ppg
//   from those. He never drops to "0 this week" at the lock.
// - Bonus of a game that is not Final stands as if it ended now, counted in
//   Pts/Total and flagged BonusProv — never in a voided week (the week
//   counts nothing, so nothing is provisional).
// - Ownership = this week's locked squads (finalize does the same for the
//   latest week). Team of the Week = the best so far among players who
//   PLAYED (real played flags; pending players never), none when voided.
// - Transfer hits, chips, invalid squads and a voided week: exactly as
//   finalize (scoreWeekCore does them).
//
// St (Fable L3), first match wins:
//   1. 'live'    — present (not marked absent in the composed attendance)
//                  in a status-1 game of his team;
//   2. 'pending' — his team has a status-0 game today and he has not played;
//   3. 'done'    — he played;
//   4. 'out'     — otherwise (no game, absent with nothing to come, no team).
// An absent player in a live game whose team has no game still to come is
// 'out', never 'live'.
//
// NODE SHAPES (Fantasy/<sport>/<season>/…; every number an int; optional
// fields are OMITTED, never undefined — RTDB rejects undefined):
//
// - Live/Meta = { Gw, State:'live', ReadAt, UpdatedAt, Games:{<gameKey>:
//   {S:0|1|2, T1, T2}} } — ReadAt = when the caller read the games (the
//   write guard compares it), UpdatedAt = nowMs. computeLiveWeek always
//   says 'live'; the 'settled' tombstone ({ Meta: { Gw, State:'settled',
//   UpdatedAt } }) is written by finalize (orchestration), not here.
// - Live/Board/<uid> = { O, R, M?, W?, WR? } — O = settled Overall whole
//   points + this week's whole points (0 when voided); R = competition rank
//   of O over every manager in the base or scored this week; M = base rank
//   (competition rank of the settled O over the base managers) - R,
//   positive = climbed, omitted for a manager not in the base; W/WR = this
//   week's whole points (wholePoints of net tenths, Dart truncation) and
//   their competition rank, only for managers scored this week (invalid
//   squads included at 0; a voided week is 0 for all, everyone rank 1).
// - Live/Players/<name> = { Pts, St, Lines?, BonusProv?:true, Total, Form,
//   Ppg, Games, Own } for every market player. Pts/Lines = PlayerWeekStats
//   (Lines omitted when empty or voided). Total = base P + Pts (voided:
//   base P). Games = base G + GP (voided: base G). Form (tenths) =
//   round(10 x mean of the window: this week unless voided, then the newest
//   base weeks, 3 weeks in all; a week the player is missing from counts
//   0; no weeks = 0). Ppg (tenths) = Games 0 ? 0 : round(10 x Total /
//   Games). Own = round(100 x holders / valid squads scored), 0 when none.
// - Live/Squads/<uid> = { T, W, Slots:[{p, c, x, s?:true}] } — T = net
//   tenths (History TotalTenths), W = wholePoints(T), one slot per pick in
//   pick order from the Breakdown: p playerId, c countedTenths, x
//   multiplier, s only when auto-subbed in. An invalid squad has no
//   Breakdown: Slots [] (RTDB drops the empty list; readers default it).
//   Malformed squads (squadFromMap throws) appear nowhere, as in finalize.
// - Live/TeamOfWeek = [{name, position, points}] — pickDreamTeam over the
//   real week, GK then DEF then ATT; [] when voided.
// Empty lists and maps (Slots, TeamOfWeek, Board before any squad, Games)
// are dropped by RTDB on write: readers default them to empty.
//
// - LiveBase/<gw> (functions-only; built ONCE per live week by
//   buildLiveBase from the stored History/PlayerWeeks/PlayerWeekStats of
//   the weeks BEFORE gw, removed by every finalize run and void toggle) =
//   { Gw, Managers:{<uid>:{O}}, Players:{<name>:{P, G}},
//   FormWeeks:{"<week>":{<name>:pts}} } — O = settled Overall whole points
//   (sum of each week's whole points; a voided week counts 0 but still puts
//   the manager on the board); P/G = season points and games over the
//   non-voided weeks (a player missing = 0/0); FormWeeks = the 3
//   highest-numbered non-voided settled weeks (numeric order), each week's
//   PlayerWeeks map copied whole. Readers note: FormWeeks' small int keys
//   may come back from RTDB list-coerced, and an empty Managers/Players/
//   FormWeeks map is dropped on write (read it back as {}).

import { FantasyPosition } from './fantasy_config';
import {
  competitionRanks, FinalizeGame, pickDreamTeam, roundTenths, scoreWeekCore,
  WeekCoreInput, wholePoints,
} from './finalize_core';
import { toIntLoose } from './orchestration_db';

/** Weeks in the form window (finalize's PlayerTotals form, Stage 6). */
const FORM_WINDOW = 3;

/** LiveBase/<gw> — see the header. */
export interface LiveBase {
  Gw: number;
  /** uid -> settled Overall whole points (voided weeks 0). */
  Managers: Record<string, { O: number }>;
  /** name -> settled season points and games (non-voided weeks). */
  Players: Record<string, { P: number; G: number }>;
  /** The 3 newest settled non-voided weeks < Gw: week -> name -> points. */
  FormWeeks: Record<string, Record<string, number>>;
}

/** One game of the day in Live/Meta.Games: status (0 not started, 1 live,
 *  2 Final) and its two teams. */
export interface LiveGameStatus {
  S: 0 | 1 | 2;
  T1: string;
  T2: string;
}

/** computeLiveWeek's input: the week-scoring input minus pendingTeams
 *  (derived here from gameStatus — one source of truth for "still to come",
 *  see pendingTeamsOf) plus the settled base and the day's status table. */
export interface LiveInput extends Omit<WeekCoreInput, 'pendingTeams'> {
  /** buildLiveBase output for [gw] (a base for any other week throws). */
  base: LiveBase;
  /** Every non-friendly game of the day, keyed by game index: the
   *  not-started ones make their teams pending; published as Meta.Games. */
  gameStatus: Record<string, LiveGameStatus>;
  /** When the caller read the games (Meta.ReadAt). */
  readAtMs: number;
  /** Meta.UpdatedAt. */
  nowMs: number;
}

export type LiveSt = 'pending' | 'live' | 'done' | 'out';

export interface LiveBoardRow {
  O: number;
  R: number;
  M?: number;
  W?: number;
  WR?: number;
}

export interface LivePlayer {
  Pts: number;
  St: LiveSt;
  Lines?: Record<string, { N: number; P: number }>;
  BonusProv?: true;
  Total: number;
  Form: number;
  Ppg: number;
  Games: number;
  Own: number;
}

export interface LiveSlot {
  p: string;
  c: number;
  x: number;
  s?: true;
}

export interface LiveSquad {
  T: number;
  W: number;
  Slots: LiveSlot[];
}

/** The Live node — see the header. */
export interface LiveOutput {
  Meta: {
    Gw: number;
    State: 'live' | 'settled';
    ReadAt: number;
    UpdatedAt: number;
    Games: Record<string, LiveGameStatus>;
  };
  Board: Record<string, LiveBoardRow>;
  Players: Record<string, LivePlayer>;
  Squads: Record<string, LiveSquad>;
  TeamOfWeek: Array<{ name: string; position: FantasyPosition; points: number }>;
}

/** History Breakdown row (finalize_core.ts scoreWeekCore, Stage 4). */
interface BreakdownRow {
  playerId: string;
  countedTenths: number;
  multiplier: number;
  autoSubbedIn: boolean;
}

/** The teams that still have a not-started (status 0) game today. */
export function pendingTeamsOf(
  gameStatus: Record<string, LiveGameStatus>,
): string[] {
  const teams = new Set<string>();
  for (const g of Object.values(gameStatus)) {
    if (g.S !== 0) continue;
    teams.add(g.T1);
    teams.add(g.T2);
  }
  return [...teams];
}

/** Numeric week keys of a week -> … map, below [gw] (settled before it). */
function weeksBefore(byWeek: Record<number, unknown>, gw: number): number[] {
  return Object.keys(byWeek).map(Number)
    .filter((w) => Number.isFinite(w) && w < gw);
}

/** LiveBase/<gw> from the stored weeks (the same maps finalize reads:
 *  History TotalTenths, PlayerWeeks, PlayerWeekStats GP). Weeks >= gw are
 *  ignored. Pure + deterministic. */
export function buildLiveBase(args: {
  gw: number;
  historyTenthsByWeek: Record<number, Record<string, number>>;
  playerWeeksByWeek: Record<number, Record<string, number>>;
  playedGamesByWeek: Record<number, Record<string, number>>;
  voidedWeeks: number[];
}): LiveBase {
  const { gw } = args;
  const voided = new Set(args.voidedWeeks);

  // Overall whole points: a voided week still lists its managers, at 0.
  const Managers: Record<string, { O: number }> = {};
  for (const w of weeksBefore(args.historyTenthsByWeek, gw)) {
    for (const [uid, tenths] of Object.entries(args.historyTenthsByWeek[w])) {
      const pts = voided.has(w) ? 0 : wholePoints(tenths);
      Managers[uid] = { O: (Managers[uid]?.O ?? 0) + pts };
    }
  }

  // Season points and games over the non-voided weeks.
  const Players: Record<string, { P: number; G: number }> = {};
  const settled = (name: string) => (Players[name] ??= { P: 0, G: 0 });
  for (const w of weeksBefore(args.playerWeeksByWeek, gw)) {
    if (voided.has(w)) continue;
    for (const [name, pts] of Object.entries(args.playerWeeksByWeek[w])) {
      settled(name).P += pts;
    }
  }
  for (const w of weeksBefore(args.playedGamesByWeek, gw)) {
    if (voided.has(w)) continue;
    for (const [name, games] of Object.entries(args.playedGamesByWeek[w])) {
      settled(name).G += games;
    }
  }

  // The form window's settled part: the 3 highest-numbered non-voided weeks.
  const FormWeeks: Record<string, Record<string, number>> = {};
  for (const w of weeksBefore(args.playerWeeksByWeek, gw)
    .filter((w) => !voided.has(w))
    .sort((a, b) => b - a)
    .slice(0, FORM_WINDOW)) {
    FormWeeks[String(w)] = { ...args.playerWeeksByWeek[w] };
  }

  return { Gw: gw, Managers, Players, FormWeeks };
}

/** A game that has started (status 1 live or 2 Final). */
function isStarted(g: FinalizeGame): boolean {
  const s = toIntLoose(g.node['status']);
  return s === 1 || s === 2;
}

/** The live gameweek, pure: scoreWeekCore over the started games with the
 *  pending rule, resummed against the settled base — see the header.
 *  Deterministic: same inputs, same node. */
export function computeLiveWeek(input: LiveInput): LiveOutput {
  const { cfg, gw, base, voided } = input;
  if (base.Gw !== gw) {
    throw new Error(
      `LiveBase is for gameweek ${base.Gw}, not the live gameweek ${gw}`);
  }

  // ── Stages 1–4, shared with finalize ──
  const games = input.games.filter(isStarted);
  const pendingTeams = new Set(pendingTeamsOf(input.gameStatus));
  const core = scoreWeekCore({
    cfg,
    gw,
    games,
    players: input.players,
    squadsByUid: input.squadsByUid,
    transferCostPointsByUid: input.transferCostPointsByUid,
    voided,
    pendingTeams: [...pendingTeams],
  });

  // ── St: first match wins (header) ──
  const statusOf = (name: string, team: string | undefined): LiveSt => {
    const played = core.week[name].played;
    if (team !== undefined) {
      for (const g of games) {
        if (toIntLoose(g.node['status']) !== 1) continue;
        if (g.node['team1'] !== team && g.node['team2'] !== team) continue;
        if (g.attendance?.[team]?.[name] !== false) return 'live';
      }
      if (pendingTeams.has(team) && !played) return 'pending';
    }
    return played ? 'done' : 'out';
  };

  // ── Players: this week on top of the settled base ──
  const baseFormWeeks = Object.keys(base.FormWeeks)
    .filter((w) => Number.isFinite(Number(w)))
    .sort((a, b) => Number(b) - Number(a)); // newest first
  const Players: Record<string, LivePlayer> = {};
  for (const [name, p] of Object.entries(input.players)) {
    const St = statusOf(name, p.teamName);
    const pending = St === 'pending';
    const settled = base.Players[name] ?? { P: 0, G: 0 };
    const stats = core.playerWeekStats[name];
    // A pending player shows his settled numbers; a voided week counts
    // nothing toward any total (finalize skips voided weeks).
    const counts = !pending && !voided;
    const Pts = pending ? 0 : stats.Pts;
    const Total = settled.P + (counts ? core.playerWeeks[name] : 0);
    const Games = settled.G + (counts ? stats.GP : 0);

    const window: number[] = counts ? [core.playerWeeks[name]] : [];
    for (const w of baseFormWeeks) {
      if (window.length === FORM_WINDOW) break;
      window.push(base.FormWeeks[w]?.[name] ?? 0);
    }
    const formSum = window.reduce((a, b) => a + b, 0);

    Players[name] = {
      Pts,
      St,
      ...(!pending && stats.Lines !== undefined ? { Lines: stats.Lines } : {}),
      ...(!pending && !voided && core.bonusProvisional.has(name)
        ? { BonusProv: true as const } : {}),
      Total,
      Form: window.length === 0 ? 0 : roundTenths((10 * formSum) / window.length),
      Ppg: Games === 0 ? 0 : roundTenths((10 * Total) / Games),
      Games,
      Own: core.scoredValid === 0
        ? 0
        : Math.round((100 * (core.holders[name] ?? 0)) / core.scoredValid),
    };
  }

  // ── Board: week points + settled Overall ──
  const weekPoints: Record<string, number> = {};
  for (const [uid, tenths] of Object.entries(core.weekTenthsByUid)) {
    weekPoints[uid] = wholePoints(tenths);
  }
  const weekRanks = competitionRanks(weekPoints);
  const baseO: Record<string, number> = {};
  for (const [uid, m] of Object.entries(base.Managers)) baseO[uid] = m.O;
  const overall: Record<string, number> = { ...baseO };
  for (const [uid, w] of Object.entries(weekPoints)) {
    overall[uid] = (overall[uid] ?? 0) + (voided ? 0 : w);
  }
  const ranks = competitionRanks(overall);
  const baseRanks = competitionRanks(baseO);
  const Board: Record<string, LiveBoardRow> = {};
  for (const [uid, O] of Object.entries(overall)) {
    const R = ranks[uid];
    Board[uid] = {
      O,
      R,
      // Positive = climbed; omitted for a manager new this week.
      ...(baseRanks[uid] !== undefined ? { M: baseRanks[uid] - R } : {}),
      ...(uid in weekPoints ? { W: weekPoints[uid], WR: weekRanks[uid] } : {}),
    };
  }

  // ── Squads: History net tenths + Breakdown ──
  const Squads: Record<string, LiveSquad> = {};
  for (const [uid, row] of Object.entries(core.historyByUid)) {
    const T = row['TotalTenths'] as number;
    const breakdown = Array.isArray(row['Breakdown'])
      ? row['Breakdown'] as BreakdownRow[] : [];
    Squads[uid] = {
      T,
      W: wholePoints(T),
      Slots: breakdown.map((b) => ({
        p: b.playerId,
        c: b.countedTenths,
        x: b.multiplier,
        ...(b.autoSubbedIn ? { s: true as const } : {}),
      })),
    };
  }

  // ── Meta (a copy: only the three published fields per game) ──
  const Games: Record<string, LiveGameStatus> = {};
  for (const [key, g] of Object.entries(input.gameStatus)) {
    Games[key] = { S: g.S, T1: g.T1, T2: g.T2 };
  }

  return {
    Meta: {
      Gw: gw,
      State: 'live',
      ReadAt: input.readAtMs,
      UpdatedAt: input.nowMs,
      Games,
    },
    Board,
    Players,
    Squads,
    TeamOfWeek: voided
      ? []
      : pickDreamTeam(core.week, input.players, cfg, input.nowMs).Players,
  };
}

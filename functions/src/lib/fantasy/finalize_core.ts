// Gameweek finalization math (P4 Phase C) — the pure heart the triggers and
// the scheduled backstop both call. No firebase imports; vitest covers every
// branch without emulators (finalize_core.test.ts), and the golden fixture
// (test/fantasy/fixtures/golden_gameweek.json) replays through
// computeGameweekFinalize to pin the cross-engine contract.
//
// Composition rule (pinned by the golden fixture + golden_replay.test.ts):
// a player's WEEK points = scorePlayerWeek(...).total + the sum of their
// per-game 3/2/1 bonus awards (awardBonus over bpsScore). Repricing and the
// Dream Team read these same bonus-inclusive week points.
//
// Forfeits (spec §8a; golden_forfeit.json + golden_forfeit_replay.test.ts)
// need nothing extra here: the mapper tags each player won/lost, scoring
// gives the team that showed up its appearance point only, bpsScore is 0
// for the whole game (no bonus), and a forfeiting player's week is NOT
// played — so auto-subs, the vice armband and the Dream Team treat him
// like an absent player. Marking or undoing a forfeit is a write to a
// Final game node, which re-runs this pipeline like any score edit.
//
// WRITE SHAPES (client contracts read from lib/fantasy/data/fantasy_parsers.dart
// and lib/fantasy/hub/*; every number crosses the write boundary per these):
//
// - Leaderboards/Gameweek/<gw>/<uid> = { points:int, rank:int }
//   Leaderboards/Overall/<uid>       = { points:int, rank:int, movement?:int }
//   points are WHOLE points (the client renders the raw int as "N pts",
//   leaderboard_rows.dart): weekly = Dart-style truncation toward zero of
//   netTenths/10; Overall = the SUM of the weekly whole points, so the season
//   total always equals what the user adds up week by week (tenths lost to a
//   bench half-point truncate per week, never resurface). rank is 1-based,
//   competition style: ties share the smaller rank (1,1,3). movement =
//   prevRank - rank against the standings BEFORE the latest finalized week
//   (positive = climbed); omitted for managers with no earlier finalized week.
//
// - History/<gw>/<uid> = engine FantasySquad.toMap (squadFromMap-compatible:
//   picks/captainId/viceId/chip — the client's squadsByWeekForUid reads just
//   these) PLUS { TotalTenths:int, Breakdown:[{playerId, countedTenths,
//   multiplier, autoSubbedIn}] }. TotalTenths is the NET squad-week tenths
//   (gross countedTenths sum minus transferCost*10) — the single source the
//   Overall board resums from on later reruns.
//
// - PlayerTotals/<name> = { points:int, ownershipPct:int } — points = season
//   sum of bonus-inclusive week points across finalized weeks; ownershipPct =
//   round(100 * managers holding the player / managers scored) measured over
//   the LATEST finalized gameweek's squads — ownership is a "right now"
//   figure, so a score-edit rerun of an OLDER week must not roll it back to
//   that week's holdings (the caller passes ownershipSquadsByUid then; S15
//   rehearsal finding 2.5c).
//
// - DreamTeam/<gw> = { Players:[{name, position, points}], ComputedAt:int,
//   Auto:true } — the week's top scorers in the config formation
//   (startersGk GK + startersDef DEF + startersAtt ATT), eligible market
//   players WHO PLAYED that week only (guests are not fantasy-selectable, so
//   they never appear; a player whose team had no game — or who was absent —
//   never makes the Team of the Week, even when every keeper who did play
//   scored below zero: S15 GW12), points desc / name asc per position,
//   listed GK then DEF then ATT. A position with too few played players
//   fills fewer slots. An existing node whose Auto flag was removed or set
//   false is an admin edit and is NEVER overwritten (dreamTeam comes back
//   null).
//
// - PlayerWeeks/<gw>/<name> = int — bonus-inclusive week points for every
//   market player (functions-internal: feeds PlayerTotals resums and the
//   Monday repricing job; not a client contract).
//
// Transfer costs: Phase E records transfer usage; until it lands the callers
// pass no costs (zero for everyone). transferCostPointsByUid is the seam.
//
// VOIDED GAMEWEEKS (owner control, spec §15: Voided/<gw> == true; the
// voidedWeeks input). A voided week counts ZERO for every manager:
//
// - History/<gw>/<uid> is still written (squad viewer + history browsing
//   keep working) with TotalTenths: 0 and Voided: true. Breakdown keeps the
//   would-have-counted slots (audit: what happened on court, none of which
//   counted). The transfer cost is waived (net is 0, not -cost).
// - Leaderboards/Gameweek/<gw> rows are written with points 0 (so rank 1,
//   everyone tied) — NOT omitted: the client's Gameweek scope renders an
//   omitted week as "Gameweek N hasn't been scored yet", which is false for
//   a settled-but-void week; zeros render the week as played-and-voided.
// - Overall and PlayerTotals resums treat EVERY voided week (this one or
//   any other) as zero, whatever its stored History/PlayerWeeks say — so a
//   stale entry from before a void can never leak into the totals.
// - PlayerWeeks/<gw> keeps the REAL week points (functions-internal: the
//   games happened; the next week's news form-comparison reads them, and the
//   Monday job skips voided weeks anyway).
// - DreamTeam/<gw> is not computed; an existing Auto:true node is removed
//   (removeAutoDreamTeam), an admin-edited one (Auto not true) is left alone.
// Un-voiding is just a rerun without the flag: everything re-settles back.

import { awardBonus, bpsScore } from './bps';
import { FantasyConfig, FantasyPosition } from './fantasy_config';
import { PlayerGameStats } from './player_game_stats';
import { scorePlayerWeek } from './scoring';
import { squadFromMap, squadToMap } from './squad';
import { PlayerWeek, scoreSquadWeek, totalTenths } from './squad_week';
import { mapGameToStats } from './stats_mapper';

/** One market entry (Fantasy/<sport>/<season>/Players/<name>) as the
 *  finalizer needs it. */
export interface MarketPlayer {
  position: FantasyPosition;
  eligible: boolean;
}

/** One real game of the gameweek's match day, attendance already composed
 *  into full per-team maps (name -> present; roster-derived, absent-only
 *  node applied) — the exact shape the golden fixture pins. */
export interface FinalizeGame {
  node: Record<string, unknown>;
  /** team name -> full attendance map; null team entry / null map = everyone
   *  with an activity event counts, default present. On a FORFEITED game
   *  (node forfeitedBy 1|2, spec §8a) these maps are the ONLY player source
   *  — its events are ignored — so the roster composition is what gives
   *  the team that showed up its +1 (stats_mapper.ts FORFEITS). */
  attendance: Record<string, Record<string, boolean> | null> | null;
}

export interface FinalizeInput {
  cfg: FantasyConfig;
  gw: number;
  /** Final, non-friendly game nodes of the gameweek's date. */
  games: FinalizeGame[];
  /** The market: name -> position/eligibility. Players outside the market
   *  (guests not yet seeded) still count in each game's BPS pool — a client
   *  replay of the engine sees them too — but get no week points, totals,
   *  or Dream Team slot (no position to score with). */
  players: Record<string, MarketPlayer>;
  /** uid -> raw squad map (source already resolved by the caller:
   *  PublishedPicks snapshot, else History, else live Squads fallback). */
  squadsByUid: Record<string, unknown>;
  /** Phase E seam: points already charged for this week's transfers.
   *  Absent uid = 0. */
  transferCostPointsByUid?: Record<string, number>;
  /** Existing PlayerWeeks node content: week -> name -> points. Week [gw]
   *  is replaced by this run. */
  playerWeeksByWeek: Record<number, Record<string, number>>;
  /** Existing History TotalTenths: week -> uid -> net tenths. Week [gw] is
   *  replaced by this run. */
  historyTenthsByWeek: Record<number, Record<string, number>>;
  /** Existing DreamTeam/<gw> Auto flag: null = node absent (write ours),
   *  true = ours (overwrite on rerun), false = admin-edited (preserve). */
  dreamTeamAuto: boolean | null;
  /** Every owner-voided gameweek (Voided/<w> == true), possibly including
   *  [gw] itself. Absent = none. See VOIDED GAMEWEEKS above. */
  voidedWeeks?: number[];
  /** uid -> raw squad of the LATEST finalized gameweek, when that is a
   *  LATER week than [gw] (a rerun of an older week): PlayerTotals
   *  ownershipPct is measured over these instead of this week's squads.
   *  Absent = [gw] is the latest — ownership comes from squadsByUid. */
  ownershipSquadsByUid?: Record<string, unknown>;
  nowMs: number;
}

export interface DreamTeamNode {
  Players: Array<{ name: string; position: FantasyPosition; points: number }>;
  ComputedAt: number;
  Auto: true;
}

export interface FinalizeOutput {
  /** PlayerWeeks/<gw> */
  playerWeeks: Record<string, number>;
  /** History/<gw> */
  historyByUid: Record<string, Record<string, unknown>>;
  /** Leaderboards/Gameweek/<gw> */
  gameweekBoard: Record<string, { points: number; rank: number }>;
  /** Leaderboards/Overall */
  overallBoard: Record<string, { points: number; rank: number; movement?: number }>;
  /** PlayerTotals */
  playerTotals: Record<string, { points: number; ownershipPct: number }>;
  /** DreamTeam/<gw>; null = not ours to write (admin-edited, or a voided
   *  week — see removeAutoDreamTeam). */
  dreamTeam: DreamTeamNode | null;
  /** True only for a voided week whose existing DreamTeam/<gw> is ours
   *  (Auto:true): the caller removes it. An admin node is never removed. */
  removeAutoDreamTeam: boolean;
  /** This gameweek is voided (it scored zero). */
  voided: boolean;
  /** Squads that failed squadFromMap (malformed) — callers log these. */
  skippedSquadUids: string[];
}

/** Dart `~/ 10` on tenths: truncation toward zero (a -155-tenth week is -15
 *  points, not -16). */
export function wholePoints(tenths: number): number {
  return Math.trunc(tenths / 10);
}

/** 1-based competition ranks: ties share the smaller rank (1,1,3). */
export function competitionRanks(
  points: Record<string, number>,
): Record<string, number> {
  const values = Object.values(points);
  const ranks: Record<string, number> = {};
  for (const [id, p] of Object.entries(points)) {
    ranks[id] = 1 + values.filter((v) => v > p).length;
  }
  return ranks;
}

/** The Overall board from History net tenths (week -> uid -> tenths):
 *  points = sum of each week's WHOLE points; rank competition-style;
 *  movement vs the standings before the LATEST week present (so a rerun of
 *  an old week after later weeks finalized still compares the current
 *  standings to the previous gameweek's, never to a stale cut). */
export function composeOverallBoard(
  historyTenthsByWeek: Record<number, Record<string, number>>,
): Record<string, { points: number; rank: number; movement?: number }> {
  const weeks = Object.keys(historyTenthsByWeek).map(Number)
    .filter((w) => Number.isFinite(w));
  if (weeks.length === 0) return {};
  const maxWeek = Math.max(...weeks);

  const totals: Record<string, number> = {};
  const prevTotals: Record<string, number> = {};
  for (const w of weeks) {
    for (const [uid, tenths] of Object.entries(historyTenthsByWeek[w])) {
      const pts = wholePoints(tenths);
      totals[uid] = (totals[uid] ?? 0) + pts;
      if (w < maxWeek) prevTotals[uid] = (prevTotals[uid] ?? 0) + pts;
    }
  }

  const ranks = competitionRanks(totals);
  const prevRanks = competitionRanks(prevTotals);
  const out: Record<string, { points: number; rank: number; movement?: number }> = {};
  for (const [uid, points] of Object.entries(totals)) {
    const prev = prevRanks[uid];
    out[uid] = {
      points,
      rank: ranks[uid],
      // Positive = climbed. Omitted for brand-new managers (no earlier
      // finalized week) — the client renders the neutral "—".
      ...(prev !== undefined ? { movement: prev - ranks[uid] } : {}),
    };
  }
  return out;
}

/** The week's Dream Team: top bonus-inclusive scorers among ELIGIBLE market
 *  players who PLAYED that week ([week] played flag — no game or absent =
 *  never picked, however low the players who did play scored), in the
 *  config formation, points desc then name asc. Short positions (tiny
 *  market, or too few players of a position played) simply fill fewer
 *  slots. */
export function pickDreamTeam(
  week: Record<string, PlayerWeek>,
  players: Record<string, MarketPlayer>,
  cfg: FantasyConfig,
  nowMs: number,
): DreamTeamNode {
  const take = (position: FantasyPosition, count: number) =>
    Object.entries(players)
      .filter(([name, p]) => p.eligible && p.position === position &&
        week[name]?.played === true)
      .map(([name]) => ({
        name, position, points: week[name].points,
      }))
      .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name))
      .slice(0, count);
  return {
    Players: [
      ...take('GK', cfg.startersGk),
      ...take('DEF', cfg.startersDef),
      ...take('ATT', cfg.startersAtt),
    ],
    ComputedAt: nowMs,
    Auto: true,
  };
}

/** The whole finalize pipeline for one gameweek, pure: games -> stats ->
 *  base+BPS+bonus -> player weeks -> squad weeks -> boards/totals/dream
 *  team. Deterministic and rerunnable: same inputs, same outputs — a
 *  score/attendance edit changes the inputs and everything downstream
 *  re-settles. */
export function computeGameweekFinalize(input: FinalizeInput): FinalizeOutput {
  const { cfg, gw, nowMs } = input;
  const costs = input.transferCostPointsByUid ?? {};
  const voidedWeeks = new Set(input.voidedWeeks ?? []);
  const voided = voidedWeeks.has(gw);

  // ── Stage 1: mapper — both teams of every game (golden replay parity) ──
  const statsByGame: Record<string, PlayerGameStats>[] = [];
  for (const g of input.games) {
    const merged: Record<string, PlayerGameStats> = {};
    for (const key of ['team1', 'team2'] as const) {
      const team = g.node[key];
      if (typeof team !== 'string' || team.length === 0) continue;
      Object.assign(merged, mapGameToStats(g.node, {
        teamName: team,
        attendance: g.attendance?.[team] ?? null,
      }));
    }
    statsByGame.push(merged);
  }

  // ── Stage 2: per-game BPS + 3/2/1 bonus. The BPS pool is EVERY player in
  // the game (guests included — a client-side engine replay sees the same
  // pool), so a hot guest can consume a bonus slot exactly as on court. ──
  const bonusByGame: Record<string, number>[] = [];
  for (const stats of statsByGame) {
    const bps: Record<string, number> = {};
    for (const [id, s] of Object.entries(stats)) {
      bps[id] = bpsScore(s, cfg);
    }
    bonusByGame.push(awardBonus(bps));
  }

  // ── Stage 3: player weeks (base + bonus) for every market player ──
  const week: Record<string, PlayerWeek> = {};
  const playerWeeks: Record<string, number> = {};
  for (const [name, p] of Object.entries(input.players)) {
    const wk = scorePlayerWeek(
      statsByGame.filter((stats) => name in stats).map((stats) => stats[name]),
      p.position,
      cfg,
    );
    const bonus = bonusByGame.reduce((a, b) => a + (b[name] ?? 0), 0);
    week[name] = { points: wk.total + bonus, played: wk.played };
    playerWeeks[name] = wk.total + bonus;
  }

  // ── Stage 4: squad weeks -> History entries + weekly board ──
  const historyByUid: Record<string, Record<string, unknown>> = {};
  const weekTenthsByUid: Record<string, number> = {};
  const holders: Record<string, number> = {};
  const skippedSquadUids: string[] = [];
  for (const [uid, raw] of Object.entries(input.squadsByUid)) {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      skippedSquadUids.push(uid);
      continue;
    }
    let squad;
    try {
      squad = squadFromMap(raw as Record<string, unknown>);
    } catch {
      skippedSquadUids.push(uid);
      continue;
    }
    const result = scoreSquadWeek(squad, week, cfg);
    const gross = totalTenths(result);
    const cost = costs[uid] ?? 0;
    // A voided week counts zero — the transfer cost is waived with it.
    const net = voided ? 0 : gross - cost * 10;
    weekTenthsByUid[uid] = net;
    historyByUid[uid] = {
      ...squadToMap(squad),
      TotalTenths: net,
      ...(voided ? { Voided: true } : {}),
      Breakdown: result.slots.map((s) => ({
        playerId: s.playerId,
        countedTenths: s.countedTenths,
        multiplier: s.multiplier,
        autoSubbedIn: s.autoSubbedIn,
      })),
    };
    for (const pick of squad.picks) {
      holders[pick.playerId] = (holders[pick.playerId] ?? 0) + 1;
    }
  }

  const weekPointsByUid: Record<string, number> = {};
  for (const [uid, tenths] of Object.entries(weekTenthsByUid)) {
    weekPointsByUid[uid] = wholePoints(tenths);
  }
  const weekRanks = competitionRanks(weekPointsByUid);
  const gameweekBoard: Record<string, { points: number; rank: number }> = {};
  for (const [uid, points] of Object.entries(weekPointsByUid)) {
    gameweekBoard[uid] = { points, rank: weekRanks[uid] };
  }

  // ── Stage 5: Overall = resum across History weeks with this week swapped
  // in (rerun-idempotent: the stored TotalTenths of other weeks are already
  // net). Every voided week resums as zero for its managers (they still
  // appear — a voided week is played, just not counted). ──
  const historyTenths: Record<number, Record<string, number>> = {};
  const historyAll: Record<number, Record<string, number>> = {
    ...input.historyTenthsByWeek,
    [gw]: weekTenthsByUid,
  };
  for (const [w, byUid] of Object.entries(historyAll)) {
    const week = Number(w);
    historyTenths[week] = voidedWeeks.has(week)
      ? Object.fromEntries(Object.keys(byUid).map((uid) => [uid, 0]))
      : byUid;
  }
  const overallBoard = composeOverallBoard(historyTenths);

  // ── Stage 6: PlayerTotals (season sum incl. bonus over NON-voided weeks
  // + the LATEST finalized week's ownership) ──
  const weeksAll: Record<number, Record<string, number>> = {
    ...input.playerWeeksByWeek,
    [gw]: playerWeeks,
  };
  let ownHolders = holders;
  let managers = Object.keys(weekTenthsByUid).length;
  if (input.ownershipSquadsByUid !== undefined) {
    // An older week re-ran: ownership stays the latest week's holdings
    // (malformed squads skipped exactly as that week's own finalize did).
    ownHolders = {};
    managers = 0;
    for (const raw of Object.values(input.ownershipSquadsByUid)) {
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) continue;
      let squad;
      try {
        squad = squadFromMap(raw as Record<string, unknown>);
      } catch {
        continue;
      }
      managers++;
      for (const pick of squad.picks) {
        ownHolders[pick.playerId] = (ownHolders[pick.playerId] ?? 0) + 1;
      }
    }
  }
  const playerTotals: Record<string, { points: number; ownershipPct: number }> = {};
  for (const name of Object.keys(input.players)) {
    let points = 0;
    for (const [w, byName] of Object.entries(weeksAll)) {
      if (voidedWeeks.has(Number(w))) continue;
      points += byName[name] ?? 0;
    }
    playerTotals[name] = {
      points,
      ownershipPct: managers === 0
        ? 0
        : Math.round((100 * (ownHolders[name] ?? 0)) / managers),
    };
  }

  // ── Stage 7: Dream Team (admin edits win; a voided week has none, and
  // only OUR earlier node is taken down) ──
  const dreamTeam = voided || input.dreamTeamAuto === false
    ? null
    : pickDreamTeam(week, input.players, cfg, nowMs);

  return {
    playerWeeks,
    historyByUid,
    gameweekBoard,
    overallBoard,
    playerTotals,
    dreamTeam,
    removeAutoDreamTeam: voided && input.dreamTeamAuto === true,
    voided,
    skippedSquadUids,
  };
}

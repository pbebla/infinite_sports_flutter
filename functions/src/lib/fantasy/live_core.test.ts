// computeLiveWeek + buildLiveBase (live design 2026-11-03 §2, §5).
//
// THE CONTRACT (the heart of this file): when every game of the day is
// Final and no team is still to kick off, computeLiveWeek must publish
// exactly what computeGameweekFinalize then writes — week board, Overall
// points/rank/movement, player week points and lines, season points, form,
// ppg, games, ownership, Team of the Week, squad net tenths and slots — so
// the hand-off from live to official numbers never jumps. Each scenario
// finalizes the earlier weeks, builds the settled base from what those
// runs wrote, and compares the live run against gw's own finalize, every
// uid and every player, field for field (toStrictEqual: an omitted M/W/WR
// or Lines must be omitted on both sides).
//
// The unit cases below the contract are hand math from futsalDefault(),
// never copied from output.

import { describe, expect, it } from 'vitest';
import { FantasyPosition, futsalDefault, parsePosition } from './fantasy_config';
import {
  computeGameweekFinalize, FinalizeGame, FinalizeOutput, MarketPlayer,
  wholePoints,
} from './finalize_core';
import { clone, Json, loadGoldenFixture } from './golden_fixture';
import {
  buildLiveBase, computeLiveWeek, LiveBase, LiveInput, LiveOutput,
} from './live_core';

const cfg = futsalDefault();
const NOW = 1_762_000_000_000;
const READ_AT = NOW - 500;

// ─────────────────────────── shared helpers ───────────────────────────

/** Paths of every undefined value (RTDB rejects a write carrying one). */
function undefinedPaths(v: unknown, path = '$'): string[] {
  if (v === undefined) return [path];
  if (v === null || typeof v !== 'object') return [];
  return Object.entries(v as Record<string, unknown>)
    .flatMap(([k, child]) => undefinedPaths(child, `${path}.${k}`));
}

type Pick = [string, FantasyPosition, boolean?];

/** A raw squad map (PublishedPicks shape); [bench] marks bench picks. */
function squad(
  picks: Pick[], captainId: string, viceId: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    picks: picks.map(([playerId, position, bench]) => ({
      playerId, position, priceTenths: 50, bench: bench === true,
    })),
    captainId,
    viceId,
    ...extra,
  };
}

/** The day's status table (Meta.Games) of [games], every game at [s]. */
function statusTable(
  games: FinalizeGame[], s: 0 | 1 | 2,
): LiveInput['gameStatus'] {
  return Object.fromEntries(games.map((g, i) => [String(i), {
    S: s, T1: String(g.node['team1']), T2: String(g.node['team2']),
  }]));
}

/** What the stored nodes a later week reads back hold for one finalized
 *  week (orchestration.ts finalizeGameweek: PlayerWeeks, PlayerWeekStats
 *  GP, History TotalTenths). */
function storedWeek(fin: FinalizeOutput) {
  return {
    playerWeeks: { ...fin.playerWeeks },
    playedGames: Object.fromEntries(
      Object.entries(fin.playerWeekStats).map(([n, e]) => [n, e.GP])),
    historyTenths: Object.fromEntries(
      Object.entries(fin.historyByUid)
        .map(([u, h]) => [u, h['TotalTenths'] as number])),
  };
}

interface BreakdownRow {
  playerId: string;
  countedTenths: number;
  multiplier: number;
  autoSubbedIn: boolean;
}

/** The Live node (Meta aside) that gw's finalize output implies at full
 *  time: Board from overallBoard + gameweekBoard, Players from
 *  playerWeekStats + playerTotals (St from the real Played flag — nobody is
 *  live or pending once every game is Final), Squads from History,
 *  TeamOfWeek from the Dream Team (none for a voided week). */
function expectedFromFinalize(fin: FinalizeOutput): Omit<LiveOutput, 'Meta'> {
  const Board: LiveOutput['Board'] = {};
  for (const [uid, o] of Object.entries(fin.overallBoard)) {
    const g = fin.gameweekBoard[uid];
    Board[uid] = {
      O: o.points,
      R: o.rank,
      ...(o.movement !== undefined ? { M: o.movement } : {}),
      ...(g !== undefined ? { W: g.points, WR: g.rank } : {}),
    };
  }
  // Every manager on the week board is on the Overall board too.
  for (const uid of Object.keys(fin.gameweekBoard)) {
    expect(Board[uid], `overall row for ${uid}`).toBeDefined();
  }

  const Players: LiveOutput['Players'] = {};
  for (const [name, t] of Object.entries(fin.playerTotals)) {
    const s = fin.playerWeekStats[name];
    Players[name] = {
      Pts: s.Pts,
      St: s.Played ? 'done' : 'out',
      ...(s.Lines !== undefined ? { Lines: s.Lines } : {}),
      Total: t.points,
      Form: t.form,
      Ppg: t.ppg,
      Games: t.games,
      Own: t.ownershipPct,
    };
  }

  const Squads: LiveOutput['Squads'] = {};
  for (const [uid, h] of Object.entries(fin.historyByUid)) {
    const T = h['TotalTenths'] as number;
    const breakdown = (h['Breakdown'] ?? []) as BreakdownRow[];
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

  return {
    Board,
    Players,
    Squads,
    TeamOfWeek: fin.dreamTeam?.Players ?? [],
  };
}

function expectLiveEqualsFinalize(
  live: LiveOutput, fin: FinalizeOutput, gw: number,
  gameStatus: LiveInput['gameStatus'],
): void {
  const { Meta, ...numbers } = live;
  expect(numbers).toStrictEqual(expectedFromFinalize(fin));
  expect(Meta).toStrictEqual({
    Gw: gw, State: 'live', ReadAt: READ_AT, UpdatedAt: NOW, Games: gameStatus,
  });
  expect(undefinedPaths(live)).toEqual([]);
}

// ─────────────────── scenario (i): the golden gameweek ───────────────────

const golden = loadGoldenFixture();

function goldenGames(): FinalizeGame[] {
  return (golden['games'] as Json[]).map((g) => {
    const byTeam: Json | null = g['attendance'] ?? null;
    const attendance: Record<string, Record<string, boolean> | null> = {};
    for (const team of [g['node']['team1'], g['node']['team2']] as string[]) {
      const raw: Json | null = byTeam?.[team] ?? null;
      if (raw === null) {
        attendance[team] = null;
        continue;
      }
      const m: Record<string, boolean> = {};
      for (const [k, v] of Object.entries(raw)) m[k] = v === true;
      attendance[team] = m;
    }
    return { node: clone(g['node']) as Record<string, unknown>, attendance };
  });
}

function goldenPlayers(): Record<string, MarketPlayer> {
  const out: Record<string, MarketPlayer> = {};
  for (const p of golden['players'] as Json[]) {
    out[p['id']] = {
      position: parsePosition(p['position']), eligible: true,
      teamName: p['team'],
    };
  }
  return out;
}

function goldenSquads(): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const s of golden['squads'] as Json[]) out[s['name']] = clone(s['squad']);
  return out;
}

// ──────────── scenarios (ii)–(iv): a 4-week synthetic season ────────────
//
// Four teams play twice a week (every team every week). Lions/Tigers/
// Bears/Wolves: GK, 2 DEF, 2 ATT each; Wolves also field Ivy (ATT,
// INELIGIBLE: never Team of the Week); Gus is a guest (not in the market)
// who scores for the Tigers in week 2 and so takes part in that game's BPS.
// Full roster attendance, one absentee per game.
//
// Managers: alpha (steady) and twin (alpha's exact squad: every rank ties);
// boost (Bench Boost in week 2, captain Wes absent that week -> vice Bo
// wears the armband); triple (Triple Captain Bo in week 3); hitter (4-point
// hit in week 2, a 40-point hit in week 4); skipper (no squad in week 3);
// bad (Invalid in week 2); newbie (joins in week 3); junk (a malformed
// squad in week 4, skipped by both engines).

const TEAMS: Record<string, Array<[string, FantasyPosition]>> = {
  Lions: [['Lex', 'GK'], ['Lou', 'DEF'], ['Lia', 'DEF'], ['Leo', 'ATT'], ['Lana', 'ATT']],
  Tigers: [['Tim', 'GK'], ['Ted', 'DEF'], ['Tia', 'DEF'], ['Tom', 'ATT'], ['Tess', 'ATT']],
  Bears: [['Bri', 'GK'], ['Bea', 'DEF'], ['Bev', 'DEF'], ['Bo', 'ATT'], ['Ben', 'ATT']],
  Wolves: [['Wox', 'GK'], ['Wil', 'DEF'], ['Wyn', 'DEF'], ['Wes', 'ATT'], ['Wren', 'ATT'], ['Ivy', 'ATT']],
};

const SEASON_PLAYERS: Record<string, MarketPlayer> = Object.fromEntries(
  Object.entries(TEAMS).flatMap(([teamName, roster]) => roster.map(
    ([name, position]) => [name, {
      position, eligible: name !== 'Ivy', teamName,
    }])));

const POS: Record<string, FantasyPosition> = Object.fromEntries(
  Object.entries(SEASON_PLAYERS).map(([n, p]) => [n, p.position]));

/** 'Goal:Leo' x times -> minute-keyed activity leaves. */
function activity(events: string[]): Record<string, unknown> {
  return Object.fromEntries(events.map((e, i) => {
    const [type, player] = e.split(':');
    return [`${i + 1}'`, [{ [type]: player }]];
  }));
}

function times(n: number, event: string): string[] {
  return Array.from({ length: n }, () => event);
}

function rosterAttendance(team: string, absent: string[]): Record<string, boolean> {
  return Object.fromEntries(TEAMS[team].map(([n]) => [n, !absent.includes(n)]));
}

function seasonGame(
  team1: string, team2: string, score: [number, number],
  ev1: string[], ev2: string[], absent: string[],
): FinalizeGame {
  return {
    node: {
      team1, team2, team1score: score[0], team2score: score[1], status: 2,
      team1activity: activity(ev1), team2activity: activity(ev2),
    },
    attendance: {
      [team1]: rosterAttendance(team1, absent),
      [team2]: rosterAttendance(team2, absent),
    },
  };
}

/** GK, DEF, DEF, ATT, ATT starters; bench DEF, ATT. */
function xi(
  names: [string, string, string, string, string, string, string],
  captainId: string, viceId: string, extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return squad(names.map((n, i) => [n, POS[n], i >= 5] as Pick),
    captainId, viceId, extra);
}

const ALPHA = (): Record<string, unknown> =>
  xi(['Lex', 'Lou', 'Lia', 'Leo', 'Tom', 'Ted', 'Wes'], 'Leo', 'Tom');
const BOOST = (extra = {}): Record<string, unknown> =>
  xi(['Tim', 'Bea', 'Wil', 'Wes', 'Bo', 'Bev', 'Tess'], 'Wes', 'Bo', extra);
const TRIPLE = (extra = {}): Record<string, unknown> =>
  xi(['Bri', 'Tia', 'Wyn', 'Tess', 'Bo', 'Lou', 'Wren'], 'Bo', 'Tess', extra);
const SKIPPER = (): Record<string, unknown> =>
  xi(['Wox', 'Wil', 'Bea', 'Wes', 'Wren', 'Tia', 'Tom'], 'Wes', 'Wren');
const BAD = (extra = {}): Record<string, unknown> =>
  xi(['Tim', 'Ted', 'Tia', 'Tom', 'Tess', 'Lou', 'Leo'], 'Tom', 'Tess', extra);
const NEWBIE = (): Record<string, unknown> =>
  xi(['Bri', 'Bev', 'Bea', 'Bo', 'Ben', 'Wil', 'Wes'], 'Bo', 'Ben');
const HITTER_W2 = (): Record<string, unknown> =>
  xi(['Lex', 'Bea', 'Ted', 'Tess', 'Leo', 'Wyn', 'Ben'], 'Tess', 'Leo');

interface SeasonWeek {
  games: FinalizeGame[];
  squads: Record<string, unknown>;
  costs: Record<string, number>;
}

function season(): SeasonWeek[] {
  return [
    { // week 1
      games: [
        seasonGame('Lions', 'Tigers', [3, 1],
          ['Goal:Leo', 'Assist:Lana', 'Goal:Leo', 'Goal:Lou', ...times(3, 'Save:Lex'), 'Yellow:Lia'],
          ['Goal:Tom', 'Assist:Tess', ...times(4, 'Save:Tim'), 'OwnGoal:Ted'],
          ['Tia']),
        seasonGame('Bears', 'Wolves', [0, 2],
          [...times(5, 'Save:Bri'), 'Yellow:Bo', 'Red:Ben'],
          ['Goal:Ivy', 'Goal:Wes', 'Assist:Wren', ...times(2, 'Save:Wox')],
          ['Bev']),
      ],
      squads: {
        alpha: ALPHA(), twin: ALPHA(), boost: BOOST(), triple: TRIPLE(),
        hitter: xi(['Wox', 'Bea', 'Ted', 'Ivy', 'Leo', 'Lia', 'Ben'], 'Ivy', 'Leo'),
        skipper: SKIPPER(), bad: BAD(),
      },
      costs: {},
    },
    { // week 2
      games: [
        seasonGame('Lions', 'Bears', [1, 1],
          ['Goal:Lana', 'Assist:Leo', ...times(5, 'DPL:Lou')],
          ['Goal:Bea', 'PenMissed:Bo', ...times(2, 'Save:Bri')],
          ['Lex']),
        seasonGame('Tigers', 'Wolves', [2, 0],
          ['Goal:Tess', 'Goal:Gus', 'Assist:Ted', ...times(2, 'Save:Tim')],
          ['OwnGoal:Wil', 'Yellow:Wyn', 'SecondYellow:Wyn', ...times(4, 'Save:Wox')],
          ['Wes']),
      ],
      squads: {
        alpha: ALPHA(), twin: ALPHA(),
        boost: BOOST({ chip: 'benchBoost' }), triple: TRIPLE(),
        hitter: HITTER_W2(), skipper: SKIPPER(),
        bad: BAD({ Invalid: ['overBudget'] }),
      },
      costs: { hitter: 4 },
    },
    { // week 3
      games: [
        seasonGame('Lions', 'Wolves', [0, 2],
          [...times(6, 'Save:Lex'), 'Yellow:Leo'],
          ['Goal:Wren', 'Goal:Wes', 'Assist:Wil', ...times(5, 'DPL:Wyn')],
          ['Lana']),
        seasonGame('Tigers', 'Bears', [1, 3],
          ['Goal:Tom', 'Red:Ted', ...times(3, 'Save:Tim')],
          ['Goal:Bo', 'Goal:Bo', 'Goal:Ben', 'Assist:Bev', 'Assist:Bea', 'Save:Bri'],
          ['Tess']),
      ],
      squads: {
        alpha: ALPHA(), twin: ALPHA(), boost: BOOST(),
        triple: TRIPLE({ chip: 'tripleCaptain' }),
        hitter: HITTER_W2(), bad: BAD(), newbie: NEWBIE(),
      },
      costs: {},
    },
    { // week 4
      games: [
        seasonGame('Lions', 'Tigers', [2, 2],
          ['Goal:Leo', 'Goal:Lia', 'Assist:Lana', ...times(2, 'Save:Lex')],
          ['Goal:Tom', 'Goal:Tess', 'Assist:Tia', 'Save:Tim'],
          ['Lou']),
        seasonGame('Bears', 'Wolves', [1, 0],
          ['Goal:Bo', ...times(3, 'Save:Bri'), 'PenSaved:Bri'],
          ['PenMissed:Wes', 'Yellow:Wren', ...times(3, 'Save:Wox')],
          ['Wyn']),
      ],
      squads: {
        alpha: ALPHA(), twin: ALPHA(), boost: BOOST(), triple: TRIPLE(),
        hitter: xi(['Bri', 'Lia', 'Tia', 'Leo', 'Tom', 'Bev', 'Wren'], 'Leo', 'Tom'),
        skipper: SKIPPER(), bad: BAD(), newbie: NEWBIE(), junk: 'garbage',
      },
      costs: { hitter: 40, alpha: 0 },
    },
  ];
}

interface SeasonRun {
  gw: number;
  week: SeasonWeek;
  fin: FinalizeOutput;
  live: LiveOutput;
  base: LiveBase;
  gameStatus: LiveInput['gameStatus'];
  /** The previous week's finalize (null for week 1). */
  prev: FinalizeOutput | null;
  /** The live run at kickoff: every game of gw still status 0. */
  kickoff: LiveOutput;
}

/** Finalizes the season week by week (each run reading back what the
 *  earlier ones stored) and, for every week, runs the live computation at
 *  full time and at kickoff from a base built on the earlier weeks. */
function runSeason(voidedWeeks: number[]): SeasonRun[] {
  const playerWeeksByWeek: Record<number, Record<string, number>> = {};
  const playedGamesByWeek: Record<number, Record<string, number>> = {};
  const historyTenthsByWeek: Record<number, Record<string, number>> = {};
  const runs: SeasonRun[] = [];
  let prev: FinalizeOutput | null = null;
  season().forEach((week, i) => {
    const gw = i + 1;
    const voided = voidedWeeks.includes(gw);
    const fin = computeGameweekFinalize({
      cfg,
      gw,
      games: week.games,
      players: SEASON_PLAYERS,
      squadsByUid: clone(week.squads),
      transferCostPointsByUid: week.costs,
      playerWeeksByWeek: clone(playerWeeksByWeek),
      playedGamesByWeek: clone(playedGamesByWeek),
      historyTenthsByWeek: clone(historyTenthsByWeek),
      dreamTeamAuto: null,
      voidedWeeks,
      nowMs: NOW,
    });
    // The base goes through a JSON round trip, as LiveBase/<gw> would.
    const base = clone(buildLiveBase({
      gw,
      historyTenthsByWeek: clone(historyTenthsByWeek),
      playerWeeksByWeek: clone(playerWeeksByWeek),
      playedGamesByWeek: clone(playedGamesByWeek),
      voidedWeeks,
    }));
    const gameStatus = statusTable(week.games, 2);
    const liveInput = (games: FinalizeGame[], status: LiveInput['gameStatus']): LiveInput => ({
      cfg,
      gw,
      games,
      players: SEASON_PLAYERS,
      squadsByUid: clone(week.squads),
      transferCostPointsByUid: week.costs,
      voided,
      base,
      gameStatus: status,
      readAtMs: READ_AT,
      nowMs: NOW,
    });
    const live = computeLiveWeek(liveInput(week.games, gameStatus));
    const kickoff = computeLiveWeek(liveInput([], statusTable(week.games, 0)));
    runs.push({ gw, week, fin, live, base, gameStatus, prev, kickoff });

    const stored = storedWeek(fin);
    playerWeeksByWeek[gw] = stored.playerWeeks;
    playedGamesByWeek[gw] = stored.playedGames;
    historyTenthsByWeek[gw] = stored.historyTenths;
    prev = fin;
  });
  return runs;
}

const SCENARIOS: Array<[string, number[]]> = [
  ['(ii) no voided week', []],
  ['(iii) week 2 voided', [2]],
  ['(iv) the live week itself voided (week 4)', [4]],
];

describe('THE CONTRACT: live at full time == finalize', () => {
  it('(i) the golden gameweek as gw 1', () => {
    const games = goldenGames();
    const gameStatus = statusTable(games, 2);
    const fin = computeGameweekFinalize({
      cfg,
      gw: 1,
      games: goldenGames(),
      players: goldenPlayers(),
      squadsByUid: goldenSquads(),
      // finalize_core.test.ts golden transfer usage: churn pays 4 points.
      transferCostPointsByUid: { alpha: 0, boost: 0, churn: 4 },
      playerWeeksByWeek: {},
      playedGamesByWeek: {},
      historyTenthsByWeek: {},
      dreamTeamAuto: null,
      nowMs: NOW,
    });
    const base = buildLiveBase({
      gw: 1, historyTenthsByWeek: {}, playerWeeksByWeek: {},
      playedGamesByWeek: {}, voidedWeeks: [],
    });
    const live = computeLiveWeek({
      cfg,
      gw: 1,
      games,
      players: goldenPlayers(),
      squadsByUid: goldenSquads(),
      transferCostPointsByUid: { alpha: 0, boost: 0, churn: 4 },
      voided: false,
      base,
      gameStatus,
      readAtMs: READ_AT,
      nowMs: NOW,
    });
    expectLiveEqualsFinalize(live, fin, 1, gameStatus);
    // Sanity: the golden board really is there (35/44/55, churn on top).
    expect(live.Board['churn']).toStrictEqual({ O: 55, R: 1, W: 55, WR: 1 });
  });

  for (const [label, voided] of SCENARIOS) {
    describe(label, () => {
      const runs = runSeason(voided);
      for (const run of runs) {
        it(`gw ${run.gw}${voided.includes(run.gw) ? ' (voided)' : ''}: every uid and every player match finalize`, () => {
          expectLiveEqualsFinalize(run.live, run.fin, run.gw, run.gameStatus);
        });
      }
    });
  }
});

describe('the synthetic season exercises everything it claims', () => {
  const runs = runSeason([]);
  const at = (gw: number) => runs[gw - 1].live;
  const slot = (live: LiveOutput, uid: string, p: string) =>
    live.Squads[uid].Slots.find((s) => s.p === p)!;
  const counted = (live: LiveOutput, uid: string) =>
    live.Squads[uid].Slots.reduce((a, s) => a + s.c, 0);

  it('Bench Boost (week 2): played bench players count in full; the vice wears the absent captain\'s armband', () => {
    const w2 = at(2);
    for (const p of ['Bev', 'Tess']) {
      expect(w2.Players[p].St, p).toBe('done');
      expect(slot(w2, 'boost', p).c, p).toBe(w2.Players[p].Pts * 10);
    }
    expect(slot(w2, 'boost', 'Wes')).toStrictEqual({ p: 'Wes', c: 0, x: 1 });
    expect(slot(w2, 'boost', 'Bo').x).toBe(2);
  });

  it('Triple Captain (week 3): the captain counts x3', () => {
    const w3 = at(3);
    expect(slot(w3, 'triple', 'Bo').x).toBe(3);
    expect(slot(w3, 'triple', 'Bo').c).toBe(w3.Players['Bo'].Pts * 30);
  });

  it('transfer hits come off the net tenths (weeks 2 and 4)', () => {
    expect(at(2).Squads['hitter'].T).toBe(counted(at(2), 'hitter') - 40);
    expect(at(4).Squads['hitter'].T).toBe(counted(at(4), 'hitter') - 400);
    expect(at(4).Board['hitter'].W).toBe(wholePoints(at(4).Squads['hitter'].T));
  });

  it('the invalid squad (week 2) scores zero with no slots, still on the boards', () => {
    expect(at(2).Squads['bad']).toStrictEqual({ T: 0, W: 0, Slots: [] });
    expect(at(2).Board['bad'].W).toBe(0);
  });

  it('a skipped week keeps the manager on Overall with movement but no week row', () => {
    const b = at(3).Board['skipper'];
    expect(b.W).toBeUndefined();
    expect(b.WR).toBeUndefined();
    expect(b.M).toBeDefined();
    expect(at(3).Squads['skipper']).toBeUndefined();
    expect(at(4).Board['skipper'].W).toBeDefined();
  });

  it('a manager new this week has no movement; the next week he has', () => {
    expect('M' in at(3).Board['newbie']).toBe(false);
    expect(at(3).Board['newbie'].W).toBeDefined();
    expect('M' in at(4).Board['newbie']).toBe(true);
  });

  it('auto-subs happen (week 4: Lou absent, Ted on in full)', () => {
    expect(slot(at(4), 'alpha', 'Ted').s).toBe(true);
    expect(slot(at(4), 'alpha', 'Lou').c).toBe(0);
  });

  it('identical squads tie on every rank; the malformed squad is nowhere', () => {
    for (const live of runs.map((r) => r.live)) {
      expect(live.Board['alpha'].W).toBeDefined();
      expect(live.Board['twin']).toStrictEqual(live.Board['alpha']);
    }
    expect(at(4).Board['junk']).toBeUndefined();
    expect(at(4).Squads['junk']).toBeUndefined();
  });

  it('the ineligible scorer and the guest never reach Players or the Team of the Week', () => {
    expect(at(1).Players['Ivy'].Pts).toBeGreaterThan(0);
    expect(at(1).TeamOfWeek.map((r) => r.name)).not.toContain('Ivy');
    expect(at(2).Players['Gus']).toBeUndefined();
  });
});

describe('kickoff: every pending player shows exactly last week\'s official numbers', () => {
  for (const [label, voided] of SCENARIOS) {
    for (const run of runSeason(voided).slice(1)) {
      it(`${label}, gw ${run.gw}`, () => {
        const prev = run.prev!;
        const { kickoff } = run;
        for (const [name, t] of Object.entries(prev.playerTotals)) {
          expect(kickoff.Players[name], name).toStrictEqual({
            Pts: 0,
            St: 'pending',
            Total: t.points,
            Form: t.form,
            Ppg: t.ppg,
            Games: t.games,
            // Ownership is this week's locked squads, as finalize will have it.
            Own: run.fin.playerTotals[name].ownershipPct,
          });
        }
        // Nobody counts a point yet; only a transfer hit moves a manager.
        const isVoided = voided.includes(run.gw);
        for (const [uid, sq] of Object.entries(kickoff.Squads)) {
          expect(sq.Slots.every((s) => s.c === 0), uid).toBe(true);
          const invalid = run.fin.historyByUid[uid]['Invalid'] !== undefined;
          const hit = isVoided || invalid ? 0 : (run.week.costs[uid] ?? 0);
          expect(sq.T, uid).toBe(0 - hit * 10); // never -0
        }
        for (const [uid, row] of Object.entries(kickoff.Board)) {
          expect(row.O, uid).toBe(
            (prev.overallBoard[uid]?.points ?? 0) + (isVoided ? 0 : row.W ?? 0));
        }
        expect(kickoff.TeamOfWeek).toEqual([]);
        expect(undefinedPaths(kickoff)).toEqual([]);
      });
    }
  }
});

// ───────────────────────────── unit cases ─────────────────────────────
//
// THE WORLD (Lions 3-1 Tigers, from week_core_pending.test.ts):
// - Lions: Leo Goal x2, Lana Goal, Vic Assist; attendance Leo/Lana/Vic/Dot
//   present, Abe absent. Tigers: Tom Goal (no attendance map).
// - BPS: Leo 24, Lana 12, Tom 12, Vic 9 -> bonus Leo 3, Lana + Tom 2.
// - Week points: Leo 1 + 8 + 3 = 12 (lines plays 1/1, goals 2/8, bonus
//   3/3); Lana 7; Tom 7; Vic 5; Dot 1; Abe 0 (absent). GP 1 each but Abe.
// - Pumas (Pia GK, Paz DEF, Pete ATT) kick off later; Bears (Bert) have no
//   game today.

const PLAYERS: Record<string, MarketPlayer> = {
  Leo: { position: 'ATT', eligible: true, teamName: 'Lions' },
  Lana: { position: 'ATT', eligible: true, teamName: 'Lions' },
  Vic: { position: 'DEF', eligible: true, teamName: 'Lions' },
  Dot: { position: 'DEF', eligible: true, teamName: 'Lions' },
  Abe: { position: 'DEF', eligible: true, teamName: 'Lions' },
  Tom: { position: 'ATT', eligible: true, teamName: 'Tigers' },
  Pia: { position: 'GK', eligible: true, teamName: 'Pumas' },
  Paz: { position: 'DEF', eligible: true, teamName: 'Pumas' },
  Pete: { position: 'ATT', eligible: true, teamName: 'Pumas' },
  Bert: { position: 'DEF', eligible: true, teamName: 'Bears' },
};

function lionsTigers(status: number): FinalizeGame {
  return {
    node: {
      team1: 'Lions', team2: 'Tigers', team1score: 3, team2score: 1, status,
      team1activity: {
        "2'": [{ Goal: 'Leo' }, { Assist: 'Vic' }],
        "7'": [{ Goal: 'Leo' }],
        "11'": [{ Goal: 'Lana' }],
      },
      team2activity: { "9'": [{ Goal: 'Tom' }] },
    },
    attendance: {
      Lions: { Leo: true, Lana: true, Vic: true, Dot: true, Abe: false },
      Tigers: null,
    },
  };
}

const LEO_LINES = {
  plays: { N: 1, P: 1 }, goals: { N: 2, P: 8 }, bonus: { N: 3, P: 3 },
};

function emptyBase(gw: number): LiveBase {
  return { Gw: gw, Managers: {}, Players: {}, FormWeeks: {} };
}

function liveInput(overrides: Partial<LiveInput> = {}): LiveInput {
  return {
    cfg,
    gw: 4,
    games: [lionsTigers(1)],
    players: PLAYERS,
    squadsByUid: {},
    voided: false,
    base: emptyBase(4),
    gameStatus: {
      '0': { S: 1, T1: 'Lions', T2: 'Tigers' },
      '1': { S: 0, T1: 'Pumas', T2: 'Hawks' },
    },
    readAtMs: READ_AT,
    nowMs: NOW,
    ...overrides,
  };
}

/** Pumas DEF Paz starts; Vic (DEF, played 5) waits on the bench. */
const PAZ_STARTS = squad([
  ['Pia', 'GK'], ['Paz', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
  ['Lana', 'ATT'], ['Vic', 'DEF', true], ['Tom', 'ATT', true],
], 'Leo', 'Lana');

/** Pia (no game: 0) GK; Vic, Dot; Leo (C) and Lana; bench Abe (absent),
 *  Tom (half). [captain]/[vice] swap the armband. */
function squadA(captainId = 'Leo', viceId = 'Lana') {
  return squad([
    ['Pia', 'GK'], ['Vic', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
    ['Lana', 'ATT'], ['Abe', 'DEF', true], ['Tom', 'ATT', true],
  ], captainId, viceId);
}

describe('computeLiveWeek: St, first match wins', () => {
  it('live > pending > done > out, game by game', () => {
    // Today: g0 Lions-Tigers LIVE; g1 Wolves-Hawks FINAL then g2
    // Wolves-Owls NOT STARTED; g3 Pumas-Rams LIVE then g4 Pumas-Owls NOT
    // STARTED; g5 Bears-Cats FINAL then g6 Bears-Kites LIVE. Geese: no game.
    const P = (teamName?: string): MarketPlayer =>
      ({ position: 'DEF', eligible: true, ...(teamName ? { teamName } : {}) });
    const players: Record<string, MarketPlayer> = {
      Leo: P('Lions'), Abe: P('Lions'), Tom: P('Tigers'),
      Xan: P('Wolves'), Yul: P('Wolves'),
      Pia: P('Pumas'), Paz: P('Pumas'),
      Bo: P('Bears'), Bez: P('Bears'), Cid: P('Cats'),
      Gus: P('Geese'), Nox: P(),
    };
    const g = (
      team1: string, team2: string, status: number,
      attendance: FinalizeGame['attendance'],
      node: Record<string, unknown> = {},
    ): FinalizeGame => ({
      node: { team1, team2, team1score: 0, team2score: 0, status, ...node },
      attendance,
    });
    const games: FinalizeGame[] = [
      g('Lions', 'Tigers', 1, { Lions: { Leo: true, Abe: false }, Tigers: null },
        { team2activity: { "3'": [{ Goal: 'Tom' }] }, team2score: 1 }),
      g('Wolves', 'Hawks', 2, { Wolves: { Xan: true, Yul: false }, Hawks: null }),
      g('Pumas', 'Rams', 1, { Pumas: { Pia: true, Paz: false }, Rams: null }),
      g('Bears', 'Cats', 2, { Bears: { Bo: true, Bez: false }, Cats: { Cid: true } }),
      g('Bears', 'Kites', 1, { Bears: { Bo: true, Bez: false }, Kites: null }),
    ];
    const S = (s: 0 | 1 | 2, T1: string, T2: string) => ({ S: s, T1, T2 });
    const out = computeLiveWeek(liveInput({
      games,
      players,
      gameStatus: {
        g0: S(1, 'Lions', 'Tigers'), g1: S(2, 'Wolves', 'Hawks'),
        g2: S(0, 'Wolves', 'Owls'), g3: S(1, 'Pumas', 'Rams'),
        g4: S(0, 'Pumas', 'Owls'), g5: S(2, 'Bears', 'Cats'),
        g6: S(1, 'Bears', 'Kites'),
      },
    }));
    const st = Object.fromEntries(
      Object.entries(out.Players).map(([n, p]) => [n, p.St]));
    expect(st).toEqual({
      Leo: 'live', // present in a live game
      Abe: 'out', // absent in a live game, no game still to come: NOT live
      Tom: 'live', // no attendance map: nobody is marked absent
      Xan: 'done', // played the Final game; his next one has not started
      Yul: 'pending', // absent in the Final game, Wolves still play today
      Pia: 'live', // present in a live game beats a game still to come
      Paz: 'pending', // absent in a live game, Pumas still play today
      Bo: 'live', // present in a live game beats having played earlier
      Bez: 'out', // absent in both, nothing to come
      Cid: 'done', // played, nothing to come
      Gus: 'out', // no game today
      Nox: 'out', // no team
    });
  });
});

describe('computeLiveWeek: player numbers', () => {
  // Settled base (gw 4): Pia P 25 over G 4, form weeks 1/2/3 = 6/2/10;
  // Leo P 30 over G 5, form weeks 1/2/3 = 4/8/(missing).
  const base: LiveBase = {
    Gw: 4,
    Managers: {},
    Players: { Pia: { P: 25, G: 4 }, Leo: { P: 30, G: 5 } },
    FormWeeks: {
      '1': { Pia: 6, Leo: 4 },
      '2': { Pia: 2, Leo: 8 },
      '3': { Pia: 10 },
    },
  };

  it('a pending player keeps his settled numbers; a playing one adds this week', () => {
    const out = computeLiveWeek(liveInput({
      base, squadsByUid: { u: PAZ_STARTS },
    }));
    // Pia pending: Total 25, Games 4, Form over the base weeks only
    // round(10 x (6+2+10)/3) = 60, Ppg round(10 x 25/4 = 62.5) = 63, Pts 0.
    // Owned by the one scored squad: 100.
    expect(out.Players['Pia']).toStrictEqual({
      Pts: 0, St: 'pending', Total: 25, Form: 60, Ppg: 63, Games: 4, Own: 100,
    });
    // Leo live: Pts 12 (provisional bonus 3 of a live game), Total 30+12 =
    // 42, Games 5+1 = 6, Form over gw4/w3/w2 = (12+0+8)/3 -> 66.7 -> 67,
    // Ppg round(10 x 42/6) = 70.
    expect(out.Players['Leo']).toStrictEqual({
      Pts: 12, St: 'live', Lines: LEO_LINES, BonusProv: true,
      Total: 42, Form: 67, Ppg: 70, Games: 6, Own: 100,
    });
    // Bert (no game, no base): out, all zero; unowned.
    expect(out.Players['Bert']).toStrictEqual({
      Pts: 0, St: 'out', Total: 0, Form: 0, Ppg: 0, Games: 0, Own: 0,
    });
    // Abe (absent in the live game): out, nothing scored.
    expect(out.Players['Abe'].St).toBe('out');
  });

  it('pending players stay on the court: no auto-sub, Team of the Week only from those who played', () => {
    // The pending rule (via the status-0 Pumas game): Paz is not auto-subbed,
    // bench DEF Vic counts half. Pia 0 + Paz 0 + Dot 10 + Leo 240 + Lana 70
    // + Vic 25 + Tom 35 = 380.
    const out = computeLiveWeek(liveInput({ squadsByUid: { u: PAZ_STARTS } }));
    expect(out.Squads['u'].T).toBe(380);
    expect(out.Squads['u'].Slots.find((s) => s.p === 'Vic'))
      .toStrictEqual({ p: 'Vic', c: 25, x: 1 });
    // GK slot stays empty (Pia has not played). DEF Vic 5, Dot 1; ATT Leo
    // 12, then Lana and Tom tie on 7 (name asc).
    expect(out.TeamOfWeek).toStrictEqual([
      { name: 'Vic', position: 'DEF', points: 5 },
      { name: 'Dot', position: 'DEF', points: 1 },
      { name: 'Leo', position: 'ATT', points: 12 },
      { name: 'Lana', position: 'ATT', points: 7 },
    ]);
  });

  it('BonusProv: only while the game is live, never in a voided week', () => {
    const final = computeLiveWeek(liveInput({
      games: [lionsTigers(2)],
      gameStatus: { '0': { S: 2, T1: 'Lions', T2: 'Tigers' } },
    }));
    expect(final.Players['Leo'].Pts).toBe(12);
    expect('BonusProv' in final.Players['Leo']).toBe(false);
    expect(final.Players['Leo'].St).toBe('done');

    const voided = computeLiveWeek(liveInput({ voided: true }));
    expect('BonusProv' in voided.Players['Leo']).toBe(false);
  });

  it('a voided week: 0 points, no lines, settled totals and form, no Team of the Week', () => {
    const out = computeLiveWeek(liveInput({
      voided: true,
      base: {
        Gw: 4,
        Managers: { a: { O: 50 } },
        Players: { Leo: { P: 30, G: 5 } },
        FormWeeks: { '1': { Leo: 4 }, '2': { Leo: 8 }, '3': { Leo: 0 } },
      },
      squadsByUid: { a: squadA() },
      transferCostPointsByUid: { a: 4 },
    }));
    // Leo still shows live (his game is on), but the week counts nothing:
    // Total 30, Games 5, Form (4+8+0)/3 = 4 -> 40, Ppg 300/5 = 60.
    expect(out.Players['Leo']).toStrictEqual({
      Pts: 0, St: 'live', Total: 30, Form: 40, Ppg: 60, Games: 5, Own: 100,
    });
    // Net 0 (the hit is waived), the would-have-counted slots kept.
    expect(out.Squads['a'].T).toBe(0);
    expect(out.Squads['a'].W).toBe(0);
    expect(out.Squads['a'].Slots.find((s) => s.p === 'Leo'))
      .toStrictEqual({ p: 'Leo', c: 240, x: 2 });
    expect(out.Board['a']).toStrictEqual({ O: 50, R: 1, M: 0, W: 0, WR: 1 });
    expect(out.TeamOfWeek).toEqual([]);
  });
});

describe('computeLiveWeek: board and squads', () => {
  // Lions 3-1 Tigers Final, nothing still to come.
  const finalDay = {
    games: [lionsTigers(2)],
    gameStatus: { '0': { S: 2 as const, T1: 'Lions', T2: 'Tigers' } },
  };

  it('ties share rank; a manager new this week has no M; an idle one has no W', () => {
    // a: squad A = Pia 0 + Vic 50 + Dot 10 + Leo 12x2 240 + Lana 70 + Abe 0
    //    + Tom half 35 = 405 -> W 40.
    // b: squad A, armband on Lana (vice Leo): 50+10+120+140+0+35 = 355 -> 35.
    // d (new): Tom starts (V), Lana benched half: 240+70+50+10+0+0+35 = 405
    //    -> 40.
    // Base O: a 50, b 55, c 45 (c has no squad this week).
    // O: a 90, b 90, c 45, d 40 -> R a 1, b 1, c 3, d 4.
    // Base ranks: b 1, a 2, c 3 -> M a +1, b 0, c 0; d omitted.
    // WR: a 40 and d 40 tie on 1, b 35 is 3.
    const out = computeLiveWeek(liveInput({
      ...finalDay,
      base: {
        ...emptyBase(4),
        Managers: { a: { O: 50 }, b: { O: 55 }, c: { O: 45 } },
      },
      squadsByUid: {
        a: squadA(),
        b: squadA('Lana', 'Leo'),
        d: squad([
          ['Pia', 'GK'], ['Vic', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
          ['Tom', 'ATT'], ['Abe', 'DEF', true], ['Lana', 'ATT', true],
        ], 'Leo', 'Tom'),
      },
    }));
    expect(out.Board).toStrictEqual({
      a: { O: 90, R: 1, M: 1, W: 40, WR: 1 },
      b: { O: 90, R: 1, M: 0, W: 35, WR: 3 },
      c: { O: 45, R: 3, M: 0 },
      d: { O: 40, R: 4, W: 40, WR: 1 },
    });
  });

  it('Squads: net tenths after the hit, whole points, slots in pick order; s only on an auto-sub', () => {
    // e: Abe (absent, Lions done for the day) starts -> bench DEF Vic on in
    // FULL 50. 0 + 0 + 10 + 240 + 70 + 50 + 35 = 405, minus a 4-point hit
    // = 365 -> W 36.
    const out = computeLiveWeek(liveInput({
      ...finalDay,
      squadsByUid: {
        e: squad([
          ['Pia', 'GK'], ['Abe', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
          ['Lana', 'ATT'], ['Vic', 'DEF', true], ['Tom', 'ATT', true],
        ], 'Leo', 'Lana'),
      },
      transferCostPointsByUid: { e: 4 },
    }));
    expect(out.Squads['e']).toStrictEqual({
      T: 365,
      W: 36,
      Slots: [
        { p: 'Pia', c: 0, x: 1 },
        { p: 'Abe', c: 0, x: 1 },
        { p: 'Dot', c: 10, x: 1 },
        { p: 'Leo', c: 240, x: 2 },
        { p: 'Lana', c: 70, x: 1 },
        { p: 'Vic', c: 50, x: 1, s: true },
        { p: 'Tom', c: 35, x: 1 },
      ],
    });
    expect(out.Board['e']).toStrictEqual({ O: 36, R: 1, W: 36, WR: 1 });
  });

  it('Meta carries the gameweek, the read and write stamps and the day\'s games', () => {
    const gameStatus = {
      '0': { S: 1 as const, T1: 'Lions', T2: 'Tigers' },
      '1': { S: 0 as const, T1: 'Pumas', T2: 'Hawks' },
    };
    const out = computeLiveWeek(liveInput({ gameStatus }));
    expect(out.Meta).toStrictEqual({
      Gw: 4, State: 'live', ReadAt: READ_AT, UpdatedAt: NOW, Games: gameStatus,
    });
    expect(undefinedPaths(out)).toEqual([]);
  });

  it('a status-0 game handed in by mistake counts nothing (spec §2)', () => {
    // Pumas-Hawks has not started; full attendance would give Pia her
    // appearance point if it were scored.
    const out = computeLiveWeek(liveInput({
      games: [lionsTigers(1), {
        node: { team1: 'Pumas', team2: 'Hawks', team1score: 0, team2score: 0, status: 0 },
        attendance: { Pumas: { Pia: true, Paz: true, Pete: true }, Hawks: null },
      }],
    }));
    expect(out.Players['Pia']).toMatchObject({ Pts: 0, St: 'pending', Games: 0 });
  });

  it('refuses a base built for another gameweek', () => {
    expect(() => computeLiveWeek(liveInput({ base: emptyBase(3) })))
      .toThrow(/gameweek/);
  });
});

describe('buildLiveBase', () => {
  it('sums settled weeks before gw (voided weeks zero), keeps the 3 newest non-voided weeks', () => {
    // gw 12; week 8 voided; weeks 12 and 13 are not settled before gw.
    const base = buildLiveBase({
      gw: 12,
      historyTenthsByWeek: {
        3: { a: 355, b: -155 },
        8: { a: 100, c: 50 },
        10: { a: 200 },
        11: { b: 300 },
        12: { a: 777 },
        13: { a: 888 },
      },
      playerWeeksByWeek: {
        3: { Leo: 4, Pia: 2 },
        8: { Leo: 9, Pia: 9, Zed: 5 },
        9: { Leo: 3 },
        10: { Leo: 1, Pia: 0 },
        11: { Leo: -2 },
        12: { Leo: 100 },
        13: { Pia: 50 },
      },
      playedGamesByWeek: {
        3: { Leo: 1, Pia: 1 },
        8: { Leo: 1, Pia: 1, Zed: 1 },
        9: { Leo: 1 },
        10: { Leo: 2, Pia: 0 },
        11: { Leo: 1 },
        12: { Leo: 1 },
        13: { Pia: 1 },
      },
      voidedWeeks: [8],
    });
    expect(base).toStrictEqual({
      Gw: 12,
      // a: 35 + 0 (voided) + 20 = 55; b: trunc(-15.5) = -15, + 30 = 15;
      // c: only in the voided week -> 0, still on the board.
      Managers: { a: { O: 55 }, b: { O: 15 }, c: { O: 0 } },
      // Leo: 4 + 3 + 1 - 2 = 6 over 1 + 1 + 2 + 1 = 5; Pia: 2 + 0 over 1.
      // Zed played only in the voided week: not settled at all.
      Players: { Leo: { P: 6, G: 5 }, Pia: { P: 2, G: 1 } },
      // Non-voided weeks before 12: 3, 9, 10, 11 -> newest three, numeric
      // (week 11 beats week 9; a string sort would keep 9 and 3).
      FormWeeks: {
        '11': { Leo: -2 },
        '10': { Leo: 1, Pia: 0 },
        '9': { Leo: 3 },
      },
    });
  });

  it('no settled weeks: an empty base', () => {
    expect(buildLiveBase({
      gw: 1, historyTenthsByWeek: {}, playerWeeksByWeek: {},
      playedGamesByWeek: {}, voidedWeeks: [],
    })).toStrictEqual({ Gw: 1, Managers: {}, Players: {}, FormWeeks: {} });
  });
});

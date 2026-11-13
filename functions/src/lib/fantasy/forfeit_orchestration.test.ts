// Forfeits through the REAL finalize entry (spec §8a): the match-day
// trigger path (maybeFinalizeGame) over production node shapes — Line Ups
// rosters composed into full attendance, the absent-only team1attendance
// node, a list Date node — on the golden_forfeit.json games. Marking a
// forfeit or undoing it is just another write to a Final game node, and
// the trigger reruns on any game-node write, so both directions must
// re-settle every number (finalize is deterministic and rerunnable).
//
// Forfeit numbers: the fixture's hand math (_notes). Normal-game numbers
// after the undo are hand-computed below.

import { describe, expect, it } from 'vitest';
import { clone, Json, loadFantasyFixture } from './golden_fixture';
import { maybeFinalizeGame } from './orchestration';
import { FakeDb } from './test_support';

const fixture = loadFantasyFixture('golden_forfeit.json');
const expected: Json = fixture['expected'];

// 2026-06-28 is a Sunday; futsal default lockHour 15 => lock 22:00Z (PDT).
const DATE_KEY = '06282026';
const AFTER_LOCK = new Date(Date.UTC(2026, 5, 28, 23));
const ROOT = 'Fantasy/Futsal/15';

function world(): Record<string, any> {
  const games: Json[] = fixture['games'];
  const players: Json = {};
  for (const p of fixture['players'] as Json[]) {
    players[p['id']] = {
      position: p['position'], priceTenths: p['priceTenths'], eligible: true,
    };
  }
  const squads: Json = {};
  for (const s of fixture['squads'] as Json[]) squads[s['name']] = clone(s['squad']);
  return {
    Fantasy: {
      Futsal: { '15': { Config: { lockHour: 15 }, Players: players, Squads: squads } },
    },
    Futsal: {
      '15': {
        // The forfeit node carries the Manager's absent-only attendance
        // (team1attendance { Lena: false }); finalize composes it with the
        // rosters below — the path that gives every rostered player of the
        // team that showed up their +1.
        Date: { [DATE_KEY]: [clone(games[0]['node']), clone(games[1]['node'])] },
        'Line Ups': {
          Lions: { Luca: { n: 1 }, Lara: { n: 2 }, Leo: { n: 3 }, Lena: { n: 4 } },
          Tigers: { Tom: { n: 1 }, Tess: { n: 2 }, Theo: { n: 3 } },
          Hawks: { Hal: { n: 1 }, Hana: { n: 2 }, Hugo: { n: 3 } },
          Foxes: { Finn: { n: 1 }, Faye: { n: 2 }, Fred: { n: 3 } },
        },
      },
    },
  };
}

function expectedForfeitWeeks(): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [id, e] of Object.entries<any>(expected['playerWeeks'])) {
    out[id] = e['points'];
  }
  return out;
}

async function finalize(db: FakeDb): Promise<void> {
  await maybeFinalizeGame(db, {
    sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
  });
}

/** The Manager's Undo (buildUndoForfeitUpdate): marker + snapshot removed,
 *  the pre-forfeit result restored — here a game that had ended Final 2–0
 *  with its recorded events (Leo + Gus goals, Lara assist, Tom 2 saves,
 *  Theo yellow) before the forfeit was marked. */
function undoForfeit(db: FakeDb): void {
  const node = db.data.Futsal['15'].Date[DATE_KEY][0];
  delete node['forfeitedBy'];
  delete node['forfeitPrev'];
  node['team1score'] = 2;
  node['team2score'] = 0;
  node['status'] = 2;
}

/** The Manager's Forfeit button (buildForfeitUpdate): Tigers forfeit. */
function markForfeit(db: FakeDb): void {
  const node = db.data.Futsal['15'].Date[DATE_KEY][0];
  node['forfeitPrev'] = {
    team1score: node['team1score'], team2score: node['team2score'],
    status: node['status'],
  };
  node['forfeitedBy'] = 2;
  node['team1score'] = 5;
  node['team2score'] = 0;
  node['status'] = 2;
}

describe('forfeit finalize (spec §8a) — mark and undo both re-settle', () => {
  it('a forfeited match day settles to the golden forfeit numbers', async () => {
    const db = new FakeDb(world());
    await finalize(db);

    expect(await db.read(`${ROOT}/PlayerWeeks/1`)).toEqual(expectedForfeitWeeks());
    const history = await db.read(`${ROOT}/History/1`) as Json;
    expect(history['split']['TotalTenths']).toBe(80);
    expect(history['noband']['TotalTenths']).toBe(315);
    expect(await db.read(`${ROOT}/Leaderboards/Gameweek/1`)).toEqual({
      split: { points: 8, rank: 2 },
      noband: { points: 31, rank: 1 },
    });
    expect(((await db.read(`${ROOT}/DreamTeam/1`)) as Json)['Players'])
      .toEqual(expected['dreamTeam']);
    // Only the scoring changed: no LockedPositions/positions side effects
    // beyond the normal first-run snapshot.
    expect(await db.read(`${ROOT}/LockedPositions/1`)).toEqual(
      Object.fromEntries((fixture['players'] as Json[])
        .map((p) => [p['id'], p['position']])));
  });

  it('UNDO after Final re-scores the game normally; re-marking returns to ' +
    'the forfeit numbers', async () => {
    const db = new FakeDb(world());
    await finalize(db);

    undoForfeit(db);
    await finalize(db); // the game-node write re-triggers finalize

    // Lions 2–0 Tigers, events now real (hand math):
    //   Luca GK  plays1 + CS8                       = 9   BPS CS5        = 5
    //   Lara DEF plays1 + assist4 + CS5             = 10  BPS 9+5        = 14
    //   Leo  ATT plays1 + goal4 + CS2               = 7   BPS 12+5       = 17
    //   Gus  (no roster, not in the market) — BPS 12+5 = 17, no week points
    //   Lena absent                                 = 0   (not played)
    //   Tom  GK  plays1 + floor(2/2) saves - floor(2/2) conceded = 1, BPS 4
    //   Tess DEF plays1 - floor(2/2) conceded       = 0   BPS 0
    //   Theo ATT plays1 - yellow1                   = 0   BPS -4
    //   Bonus: Leo 17 = Gus 17 -> both 3 (slots 1+2), Lara 14 -> 1.
    // Game B unchanged (fixture): Hal 2, Hana 14, Hugo 7, Finn 1, Faye 3,
    // Fred 7.
    expect(await db.read(`${ROOT}/PlayerWeeks/1`)).toEqual({
      Luca: 9, Lara: 11, Leo: 10, Lena: 0, Tom: 1, Tess: 0, Theo: 0,
      Hal: 2, Hana: 14, Hugo: 7, Finn: 1, Faye: 3, Fred: 7,
    });
    // split (tripleCaptain): everyone played -> no auto-sub; captain Theo
    // played -> armband Theo x3 on 0. Luca 90 + Tess 0 + Faye 30 + Theo 0 +
    // Leo 100 + bench Lara 11*50~/10 = 55 + Lena 0 = 275.
    // noband: captain Tom played -> x2: 20 + Tess 0 + Hana 140 + Hugo 70 +
    // Fred 70 + bench Faye 3*50~/10 = 15 + bench Leo 10*50~/10 = 50 = 365.
    const history = await db.read(`${ROOT}/History/1`) as Json;
    expect(history['split']['TotalTenths']).toBe(275);
    expect(history['noband']['TotalTenths']).toBe(365);
    expect(history['split']['chip']).toBe('tripleCaptain'); // squad untouched
    const theo = (history['split']['Breakdown'] as Json[])
      .find((b) => b['playerId'] === 'Theo')!;
    expect(theo['multiplier']).toBe(3);
    expect(theo['autoSubbedIn']).toBe(false);
    expect(await db.read(`${ROOT}/Leaderboards/Gameweek/1`)).toEqual({
      split: { points: 27, rank: 2 },
      noband: { points: 36, rank: 1 },
    });
    // Dream Team: GK Luca 9; DEF Hana 14, Lara 11; ATT Leo 10, Fred 7
    // (Fred = Hugo 7, name order).
    expect(((await db.read(`${ROOT}/DreamTeam/1`)) as Json)['Players']).toEqual([
      { name: 'Luca', position: 'GK', points: 9 },
      { name: 'Hana', position: 'DEF', points: 14 },
      { name: 'Lara', position: 'DEF', points: 11 },
      { name: 'Leo', position: 'ATT', points: 10 },
      { name: 'Fred', position: 'ATT', points: 7 },
    ]);
    expect((await db.read(`${ROOT}/PlayerTotals`) as Json)['Leo'])
      .toEqual({ points: 10, ownershipPct: 100, form: 100, ppg: 100, games: 1 });

    // Re-marking the forfeit settles straight back to the golden numbers.
    markForfeit(db);
    await finalize(db);
    expect(await db.read(`${ROOT}/PlayerWeeks/1`)).toEqual(expectedForfeitWeeks());
    const again = await db.read(`${ROOT}/History/1`) as Json;
    expect(again['split']['TotalTenths']).toBe(80);
    expect(again['noband']['TotalTenths']).toBe(315);
    expect((await db.read(`${ROOT}/PlayerTotals`) as Json)['Leo'])
      .toEqual({ points: 1, ownershipPct: 100, form: 10, ppg: 10, games: 1 });
  });
});

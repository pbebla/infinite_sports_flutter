// Shared vitest support for the P4 orchestration suites (Phases E–G): the
// in-memory FantasyDb, a capturing FantasyPusher, and the two-gameweek
// golden world. Test-only, golden_fixture.ts style — no production module
// imports it.

import { clone, Json, loadGoldenFixture } from './golden_fixture';
import { FantasyDb, FantasyTxResult } from './orchestration_db';
import { FantasyPusher, FantasyUserPush } from './pushes';

export const fixture = loadGoldenFixture();

export const GW1_DATE = '06212026'; // Sunday
export const GW2_DATE = '06282026'; // Sunday; lockHour 15 => lock 22:00Z (PDT)
export const LOCK2_MS = Date.UTC(2026, 5, 28, 22);
export const AFTER_LOCK2 = new Date(Date.UTC(2026, 5, 28, 23));
export const F_ROOT = 'Fantasy/Futsal/15';

export class FakeDb implements FantasyDb {
  data: Record<string, any>;
  writes: string[] = [];

  constructor(seed: Record<string, any>) {
    this.data = seed;
  }

  private parts(path: string): string[] {
    return path.split('/').filter((p) => p.length > 0);
  }

  async read(path: string): Promise<unknown> {
    let node: any = this.data;
    for (const p of this.parts(path)) {
      if (node === null || node === undefined || typeof node !== 'object') {
        return null;
      }
      node = Array.isArray(node) ? node[Number(p)] : node[p];
    }
    return node === undefined ? null : node;
  }

  async write(path: string, value: unknown): Promise<void> {
    this.writes.push(path);
    const parts = this.parts(path);
    let node: any = this.data;
    for (const p of parts.slice(0, -1)) {
      if (node[p] === null || node[p] === undefined || typeof node[p] !== 'object') {
        node[p] = {};
      }
      node = node[p];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) {
      delete node[last];
    } else {
      node[last] = clone(value);
    }
  }

  async writeIfAbsent(path: string, value: unknown): Promise<boolean> {
    if ((await this.read(path)) !== null) return false;
    await this.write(path, value);
    return true;
  }

  async transaction(
    path: string, update: (current: unknown) => unknown,
  ): Promise<FantasyTxResult> {
    const current = await this.read(path);
    // Real RTDB runs the update FIRST on its local cache, which is always
    // empty in a Cloud Function, and asks the server only when that guess
    // returns a value. An update that aborts on that null never sees the
    // real node (the 2026-11-02 card-refund bug), so the fake does the same.
    const guess = update(null);
    if (guess === undefined) return { committed: false, value: current };
    // The re-run on the server value sees a COPY (it may not mutate stored
    // state, as in RTDB).
    const next = current === null ? guess : update(clone(current));
    if (next === undefined) return { committed: false, value: current };
    // null over an absent node is RTDB's no-op: nothing written, no stub.
    if (!(next === null && current === null)) await this.write(path, next);
    return { committed: true, value: next === null ? null : clone(next) };
  }

  snapshot(): string {
    return JSON.stringify(this.data);
  }
}

export interface FakeTopicSend {
  topic: string;
  title: string;
  body: string;
  data: Record<string, string>;
}

/** Captures every sendToUsers batch and every topic send; "delivers" to
 *  everyone (a topic send counts 1, like the real adapter). */
export class FakePusher implements FantasyPusher {
  sends: FantasyUserPush[][] = [];
  topicSends: FakeTopicSend[] = [];

  async sendToUsers(messages: FantasyUserPush[]): Promise<number> {
    this.sends.push(messages);
    return messages.length;
  }

  async sendToTopic(
    topic: string, title: string, body: string, data: Record<string, string>,
  ): Promise<number> {
    this.topicSends.push({ topic, title, body, data });
    return 1;
  }
}

export function fixtureSquad(name: string): Json {
  const s = (fixture['squads'] as Json[]).find((x) => x['name'] === name)!;
  return clone(s['squad']);
}

/** Two gameweeks: GW1 finalized (History + PublishedPicks seeded from the
 *  golden squads — boost's GW1 chip was benchBoost; golden gross tenths
 *  alpha 350 / boost 440 / churn 595), GW2 the week under test, GwState
 *  open on GW2. */
export function world2(opts: {
  gw2Status?: number;
  chipSet1EndGw?: number;
} = {}): Record<string, any> {
  const games: Json[] = fixture['games'];
  const mkGames = (status?: number) => {
    const g1 = clone(games[0]['node']) as Json;
    const g2 = clone(games[1]['node']) as Json;
    g2['team1attendance'] = { Ezra: false };
    if (status !== undefined) {
      g1['status'] = status;
      g2['status'] = status;
    }
    return [g1, g2];
  };
  const players: Json = {};
  for (const p of fixture['players'] as Json[]) {
    players[p['id']] = {
      position: p['position'], priceTenths: p['priceTenths'], eligible: true,
    };
  }
  const squads: Json = {};
  const history1: Json = {};
  const published1: Json = {};
  const grossTenths: Record<string, number> = {
    alpha: 350, boost: 440, churn: 595,
  };
  for (const s of fixture['squads'] as Json[]) {
    const name = s['name'] as string;
    squads[name] = clone(s['squad']);
    published1[name] = clone(s['squad']);
    history1[name] = {
      ...clone(s['squad']), TotalTenths: grossTenths[name], Breakdown: [],
    };
  }
  return {
    Fantasy: {
      Futsal: {
        '15': {
          Config: {
            lockHour: 15,
            ...(opts.chipSet1EndGw !== undefined
              ? { chipSet1EndGw: opts.chipSet1EndGw } : {}),
          },
          Players: players,
          Squads: squads,
          History: { 1: history1 },
          PublishedPicks: { 1: published1 },
          GwState: {
            current: 2, status: 'open', lockAtUtc: LOCK2_MS, date: GW2_DATE,
          },
        },
      },
    },
    Futsal: {
      '15': {
        Date: {
          [GW1_DATE]: mkGames(),
          [GW2_DATE]: mkGames(opts.gw2Status),
        },
        'Line Ups': {
          Sharks: { Sam: { n: 1 }, Dana: { n: 2 }, Alex: { n: 3 } },
          Wolves: { Wes: { n: 1 }, Will: { n: 2 }, Wren: { n: 3 } },
          Eagles: { Eli: { n: 1 }, Eva: { n: 2 }, Ezra: { n: 3 } },
          Bulls: { Bo: { n: 1 }, Bea: { n: 2 }, Ben: { n: 3 } },
        },
      },
    },
  };
}

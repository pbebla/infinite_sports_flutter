// Phase G news over the in-memory FantasyDb: the NewsDrafted-guarded
// post-finalize drafting step (deterministic Dream Team post + AI drafts
// through a fake fetch, including the write-NOTHING failure paths) and the
// sweep's dream-team auto-publish honor/skip. World: test_support.ts world2.

import { describe, expect, it } from 'vitest';
import { FetchLike } from '../support';
import { Json } from './golden_fixture';
import { maybeFinalizeGame, runLifecycleSweep } from './orchestration';
import { AFTER_LOCK2, F_ROOT, FakeDb, world2 } from './test_support';

const replyWith = (text: string): FetchLike => async () => ({
  ok: true,
  status: 200,
  json: async () => ({ content: [{ type: 'text', text }] }),
});

// The golden games' Dream Team (same either gameweek): Bo/Bea/Dana/Alex/Ben.
const DREAM_BODY =
  'Bo (GK) 12 · Bea (DEF) 15 · Dana (DEF) 13 · Alex (ATT) 12 · Ben (ATT) 9';

describe('post-finalize news drafting (NewsDrafted-guarded)', () => {
  it('queues the Dream Team post and the AI drafts into News/Drafts', async () => {
    const db = new FakeDb(world2());
    const fetchImpl = replyWith(JSON.stringify([
      { title: 'Bea on fire', body: 'Fifteen points for the Bulls wall.' },
      { title: 'Captain Bo', body: 'A twelve-point week between the posts.' },
    ]));
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, {
      news: { apiKey: 'k', fetchImpl },
    });

    expect(await db.read(`${F_ROOT}/NewsDrafted/2`))
      .toEqual({ At: AFTER_LOCK2.getTime() });
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2dreamteam`)).toEqual({
      Title: 'Team of the Week — GW2',
      Body: DREAM_BODY,
      Gw: 2,
      CreatedAt: AFTER_LOCK2.getTime(),
      Source: 'dreamteam', // no AutoPublishAt: auto-publish is opt-in
    });
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toEqual({
      Title: 'Bea on fire',
      Body: 'Fifteen points for the Bulls wall.',
      Gw: 2,
      CreatedAt: AFTER_LOCK2.getTime(),
      Source: 'ai',
    });
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2ai2`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/News/Drafts/gw2ai3`)).toBeNull();
  });

  it('owner schedule: the Dream Team draft carries the next league-local instant', async () => {
    const db = new FakeDb(world2());
    db.data.Fantasy.Futsal['15'].Config.DreamTeamPost = {
      AutoPublish: true, Weekday: 'tuesday', Hour: 10,
    };
    await runLifecycleSweep(db, AFTER_LOCK2); // no AI deps: dream post only
    const draft = await db.read(`${F_ROOT}/News/Drafts/gw2dreamteam`) as Json;
    // Sunday 23:00Z -> Tuesday Jun 30 10:00 PDT = 17:00Z.
    expect(draft['AutoPublishAt']).toBe(Date.UTC(2026, 5, 30, 17));
  });

  it('AI failure or blank key writes NOTHING from the model — and the claim holds', async () => {
    const garbage = new FakeDb(world2());
    await runLifecycleSweep(garbage, AFTER_LOCK2, undefined, {
      news: { apiKey: 'k', fetchImpl: replyWith('I cannot write that.') },
    });
    expect(await garbage.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toBeNull();
    expect(await garbage.read(`${F_ROOT}/News/Drafts/gw2dreamteam`)).not.toBeNull();
    expect(await garbage.read(`${F_ROOT}/History/2`)).not.toBeNull(); // never blocks

    const blankKey = new FakeDb(world2());
    let calls = 0;
    const counting: FetchLike = async (url, init) => {
      calls++;
      return replyWith('[]')(url, init);
    };
    await runLifecycleSweep(blankKey, AFTER_LOCK2, undefined, {
      news: { apiKey: '', fetchImpl: counting },
    });
    expect(calls).toBe(0);
    expect(await blankKey.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toBeNull();

    // Drafting is once-only: a rerun with a now-working model stays silent
    // (the owner already saw this week's queue).
    await maybeFinalizeGame(garbage, {
      sport: 'Futsal', season: '15', dateKey: '06282026', nowUtc: AFTER_LOCK2,
      deps: { news: { apiKey: 'k', fetchImpl: replyWith(
        '[{"title":"Late","body":"Too late."}]') } },
    });
    expect(await garbage.read(`${F_ROOT}/News/Drafts/gw2ai1`)).toBeNull();
  });
});

describe('dream-team auto-publish (sweep step)', () => {
  it('publishes due dreamteam drafts; edited, future and ai drafts stay queued', async () => {
    const db = new FakeDb(world2({ gw2Status: 1 })); // games live: no finalize
    const now = new Date(Date.UTC(2026, 5, 24, 12));
    db.data.Fantasy.Futsal['15'].News = {
      Drafts: {
        due: {
          Title: 'Team of the Week — GW1', Body: DREAM_BODY, Gw: 1,
          CreatedAt: 1, Source: 'dreamteam', AutoPublishAt: now.getTime() - 1,
        },
        edited: { // the Manager's edit cleared AutoPublishAt (acted-on rule)
          Title: 'Edited', Body: 'B', Gw: 1, CreatedAt: 1, Source: 'dreamteam',
        },
        future: {
          Title: 'Later', Body: 'B', Gw: 1, CreatedAt: 1,
          Source: 'dreamteam', AutoPublishAt: now.getTime() + 3_600_000,
        },
        ai1: {
          Title: 'AI', Body: 'B', Gw: 1, CreatedAt: 1,
          Source: 'ai', AutoPublishAt: now.getTime() - 1, // never auto
        },
      },
    };
    await runLifecycleSweep(db, now);

    expect(await db.read(`${F_ROOT}/News/Published/due`)).toEqual({
      Title: 'Team of the Week — GW1', Body: DREAM_BODY, At: now.getTime(),
    });
    expect(await db.read(`${F_ROOT}/News/Drafts/due`)).toBeNull();
    expect(await db.read(`${F_ROOT}/News/Drafts/edited`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/News/Drafts/future`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/News/Drafts/ai1`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/News/Published/ai1`)).toBeNull();

    // Idempotent: the next sweep republishes nothing.
    const before = db.snapshot();
    await runLifecycleSweep(db, now);
    expect(db.snapshot()).toBe(before);
  });
});

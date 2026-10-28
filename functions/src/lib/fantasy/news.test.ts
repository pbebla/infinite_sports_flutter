// Phase G pure news logic: stats building (only real numbers reach the
// model), the Claude call through a FAKE fetch (happy path, refusal prose,
// garbage JSON, HTTP failure, missing key, thrown fetch), draft validation
// + clamping, the Dream Team draft, the owner schedule math and the
// acted-on auto-publish rule.

import { describe, expect, it } from 'vitest';
import { FetchLike } from '../support';
import { MarketPlayer } from './finalize_core';
import {
  buildDreamTeamDraft, buildNewsPrompt, buildNewsStats,
  dreamTeamPostConfigFrom, generateNewsDrafts, NEWS_BODY_MAX, NEWS_MODEL,
  NEWS_TITLE_MAX, nextLeagueWeekdayInstantUtc, parseNewsDrafts,
  shouldAutoPublish,
} from './news';

const players: Record<string, MarketPlayer> = {
  A: { position: 'GK', eligible: true },
  B: { position: 'ATT', eligible: true },
  C: { position: 'ATT', eligible: false }, // guests never make the news
};

describe('buildNewsStats', () => {
  it('top scorer among ELIGIBLE players; riser/faller skip the Manual flag', () => {
    const stats = buildNewsStats({
      gw: 3,
      playerWeeksThisGw: { A: 5, B: 9, C: 50 },
      playerWeeksPrevGw: null,
      players,
      dreamTeamRaw: {
        Players: [{ name: 'B', position: 'ATT', points: 9 }],
        ComputedAt: 1, Auto: true,
      },
      priceChangesRaw: {
        Manual: true, X: { delta: 5 }, Y: { delta: -10 }, Z: { delta: 2 },
      },
    });
    expect(stats.topScorer).toEqual({ name: 'B', points: 9 });
    expect(stats.dreamTeam).toEqual([{ name: 'B', position: 'ATT', points: 9 }]);
    expect(stats.riser).toEqual({ name: 'X', deltaTenths: 5 });
    expect(stats.faller).toEqual({ name: 'Y', deltaTenths: -10 });
    expect(stats.coldStreak).toBeNull(); // needs two weeks of data
  });

  it('cold streak = lowest two-week total, only when a previous week exists', () => {
    const stats = buildNewsStats({
      gw: 3,
      playerWeeksThisGw: { A: 1, B: 9 },
      playerWeeksPrevGw: { A: -2, B: 3 },
      players,
      dreamTeamRaw: null,
      priceChangesRaw: null,
    });
    expect(stats.coldStreak).toEqual({ name: 'A', lastTwoWeeksPoints: -1 });
    expect(stats.riser).toBeNull();
    expect(stats.faller).toBeNull();
    expect(stats.dreamTeam).toEqual([]);
  });
});

describe('parseNewsDrafts (validation)', () => {
  it('accepts a clean JSON array, with or without markdown fences', () => {
    const json = '[{"title":"A","body":"B"},{"title":"C","body":"D"}]';
    expect(parseNewsDrafts(json)).toEqual([
      { title: 'A', body: 'B' }, { title: 'C', body: 'D' },
    ]);
    expect(parseNewsDrafts('```json\n' + json + '\n```'))
      .toEqual([{ title: 'A', body: 'B' }, { title: 'C', body: 'D' }]);
  });

  it('refusal prose, garbage JSON, non-arrays and empty arrays are null', () => {
    expect(parseNewsDrafts('I cannot help with that.')).toBeNull();
    expect(parseNewsDrafts('[{"title":"A"')).toBeNull();
    expect(parseNewsDrafts('{"title":"A","body":"B"}')).toBeNull();
    expect(parseNewsDrafts('[]')).toBeNull();
    expect(parseNewsDrafts('[{"title":"","body":"x"},{"title":5}]')).toBeNull();
  });

  it('drops invalid items, clamps lengths, cuts after four', () => {
    expect(parseNewsDrafts(
      '[{"title":"A","body":"B"},{"nope":1},{"title":7,"body":"x"}]',
    )).toEqual([{ title: 'A', body: 'B' }]);

    const long = parseNewsDrafts(JSON.stringify([
      { title: 'T'.repeat(100), body: 'B'.repeat(500) },
    ]))!;
    expect(long[0].title).toHaveLength(NEWS_TITLE_MAX);
    expect(long[0].body).toHaveLength(NEWS_BODY_MAX);

    const five = Array.from({ length: 5 }, (_, i) => ({
      title: `T${i}`, body: `B${i}`,
    }));
    expect(parseNewsDrafts(JSON.stringify(five))).toHaveLength(4);
  });
});

describe('generateNewsDrafts (fake fetch — never throws, null = skip)', () => {
  const stats = buildNewsStats({
    gw: 2, playerWeeksThisGw: { A: 5 }, playerWeeksPrevGw: null,
    players, dreamTeamRaw: null, priceChangesRaw: null,
  });
  const reply = (text: string): FetchLike => async () => ({
    ok: true,
    status: 200,
    json: async () => ({ content: [{ type: 'text', text }] }),
  });

  it('happy path: posts the stats to the model and returns the drafts', async () => {
    let captured: { body: string } | null = null;
    const fetchImpl: FetchLike = async (url, init) => {
      captured = { body: init.body };
      expect(url).toBe('https://api.anthropic.com/v1/messages');
      expect(init.headers['x-api-key']).toBe('key-1');
      return reply('[{"title":"A","body":"B"},{"title":"C","body":"D"}]')(url, init);
    };
    const drafts = await generateNewsDrafts({ stats, apiKey: 'key-1', fetchImpl });
    expect(drafts).toEqual([
      { title: 'A', body: 'B' }, { title: 'C', body: 'D' },
    ]);
    const body = JSON.parse(captured!.body);
    expect(body.model).toBe(NEWS_MODEL);
    expect(body.messages[0].content).toBe(buildNewsPrompt(stats));
    expect(String(body.system)).toContain('NEVER mean');
  });

  it('blank key: null without ever calling fetch', async () => {
    let calls = 0;
    const fetchImpl: FetchLike = async (url, init) => {
      calls++;
      return reply('[]')(url, init);
    };
    expect(await generateNewsDrafts({ stats, apiKey: '', fetchImpl })).toBeNull();
    expect(calls).toBe(0);
  });

  it('HTTP failure, refusal prose and a thrown fetch are all null', async () => {
    const failed: FetchLike = async () => ({
      ok: false, status: 500, json: async () => ({}),
    });
    expect(await generateNewsDrafts({ stats, apiKey: 'k', fetchImpl: failed }))
      .toBeNull();
    expect(await generateNewsDrafts({
      stats, apiKey: 'k', fetchImpl: reply('Sorry, I will not write that.'),
    })).toBeNull();
    const thrower: FetchLike = async () => { throw new Error('boom'); };
    expect(await generateNewsDrafts({ stats, apiKey: 'k', fetchImpl: thrower }))
      .toBeNull();
  });
});

describe('Dream Team post + schedule', () => {
  const dreamTeamRaw = {
    Players: [
      { name: 'Bo', position: 'GK', points: 12 },
      { name: 'Bea', position: 'DEF', points: 15 },
    ],
    ComputedAt: 1,
    Auto: true,
  };

  it('builds the structured post from the stored node', () => {
    expect(buildDreamTeamDraft({
      gw: 2, dreamTeamRaw, nowMs: 777, autoPublishAtMs: null,
    })).toEqual({
      Title: 'Team of the Week — GW2',
      Body: 'Bo (GK) 12 · Bea (DEF) 15',
      Gw: 2,
      CreatedAt: 777,
      Source: 'dreamteam',
    });
    expect(buildDreamTeamDraft({
      gw: 2, dreamTeamRaw, nowMs: 777, autoPublishAtMs: 999,
    })!['AutoPublishAt']).toBe(999);
    expect(buildDreamTeamDraft({
      gw: 2, dreamTeamRaw: null, nowMs: 777, autoPublishAtMs: null,
    })).toBeNull();
  });

  it('Config/DreamTeamPost: auto-publish OFF by default; Tuesday 10 stock schedule', () => {
    expect(dreamTeamPostConfigFrom(null))
      .toEqual({ autoPublish: false, weekday: 2, hour: 10 });
    expect(dreamTeamPostConfigFrom({
      AutoPublish: true, Weekday: 'Friday', Hour: 18,
    })).toEqual({ autoPublish: true, weekday: 5, hour: 18 });
  });

  it('nextLeagueWeekdayInstantUtc: next league-local weekday+hour, DST-aware', () => {
    // Sunday Jun 28 2026 23:00Z (league Sun 16:00 PDT) -> Tue Jun 30 10:00
    // PDT = 17:00Z.
    expect(nextLeagueWeekdayInstantUtc(
      new Date(Date.UTC(2026, 5, 28, 23)), 2, 10).getTime())
      .toBe(Date.UTC(2026, 5, 30, 17));
    // Tuesday morning (league 03:00) -> the SAME Tuesday.
    expect(nextLeagueWeekdayInstantUtc(
      new Date(Date.UTC(2026, 5, 30, 10)), 2, 10).getTime())
      .toBe(Date.UTC(2026, 5, 30, 17));
    // Tuesday past the hour (league 11:00) -> a week later.
    expect(nextLeagueWeekdayInstantUtc(
      new Date(Date.UTC(2026, 5, 30, 18)), 2, 10).getTime())
      .toBe(Date.UTC(2026, 6, 7, 17));
    // Winter (PST, offset 8): Wed Jan 14 -> Thu Jan 15 10:00 PST = 18:00Z.
    expect(nextLeagueWeekdayInstantUtc(
      new Date(Date.UTC(2026, 0, 14, 12)), 4, 10).getTime())
      .toBe(Date.UTC(2026, 0, 15, 18));
  });

  it('shouldAutoPublish: the acted-on rule', () => {
    const due = { Source: 'dreamteam', AutoPublishAt: 1000 };
    expect(shouldAutoPublish(due, 1000)).toBe(true);
    expect(shouldAutoPublish(due, 999)).toBe(false); // not yet
    expect(shouldAutoPublish(
      { Source: 'dreamteam' }, 5000)).toBe(false); // edit cleared the schedule
    expect(shouldAutoPublish(
      { Source: 'ai', AutoPublishAt: 1 }, 5000)).toBe(false); // never for ai
    expect(shouldAutoPublish(null, 5000)).toBe(false);
  });
});

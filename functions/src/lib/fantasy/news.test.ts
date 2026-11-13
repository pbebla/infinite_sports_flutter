// Phase G pure news logic: stats building (only real numbers reach the
// model), the Claude call through a FAKE fetch (happy path, refusal prose,
// garbage JSON, HTTP failure, missing key, thrown fetch), draft validation
// + clamping (incl. the tagged players), the Dream Team draft, the autopilot
// config + schedule math + league-time formatting and the auto-publish rule.

import { describe, expect, it } from 'vitest';
import { FetchLike } from '../support';
import { MarketPlayer } from './finalize_core';
import {
  autopilotPublishAtUtc, buildDreamTeamDraft, buildNewsPrompt, buildNewsStats,
  dreamTeamNames, formatLeagueWeekdayTime, generateNewsDrafts, NEWS_BODY_MAX,
  NEWS_MODEL, NEWS_REVIEW_WINDOW_MS, NEWS_SYSTEM_PROMPT, NEWS_TITLE_MAX,
  newsAutopilotConfigFrom, nextLeagueWeekdayInstantUtc, parseNewsDrafts,
  shouldAutoPublish,
} from './news';
import { PlayerCard } from './news_cards';

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
    // No "players" key on an item = no tagged players.
    const json = '[{"title":"A","body":"B"},{"title":"C","body":"D"}]';
    expect(parseNewsDrafts(json)).toEqual([
      { title: 'A', body: 'B', players: [] },
      { title: 'C', body: 'D', players: [] },
    ]);
    expect(parseNewsDrafts('```json\n' + json + '\n```')).toEqual([
      { title: 'A', body: 'B', players: [] },
      { title: 'C', body: 'D', players: [] },
    ]);
  });

  it('players: strings only (trimmed, blanks + repeats dropped), max 3', () => {
    expect(parseNewsDrafts(JSON.stringify([
      { title: 'A', body: 'B', players: ['Bea', 7, null, ' Bo ', '', 'Bea'] },
      { title: 'C', body: 'D', players: ['P1', 'P2', 'P3', 'P4', 'P5'] },
      { title: 'E', body: 'F', players: 'Bea' }, // not a list -> none
    ]))).toEqual([
      { title: 'A', body: 'B', players: ['Bea', 'Bo'] },
      { title: 'C', body: 'D', players: ['P1', 'P2', 'P3'] },
      { title: 'E', body: 'F', players: [] },
    ]);
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
    )).toEqual([{ title: 'A', body: 'B', players: [] }]);

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

  it('cuts at a word boundary and never splits an emoji (the copywriter clamp)', () => {
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}'; // one grapheme, 8 UTF-16 units
    const [d] = parseNewsDrafts(JSON.stringify([{
      // The 60-char cut lands inside "fantastic" -> back up to the space.
      title: `${'x'.repeat(55)} fantastic week`,
      // The 400th character is the emoji: kept whole, never half a surrogate.
      body: `${'b'.repeat(399)}${family} and more`,
    }]))!;
    expect(d.title).toBe('x'.repeat(55));
    expect(d.body).toBe(`${'b'.repeat(399)}${family}`);
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
      { title: 'A', body: 'B', players: [] },
      { title: 'C', body: 'D', players: [] },
    ]);
    const body = JSON.parse(captured!.body);
    expect(body.model).toBe(NEWS_MODEL);
    expect(body.messages[0].content).toBe(buildNewsPrompt(stats));
    expect(String(body.system)).toContain('NEVER mean');
  });

  it('the prompt asks for 0–3 tagged players from the stats JSON', () => {
    expect(NEWS_SYSTEM_PROMPT).toContain('"players"');
    expect(NEWS_SYSTEM_PROMPT).toContain('0 to 3');
    expect(NEWS_SYSTEM_PROMPT).toContain('stats JSON');
  });

  it('prices are always written with a leading "$" (release report #9)', () => {
    expect(NEWS_SYSTEM_PROMPT).toContain('Prices are always written with a leading "$" (e.g. "$7.0M")');
    expect(NEWS_SYSTEM_PROMPT).toContain('tenths of $1M');
  });

  it('tagged players must be named in the stats the model was given', async () => {
    // This week's stats name only A (top scorer). B is a market player the
    // model was never shown; Zed does not exist — both dropped.
    const drafts = await generateNewsDrafts({
      stats,
      apiKey: 'k',
      fetchImpl: reply(JSON.stringify([
        { title: 'A again', body: 'Five points.', players: ['A', 'B', 'Zed'] },
        { title: 'Quiet', body: 'Nobody else.', players: ['B'] },
      ])),
    });
    expect(drafts).toEqual([
      { title: 'A again', body: 'Five points.', players: ['A'] },
      { title: 'Quiet', body: 'Nobody else.', players: [] },
    ]);
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

  const boCard: PlayerCard = {
    name: 'Bo', position: 'GK', team: 'Bulls', priceTenths: 75,
    gw: 2, gwPoints: 12, goals: 0, assists: 0,
  };
  const beaCard: PlayerCard = {
    name: 'Bea', position: 'DEF', team: 'Bulls', priceTenths: 70,
    gw: 2, gwPoints: 15, goals: 0, assists: 1,
  };
  const DT_PUSH = {
    Title: 'Team of the Week is out',
    Body: "GW2's best five are in — see who made it.",
    Audience: 'managers',
  };

  it('dreamTeamNames: the stored rows in order, blanks skipped', () => {
    expect(dreamTeamNames(dreamTeamRaw)).toEqual(['Bo', 'Bea']);
    expect(dreamTeamNames({ Players: [{ name: '' }, 'junk', { name: 'X' }] }))
      .toEqual(['X']);
    expect(dreamTeamNames(null)).toEqual([]);
  });

  it('builds the structured post from the stored node', () => {
    expect(buildDreamTeamDraft({
      gw: 2, dreamTeamRaw, nowMs: 777, autoPublishAtMs: null,
      cards: [boCard, null, beaCard], // an unknown name (null) is dropped
    })).toEqual({
      Title: 'Team of the Week — GW2',
      Body: 'Bo (GK) 12 · Bea (DEF) 15',
      Gw: 2,
      CreatedAt: 777,
      Source: 'dreamteam',
      Template: 'dreamteam',
      Players: { 0: boCard, 1: beaCard },
      Push: DT_PUSH,
    });
    expect(buildDreamTeamDraft({
      gw: 2, dreamTeamRaw, nowMs: 777, autoPublishAtMs: 999, cards: [boCard],
    })!['AutoPublishAt']).toBe(999);
    // No resolvable cards: the Players node is omitted, the post still builds.
    const bare = buildDreamTeamDraft({
      gw: 2, dreamTeamRaw, nowMs: 777, autoPublishAtMs: null, cards: [null],
    })!;
    expect('Players' in bare).toBe(false);
    expect(bare['Push']).toEqual(DT_PUSH);
    expect(buildDreamTeamDraft({
      gw: 2, dreamTeamRaw: null, nowMs: 777, autoPublishAtMs: null, cards: [],
    })).toBeNull();
  });

  it('newsAutopilotConfigFrom: ON by default; Tuesday 10 stock schedule', () => {
    expect(newsAutopilotConfigFrom(null, null))
      .toEqual({ enabled: true, weekday: 2, hour: 10 });
    expect(newsAutopilotConfigFrom({}, null))
      .toEqual({ enabled: true, weekday: 2, hour: 10 });
    // Garbage per field falls back; only Enabled === false turns it off.
    expect(newsAutopilotConfigFrom(
      { Enabled: 'no', Weekday: 'Funday', Hour: 31 }, null))
      .toEqual({ enabled: true, weekday: 2, hour: 10 });
  });

  it('newsAutopilotConfigFrom: Config/NewsAutopilot fields', () => {
    expect(newsAutopilotConfigFrom(
      { Enabled: false, Weekday: 'Friday', Hour: 18 }, null))
      .toEqual({ enabled: false, weekday: 5, hour: 18 });
    expect(newsAutopilotConfigFrom(
      { Enabled: true, Weekday: 'sunday', Hour: 0 }, null))
      .toEqual({ enabled: true, weekday: 7, hour: 0 });
  });

  it('newsAutopilotConfigFrom: NewsAutopilot wins over the legacy DreamTeamPost', () => {
    expect(newsAutopilotConfigFrom(
      { Enabled: true, Weekday: 'monday', Hour: 9 },
      { AutoPublish: false, Weekday: 'friday', Hour: 18 }))
      .toEqual({ enabled: true, weekday: 1, hour: 9 });
  });

  it('newsAutopilotConfigFrom: legacy DreamTeamPost fallback (AutoPublish -> enabled)', () => {
    expect(newsAutopilotConfigFrom(null,
      { AutoPublish: false, Weekday: 'Friday', Hour: 18 }))
      .toEqual({ enabled: false, weekday: 5, hour: 18 });
    expect(newsAutopilotConfigFrom(null,
      { AutoPublish: true, Weekday: 'wednesday', Hour: 7 }))
      .toEqual({ enabled: true, weekday: 3, hour: 7 });
    // A legacy row without the flag is not an "off" — automation first.
    expect(newsAutopilotConfigFrom(null, { Hour: 12 }))
      .toEqual({ enabled: true, weekday: 2, hour: 12 });
  });

  it('formatLeagueWeekdayTime: short weekday + h:mm AM/PM in league time', () => {
    // Summer (PDT, UTC-7): Tue Jun 30 17:00Z = Tue 10:00 AM.
    expect(formatLeagueWeekdayTime(new Date(Date.UTC(2026, 5, 30, 17))))
      .toBe('Tue 10:00 AM');
    // Winter (PST, UTC-8): Thu Jan 15 18:00Z = Thu 10:00 AM.
    expect(formatLeagueWeekdayTime(new Date(Date.UTC(2026, 0, 15, 18))))
      .toBe('Thu 10:00 AM');
    // Afternoon with minutes: Jan 15 23:05Z = Thu 3:05 PM PST.
    expect(formatLeagueWeekdayTime(new Date(Date.UTC(2026, 0, 15, 23, 5))))
      .toBe('Thu 3:05 PM');
    // Midnight and noon: Jan 16 08:00Z = Fri 12:00 AM; Jan 16 20:00Z = Fri
    // 12:00 PM.
    expect(formatLeagueWeekdayTime(new Date(Date.UTC(2026, 0, 16, 8))))
      .toBe('Fri 12:00 AM');
    expect(formatLeagueWeekdayTime(new Date(Date.UTC(2026, 0, 16, 20))))
      .toBe('Fri 12:00 PM');
    // The UTC date is already Wednesday, league time still Tuesday night:
    // Wed Jul 1 03:30Z = Tue Jun 30 8:30 PM PDT.
    expect(formatLeagueWeekdayTime(new Date(Date.UTC(2026, 6, 1, 3, 30))))
      .toBe('Tue 8:30 PM');
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

  it('autopilotPublishAtUtc: the next slot, but never under 12 h of review', () => {
    expect(NEWS_REVIEW_WINDOW_MS).toBe(12 * 3_600_000);
    // Sun Jun 28 23:00Z -> the Tue 10:00 PDT slot is 42 h away: the slot.
    expect(autopilotPublishAtUtc(
      new Date(Date.UTC(2026, 5, 28, 23)), 2, 10).getTime())
      .toBe(Date.UTC(2026, 5, 30, 17));
    // Exactly 12 h before the slot: still the slot.
    expect(autopilotPublishAtUtc(
      new Date(Date.UTC(2026, 5, 30, 5)), 2, 10).getTime())
      .toBe(Date.UTC(2026, 5, 30, 17));
    // A late finalize Tue 08:00 PDT (15:00Z): the slot is 2 h away -> now +
    // 12 h = Tue 20:00 PDT (Wed 03:00Z).
    const late = new Date(Date.UTC(2026, 5, 30, 15));
    expect(autopilotPublishAtUtc(late, 2, 10).getTime())
      .toBe(Date.UTC(2026, 6, 1, 3));
  });

  it('shouldAutoPublish: any Source with a due numeric AutoPublishAt', () => {
    const due = { Source: 'dreamteam', AutoPublishAt: 1000 };
    expect(shouldAutoPublish(due, 1000)).toBe(true);
    expect(shouldAutoPublish(due, 999)).toBe(false); // not yet
    expect(shouldAutoPublish(
      { Source: 'dreamteam' }, 5000)).toBe(false); // owner switched it off
    expect(shouldAutoPublish(
      { Source: 'ai', AutoPublishAt: 1 }, 5000)).toBe(true);
    expect(shouldAutoPublish(
      { Source: 'owner', AutoPublishAt: 1 }, 5000)).toBe(true);
    expect(shouldAutoPublish({ AutoPublishAt: 1 }, 5000)).toBe(true);
    expect(shouldAutoPublish(
      { Source: 'ai', AutoPublishAt: '1' }, 5000)).toBe(false); // not numeric
    expect(shouldAutoPublish(
      { Source: 'ai', AutoPublishAt: Number.NaN }, 5000)).toBe(false);
    expect(shouldAutoPublish(null, 5000)).toBe(false);
  });
});

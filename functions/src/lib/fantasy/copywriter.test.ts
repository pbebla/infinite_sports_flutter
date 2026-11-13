// AI copywriter for the Manager (spec 2026-10-28 §4.5 writeFantasyCopy):
// one Anthropic call per request through an injected fetch (the
// generateNewsDrafts pattern — same model, headers, 8s abort, first text
// block), a per-mode system prompt (post 60/400, push 40/110, message
// 40/140), facts limited to the tagged players' cards + the owner's current
// text and hint, and a strict {"title","body"} reply — anything else is null
// (the callable maps null to HttpsError 'unavailable').

import { describe, expect, it } from 'vitest';
import { FetchLike } from '../support';
import {
  buildCopyPrompt, clampText, COPY_LIMITS, copySystemPrompt, isCopyMode,
  loadCopyCards, parseCopy, writeCopy,
} from './copywriter';
import { NEWS_MODEL } from './news';
import { PlayerCard } from './news_cards';
import { FakeDb } from './test_support';

const ALEX: PlayerCard = {
  name: 'Alex', position: 'ATT', team: 'Sharks', priceTenths: 75,
  priceDeltaTenths: 5, gw: 3, gwPoints: 12, seasonPoints: 40,
  ownershipPct: 30, goals: 6, assists: 2,
};

const reply = (text: string): FetchLike => async () => ({
  ok: true,
  status: 200,
  json: async () => ({ content: [{ type: 'text', text }] }),
});

describe('copySystemPrompt', () => {
  it('per-mode limits, the tone + facts rules and the JSON-object reply rule', () => {
    for (const [mode, title, body] of [
      ['post', 60, 400], ['push', 40, 110], ['message', 40, 140],
    ] as const) {
      expect(COPY_LIMITS[mode]).toEqual({ title, body });
      const p = copySystemPrompt(mode);
      expect(p).toContain(`"title" at most ${title} characters`);
      expect(p).toContain(`"body" at most ${body} characters`);
      expect(p).toContain('NEVER mean');
      expect(p).toContain('Use ONLY the facts');
      expect(p).toContain('Reply with ONLY a JSON object {"title": string, "body": string}');
    }
  });

  it('prices are always written with a leading "$" (release report #9: a body said "7.0M" next to a "$7.0M" card)', () => {
    for (const mode of ['post', 'push', 'message'] as const) {
      const p = copySystemPrompt(mode);
      expect(p).toContain('Prices are always written with a leading "$" (e.g. "$7.0M")');
      // The card-field explanation itself never models a bare price.
      expect(p).toContain('(75 = $7.5M)');
      expect(p).toContain('(5 = up $0.5M)');
      expect(p).not.toContain('= 7.5M');
      expect(p).not.toContain('up 0.5M');
    }
  });
});

describe('buildCopyPrompt', () => {
  it('is the JSON of {mode, template, players, currentTitle, currentBody, hint}; blanks read null', () => {
    const json = JSON.parse(buildCopyPrompt({
      mode: 'post', template: 'spotlight', cards: [ALEX],
      title: ' Spotlight: Alex ', body: '', hint: '  make it fun ',
    }));
    expect(json).toEqual({
      mode: 'post', template: 'spotlight', players: [ALEX],
      currentTitle: 'Spotlight: Alex', currentBody: null, hint: 'make it fun',
    });
    expect(Object.keys(json)).toEqual(
      ['mode', 'template', 'players', 'currentTitle', 'currentBody', 'hint']);
    expect(JSON.parse(buildCopyPrompt({ mode: 'message', cards: [] }))).toEqual({
      mode: 'message', template: null, players: [],
      currentTitle: null, currentBody: null, hint: null,
    });
  });
});

describe('parseCopy', () => {
  it('a JSON object (fences tolerated) with non-empty title + body', () => {
    expect(parseCopy('{"title":" A ","body":" B "}', 'post'))
      .toEqual({ title: 'A', body: 'B' });
    expect(parseCopy('```json\n{"title":"A","body":"B"}\n```', 'push'))
      .toEqual({ title: 'A', body: 'B' });
  });

  it('garbage is null: prose, an array, blanks, non-strings', () => {
    for (const text of [
      'Sorry, I cannot help with that.',
      '[{"title":"A","body":"B"}]',
      '{"title":"","body":"B"}',
      '{"title":"A"}',
      '{"title":"A","body":7}',
      'null',
    ]) {
      expect(parseCopy(text, 'post')).toBeNull();
    }
  });

  it('clamps to the mode limits at a word boundary', () => {
    const words = 'Alex scores again and again and again for the Sharks tonight';
    const longBody = `${'word '.repeat(60)}end`;
    const out = parseCopy(JSON.stringify({ title: words, body: longBody }), 'push')!;
    expect(out.title.length).toBeLessThanOrEqual(40);
    expect(words.startsWith(out.title)).toBe(true);
    expect(out.title.endsWith(' ')).toBe(false);
    expect(out.title).toBe('Alex scores again and again and again');
    expect(out.body.length).toBeLessThanOrEqual(110);
    expect(out.body.endsWith('word')).toBe(true);
  });
});

describe('clampText', () => {
  it('keeps short text, hard-cuts by default, backs up to a space on request', () => {
    expect(clampText('short', 10)).toBe('short');
    expect(clampText('abcdef ghij', 9)).toBe('abcdef gh');
    expect(clampText('abcdef ghij', 9, { wordBoundary: true })).toBe('abcdef');
    // A cut that lands exactly before a space keeps the whole word.
    expect(clampText('abcdef ghij', 6, { wordBoundary: true })).toBe('abcdef');
    // One long word: no space to back up to -> hard cut.
    expect(clampText('abcdefghij', 4, { wordBoundary: true })).toBe('abcd');
    // Trailing whitespace at the cut is trimmed.
    expect(clampText('abc   defgh', 5)).toBe('abc');
  });

  it('counts grapheme clusters (an emoji family is one character)', () => {
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
    expect(clampText(`ab${family}cd`, 3)).toBe(`ab${family}`);
  });
});

describe('isCopyMode', () => {
  it('post / push / message only', () => {
    expect(isCopyMode('post')).toBe(true);
    expect(isCopyMode('push')).toBe(true);
    expect(isCopyMode('message')).toBe(true);
    expect(isCopyMode('tweet')).toBe(false);
    expect(isCopyMode(undefined)).toBe(false);
  });
});

describe('writeCopy (fake fetch — never throws, null = could not write)', () => {
  it('happy path: one Messages call with the mode prompt + the facts JSON', async () => {
    let captured: { url: string; headers: Record<string, string>; body: string } | null = null;
    const fetchImpl: FetchLike = async (url, init) => {
      captured = { url, headers: init.headers, body: init.body };
      expect(init.signal).toBeDefined();
      return reply('{"title":"Alex is flying","body":"Six goals and counting."}')(url, init);
    };
    const out = await writeCopy({
      mode: 'post', template: 'spotlight', cards: [ALEX], hint: 'celebrate',
      apiKey: 'key-1', fetchImpl,
    });
    expect(out).toEqual({ title: 'Alex is flying', body: 'Six goals and counting.' });

    expect(captured!.url).toBe('https://api.anthropic.com/v1/messages');
    expect(captured!.headers).toEqual({
      'x-api-key': 'key-1',
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    });
    const body = JSON.parse(captured!.body);
    expect(body.model).toBe(NEWS_MODEL);
    expect(body.system).toBe(copySystemPrompt('post'));
    expect(body.messages).toEqual([{
      role: 'user',
      content: buildCopyPrompt({
        mode: 'post', template: 'spotlight', cards: [ALEX], hint: 'celebrate',
      }),
    }]);
  });

  it('fenced JSON is accepted', async () => {
    expect(await writeCopy({
      mode: 'message', cards: [], title: 'Deadline moved', apiKey: 'k',
      fetchImpl: reply('```json\n{"title":"Deadline moved","body":"Now Sunday 5 PM."}\n```'),
    })).toEqual({ title: 'Deadline moved', body: 'Now Sunday 5 PM.' });
  });

  it('garbage, non-ok, a thrown fetch and a timeout are all null', async () => {
    const args = { mode: 'push' as const, cards: [ALEX], apiKey: 'k' };
    expect(await writeCopy({ ...args, fetchImpl: reply('Nope.') })).toBeNull();
    expect(await writeCopy({
      ...args, fetchImpl: async () => ({ ok: false, status: 529, json: async () => ({}) }),
    })).toBeNull();
    expect(await writeCopy({
      ...args, fetchImpl: async () => { throw new Error('boom'); },
    })).toBeNull();
    expect(await writeCopy({
      ...args, fetchImpl: async () => ({ ok: true, status: 200, json: async () => ({}) }),
    })).toBeNull();
    const hang: FetchLike = (_url, init) => new Promise((_resolve, reject) => {
      init.signal?.addEventListener('abort', () => reject(new Error('aborted')));
    });
    expect(await writeCopy({ ...args, fetchImpl: hang, timeoutMs: 5 })).toBeNull();
  });

  it('blank key: null without calling fetch', async () => {
    let calls = 0;
    const fetchImpl: FetchLike = async (url, init) => {
      calls++;
      return reply('{"title":"A","body":"B"}')(url, init);
    };
    expect(await writeCopy({ mode: 'post', cards: [ALEX], apiKey: '', fetchImpl }))
      .toBeNull();
    expect(calls).toBe(0);
  });

  it('nothing to write from (no players, no text, no hint): null without calling fetch', async () => {
    let calls = 0;
    const fetchImpl: FetchLike = async (url, init) => {
      calls++;
      return reply('{"title":"A","body":"B"}')(url, init);
    };
    expect(await writeCopy({
      mode: 'post', template: 'free', cards: [], title: ' ', body: '', hint: '',
      apiKey: 'k', fetchImpl,
    })).toBeNull();
    expect(calls).toBe(0);
  });
});

describe('loadCopyCards (the callable\'s facts)', () => {
  function world(): FakeDb {
    return new FakeDb({
      Fantasy: {
        Futsal: {
          '15': {
            Players: {
              Alex: { position: 'ATT', priceTenths: 75, eligible: true, teamName: 'Sharks' },
              Sam: { position: 'GK', priceTenths: 50, eligible: true, teamName: 'Wolves' },
              Bea: { position: 'DEF', priceTenths: 55, eligible: true, teamName: 'Bulls' },
            },
            PlayerTotals: { Alex: { points: 40, ownershipPct: 30 }, Sam: 12 },
            PlayerWeeks: [null, { Alex: 3 }, { Alex: 12, Sam: 2 }],
            PriceChanges: { 2: { Manual: true, Alex: { delta: 5 } } },
          },
        },
      },
      Futsal: {
        '15': {
          Date: {
            '06212026': [{
              team1: 'Sharks', team2: 'Wolves', status: 2,
              team1score: 2, team2score: 0,
              team1activity: {
                "5'": [{ Goal: 'Alex' }],
                "9'": [{ PenGoal: 'Alex' }, { Assist: 'Bea' }],
              },
            }],
          },
        },
      },
    });
  }

  it('cards for the requested names in order; unknown/blank/repeat names dropped', async () => {
    const cards = await loadCopyCards(world(), {
      sport: 'Futsal', season: '15', names: [' Sam', 'Nobody', '', 'Alex', 'Sam'],
    });
    expect(cards.map((c) => c.name)).toEqual(['Sam', 'Alex']);
    expect(cards[0]).toEqual({
      name: 'Sam', position: 'GK', team: 'Wolves', priceTenths: 50,
      gw: 2, gwPoints: 2, seasonPoints: 12, goals: 0, assists: 0,
    });
    expect(cards[1]).toEqual({
      name: 'Alex', position: 'ATT', team: 'Sharks', priceTenths: 75,
      priceDeltaTenths: 5, gw: 2, gwPoints: 12, seasonPoints: 40,
      ownershipPct: 30, goals: 2, assists: 0, // Goal + PenGoal from the Date node
    });
  });

  it('at most 5 cards; no names -> []', async () => {
    const db = world();
    const players = db.data.Fantasy.Futsal['15'].Players;
    for (const n of ['P1', 'P2', 'P3', 'P4']) {
      players[n] = { position: 'DEF', priceTenths: 40, eligible: true, teamName: 'X' };
    }
    const cards = await loadCopyCards(db, {
      sport: 'Futsal', season: '15',
      names: ['Alex', 'Sam', 'Bea', 'P1', 'P2', 'P3', 'P4'],
    });
    expect(cards.map((c) => c.name)).toEqual(['Alex', 'Sam', 'Bea', 'P1', 'P2']);
    expect(await loadCopyCards(db, { sport: 'Futsal', season: '15', names: [] }))
      .toEqual([]);
  });
});

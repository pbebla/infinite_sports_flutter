# Tournament Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fans who tap a bell on a tournament or team page get automated lock-screen pushes for goals (with scorer + assist), kickoff, and full time, sent by database-triggered Cloud Functions — zero manual sending.

**Architecture:** A new `functions/` workspace ("the Watcher", TypeScript, Firebase Functions v2 RTDB triggers) reacts to the Manager app's existing writes (`Team{1|2}Score`, `Status`) and sends one FCM topic-condition message per event with `NotificationsMeta` dedupe. The fan app adds topic subscribe bells, a Settings section, and tap-to-open deep links. The Manager app is untouched.

**Tech Stack:** Firebase Functions v2 (`firebase-functions` ^6, `firebase-admin` ^13, Node 22 runtime), TypeScript 5, vitest (functions unit tests), Flutter (`firebase_messaging`, `flutter_local_notifications`, `shared_preferences` — all already in pubspec).

**Spec:** `docs/superpowers/specs/2026-06-11-push-notifications-design.md`

---

## Ground rules for every task

- Repo: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`, branch `zaya/push-notifications`, work in the main checkout (owner tests on-device here). NOT a worktree.
- All commits stay LOCAL. Never push unless the owner says so.
- NEVER stage the owner's stray files: `PROJECT_REFERENCE.md`, `SoccerStats.png`. Stage files by exact path only — no `git add -A`.
- If `pubspec.lock` shows modified after running flutter commands, leave it unstaged (or `git restore pubspec.lock`).
- Firebase schema facts (verified): `Tournaments/{tid}/Matches/{mid}/Status` int 0=pending/1=live/2=finished; `Team1Score`/`Team2Score` ints; `Team1Id`/`Team2Id`; activity at `Team{1|2}Activity/{minute}` = list of single-entry `{EventType: PlayerName}` maps (container and buckets may come back as arrays with null holes); names at `Tournaments/{tid}/Name` and `Tournaments/{tid}/Teams/{teamId}/Name`; matches also have `MatchLocation`.
- Node v24 + npm 11 are installed on this machine (verified). Functions runtime targets Node 22 — local Node 24 is fine for build/test.

### File map (whole feature)

| File | Role |
|---|---|
| `firebase.json`, `.firebaserc` (repo root) — Create | Functions + emulator config; project alias |
| `functions/package.json`, `functions/tsconfig.json`, `functions/.gitignore` — Create | Watcher workspace |
| `functions/src/lib/decide.ts` — Create | ALL pure decision logic (topics, sanitizer, parsing, goal/kickoff/fulltime rules, dedupe keys) |
| `functions/src/lib/fcm.ts` — Create | FCM condition sender (dry-run in emulator) |
| `functions/src/lib/names.ts` — Create | Tournament/team display-name lookups with cache |
| `functions/src/index.ts` — Create | Trigger wiring + dedupe claim + grace window |
| `functions/test/decide.test.ts` — Create | Unit tests for every rule |
| `lib/misc/notification_topics.dart` — Create | Dart topic builders (parity with decide.ts) |
| `lib/misc/follow_store.dart` — Create | Follow list + master switch + subscribe/unsubscribe |
| `lib/widgets/follow_bell.dart` — Create | Reusable AppBar bell |
| `lib/misc/notification_router.dart` — Create | Deep link: payload → TournamentMatchDetailPage |
| `lib/tournamentdetail.dart` — Modify (~line 144 SliverAppBar) | Tournament bell |
| `lib/tournamentteamdetail.dart` — Modify (~line 901 SliverAppBar) | Team bell |
| `lib/settings.dart` — Modify (insert before "League Table Info" header ~line 113) | Notifications section |
| `lib/main.dart` — Modify (lines 38–49 area) | onMessageOpenedApp + initial-message routing |
| `lib/misc/pushnotifications.dart` — Modify | onNotificationTap body |
| `test/notification_topics_test.dart`, `test/follow_store_test.dart` — Create | Fan-app unit tests |

---

### Task 1: Scaffold the functions workspace

**Files:**
- Create: `firebase.json`, `.firebaserc`, `functions/package.json`, `functions/tsconfig.json`, `functions/.gitignore`, `functions/src/index.ts` (placeholder)

- [ ] **Step 1: Create `firebase.json` at repo root**

```json
{
  "functions": {
    "source": "functions",
    "predeploy": ["npm --prefix functions run build"]
  },
  "emulators": {
    "functions": { "port": 5001 },
    "database": { "port": 9000 },
    "ui": { "enabled": false }
  }
}
```

Note: deliberately NO `database.rules` key — a plain `firebase deploy` must never touch production database rules.

- [ ] **Step 2: Create `.firebaserc` at repo root**

```json
{
  "projects": {
    "default": "infinite-sports-app"
  }
}
```

- [ ] **Step 3: Create `functions/package.json`**

```json
{
  "name": "functions",
  "private": true,
  "engines": { "node": "22" },
  "main": "lib/index.js",
  "scripts": {
    "build": "tsc",
    "test": "vitest run"
  },
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.1.0"
  },
  "devDependencies": {
    "typescript": "^5.5.0",
    "vitest": "^3.0.0"
  }
}
```

- [ ] **Step 4: Create `functions/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "CommonJS",
    "moduleResolution": "node",
    "outDir": "lib",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "sourceMap": true
  },
  "include": ["src"]
}
```

- [ ] **Step 5: Create `functions/.gitignore`**

```
node_modules/
lib/
*.log
```

- [ ] **Step 6: Create placeholder `functions/src/index.ts`**

```ts
// Trigger wiring lands in Task 3. Placeholder so `npm run build` succeeds.
export {};
```

- [ ] **Step 7: Install and verify build**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm install && npm run build`
Expected: install completes; `tsc` exits 0 (creates `functions/lib/`).

- [ ] **Step 8: Commit**

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add firebase.json .firebaserc functions/package.json functions/package-lock.json functions/tsconfig.json functions/.gitignore functions/src/index.ts
git commit -m "chore: scaffold Cloud Functions workspace for push notifications"
```

---

### Task 2: Pure decision logic — `decide.ts` (TDD)

**Files:**
- Create: `functions/src/lib/decide.ts`
- Test: `functions/test/decide.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `functions/test/decide.test.ts`:

```ts
import { describe, expect, test } from 'vitest';
import {
  sanitizeId, tournamentTopic, teamTopic, buildCondition,
  parseMatch, decideGoal, decideStatus, goalKeysToClear,
} from '../src/lib/decide';

const NAMES = { tournament: 'Test Tournament 2026', team1: 'Eagles', team2: 'Lions' };

function liveMatch(extra: Record<string, unknown> = {}) {
  return parseMatch({
    Team1Id: 'eaglesId', Team2Id: 'lionsId',
    Team1Score: 2, Team2Score: 1, Status: 1,
    Team1Activity: {
      '12': [{ Goal: 'Sam Smith' }, { Assist: 'Skylar Jackson' }],
    },
    ...extra,
  });
}

describe('topics', () => {
  test('sanitizeId keeps [A-Za-z0-9_-], replaces the rest with _', () => {
    expect(sanitizeId('Test Tournament 2026!')).toBe('Test_Tournament_2026_');
    expect(sanitizeId('abc-DEF_123')).toBe('abc-DEF_123');
  });
  test('topic builders', () => {
    expect(tournamentTopic('T 1')).toBe('tournament_T_1');
    expect(teamTopic('T1', 'team a')).toBe('tournament_T1_team_team_a');
  });
  test('buildCondition includes only known team ids', () => {
    expect(buildCondition('T1', 'a', 'b')).toBe(
      "'tournament_T1' in topics || 'tournament_T1_team_a' in topics || 'tournament_T1_team_b' in topics");
    expect(buildCondition('T1', null, 'b')).toBe(
      "'tournament_T1' in topics || 'tournament_T1_team_b' in topics");
    expect(buildCondition('T1', null, null)).toBe("'tournament_T1' in topics");
  });
});

describe('parseMatch', () => {
  test('reads PascalCase fields and coerces ints', () => {
    const m = liveMatch();
    expect(m.team1Score).toBe(2);
    expect(m.status).toBe(1);
    expect(m.team1Id).toBe('eaglesId');
  });
  test('tolerates camelCase and missing fields', () => {
    const m = parseMatch({ team1Score: '3', status: 2 });
    expect(m.team1Score).toBe(3);
    expect(m.status).toBe(2);
    expect(m.team1Id).toBeNull();
  });
  test('recovers activity buckets returned as arrays with null holes', () => {
    const m = parseMatch({
      Status: 1, Team1Score: 1, Team2Score: 0,
      Team1Activity: [null, [{ Goal: 'Ana' }]], // minute 1 as array index
    });
    const d = decideGoal({ teamTag: 1, before: 0, after: 1, match: m,
      names: NAMES, tid: 'T1', mid: 'M1' });
    expect(d?.body).toBe("Ana (Eagles) 1'");
  });
});

describe('decideGoal', () => {
  const base = { teamTag: 1 as const, before: 1, after: 2, tid: 'T1', mid: 'M1', names: NAMES };

  test('full goal alert with scorer and assist', () => {
    const d = decideGoal({ ...base, match: liveMatch() });
    expect(d).not.toBeNull();
    expect(d!.kind).toBe('goal');
    expect(d!.title).toBe('GOAL! Eagles 2 – 1 Lions');
    expect(d!.body).toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
    expect(d!.dedupeKey).toBe('goal_t1_2');
    expect(d!.condition).toBe(
      "'tournament_T1' in topics || 'tournament_T1_team_eaglesId' in topics || 'tournament_T1_team_lionsId' in topics");
    expect(d!.data).toEqual({ type: 'goal', tournamentId: 'T1', matchId: 'M1' });
  });

  test('assist may sit in the NEXT minute bucket (clock ticked between taps)', () => {
    const m = liveMatch({ Team1Activity: {
      '12': [{ Goal: 'Sam Smith' }], '13': [{ Assist: 'Skylar Jackson' }] } });
    expect(decideGoal({ ...base, match: m })!.body)
      .toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
  });

  test('assist-then-goal tap order pairs identically (same bucket, any order)', () => {
    const m = liveMatch({ Team1Activity: {
      '12': [{ Assist: 'Skylar Jackson' }, { Goal: 'Sam Smith' }] } });
    expect(decideGoal({ ...base, match: m })!.body)
      .toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
  });

  test('no assist -> scorer line alone', () => {
    const m = liveMatch({ Team1Activity: { '12': [{ Goal: 'Sam Smith' }] } });
    expect(decideGoal({ ...base, match: m })!.body).toBe("Sam Smith (Eagles) 12'");
  });

  test('penalty goal counts as scorer event', () => {
    const m = liveMatch({ Team1Activity: { '9': [{ 'Penalty Goal': 'Ana' }] } });
    expect(decideGoal({ ...base, match: m })!.body).toBe("Ana (Eagles) 9'");
  });

  test('no scorer found -> empty body, alert still sent', () => {
    const m = liveMatch({ Team1Activity: null });
    const d = decideGoal({ ...base, match: m });
    expect(d).not.toBeNull();
    expect(d!.body).toBe('');
  });

  test('team 2 goal uses team 2 activity and name', () => {
    const m = liveMatch({ Team2Activity: { '30': [{ Goal: 'Leo' }] } });
    const d = decideGoal({ ...base, teamTag: 2, match: m });
    expect(d!.body).toBe("Leo (Lions) 30'");
    expect(d!.dedupeKey).toBe('goal_t2_2');
  });

  test('silence when score did not increase', () => {
    expect(decideGoal({ ...base, before: 2, after: 2, match: liveMatch() })).toBeNull();
    expect(decideGoal({ ...base, before: 3, after: 2, match: liveMatch() })).toBeNull();
  });

  test('silence when match is not live', () => {
    expect(decideGoal({ ...base, match: liveMatch({ Status: 2 }) })).toBeNull();
    expect(decideGoal({ ...base, match: liveMatch({ Status: 0 }) })).toBeNull();
  });
});

describe('decideStatus', () => {
  const base = { tid: 'T1', mid: 'M1', names: NAMES };

  test('kickoff on 0 -> 1, with location', () => {
    const d = decideStatus({ ...base, before: 0, after: 1,
      match: liveMatch({ MatchLocation: 'Field A' }) });
    expect(d!.kind).toBe('kickoff');
    expect(d!.title).toBe('Kickoff: Eagles vs Lions');
    expect(d!.body).toBe('Now playing — Field A');
    expect(d!.dedupeKey).toBe('kickoff');
    expect(d!.data.type).toBe('kickoff');
  });

  test('kickoff without location uses generic body', () => {
    const d = decideStatus({ ...base, before: 0, after: 1, match: liveMatch() });
    expect(d!.body).toBe('Now playing — follow it live!');
  });

  test('full time on -> 2 with final score', () => {
    const d = decideStatus({ ...base, before: 1, after: 2,
      match: liveMatch({ Status: 2, Team1Score: 3 }) });
    expect(d!.kind).toBe('fulltime');
    expect(d!.title).toBe('Full time: Eagles 3 – 1 Lions');
    expect(d!.body).toBe('');
    expect(d!.dedupeKey).toBe('fulltime');
  });

  test('silence on no-change, reopen (2 -> 1), and reset (1 -> 0)', () => {
    expect(decideStatus({ ...base, before: 1, after: 1, match: liveMatch() })).toBeNull();
    expect(decideStatus({ ...base, before: 2, after: 1, match: liveMatch() })).toBeNull();
    expect(decideStatus({ ...base, before: 1, after: 0, match: liveMatch() })).toBeNull();
  });
});

describe('goalKeysToClear (re-arm on undo)', () => {
  test('lists keys above the new score up to the old score', () => {
    expect(goalKeysToClear(1, 3, 1)).toEqual(['goal_t1_2', 'goal_t1_3']);
    expect(goalKeysToClear(2, 5, 4)).toEqual(['goal_t2_5']);
    expect(goalKeysToClear(1, 2, 2)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm test`
Expected: FAIL — cannot resolve `../src/lib/decide`.

- [ ] **Step 3: Implement `functions/src/lib/decide.ts`**

```ts
// Pure decision logic for the notification Watcher. No Firebase imports —
// everything here is unit-testable with plain objects.

export interface MatchContext {
  team1Id: string | null;
  team2Id: string | null;
  team1Score: number;
  team2Score: number;
  status: number; // 0 pending, 1 live, 2 finished
  team1Activity: Record<string, unknown> | null;
  team2Activity: Record<string, unknown> | null;
  matchLocation: string | null;
}

export interface Names { tournament: string; team1: string; team2: string }

export interface AlertDecision {
  kind: 'goal' | 'kickoff' | 'fulltime';
  dedupeKey: string;
  title: string;
  body: string;
  condition: string;
  data: { type: string; tournamentId: string; matchId: string };
}

// ---- topics (MUST stay in parity with lib/misc/notification_topics.dart) ----

export function sanitizeId(id: string): string {
  return id.replace(/[^A-Za-z0-9_-]/g, '_');
}

export function tournamentTopic(tournamentId: string): string {
  return `tournament_${sanitizeId(tournamentId)}`;
}

export function teamTopic(tournamentId: string, teamId: string): string {
  return `tournament_${sanitizeId(tournamentId)}_team_${sanitizeId(teamId)}`;
}

export function buildCondition(
  tid: string, team1Id: string | null, team2Id: string | null,
): string {
  const topics = [tournamentTopic(tid)];
  if (team1Id) topics.push(teamTopic(tid, team1Id));
  if (team2Id) topics.push(teamTopic(tid, team2Id));
  return topics.map((t) => `'${t}' in topics`).join(' || ');
}

// ---- parsing (tolerates PascalCase/camelCase and array-with-holes) ----

function firstNonNull(data: Record<string, unknown>, keys: string[]): unknown {
  for (const k of keys) {
    if (data[k] !== undefined && data[k] !== null) return data[k];
  }
  return null;
}

function toInt(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function toStringOrNull(v: unknown): string | null {
  return v === null || v === undefined ? null : String(v);
}

/** RTDB returns near-contiguous int-keyed maps as arrays with null holes.
 *  Normalize to a minute->bucket record either way. */
function normalizeBuckets(raw: unknown): Record<string, unknown> | null {
  if (raw === null || raw === undefined) return null;
  if (Array.isArray(raw)) {
    const out: Record<string, unknown> = {};
    raw.forEach((v, i) => { if (v !== null && v !== undefined) out[String(i)] = v; });
    return Object.keys(out).length ? out : null;
  }
  if (typeof raw === 'object') return raw as Record<string, unknown>;
  return null;
}

export function parseMatch(raw: unknown): MatchContext {
  const d = (raw ?? {}) as Record<string, unknown>;
  return {
    team1Id: toStringOrNull(firstNonNull(d, ['Team1Id', 'team1Id'])),
    team2Id: toStringOrNull(firstNonNull(d, ['Team2Id', 'team2Id'])),
    team1Score: toInt(firstNonNull(d, ['Team1Score', 'team1Score'])),
    team2Score: toInt(firstNonNull(d, ['Team2Score', 'team2Score'])),
    status: toInt(firstNonNull(d, ['Status', 'status'])),
    team1Activity: normalizeBuckets(firstNonNull(d, ['Team1Activity', 'team1Activity'])),
    team2Activity: normalizeBuckets(firstNonNull(d, ['Team2Activity', 'team2Activity'])),
    matchLocation: toStringOrNull(firstNonNull(d, ['MatchLocation', 'matchLocation'])),
  };
}

// ---- scorer / assist pairing ----

const SCORER_EVENTS = new Set(['goal', 'penalty goal']);

interface MinuteEvent { minute: number; eventType: string; player: string }

function bucketEvents(bucket: unknown, minute: number): MinuteEvent[] {
  const list = Array.isArray(bucket)
    ? bucket
    : (bucket && typeof bucket === 'object' ? Object.values(bucket) : []);
  const out: MinuteEvent[] = [];
  for (const ev of list) {
    if (!ev || typeof ev !== 'object') continue;
    const entries = Object.entries(ev as Record<string, unknown>);
    if (!entries.length) continue;
    const [type, player] = entries[0];
    out.push({ minute, eventType: type.toLowerCase().trim(), player: String(player) });
  }
  return out;
}

function allEvents(activity: Record<string, unknown> | null): MinuteEvent[] {
  if (!activity) return [];
  return Object.entries(activity)
    .map(([k, v]) => ({ minute: toInt(k), bucket: v }))
    .sort((a, b) => a.minute - b.minute)
    .flatMap(({ minute, bucket }) => bucketEvents(bucket, minute));
}

/** Newest goal-type event, plus an assist in the same or next minute. */
function findScorerAndAssist(activity: Record<string, unknown> | null):
    { scorer: MinuteEvent | null; assist: MinuteEvent | null } {
  const events = allEvents(activity);
  const scorer = [...events].reverse().find((e) => SCORER_EVENTS.has(e.eventType)) ?? null;
  if (!scorer) return { scorer: null, assist: null };
  const assist = events.find((e) =>
    e.eventType === 'assist' &&
    (e.minute === scorer.minute || e.minute === scorer.minute + 1)) ?? null;
  return { scorer, assist };
}

// ---- decisions ----

export function decideGoal(args: {
  teamTag: 1 | 2; before: number; after: number;
  match: MatchContext; names: Names; tid: string; mid: string;
}): AlertDecision | null {
  const { teamTag, before, after, match, names, tid, mid } = args;
  if (after <= before) return null;
  if (match.status !== 1) return null;

  const scoringTeamName = teamTag === 1 ? names.team1 : names.team2;
  const activity = teamTag === 1 ? match.team1Activity : match.team2Activity;
  const { scorer, assist } = findScorerAndAssist(activity);

  let body = '';
  if (scorer) {
    body = `${scorer.player} (${scoringTeamName}) ${scorer.minute}'`;
    if (assist) body += ` · Assist: ${assist.player}`;
  }

  return {
    kind: 'goal',
    dedupeKey: `goal_t${teamTag}_${after}`,
    title: `GOAL! ${names.team1} ${match.team1Score} – ${match.team2Score} ${names.team2}`,
    body,
    condition: buildCondition(tid, match.team1Id, match.team2Id),
    data: { type: 'goal', tournamentId: tid, matchId: mid },
  };
}

export function decideStatus(args: {
  before: number; after: number;
  match: MatchContext; names: Names; tid: string; mid: string;
}): AlertDecision | null {
  const { before, after, match, names, tid, mid } = args;
  if (before === after) return null;
  const condition = buildCondition(tid, match.team1Id, match.team2Id);

  if (before === 0 && after === 1) {
    return {
      kind: 'kickoff',
      dedupeKey: 'kickoff',
      title: `Kickoff: ${names.team1} vs ${names.team2}`,
      body: match.matchLocation
        ? `Now playing — ${match.matchLocation}`
        : 'Now playing — follow it live!',
      condition,
      data: { type: 'kickoff', tournamentId: tid, matchId: mid },
    };
  }

  if (after === 2) {
    return {
      kind: 'fulltime',
      dedupeKey: 'fulltime',
      title: `Full time: ${names.team1} ${match.team1Score} – ${match.team2Score} ${names.team2}`,
      body: '',
      condition,
      data: { type: 'fulltime', tournamentId: tid, matchId: mid },
    };
  }

  return null; // reopen (2->1), reset (1->0), or anything else: silence
}

/** Keys to delete when a score DECREASES, so a re-recorded goal alerts again. */
export function goalKeysToClear(
  teamTag: 1 | 2, oldScore: number, newScore: number,
): string[] {
  const keys: string[] = [];
  for (let n = newScore + 1; n <= oldScore; n++) keys.push(`goal_t${teamTag}_${n}`);
  return keys;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm test`
Expected: PASS — all decide tests green.

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add functions/src/lib/decide.ts functions/test/decide.test.ts
git commit -m "feat: pure Watcher decision logic (goal/kickoff/fulltime, assist pairing, dedupe)"
```

---

### Task 3: Watcher wiring — `names.ts`, `fcm.ts`, `index.ts`

**Files:**
- Create: `functions/src/lib/names.ts`, `functions/src/lib/fcm.ts`
- Modify: `functions/src/index.ts` (replace placeholder)

No unit tests for this glue layer — it is exercised by the Task 10 emulator rehearsal. Keep every branch decision inside `decide.ts` (already tested).

- [ ] **Step 1: Create `functions/src/lib/names.ts`**

```ts
import * as admin from 'firebase-admin';
import type { MatchContext, Names } from './decide';

const cache = new Map<string, string>();

async function readName(path: string, fallback: string): Promise<string> {
  const hit = cache.get(path);
  if (hit !== undefined) return hit;
  try {
    const snap = await admin.database().ref(path).get();
    const v = snap.val();
    const name = typeof v === 'string' && v.trim() ? v : fallback;
    cache.set(path, name);
    return name;
  } catch {
    return fallback;
  }
}

export async function loadNames(tid: string, match: MatchContext): Promise<Names> {
  const [tournament, team1, team2] = await Promise.all([
    readName(`Tournaments/${tid}/Name`, tid),
    match.team1Id ? readName(`Tournaments/${tid}/Teams/${match.team1Id}/Name`, match.team1Id) : Promise.resolve('TBD'),
    match.team2Id ? readName(`Tournaments/${tid}/Teams/${match.team2Id}/Name`, match.team2Id) : Promise.resolve('TBD'),
  ]);
  return { tournament, team1, team2 };
}
```

- [ ] **Step 2: Create `functions/src/lib/fcm.ts`**

```ts
import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import type { AlertDecision } from './decide';

export async function sendAlert(d: AlertDecision): Promise<void> {
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    // Emulator dress rehearsal: log instead of sending real pushes.
    logger.info('DRY-RUN sendAlert', {
      kind: d.kind, title: d.title, body: d.body, condition: d.condition, data: d.data,
    });
    return;
  }
  await admin.messaging().send({
    condition: d.condition,
    notification: { title: d.title, ...(d.body ? { body: d.body } : {}) },
    data: d.data,
  });
  logger.info('sent', { kind: d.kind, title: d.title });
}
```

- [ ] **Step 3: Replace `functions/src/index.ts`**

```ts
import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { onValueWritten } from 'firebase-functions/v2/database';
import {
  decideGoal, decideStatus, goalKeysToClear, parseMatch,
} from './lib/decide';
import { loadNames } from './lib/names';
import { sendAlert } from './lib/fcm';

admin.initializeApp();

const GOAL_GRACE_MS = 10_000; // wait for the assist to be entered

function toInt(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Atomically claim a dedupe key. Returns false if someone already claimed it. */
async function claimKey(tid: string, mid: string, key: string): Promise<boolean> {
  const ref = admin.database().ref(`NotificationsMeta/${tid}/${mid}/${key}`);
  const result = await ref.transaction((cur) =>
    cur === null ? admin.database.ServerValue.TIMESTAMP : undefined);
  return result.committed;
}

async function handleScore(teamTag: 1 | 2, event: {
  params: Record<string, string>;
  data: { before: { val(): unknown }; after: { val(): unknown } };
}): Promise<void> {
  const tid = event.params.tid;
  const mid = event.params.mid;
  const before = toInt(event.data.before.val());
  const after = toInt(event.data.after.val());

  if (after < before) {
    // Undo: re-arm the cleared scores so a corrected goal alerts again.
    const meta = admin.database().ref(`NotificationsMeta/${tid}/${mid}`);
    await Promise.all(goalKeysToClear(teamTag, before, after)
      .map((k) => meta.child(k).remove()));
    return;
  }
  if (after === before) return;

  // Guard on the match state at the moment of the goal, BEFORE the grace
  // window — an "End match" tapped during the wait must not kill the alert.
  const matchRef = admin.database().ref(`Tournaments/${tid}/Matches/${mid}`);
  const preMatch = parseMatch((await matchRef.get()).val());
  if (preMatch.status !== 1) return;

  if (!(await claimKey(tid, mid, `goal_t${teamTag}_${after}`))) return;

  await sleep(GOAL_GRACE_MS); // let the scorekeeper enter the assist

  // Re-read for fresh activity (scorer + assist), keep pre-grace live status.
  const match = parseMatch((await matchRef.get()).val());
  match.status = 1;
  const names = await loadNames(tid, match);
  const decision = decideGoal({ teamTag, before, after, match, names, tid, mid });
  if (decision) {
    await sendAlert(decision);
  } else {
    logger.info('goal decision was null after grace window', { tid, mid, teamTag, after });
  }
}

export const onTeam1Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team1Score',
  (event) => handleScore(1, event),
);

export const onTeam2Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team2Score',
  (event) => handleScore(2, event),
);

export const onMatchStatus = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Status',
  async (event) => {
    const tid = event.params.tid;
    const mid = event.params.mid;
    const before = toInt(event.data.before.val());
    const after = toInt(event.data.after.val());
    if (before === after) return;

    const kind = before === 0 && after === 1 ? 'kickoff' : after === 2 ? 'fulltime' : null;
    if (!kind) return;
    if (!(await claimKey(tid, mid, kind))) return;

    const matchRef = admin.database().ref(`Tournaments/${tid}/Matches/${mid}`);
    const match = parseMatch((await matchRef.get()).val());
    const names = await loadNames(tid, match);
    const decision = decideStatus({ before, after, match, names, tid, mid });
    if (decision) await sendAlert(decision);
  },
);
```

- [ ] **Step 4: Build + tests still pass**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm run build && npm test`
Expected: `tsc` exits 0; all tests PASS.

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add functions/src/index.ts functions/src/lib/names.ts functions/src/lib/fcm.ts
git commit -m "feat: wire Watcher triggers with dedupe claim, grace window, and FCM sender"
```

---

### Task 4: Dart topic helpers (TDD)

**Files:**
- Create: `lib/misc/notification_topics.dart`
- Test: `test/notification_topics_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notification_topics_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';

void main() {
  group('sanitizeTopicId', () {
    test('keeps letters, digits, underscore, hyphen', () {
      expect(sanitizeTopicId('abc-DEF_123'), 'abc-DEF_123');
    });
    test('replaces everything else with underscore (parity with decide.ts)', () {
      expect(sanitizeTopicId('Test Tournament 2026!'), 'Test_Tournament_2026_');
    });
  });

  group('topic builders', () {
    test('tournamentTopic', () {
      expect(tournamentTopic('T 1'), 'tournament_T_1');
    });
    test('teamTopic', () {
      expect(teamTopic('T1', 'team a'), 'tournament_T1_team_team_a');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test test/notification_topics_test.dart`
Expected: FAIL — file `notification_topics.dart` not found.

- [ ] **Step 3: Implement `lib/misc/notification_topics.dart`**

```dart
/// FCM topic naming for follow bells.
/// MUST stay in parity with functions/src/lib/decide.ts (sanitizeId,
/// tournamentTopic, teamTopic) — the Watcher addresses these exact topics.
String sanitizeTopicId(String id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

String tournamentTopic(String tournamentId) =>
    'tournament_${sanitizeTopicId(tournamentId)}';

String teamTopic(String tournamentId, String teamId) =>
    'tournament_${sanitizeTopicId(tournamentId)}_team_${sanitizeTopicId(teamId)}';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/notification_topics_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/misc/notification_topics.dart test/notification_topics_test.dart
git commit -m "feat: Dart topic builders in parity with Watcher topics"
```

---

### Task 5: Follow store (TDD)

**Files:**
- Create: `lib/misc/follow_store.dart`
- Test: `test/follow_store_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/follow_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeMessaging implements TopicMessaging {
  final List<String> subscribed = [];
  final List<String> unsubscribed = [];
  @override
  Future<void> subscribeToTopic(String topic) async => subscribed.add(topic);
  @override
  Future<void> unsubscribeFromTopic(String topic) async =>
      unsubscribed.add(topic);
}

void main() {
  late FakeMessaging messaging;
  late FollowStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messaging = FakeMessaging();
    store = FollowStore(messaging: messaging);
  });

  test('starts empty with master enabled', () async {
    expect(await store.follows(), isEmpty);
    expect(await store.masterEnabled(), isTrue);
  });

  test('follow stores the channel and subscribes', () async {
    await store.follow(const FollowedChannel(
        topic: 'tournament_T1', label: 'Test Tournament 2026', kind: 'tournament'));
    expect(await store.isFollowed('tournament_T1'), isTrue);
    expect(messaging.subscribed, ['tournament_T1']);
    final follows = await store.follows();
    expect(follows.single.label, 'Test Tournament 2026');
    expect(follows.single.kind, 'tournament');
  });

  test('unfollow removes and unsubscribes', () async {
    await store.follow(const FollowedChannel(
        topic: 'tournament_T1_team_a', label: 'Eagles', kind: 'team'));
    await store.unfollow('tournament_T1_team_a');
    expect(await store.isFollowed('tournament_T1_team_a'), isFalse);
    expect(messaging.unsubscribed, ['tournament_T1_team_a']);
  });

  test('master off unsubscribes all but keeps the list', () async {
    await store.follow(const FollowedChannel(
        topic: 't1', label: 'A', kind: 'tournament'));
    await store.follow(const FollowedChannel(topic: 't2', label: 'B', kind: 'team'));
    await store.setMasterEnabled(false);
    expect(messaging.unsubscribed, containsAll(['t1', 't2']));
    expect((await store.follows()).length, 2); // list preserved
    expect(await store.masterEnabled(), isFalse);
  });

  test('master back on resubscribes the whole list', () async {
    await store.follow(const FollowedChannel(
        topic: 't1', label: 'A', kind: 'tournament'));
    await store.setMasterEnabled(false);
    messaging.subscribed.clear();
    await store.setMasterEnabled(true);
    expect(messaging.subscribed, ['t1']);
  });

  test('following while master is off re-enables master', () async {
    await store.setMasterEnabled(false);
    await store.follow(const FollowedChannel(
        topic: 't9', label: 'C', kind: 'team'));
    expect(await store.masterEnabled(), isTrue);
    expect(messaging.subscribed, contains('t9'));
  });

  test('follows survive a new store instance (persisted)', () async {
    await store.follow(const FollowedChannel(
        topic: 't1', label: 'A', kind: 'tournament'));
    final fresh = FollowStore(messaging: messaging);
    expect(await fresh.isFollowed('t1'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/follow_store_test.dart`
Expected: FAIL — `follow_store.dart` not found.

- [ ] **Step 3: Implement `lib/misc/follow_store.dart`**

```dart
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin seam over FCM topic calls so FollowStore is unit-testable.
abstract class TopicMessaging {
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
}

class FirebaseTopicMessaging implements TopicMessaging {
  @override
  Future<void> subscribeToTopic(String topic) =>
      FirebaseMessaging.instance.subscribeToTopic(topic);
  @override
  Future<void> unsubscribeFromTopic(String topic) =>
      FirebaseMessaging.instance.unsubscribeFromTopic(topic);
}

class FollowedChannel {
  final String topic;
  final String label;
  final String kind; // 'tournament' | 'team'

  const FollowedChannel(
      {required this.topic, required this.label, required this.kind});

  Map<String, String> toJson() => {'topic': topic, 'label': label, 'kind': kind};

  factory FollowedChannel.fromJson(Map<String, dynamic> json) =>
      FollowedChannel(
        topic: json['topic']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'tournament',
      );
}

/// Device-local list of followed channels + the master notifications switch.
/// Master OFF unsubscribes every topic but keeps the stored list, so turning
/// it back ON restores all bells exactly as they were.
class FollowStore {
  static const _followsKey = 'followedChannels';
  static const _masterKey = 'notificationsMasterEnabled';

  final TopicMessaging _messaging;

  FollowStore({TopicMessaging? messaging})
      : _messaging = messaging ?? FirebaseTopicMessaging();

  Future<List<FollowedChannel>> follows() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_followsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => FollowedChannel.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.topic.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isFollowed(String topic) async =>
      (await follows()).any((c) => c.topic == topic);

  Future<bool> masterEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_masterKey) ?? true;
  }

  Future<void> follow(FollowedChannel channel) async {
    final current = await follows();
    if (!current.any((c) => c.topic == channel.topic)) {
      current.add(channel);
      await _save(current);
    }
    if (!await masterEnabled()) {
      // A fresh follow means the fan wants alerts again.
      await setMasterEnabled(true);
    } else {
      await _messaging.subscribeToTopic(channel.topic);
    }
  }

  Future<void> unfollow(String topic) async {
    final current = await follows();
    current.removeWhere((c) => c.topic == topic);
    await _save(current);
    await _messaging.unsubscribeFromTopic(topic);
  }

  Future<void> setMasterEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_masterKey, enabled);
    final current = await follows();
    for (final c in current) {
      if (enabled) {
        await _messaging.subscribeToTopic(c.topic);
      } else {
        await _messaging.unsubscribeFromTopic(c.topic);
      }
    }
  }

  Future<void> _save(List<FollowedChannel> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _followsKey, jsonEncode(list.map((c) => c.toJson()).toList()));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/follow_store_test.dart`
Expected: PASS — all follow-store tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/misc/follow_store.dart test/follow_store_test.dart
git commit -m "feat: FollowStore — persisted follows, master switch, topic subscriptions"
```

---

### Task 6: FollowBell widget

**Files:**
- Create: `lib/widgets/follow_bell.dart`

Logic lives in FollowStore (tested in Task 5); the bell is a thin shell verified on-device in Task 11.

- [ ] **Step 1: Implement `lib/widgets/follow_bell.dart`**

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';

/// AppBar bell that follows/unfollows one channel (tournament or team).
/// Outline = not following, filled = following — FotMob-style.
class FollowBell extends StatefulWidget {
  final String topic;
  final String label;
  final String kind; // 'tournament' | 'team'

  const FollowBell({
    super.key,
    required this.topic,
    required this.label,
    required this.kind,
  });

  @override
  State<FollowBell> createState() => _FollowBellState();
}

class _FollowBellState extends State<FollowBell> {
  final FollowStore _store = FollowStore();
  bool _followed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store.isFollowed(widget.topic).then((value) {
      if (mounted) setState(() => _followed = value);
    });
  }

  Future<bool> _ensurePermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notifications are off'),
          content: const Text(
              'Notifications are turned off for Infinite Sports in your '
              "phone's Settings. Turn them on there, then tap the bell again."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_followed) {
        await _store.unfollow(widget.topic);
        if (!mounted) return;
        setState(() => _followed = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Alerts for ${widget.label} turned off.')));
      } else {
        if (!await _ensurePermission()) return;
        await _store.follow(FollowedChannel(
            topic: widget.topic, label: widget.label, kind: widget.kind));
        if (!mounted) return;
        setState(() => _followed = true);
        final message = widget.kind == 'tournament'
            ? "You'll get goal, kickoff and full-time alerts for this tournament."
            : "You'll get alerts when ${widget.label} plays.";
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _followed
          ? 'Stop alerts for ${widget.label}'
          : 'Get alerts for ${widget.label}',
      icon: Icon(
          _followed ? Icons.notifications_active : Icons.notifications_none),
      onPressed: _toggle,
    );
  }
}
```

- [ ] **Step 2: Analyze the new files**

Run: `flutter analyze lib/widgets/follow_bell.dart lib/misc/follow_store.dart lib/misc/notification_topics.dart`
Expected: No issues (or only pre-existing info-level lints).

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/follow_bell.dart
git commit -m "feat: FollowBell app-bar widget with permission check and snackbar feedback"
```

---

### Task 7: Wire bells into the tournament and team pages

**Files:**
- Modify: `lib/tournamentdetail.dart` (SliverAppBar ~line 144; imports at top)
- Modify: `lib/tournamentteamdetail.dart` (SliverAppBar ~line 901; imports at top)

- [ ] **Step 1: Tournament page — add imports**

In `lib/tournamentdetail.dart`, after the existing imports add:

```dart
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/widgets/follow_bell.dart';
```

- [ ] **Step 2: Tournament page — add the bell to the SliverAppBar**

Find the loaded-state `SliverAppBar` (~line 144):

```dart
                  SliverAppBar(
                    expandedHeight: 160,
                    pinned: true,
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
```

Add an `actions:` parameter to that same SliverAppBar (after `foregroundColor`):

```dart
                    actions: [
                      FollowBell(
                        topic: tournamentTopic(widget.tournamentId),
                        label: _tournament?.name ?? widget.tournamentName,
                        kind: 'tournament',
                      ),
                    ],
```

- [ ] **Step 3: Team page — add imports**

In `lib/tournamentteamdetail.dart`, after the existing imports add:

```dart
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/widgets/follow_bell.dart';
```

- [ ] **Step 4: Team page — add the bell to the SliverAppBar**

Find the loaded-state `SliverAppBar` (~line 901):

```dart
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
```

Add to that same SliverAppBar (after `foregroundColor`):

```dart
              actions: [
                FollowBell(
                  topic: teamTopic(widget.tournamentId, widget.teamId),
                  label: _team?.name ?? 'this team',
                  kind: 'team',
                ),
              ],
```

(`_team` is the page's loaded `TournamentTeam?` field; its `name` is non-null on the model.)

- [ ] **Step 5: Analyze + full test suite**

Run: `flutter analyze lib/tournamentdetail.dart lib/tournamentteamdetail.dart && flutter test`
Expected: no new analyzer errors; all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/tournamentdetail.dart lib/tournamentteamdetail.dart
git commit -m "feat: follow bells on tournament and team pages"
```

---

### Task 8: Settings — Notifications section

**Files:**
- Modify: `lib/settings.dart` (state fields + new section inserted between the Profile section ending ~line 112 and the "League Table Info" `SliverStickyHeader` ~line 113)

- [ ] **Step 1: Add imports**

In `lib/settings.dart` add after existing imports:

```dart
import 'package:infinite_sports_flutter/misc/follow_store.dart';
```

- [ ] **Step 2: Add state fields and loader to `_SettingsState`**

After the `_emailErrorText` declaration add:

```dart
  final FollowStore _followStore = FollowStore();
  List<FollowedChannel> _follows = [];
  bool _masterEnabled = true;
```

In `initState()`, after `_emailErrorText = "";` add:

```dart
    _loadNotificationSettings();
```

And add this method to `_SettingsState`:

```dart
  Future<void> _loadNotificationSettings() async {
    final follows = await _followStore.follows();
    final master = await _followStore.masterEnabled();
    if (!mounted) return;
    setState(() {
      _follows = follows;
      _masterEnabled = master;
    });
  }
```

- [ ] **Step 3: Insert the Notifications section**

In `build()`, between the Profile `SliverVisibility(...)` (ends ~line 112) and the `SliverStickyHeader(header: const Text("League Table Info"), ...)`, insert:

```dart
        SliverStickyHeader(
          header: const Text("Notifications"),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const Divider(color: Colors.grey),
                ListTile(
                  title: const Text("All notifications"),
                  minTileHeight: 40,
                  trailing: Switch(
                    value: _masterEnabled,
                    onChanged: (value) async {
                      await _followStore.setMasterEnabled(value);
                      setState(() => _masterEnabled = value);
                    },
                  ),
                ),
                if (_follows.isEmpty)
                  const ListTile(
                    minTileHeight: 40,
                    title: Text(
                      "Turn on the bell on any tournament or team page to follow it here.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  )
                else
                  for (final channel in _follows)
                    ListTile(
                      minTileHeight: 40,
                      title: Text(channel.label),
                      subtitle: Text(
                        channel.kind == 'tournament' ? 'All matches' : 'Team',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        tooltip: 'Stop alerts',
                        icon: const Icon(Icons.notifications_active),
                        onPressed: () async {
                          await _followStore.unfollow(channel.topic);
                          await _loadNotificationSettings();
                        },
                      ),
                    ),
                const Divider(color: Colors.grey),
              ],
            ),
          ),
        ),
```

- [ ] **Step 4: Analyze + tests**

Run: `flutter analyze lib/settings.dart && flutter test`
Expected: no new analyzer errors; all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/settings.dart
git commit -m "feat: Notifications section in Settings (master switch + followed list)"
```

---

### Task 9: Tap-to-open deep link

**Files:**
- Create: `lib/misc/notification_router.dart`
- Modify: `lib/misc/pushnotifications.dart` (fill `onNotificationTap`)
- Modify: `lib/main.dart` (onMessageOpenedApp listener; route the initial message)

- [ ] **Step 1: Create `lib/misc/notification_router.dart`**

```dart
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_match_detail.dart';

/// Message that launched the app from a terminated state; routed by
/// MyHomePage once the first frame (and mainContext) exists.
RemoteMessage? pendingLaunchMessage;

/// Opens the match page for a Watcher notification payload
/// `{type, tournamentId, matchId}`. Silently no-ops on bad payloads —
/// a tap must never crash the app.
Future<void> openMatchFromNotification(Map<String, dynamic> data) async {
  final tid = data['tournamentId']?.toString() ?? '';
  final mid = data['matchId']?.toString() ?? '';
  if (tid.isEmpty || mid.isEmpty) return;
  try {
    final results = await Future.wait([
      TournamentService.getTournamentHeader(tid),
      TournamentService.getTeams(tid),
      TournamentService.getMatches(tid),
    ]);
    final tournament = results[0] as Tournament?;
    final teams = results[1] as Map<String, TournamentTeam>;
    final matches = results[2] as List<TournamentMatch>;
    TournamentMatch? match;
    for (final m in matches) {
      if (m.id == mid) {
        match = m;
        break;
      }
    }
    if (match == null) return;
    final rosters = await TournamentService.getRosters(tid, teams);
    Navigator.of(mainContext, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => TournamentMatchDetailPage(
        match: match!,
        teams: teams,
        rosters: rosters,
        tournamentId: tid,
        sport: tournament?.sport ?? 'Soccer',
      ),
    ));
  } catch (e) {
    debugPrint('openMatchFromNotification failed: $e');
  }
}

/// For local-notification taps where the payload is the JSON-encoded
/// `message.data` (see main.dart onMessage handler).
Future<void> openMatchFromPayloadString(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  try {
    final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    await openMatchFromNotification(data);
  } catch (e) {
    debugPrint('openMatchFromPayloadString failed: $e');
  }
}
```

- [ ] **Step 2: Fill in `PushNotifications.onNotificationTap`**

In `lib/misc/pushnotifications.dart` add the import:

```dart
import 'package:infinite_sports_flutter/misc/notification_router.dart';
```

Replace the empty handler:

```dart
  static void onNotificationTap(notificationresponse) {
  }
```

with:

```dart
  static void onNotificationTap(NotificationResponse notificationResponse) {
    openMatchFromPayloadString(notificationResponse.payload);
  }
```

- [ ] **Step 3: Route background-tap and launch messages in `lib/main.dart`**

Add the import:

```dart
import 'package:infinite_sports_flutter/misc/notification_router.dart';
```

After the existing `FirebaseMessaging.onMessage.listen((message) {...});` block (ends ~line 44) add:

```dart
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    openMatchFromNotification(message.data);
  });
```

Replace this existing block:

```dart
  final RemoteMessage? message = 
    await FirebaseMessaging.instance.getInitialMessage();
  if (message != null) {
    print("Launched from terminated state");
  }
```

with:

```dart
  pendingLaunchMessage = await FirebaseMessaging.instance.getInitialMessage();
```

- [ ] **Step 4: Consume the pending launch message once the UI exists**

In `_MyHomePageState.initState()` (in `lib/main.dart`), after `_fetchCurrentValues = setCurrentValues();` add:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = pendingLaunchMessage;
      if (message != null) {
        pendingLaunchMessage = null;
        openMatchFromNotification(message.data);
      }
    });
```

- [ ] **Step 5: Analyze + tests**

Run: `flutter analyze lib/main.dart lib/misc/notification_router.dart lib/misc/pushnotifications.dart && flutter test`
Expected: no new analyzer errors; all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/misc/notification_router.dart lib/misc/pushnotifications.dart lib/main.dart
git commit -m "feat: tap a notification to open the match page (foreground, background, cold start)"
```

---

### Task 10: Emulator dress rehearsal

**Files:**
- Create: `functions/REHEARSAL.md` (the script below, for repeatability)

Runs the Watcher against local emulators with a fake database — `sendAlert` logs `DRY-RUN sendAlert` instead of pushing (Task 3 guard). The `--project demo-rehearsal` prefix keeps everything offline; no production data or fans can be touched.

- [ ] **Step 1: Build, then start emulators (background)**

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm run build
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && npx firebase-tools emulators:start --only functions,database --project demo-rehearsal
```

Expected: emulators report functions + database running (database on port 9000). Leave running (background task).

- [ ] **Step 2: Seed a fake match**

```bash
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1.json?ns=demo-rehearsal-default-rtdb" -d "{\"Name\":\"Test Tournament 2026\",\"Teams\":{\"e1\":{\"Name\":\"Eagles\"},\"l1\":{\"Name\":\"Lions\"}},\"Matches\":{\"M1\":{\"Team1Id\":\"e1\",\"Team2Id\":\"l1\",\"Team1Score\":0,\"Team2Score\":0,\"Status\":0,\"MatchLocation\":\"Field A\"}}}"
```

Expected: JSON echo of the written object.

- [ ] **Step 3: Simulate the match and watch the logs**

```bash
# Kickoff (0 -> 1)
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1/Matches/M1/Status.json?ns=demo-rehearsal-default-rtdb" -d "1"
# Goal + assist activity, then score 0 -> 1 (alert should appear ~10s later)
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1/Matches/M1/Team1Activity.json?ns=demo-rehearsal-default-rtdb" -d "{\"12\":[{\"Goal\":\"Sam Smith\"},{\"Assist\":\"Skylar Jackson\"}]}"
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1/Matches/M1/Team1Score.json?ns=demo-rehearsal-default-rtdb" -d "1"
# Undo (1 -> 0): must NOT alert; then re-record (0 -> 1): MUST alert again
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1/Matches/M1/Team1Score.json?ns=demo-rehearsal-default-rtdb" -d "0"
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1/Matches/M1/Team1Score.json?ns=demo-rehearsal-default-rtdb" -d "1"
# Full time (1 -> 2)
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1/Matches/M1/Status.json?ns=demo-rehearsal-default-rtdb" -d "2"
# Post-final edit: must be silent
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1/Matches/M1/Team1Score.json?ns=demo-rehearsal-default-rtdb" -d "2"
```

Check the emulator log output. Expected `DRY-RUN sendAlert` entries, in order:
1. `kind: 'kickoff'`, title `Kickoff: Eagles vs Lions`, body `Now playing — Field A`
2. `kind: 'goal'`, title `GOAL! Eagles 1 – 0 Lions`, body `Sam Smith (Eagles) 12' · Assist: Skylar Jackson` (~10 s after the score write)
3. a second `kind: 'goal'` for the re-recorded goal (re-arm worked)
4. `kind: 'fulltime'`, title `Full time: Eagles 1 – 0 Lions`
And NO send for the undo write or the post-final edit.

- [ ] **Step 4: Stop emulators, save the rehearsal script**

Stop the emulator process. Save Steps 1–3 verbatim into `functions/REHEARSAL.md` so the rehearsal is repeatable before every future functions change.

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add functions/REHEARSAL.md
git commit -m "test: emulator dress-rehearsal script for the notification Watcher"
```

---

### Task 11: Full verification + owner sign-off prep

**Files:** none (verification + documentation only)

- [ ] **Step 1: Full automated verification**

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm run build && npm test
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test
```

Expected: tsc 0 errors; all vitest tests PASS; all Flutter tests PASS.
Then `flutter analyze` (note: can time out per CLAUDE.md — if so, analyze just the changed files listed in this plan's file map).
If `pubspec.lock` shows modified: `git restore pubspec.lock`.

- [ ] **Step 2: On-device test (owner, plain language)**

Ask the owner (in the **Infinite app** on their phone/emulator):
1. Open Tournaments → *Test Tournament 2026* → see the bell top-right; tap it → it fills + confirmation message appears.
2. Open a team page → tap its bell too.
3. Settings → "Notifications" section shows both follows + the master switch.
4. Tap a notification later (after deploy) → lands on the match page.
Note: real pushes require the deploy below — bells and Settings work before deploy (they just subscribe).

- [ ] **Step 3: Deploy checklist (DO NOT run without the owner)**

Document for the owner — actual deployment happens only when the owner says go (ideally after friends review):
1. Firebase Console → `infinite-sports-app` → confirm **Blaze** plan.
2. Console → Project Settings → Cloud Messaging → confirm an **APNs key** is uploaded (needed for iPhone alerts; Android needs nothing).
3. `npx firebase-tools login` (browser sign-in with an account that has project access).
4. `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && npx firebase-tools deploy --only functions`
   - Deploys ONLY the Watcher. Never run a bare `firebase deploy`.
5. Live sign-off: owner follows Test Tournament 2026 on a real phone; record a goal in the **Manager app**; phone buzzes (~10–15 s for goals, 1–3 s for kickoff/full time).

- [ ] **Step 4: Use superpowers:finishing-a-development-branch**

Tests verified in Step 1. Branch stays local (owner pushes only on their say-so, then friends review/merge per repo convention).

---

## Self-review notes (done at plan time)

- Spec coverage: §1 alerts → Tasks 2–3; §3 topics → Tasks 2/4; §4 Watcher incl. grace + re-arm → Tasks 2–3; §5 fan units/wiring/deep link → Tasks 4–9; §6 edge cases → encoded in Task 2 tests + Task 10 rehearsal; §7 testing layers → Tasks 2/5/10/11; §8 setup → Task 11. Manager app untouched throughout.
- Pre-grace status guard (Task 3) intentionally differs from naive post-grace check: a goal followed within 10 s by "End match" still alerts (decide.ts is called with the pre-grace live status).
- `TournamentTeam.name` is a required non-null field on the fan model; `_team?.name ?? 'this team'` covers only the unloaded case.

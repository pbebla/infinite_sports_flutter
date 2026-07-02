# Registration Redesign L1c Implementation Plan (Stripe Auto-Pay)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build phase L1c of the registration redesign: a "Pay with card" button on the fan payment screen that creates a Stripe PaymentIntent through a new Cloud Function, opens Stripe's PaymentSheet (card + Apple Pay + Google Pay), and — on success — a webhook Cloud Function flips `Paid: true, PaidVia: 'card'` automatically (plus the legacy `Sign Ups/.../NotPaid` → `Paid` move), so a captain or player who pays by card never waits on an admin. Manager gets its Stripe toggle un-disabled. Venmo/Zelle/manual-flip (L1a) and team paths (L1b) are unchanged and keep working exactly as shipped.

**Architecture:**
1. A new pure TS module `functions/src/lib/stripe_pay.ts` ports the fan's dollar `amountOwed`/`legacySignUpTarget` logic to cents-based server-side math (`owedCents`, `legacyTarget`) plus a webhook-metadata builder/parser — unit-tested with `vitest`, no Firebase/Stripe imports, mirroring the existing `functions/src/lib/decide.ts` pure-module style.
2. A new callable v2 function `createRegistrationPaymentIntent` (auth required, secrets-bound) reads the caller's `Registrations/{regId}/Config` + `Submissions/{uid}` (+ the joiner's team when relevant) from RTDB via the admin SDK, recomputes the owed amount server-side (never trusts the client), and creates a Stripe PaymentIntent, returning `{clientSecret, publishableKey}`.
3. A new HTTP v2 function `stripeWebhook` verifies the Stripe signature with the raw body, and on `payment_intent.succeeded` flips `Paid`/`PaidVia` on the submission and dual-writes the legacy `Sign Ups` move — idempotent so Stripe's at-least-once delivery can't double count or crash.
4. The fan `PaymentScreen` grows a purple "Pay with card" button, shown only when `config.stripe` is on, the amount is greater than zero, and a Stripe publishable key is configured in `AppConfig/StripePublishableKey` (RTDB) — otherwise a muted "Card payments unavailable" note appears instead of a broken button. Tapping it calls the callable via `cloud_functions`, then drives `flutter_stripe`'s PaymentSheet; success shows a snackbar and relies on the already-live `RegistrationStatusPage` stream to flip to Paid once the webhook lands (no polling, no new UI there).
5. Android's `MainActivity` becomes a `FlutterFragmentActivity` and the launch/normal themes move to `Theme.MaterialComponents.DayNight.NoActionBar` parents — both are hard `flutter_stripe` requirements documented in its own README.
6. The Manager wizard's disabled "Card (Stripe)" toggle becomes a live `SwitchListTile` like Venmo/Zelle.
7. A final owner-interactive task prints the exact `firebase functions:secrets:set` commands, the RTDB publishable-key write command, the Stripe Dashboard webhook setup steps, and the on-device test-mode script (card `4242 4242 4242 4242`) — no secret value is ever typed into chat or committed.

**Tech Stack:** Functions workspace (`FAN functions/`): Node 22, TypeScript 5.5, `firebase-functions@^6.1.0` (v2 API: `onCall`, `onRequest`, `defineSecret`), `firebase-admin@^13`, new dependency `stripe` (Node SDK), tests via `vitest run` (`npm test`), build via `tsc`. Fan Flutter app: new dependency `flutter_stripe ^12.1.0` (PaymentSheet) + `cloud_functions` (invoke the callable), Dart >=3.11 toolchain already in `pubspec.yaml`. Manager: existing Riverpod/go_router wizard, one `SwitchListTile` change, no new dependency.

**Spec:** `docs/superpowers/specs/2026-06-30-registration-redesign-design.md` (fan repo) — §6 "L1c (follow-on phase)" is the authoritative scope; §2 notes `flutter_stripe` is "added only in L1c"; §9 lists L1c as the final build phase ("Stripe auto-confirm. Ship."). L1a (`docs/superpowers/plans/2026-06-30-registration-l1a.md`) and L1b (`docs/superpowers/plans/2026-07-01-registration-l1b.md`) are DONE and committed on `zaya-registration` in both repos — this plan builds only the L1c delta on top of them.

**Branches:** `zaya-registration` in BOTH repos (both already checked out). All commits LOCAL (no push) until the owner says otherwise.

---

## Conventions for every task below

- **Repo roots:** `FAN` = `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`, `MANAGER` = `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`. Every file path in a task is prefixed with the repo it belongs to. Almost everything in this plan lives in `FAN` — Manager gets exactly one small edit (Task 7).
- **Run flutter via PowerShell** (never rely on PATH):
  ```powershell
  $env:Path = "C:\src\flutter\bin;" + $env:Path
  Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"   # or the MANAGER root
  ```
- **Branch check before touching files** in a repo: `git rev-parse --abbrev-ref HEAD` must print `zaya-registration` in BOTH repos. If it doesn't, STOP and ask — do not create branches in this phase.
- **Stage exact paths only** — never `git add -A` or `git add .`. In the FAN repo NEVER stage `PROJECT_REFERENCE.md`, `SoccerStats.png`, `.claude/`, or any file under `docs/` (this plan file itself lives under `docs/` — do not commit it; the controller reviews it separately).
- **pubspec.lock:** if a task incidentally modifies it, run `git restore pubspec.lock` before committing — EXCEPT the fan-dependency task (Task 5), where `pubspec.lock` MUST be committed alongside `pubspec.yaml`.
- **functions/package-lock.json:** the same rule applies — commit it alongside `functions/package.json` in the task that adds the `stripe` dependency (Task 1), restore it in any other task where `npm install` incidentally touches it.
- All commits stay local. Do not merge to `zaya-features`; the owner decides after on-device testing.
- Build/install one app at a time (never two Gradle builds in parallel). Device serial: `GN434J02403404RL`.
- The fan repo's full `flutter analyze` can be slow; analyze the touched paths first, then do one full pass in the verify task with a generous timeout.
- **Repo lint gotchas (Flutter 3.44):** file-header comments use `//` (not `///`); `ListTile` needs a `Material` ancestor (`Card` provides one) — never a bare decorated `Container`; avoid `RadioListTile` and `DropdownButtonFormField` (use `ChoiceChip` rows and `InputDecorator`+`DropdownButton` instead).
- **Secrets never appear in chat, code, or commits.** `defineSecret('STRIPE_SECRET_KEY')` / `defineSecret('STRIPE_WEBHOOK_SECRET')` are read at runtime from Firebase Functions secret storage; the owner runs the `firebase functions:secrets:set` commands themselves (Task 9). The Stripe **publishable** key is not secret (it's shipped to every client by design) but is still kept out of source — it lives in RTDB `AppConfig/StripePublishableKey`, written by the owner via the CLI, and is read at runtime by both the callable and the fan app.
- **TDD for the pure TS module** (Task 1): write the failing vitest spec first, watch it fail to compile/run, then implement.

---

## File Structure

**FAN (`infinite_sports_flutter`):**
- **Create** `functions/src/lib/stripe_pay.ts` — pure cents-based owed/legacy-target/webhook-metadata helpers.
- **Create** `functions/src/lib/stripe_pay.test.ts` — vitest coverage mirroring the Dart `amountOwed`/`legacySignUpTarget` cases.
- **Modify** `functions/package.json` (+ commit `functions/package-lock.json`) — add the `stripe` npm dependency.
- **Create** `functions/src/createRegistrationPaymentIntent.ts` — the `onCall` function.
- **Create** `functions/src/stripeWebhook.ts` — the `onRequest` function.
- **Modify** `functions/src/index.ts` — export both new functions.
- **Modify** `pubspec.yaml` (+ commit `pubspec.lock`) — add `flutter_stripe` and `cloud_functions`.
- **Modify** `android/app/src/main/kotlin/com/example/flutter_application/MainActivity.kt` — `FlutterFragmentActivity`.
- **Modify** `android/app/src/main/res/values/styles.xml`, `android/app/src/main/res/values-night/styles.xml`, `android/app/src/main/res/values-v31/styles.xml`, `android/app/src/main/res/values-night-v31/styles.xml` — `Theme.MaterialComponents.DayNight.NoActionBar` parents.
- **Modify** `lib/registration/payment_screen.dart` — "Pay with card" button + PaymentSheet flow (full-file rewrite of the relevant section).
- **Modify** `lib/main.dart` — one-line `Stripe.publishableKey` readiness is deferred to first use in the payment screen (no global init needed); confirmed no change required after Task 6 investigation — see Task 6 Step 1.

**MANAGER (`InfiniteSportsManagerFlutter`):**
- **Modify** `lib/ui/registrations/open_registration_wizard_page.dart` — enable the Stripe `SwitchListTile` (lines 480-486) and wire `_stripe` into the `RegistrationConfig` construction (line 218).

**RTDB (additive only):** `AppConfig/StripePublishableKey` (string, owner-written). No schema removal; `Registrations/{regId}/Submissions/{uid}/Paid`+`PaidVia` gain the value `'card'` as an additional legal `PaidVia`, already parsed as a free-form string by the existing `RegSubmission.fromFirebase`.

---

## Task 1: Pure Stripe-pay TS module (TDD)

**Files:**
- Create: `FAN functions/src/lib/stripe_pay.ts`
- Create: `FAN functions/src/lib/stripe_pay.test.ts`

- [ ] **Step 1: Branch check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`.

- [ ] **Step 2: Write the failing tests**

Create `FAN functions/src/lib/stripe_pay.test.ts`:

```typescript
import { describe, expect, it } from 'vitest';
import {
  legacyTarget, owedCents, parseWebhookMetadata, RegistrationConfigLike,
  SubmissionLike, TeamLike, webhookMetadata,
} from './stripe_pay';

function config(overrides: Partial<RegistrationConfigLike> = {}): RegistrationConfigLike {
  return {
    targetType: 'league',
    sport: 'Futsal',
    season: '17',
    tournamentId: '',
    tournamentName: '',
    fee: 20,
    teamFee: 300,
    paymentMode: 'perPlayer',
    ...overrides,
  };
}

function submission(overrides: Partial<SubmissionLike> = {}): SubmissionLike {
  return { path: 'individual', paid: false, ...overrides };
}

describe('owedCents', () => {
  it('individual owes the per-player fee in cents under perPlayer/both', () => {
    expect(owedCents(config({ paymentMode: 'perPlayer' }), submission())).toBe(2000);
    expect(owedCents(config({ paymentMode: 'both' }), submission())).toBe(2000);
  });

  it('individual owes 0 under teamFee mode', () => {
    expect(owedCents(config({ paymentMode: 'teamFee' }), submission())).toBe(0);
  });

  it('captain owes the flat team fee in cents under teamFee/both', () => {
    expect(owedCents(config({ paymentMode: 'teamFee' }), submission({ path: 'captain' }))).toBe(30000);
    expect(owedCents(config({ paymentMode: 'both' }), submission({ path: 'captain' }))).toBe(30000);
  });

  it('captain owes 0 under perPlayer mode', () => {
    expect(owedCents(config({ paymentMode: 'perPlayer' }), submission({ path: 'captain' }))).toBe(0);
  });

  it('joiner owes the per-player fee unless the team code waives it', () => {
    const team: TeamLike = { codeWaivesPayment: false };
    const waived: TeamLike = { codeWaivesPayment: true };
    expect(owedCents(config(), submission({ path: 'joiner' }), team)).toBe(2000);
    expect(owedCents(config(), submission({ path: 'joiner' }), waived)).toBe(0);
  });

  it('joiner with no team info owes the per-player fee (defensive default)', () => {
    expect(owedCents(config(), submission({ path: 'joiner' }))).toBe(2000);
  });

  it('anything already paid owes 0', () => {
    expect(owedCents(config(), submission({ paid: true }))).toBe(0);
    expect(owedCents(config({ paymentMode: 'teamFee' }), submission({ path: 'captain', paid: true }))).toBe(0);
  });

  it('a free registration (fee 0) owes 0', () => {
    expect(owedCents(config({ fee: 0, paymentMode: 'perPlayer' }), submission())).toBe(0);
  });

  it('rounds fractional dollar fees to the nearest cent', () => {
    expect(owedCents(config({ fee: 19.99, paymentMode: 'perPlayer' }), submission())).toBe(1999);
    expect(owedCents(config({ fee: 12.345, paymentMode: 'perPlayer' }), submission())).toBe(1235);
  });
});

describe('legacyTarget', () => {
  it('leagues target Sport/Season', () => {
    expect(legacyTarget(config())).toEqual({ league: 'Futsal', season: '17' });
  });

  it('tournaments target TournamentName/TournamentId, falling back to the id', () => {
    expect(legacyTarget(config({
      targetType: 'tournament', tournamentId: 't1', tournamentName: 'Summer Cup',
    }))).toEqual({ league: 'Summer Cup', season: 't1' });
    expect(legacyTarget(config({
      targetType: 'tournament', tournamentId: 't1', tournamentName: '',
    }))).toEqual({ league: 't1', season: 't1' });
  });
});

describe('webhookMetadata / parseWebhookMetadata', () => {
  it('round-trips regId/uid/league/season through Stripe metadata strings', () => {
    const meta = webhookMetadata({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal', season: '17' });
    expect(meta).toEqual({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal', season: '17' });
    const parsed = parseWebhookMetadata(meta);
    expect(parsed).toEqual({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal', season: '17' });
  });

  it('parseWebhookMetadata returns null when a required field is missing', () => {
    expect(parseWebhookMetadata({ regId: 'Futsal-17', uid: 'uid-1', league: 'Futsal' })).toBeNull();
    expect(parseWebhookMetadata(null)).toBeNull();
    expect(parseWebhookMetadata(undefined)).toBeNull();
  });

  it('parseWebhookMetadata rejects non-string values defensively', () => {
    expect(parseWebhookMetadata({ regId: 'x', uid: 1, league: 'Futsal', season: '17' })).toBeNull();
  });
});
```

- [ ] **Step 3: Run the tests to verify they fail**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\functions"
npm test
```
Expected: FAIL — `./stripe_pay` does not exist (`ERR_MODULE_NOT_FOUND` / TS resolution error reported by vitest).

- [ ] **Step 4: Implement the module**

Create `FAN functions/src/lib/stripe_pay.ts`:

```typescript
// Pure Stripe payment-amount + legacy-target + webhook-metadata helpers
// (Leagues epic L1, phase L1c). No Firebase/Stripe imports — unit-tested
// directly with vitest. This is the server-side (cents-based) twin of the
// Dart dollar-based amountOwed/legacySignUpTarget in
// lib/registration/registration_models.dart — the two MUST agree on every
// case; when one changes, check the other.

/** The subset of RegistrationConfig fields the payment math needs. */
export interface RegistrationConfigLike {
  targetType: 'league' | 'tournament';
  sport: string;
  season: string;
  tournamentId: string;
  tournamentName: string;
  fee: number; // dollars
  teamFee: number; // dollars
  paymentMode: 'perPlayer' | 'teamFee' | 'both';
}

/** The subset of RegSubmission fields the payment math needs. */
export interface SubmissionLike {
  path: 'individual' | 'captain' | 'joiner' | string;
  paid: boolean;
}

/** The subset of RegTeam fields the payment math needs. */
export interface TeamLike {
  codeWaivesPayment: boolean;
}

/** Dollars -> integer cents, rounded to the nearest cent (Stripe requires
 *  an integer amount). */
function toCents(dollars: number): number {
  return Math.round(dollars * 100);
}

/**
 * The amount (in cents) [submission] owes right now — 0 whenever nothing is
 * owed. Mirrors Dart's `paymentOwed` + `amountOwed` combined:
 *  - already paid -> 0
 *  - joiner -> the per-player fee, unless [team].codeWaivesPayment
 *  - captain -> the flat team fee, only under 'teamFee' or 'both'
 *  - individual (or any other/legacy path) -> the per-player fee, only
 *    under 'perPlayer' or 'both'
 * [team] is omitted for individual/captain paths; a joiner with no [team]
 * defensively owes the full per-player fee (fail closed, never accidentally
 * free).
 */
export function owedCents(
  config: RegistrationConfigLike,
  submission: SubmissionLike,
  team?: TeamLike,
): number {
  if (submission.paid) return 0;
  if (submission.path === 'joiner') {
    if (config.fee <= 0) return 0;
    if (team?.codeWaivesPayment) return 0;
    return toCents(config.fee);
  }
  if (submission.path === 'captain') {
    if (config.teamFee <= 0) return 0;
    if (config.paymentMode !== 'teamFee' && config.paymentMode !== 'both') return 0;
    return toCents(config.teamFee);
  }
  // individual (and any other/legacy path)
  if (config.fee <= 0) return 0;
  if (config.paymentMode !== 'perPlayer' && config.paymentMode !== 'both') return 0;
  return toCents(config.fee);
}

/** Where the legacy dual-write goes — mirrors Dart's legacySignUpTarget. */
export function legacyTarget(config: RegistrationConfigLike): { league: string; season: string } {
  if (config.targetType === 'tournament') {
    return {
      league: config.tournamentName.length > 0 ? config.tournamentName : config.tournamentId,
      season: config.tournamentId,
    };
  }
  return { league: config.sport, season: config.season };
}

/** The identifying fields the webhook needs to flip Paid on the right
 *  submission — carried as Stripe PaymentIntent metadata (Stripe stores
 *  metadata values as strings; keys/values here are already strings). */
export interface WebhookMeta {
  regId: string;
  uid: string;
  league: string;
  season: string;
}

/** Builds the metadata object passed to `stripe.paymentIntents.create`. */
export function webhookMetadata(meta: WebhookMeta): Record<string, string> {
  return { regId: meta.regId, uid: meta.uid, league: meta.league, season: meta.season };
}

/** Defensive parse of a Stripe event's `metadata` back into [WebhookMeta].
 *  Returns null when any required field is missing or not a string, so the
 *  webhook can log-and-200 instead of crashing on a malformed/foreign event. */
export function parseWebhookMetadata(raw: unknown): WebhookMeta | null {
  if (raw === null || raw === undefined || typeof raw !== 'object') return null;
  const m = raw as Record<string, unknown>;
  const regId = m['regId'];
  const uid = m['uid'];
  const league = m['league'];
  const season = m['season'];
  if (
    typeof regId !== 'string' || regId.length === 0 ||
    typeof uid !== 'string' || uid.length === 0 ||
    typeof league !== 'string' || league.length === 0 ||
    typeof season !== 'string'
  ) {
    return null;
  }
  return { regId, uid, league, season };
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```powershell
npm test
```
Expected: All `stripe_pay.test.ts` tests pass.

- [ ] **Step 6: Build check**

```powershell
npm run build
```
Expected: `tsc` completes with no errors (compiles `lib/stripe_pay.js` under `functions/lib/`).

- [ ] **Step 7: Commit**

```powershell
git add functions/src/lib/stripe_pay.ts functions/src/lib/stripe_pay.test.ts
git commit -m "feat(registration): pure Stripe owed-cents + legacy-target + webhook-metadata helpers (L1c)"
```

---

## Task 2: Add the `stripe` npm dependency to the functions workspace

**Files:**
- Modify: `FAN functions/package.json`
- Modify: `FAN functions/package-lock.json` (committed alongside)

- [ ] **Step 1: Read the current package.json**

Already read in full above. Current `dependencies` block (lines 10-13):

```json
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.1.0"
  },
```

- [ ] **Step 2: Add the dependency**

In `FAN functions/package.json`, find:

```json
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.1.0"
  },
```

Replace with:

```json
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.1.0",
    "stripe": "^18.0.0"
  },
```

- [ ] **Step 3: Install**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\functions"
npm install
```
Expected: `stripe` added to `node_modules` and `package-lock.json` updated with the resolved version. If `npm install` reports a peer-dependency conflict, re-run with `npm install --legacy-peer-deps` and note the flag was needed in the commit body.

- [ ] **Step 4: Build check**

```powershell
npm run build
```
Expected: `tsc` still completes with no errors (no code uses `stripe` yet, so this just confirms nothing broke).

- [ ] **Step 5: Commit**

```powershell
git add functions/package.json functions/package-lock.json
git commit -m "chore(functions): add stripe npm dependency (L1c)"
```

---

## Task 3: `createRegistrationPaymentIntent` callable

**Files:**
- Create: `FAN functions/src/createRegistrationPaymentIntent.ts`

This function is auth-required. It re-reads `Registrations/{regId}/Config`, the caller's own `Submissions/{uid}`, and (for a joiner) the referenced `Teams/{teamId}` — ALL from the admin SDK, never trusting client-supplied amounts — computes `owedCents` from Task 1's pure module, and creates a Stripe PaymentIntent for that amount. Rejects with a clear error when nothing is owed (already paid, or a 0-fee registration) so the fan app never opens a PaymentSheet for $0.

- [ ] **Step 1: Branch check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`.

- [ ] **Step 2: Create the function**

Create `FAN functions/src/createRegistrationPaymentIntent.ts`:

```typescript
// Cloud Function (L1c): creates a Stripe PaymentIntent for the signed-in
// caller's own registration submission. The amount is ALWAYS recomputed
// server-side from RTDB — the client never gets to name its own price.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import Stripe from 'stripe';
import {
  legacyTarget, owedCents, RegistrationConfigLike, SubmissionLike, TeamLike,
  webhookMetadata,
} from './lib/stripe_pay';

export const stripeSecretKey = defineSecret('STRIPE_SECRET_KEY');

function parseConfig(raw: unknown): RegistrationConfigLike | null {
  if (raw === null || typeof raw !== 'object') return null;
  const c = raw as Record<string, unknown>;
  const targetType = c['TargetType'] === 'tournament' ? 'tournament' : 'league';
  const methods = (c['Methods'] ?? {}) as Record<string, unknown>;
  if (methods['stripe'] !== true) return null; // Stripe not enabled for this registration
  const paymentModeRaw = c['PaymentMode'];
  const paymentMode = paymentModeRaw === 'teamFee' || paymentModeRaw === 'both'
    ? paymentModeRaw : 'perPlayer';
  return {
    targetType,
    sport: String(c['Sport'] ?? ''),
    season: String(c['Season'] ?? ''),
    tournamentId: String(c['TournamentId'] ?? ''),
    tournamentName: String(c['TournamentName'] ?? ''),
    fee: Number(c['Fee'] ?? 0),
    teamFee: Number(c['TeamFee'] ?? 0),
    paymentMode,
  };
}

function parseSubmission(raw: unknown): SubmissionLike | null {
  if (raw === null || typeof raw !== 'object') return null;
  const s = raw as Record<string, unknown>;
  const path = s['Path'];
  if (typeof path !== 'string' || path.length === 0) return null;
  return {
    path,
    paid: s['Paid'] === true,
  };
}

function parseTeam(raw: unknown): TeamLike | null {
  if (raw === null || typeof raw !== 'object') return null;
  const t = raw as Record<string, unknown>;
  return { codeWaivesPayment: t['CodeWaivesPayment'] === true };
}

export const createRegistrationPaymentIntent = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to pay.');
    }
    const regId = request.data?.regId;
    if (typeof regId !== 'string' || regId.length === 0) {
      throw new HttpsError('invalid-argument', 'Missing regId.');
    }

    const db = admin.database();
    const [configSnap, submissionSnap] = await Promise.all([
      db.ref(`Registrations/${regId}/Config`).get(),
      db.ref(`Registrations/${regId}/Submissions/${uid}`).get(),
    ]);
    const config = parseConfig(configSnap.val());
    if (!config) {
      throw new HttpsError('failed-precondition', 'Card payments are not enabled for this registration.');
    }
    const submission = parseSubmission(submissionSnap.val());
    if (!submission) {
      throw new HttpsError('not-found', 'No registration submission found for your account.');
    }

    let team: TeamLike | null = null;
    if (submission.path === 'joiner') {
      const teamId = (submissionSnap.val() as Record<string, unknown>)?.['TeamId'];
      if (typeof teamId === 'string' && teamId.length > 0) {
        const teamSnap = await db.ref(`Registrations/${regId}/Teams/${teamId}`).get();
        team = parseTeam(teamSnap.val());
      }
    }

    const amount = owedCents(config, submission, team ?? undefined);
    if (amount <= 0) {
      throw new HttpsError('failed-precondition', 'Nothing is owed for this registration.');
    }

    const target = legacyTarget(config);
    const stripe = new Stripe(stripeSecretKey.value());
    const intent = await stripe.paymentIntents.create({
      amount,
      currency: 'usd',
      automatic_payment_methods: { enabled: true },
      metadata: webhookMetadata({ regId, uid, league: target.league, season: target.season }),
    });

    logger.info('created PaymentIntent', { regId, uid, amount });

    const keySnap = await db.ref('AppConfig/StripePublishableKey').get();
    const publishableKey = typeof keySnap.val() === 'string' ? keySnap.val() : '';

    return { clientSecret: intent.client_secret, publishableKey };
  },
);
```

- [ ] **Step 3: Build check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\functions"
npm run build
```
Expected: `tsc` completes with no errors.

- [ ] **Step 4: Commit**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git add functions/src/createRegistrationPaymentIntent.ts
git commit -m "feat(registration): createRegistrationPaymentIntent callable (L1c)"
```

---

## Task 4: `stripeWebhook` HTTP function

**Files:**
- Create: `FAN functions/src/stripeWebhook.ts`

Stripe delivers webhook events at-least-once, so the handler must be idempotent: it checks the submission is not already `Paid` before writing, and always returns `200` for events it recognizes-but-ignores (so Stripe stops retrying) or doesn't understand (defensive — a malformed/foreign event must never crash the function or leave Stripe retrying forever). Signature verification requires the RAW request body, which `onRequest` gives access to via `request.rawBody`.

- [ ] **Step 1: Create the function**

Create `FAN functions/src/stripeWebhook.ts`:

```typescript
// Cloud Function (L1c): Stripe webhook. On payment_intent.succeeded, flips
// Paid/PaidVia on the matching submission and moves the legacy Sign Ups
// entry from NotPaid to Paid — the same two writes the Manager's manual
// "Mark Paid" flip performs, so every existing consumer (Sign Ups page,
// Add-from-signups roster builder) keeps working unchanged.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { onRequest } from 'firebase-functions/v2/https';
import Stripe from 'stripe';
import { parseWebhookMetadata } from './lib/stripe_pay';

export const stripeWebhookSecret = defineSecret('STRIPE_WEBHOOK_SECRET');
export const stripeSecretKeyForWebhook = defineSecret('STRIPE_SECRET_KEY');

async function markPaid(meta: { regId: string; uid: string; league: string; season: string }): Promise<void> {
  const db = admin.database();
  const submissionRef = db.ref(`Registrations/${meta.regId}/Submissions/${meta.uid}`);
  const snap = await submissionRef.get();
  const submission = snap.val() as Record<string, unknown> | null;
  if (!submission) {
    logger.warn('stripeWebhook: submission not found, skipping', meta);
    return;
  }
  if (submission['Paid'] === true) {
    logger.info('stripeWebhook: already Paid, skipping (idempotent replay)', meta);
    return;
  }

  const displayName = typeof submission['DisplayName'] === 'string' ? submission['DisplayName'] : '';
  await submissionRef.update({ Paid: true, PaidVia: 'card' });

  const notPaidRef = db.ref(`Sign Ups/${meta.league}/${meta.season}/NotPaid/${meta.uid}`);
  const paidRef = db.ref(`Sign Ups/${meta.league}/${meta.season}/Paid/${meta.uid}`);
  await paidRef.set(displayName);
  await notPaidRef.remove();

  logger.info('stripeWebhook: marked Paid via card', meta);
}

export const stripeWebhook = onRequest(
  { secrets: [stripeWebhookSecret, stripeSecretKeyForWebhook] },
  async (request, response) => {
    const signature = request.headers['stripe-signature'];
    if (typeof signature !== 'string') {
      logger.warn('stripeWebhook: missing stripe-signature header');
      response.status(400).send('Missing signature');
      return;
    }

    const stripe = new Stripe(stripeSecretKeyForWebhook.value());
    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        request.rawBody, signature, stripeWebhookSecret.value(),
      );
    } catch (err) {
      logger.error('stripeWebhook: signature verification failed', { err: String(err) });
      response.status(400).send('Invalid signature');
      return;
    }

    if (event.type !== 'payment_intent.succeeded') {
      logger.info('stripeWebhook: ignoring unhandled event type', { type: event.type });
      response.status(200).send('ignored');
      return;
    }

    const intent = event.data.object as Stripe.PaymentIntent;
    const meta = parseWebhookMetadata(intent.metadata);
    if (!meta) {
      logger.error('stripeWebhook: payment_intent.succeeded with malformed metadata', {
        id: intent.id, metadata: intent.metadata,
      });
      response.status(200).send('malformed metadata, ignored'); // 200 so Stripe stops retrying
      return;
    }

    try {
      await markPaid(meta);
      response.status(200).send('ok');
    } catch (err) {
      logger.error('stripeWebhook: failed to mark Paid', { err: String(err), meta });
      response.status(500).send('internal error'); // 500 so Stripe retries
    }
  },
);
```

- [ ] **Step 2: Build check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\functions"
npm run build
```
Expected: `tsc` completes with no errors.

- [ ] **Step 3: Commit**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git add functions/src/stripeWebhook.ts
git commit -m "feat(registration): stripeWebhook — auto-flip Paid on payment_intent.succeeded (L1c)"
```

---

## Task 5: Export both functions from `index.ts` + full functions verification

**Files:**
- Modify: `FAN functions/src/index.ts`

- [ ] **Step 1: Add the exports**

In `FAN functions/src/index.ts`, find the last two lines (the end of the file):

```typescript
export const onPredictMatchQuestion = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/PredictionQuestions/{qid}',
  async (event) => { await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string); },
);
```

Replace with (same block, plus the new exports appended after it):

```typescript
export const onPredictMatchQuestion = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/PredictionQuestions/{qid}',
  async (event) => { await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string); },
);

// ---- Registration payments (L1c) ----

export { createRegistrationPaymentIntent } from './createRegistrationPaymentIntent';
export { stripeWebhook } from './stripeWebhook';
```

- [ ] **Step 2: Full build**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\functions"
npm run build
```
Expected: `tsc` completes with no errors; `functions/lib/index.js` re-exports `createRegistrationPaymentIntent` and `stripeWebhook` alongside the existing tournament-notification functions.

- [ ] **Step 3: Full test run**

```powershell
npm test
```
Expected: All tests pass, including `stripe_pay.test.ts` from Task 1 and every pre-existing spec under `functions/src/lib/`.

- [ ] **Step 4: Commit**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git add functions/src/index.ts
git commit -m "feat(registration): export createRegistrationPaymentIntent + stripeWebhook (L1c)"
```

---

## Task 6: Fan Flutter dependencies + Android prerequisites for `flutter_stripe`

**Files:**
- Modify: `FAN pubspec.yaml` (+ commit `pubspec.lock`)
- Modify: `FAN android/app/src/main/kotlin/com/example/flutter_application/MainActivity.kt`
- Modify: `FAN android/app/src/main/res/values/styles.xml`
- Modify: `FAN android/app/src/main/res/values-night/styles.xml`
- Modify: `FAN android/app/src/main/res/values-v31/styles.xml`
- Modify: `FAN android/app/src/main/res/values-night-v31/styles.xml`

`flutter_stripe` has two hard Android requirements documented in its own README: (1) `MainActivity` must extend `FlutterFragmentActivity`, not `FlutterActivity` (the PaymentSheet is shown as a Fragment); (2) the app's launch/normal themes must descend from a `Theme.MaterialComponents...` (or `Theme.AppCompat...`) parent, not a bare `@android:style/Theme.*` parent, because the PaymentSheet's Material components need Material theme attributes to resolve. This project's four `styles.xml` variants currently use `@android:style/Theme.Light.NoTitleBar` / `@android:style/Theme.Black.NoTitleBar` (confirmed by reading all four files) — none satisfy requirement (2) yet.

- [ ] **Step 1: Branch check + confirm no global Stripe init is needed**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`.

Note: `Stripe.publishableKey` is set lazily inside `PaymentScreen` right before `presentPaymentSheet` is called (Task 8), using the key returned by the callable / read from RTDB — there is no eager Stripe init in `lib/main.dart` and none is needed, since the key is only known once a payment screen with `config.stripe == true` loads it. This keeps app startup unaffected for the vast majority of users who never see a Stripe-enabled registration.

- [ ] **Step 2: Add the pubspec dependencies**

In `FAN pubspec.yaml`, find (the tail of the `dependencies:` block):

```yaml
  flutter_form_builder: ^10.2.0
  form_builder_validators: ^11.2.0
  mask_text_input_formatter: ^2.9.0
  pin_code_fields: ^8.0.1
```

Replace with:

```yaml
  flutter_form_builder: ^10.2.0
  form_builder_validators: ^11.2.0
  mask_text_input_formatter: ^2.9.0
  pin_code_fields: ^8.0.1
  flutter_stripe: ^12.1.0
  cloud_functions: ^6.1.0
```

- [ ] **Step 3: Resolve dependencies**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter pub get
```
Expected: resolves cleanly and updates `pubspec.lock`. If resolution fails (version conflict), fall back to:
```powershell
flutter pub add flutter_stripe cloud_functions
```
and let `pub add` pick a compatible version; then re-open `pubspec.yaml` and confirm the two lines were added (adjust the version pins above to match whatever `pub add` wrote, and note the actual resolved versions in the Task 6 commit message).

- [ ] **Step 4: MainActivity — FlutterActivity to FlutterFragmentActivity**

Read `FAN android/app/src/main/kotlin/com/example/flutter_application/MainActivity.kt` (current full contents):

```kotlin
package com.infinitesports.Infinite_Sports_App

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity()
```

Replace the entire file with:

```kotlin
package com.infinitesports.Infinite_Sports_App

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity()
```

- [ ] **Step 5: styles.xml — LaunchTheme/NormalTheme parents**

Four files, each with the SAME two-string substitution (only the theme family — Light vs Black — differs per file; the values-v31 variants add extra splash-screen items that must be preserved untouched).

**`FAN android/app/src/main/res/values/styles.xml`** — current full contents (already read above):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

Replace with:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

**`FAN android/app/src/main/res/values-night/styles.xml`** — current full contents (already read above):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is on -->
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

Replace with:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is on -->
    <style name="LaunchTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

**`FAN android/app/src/main/res/values-v31/styles.xml`** — current full contents (already read above):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowSplashScreenBackground">#ffffff</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/android12splash</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.
         
         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

Replace with (only the two `parent=` values change; the splash-screen items are untouched):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowSplashScreenBackground">#ffffff</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/android12splash</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.
         
         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

**`FAN android/app/src/main/res/values-night-v31/styles.xml`** — current full contents (already read above):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is on -->
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowSplashScreenBackground">#131313</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/android12splash</item>
        <item name="android:windowSplashScreenIconBackgroundColor">#131313</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.
         
         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

Replace with (only the two `parent=` values change):

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is on -->
    <style name="LaunchTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowSplashScreenBackground">#131313</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/android12splash</item>
        <item name="android:windowSplashScreenIconBackgroundColor">#131313</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.
         
         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

- [ ] **Step 6: Confirm desugaring is already enabled**

`flutter_stripe` requires Java 8+ core library desugaring on Android. `FAN android/app/build.gradle` already has this (read above, lines 36-40):

```gradle
    compileOptions {
        coreLibraryDesugaringEnabled true
        sourceCompatibility JavaVersion.VERSION_21
        targetCompatibility JavaVersion.VERSION_21
    }
```

and the desugaring artifact is already a dependency (lines 74-78):

```gradle
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
    ...
}
```

No change needed here — just confirm both blocks are still present after `flutter pub get` (plugin registration sometimes touches `android/app/build.gradle`'s auto-generated plugin-loader file, never this hand-written one).

- [ ] **Step 7: Build check (debug APK)**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
flutter build apk --debug
```
Expected: builds successfully. This is the earliest point a `flutter_stripe` Android integration mismatch (missing FragmentActivity, wrong theme parent, missing desugaring) would surface as a Gradle/Kotlin compile error — catching it here, before any Dart payment-screen code exists, isolates the failure to Android wiring alone.

- [ ] **Step 8: Commit**

```powershell
git add pubspec.yaml pubspec.lock android/app/src/main/kotlin/com/example/flutter_application/MainActivity.kt android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml android/app/src/main/res/values-v31/styles.xml android/app/src/main/res/values-night-v31/styles.xml
git commit -m "chore(registration): add flutter_stripe + cloud_functions, Android FragmentActivity + Material theme prerequisites (L1c)"
```

---

## Task 7: Fan payment screen — "Pay with card" button + PaymentSheet flow

**Files:**
- Modify: `FAN lib/registration/payment_screen.dart`

The current file (read in full above, 156 lines) is a `StatelessWidget`. Adding the card button requires local mutable state (loading spinner while the PaymentIntent is created / the sheet is being presented, and the publishable-key lookup), so this task converts it to a `StatefulWidget`. The public constructor signature (`regId`, `config`, `amount`, `fromSubmission`) is unchanged — no caller (`registration_status_page.dart`, `registration_form_page.dart`) needs to change.

- [ ] **Step 1: Branch check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`.

- [ ] **Step 2: Replace the whole file**

The current full contents of `FAN lib/registration/payment_screen.dart` were read above (156 lines, `StatelessWidget`). Replace the ENTIRE file with:

```dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Zelle account's registered number (shown + copyable).
const String kZelleNumber = '408-693-9436';

/// The recipient name Zelle displays for 408-693-9436 (owner-confirmed).
const String kZelleDisplayName = 'Zaya Shahbaz Arami';

/// Venmo handle for the business profile.
const String kVenmoHandle = 'infinite-sports';

/// Stripe's brand purple, used for the "Pay with card" button so it reads as
/// a distinct payment method next to Venmo blue and the Zelle card.
const Color kStripePurple = Color(0xFF635BFF);

/// Payment screen (L1a: Venmo + Zelle; L1c adds card via Stripe PaymentSheet).
/// Venmo/Zelle never auto-confirm — the admin flips Paid in the Manager.
/// Card payments DO auto-confirm: a webhook flips Paid the moment Stripe
/// reports success, and the status page (which streams the submission live)
/// picks it up with no extra work here. Re-openable from the status page
/// until Paid.
class PaymentScreen extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  /// The dollar amount THIS registrant owes — captains owe config.teamFee,
  /// individuals/joiners config.fee. Callers compute it with [amountOwed].
  final num amount;

  /// True when reached straight from a fresh submission (the status page is
  /// not underneath us) — the exit button pushes the status page instead of
  /// popping.
  final bool fromSubmission;

  const PaymentScreen({
    super.key,
    required this.regId,
    required this.config,
    required this.amount,
    this.fromSubmission = false,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  /// null while loading, '' when no key is configured (card button hidden).
  String? _publishableKey;
  bool _payingWithCard = false;

  @override
  void initState() {
    super.initState();
    if (widget.config.stripe) _loadPublishableKey();
  }

  Future<void> _loadPublishableKey() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('AppConfig/StripePublishableKey')
          .get();
      final key = snap.value;
      if (!mounted) return;
      setState(() => _publishableKey = key is String ? key : '');
    } catch (_) {
      if (mounted) setState(() => _publishableKey = '');
    }
  }

  /// venmo.com profile links open the Venmo app when it is installed
  /// (Android App Links / iOS Universal Links); otherwise the browser loads
  /// the profile page. txn=pay + amount + note pre-fill the payment.
  Uri get _venmoUri {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final note = Uri.encodeComponent('${widget.regId} - $name');
    return Uri.parse(
        'https://venmo.com/$kVenmoHandle?txn=pay&amount=${widget.amount}&note=$note');
  }

  void _exit() {
    if (widget.fromSubmission) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => RegistrationStatusPage(
                regId: widget.regId, config: widget.config)),
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _payWithCard() async {
    setState(() => _payingWithCard = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('createRegistrationPaymentIntent');
      final result = await callable.call<Map<String, dynamic>>({
        'regId': widget.regId,
      });
      final clientSecret = result.data['clientSecret'] as String?;
      final publishableKey =
          (result.data['publishableKey'] as String?) ?? _publishableKey ?? '';
      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception('No client secret returned.');
      }
      if (publishableKey.isEmpty) {
        throw Exception('No Stripe publishable key configured.');
      }

      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Infinite Sports',
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'US',
            testEnv: true, // flip to false for the production Stripe key
          ),
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'US',
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment received — confirming...')));
    } on StripeException catch (e) {
      // User-cancelled the sheet is the common case — stay silent for that,
      // show everything else.
      final isCancel = e.error.code == FailureCode.Canceled;
      if (!isCancel && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                e.error.localizedMessage ?? 'Card payment failed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Card payment failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _payingWithCard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCardButton = widget.config.stripe &&
        widget.amount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isNotEmpty;
    final cardUnavailable = widget.config.stripe &&
        widget.amount > 0 &&
        _publishableKey != null &&
        _publishableKey!.isEmpty;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Payment'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.attach_money),
              title: Text('\$${widget.amount}',
                  style: Theme.of(context).textTheme.headlineSmall),
              subtitle: Text([
                widget.config.label,
                if (widget.config.feeNote.isNotEmpty) widget.config.feeNote,
              ].join(' — ')),
            ),
          ),
          const SizedBox(height: 15),
          if (showCardButton) ...[
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kStripePurple,
                  foregroundColor: Colors.white,
                ),
                icon: _payingWithCard
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.credit_card),
                label: const Text('Pay with card',
                    style: TextStyle(fontSize: 18)),
                onPressed: _payingWithCard ? null : _payWithCard,
              ),
            ),
            const SizedBox(height: 15),
          ] else if (cardUnavailable) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Text(
                'Card payments unavailable right now.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ],
          if (widget.config.venmo) ...[
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008CFF),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Pay with Venmo',
                    style: TextStyle(fontSize: 18)),
                onPressed: () async {
                  await launchUrl(_venmoUri,
                      mode: LaunchMode.externalApplication);
                },
              ),
            ),
            const SizedBox(height: 15),
          ],
          if (widget.config.zelle) ...[
            Card(
              elevation: 2,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_balance),
                    title: const Text('Zelle',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(kZelleNumber,
                        style: TextStyle(fontSize: 18)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy number',
                      onPressed: () {
                        Clipboard.setData(
                            const ClipboardData(text: kZelleNumber));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Zelle number copied.')),
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(15, 0, 15, 12),
                    child: Text(
                        'Before sending, confirm the recipient name shows "$kZelleDisplayName".'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
          ],
          Text(
            showCardButton
                ? 'Card payments confirm automatically — your status page updates as soon as Stripe processes it. Venmo/Zelle still require an admin to mark you Paid.'
                : 'Nothing confirms automatically yet — an admin marks you Paid once your payment arrives. You can reopen this screen from your registration status any time until then.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          OutlinedButton(
            onPressed: _exit,
            child: const Text('View my registration'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze the touched file**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/registration/payment_screen.dart
```
Expected: No issues found.

- [ ] **Step 4: Run the existing widget/unit tests**

```powershell
flutter test test/registration_models_test.dart
```
Expected: unaffected, all pass (this task touches no model code).

- [ ] **Step 5: Commit**

```powershell
git add lib/registration/payment_screen.dart
git commit -m "feat(registration): Pay-with-card button + Stripe PaymentSheet flow (L1c)"
```

---

## Task 8: Manager — enable the wizard's Stripe toggle

**Files:**
- Modify: `MANAGER lib/ui/registrations/open_registration_wizard_page.dart`

The wizard (read in full above) already has a `_venmo`/`_zelle` bool-field + `SwitchListTile` pattern; it hardcodes `stripe: false` when building the `RegistrationConfig` (line 218) and shows a disabled "Coming soon" switch (lines 480-486). This task adds a `_stripe` field alongside `_venmo`/`_zelle`, wires it into the config, and turns the switch live.

- [ ] **Step 1: Branch check**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
git rev-parse --abbrev-ref HEAD
```
Expected: `zaya-registration`.

- [ ] **Step 2: Add the `_stripe` field**

In `MANAGER lib/ui/registrations/open_registration_wizard_page.dart`, find (lines 34-37):

```dart
  bool _venmo = true;
  bool _zelle = true;
  String _paymentMode = 'perPlayer';
  bool _saving = false;
```

Replace with:

```dart
  bool _venmo = true;
  bool _zelle = true;
  bool _stripe = false;
  String _paymentMode = 'perPlayer';
  bool _saving = false;
```

- [ ] **Step 3: Wire it into the config construction**

Find (line 218, inside the `RegistrationConfig(...)` constructor call in `_open()`):

```dart
      venmo: _venmo,
      zelle: _zelle,
      stripe: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
```

Replace with:

```dart
      venmo: _venmo,
      zelle: _zelle,
      stripe: _stripe,
      createdAt: DateTime.now().millisecondsSinceEpoch,
```

- [ ] **Step 4: Turn the switch live**

Find (lines 480-486):

```dart
                const SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Card (Stripe)'),
                  subtitle: Text('Coming soon — lands with phase L1c'),
                  value: false,
                  onChanged: null,
                ),
```

Replace with:

```dart
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Card (Stripe)'),
                  subtitle: const Text(
                      'Players can pay by card; Paid flips automatically'),
                  value: _stripe,
                  onChanged: (v) => setState(() => _stripe = v),
                ),
```

- [ ] **Step 5: Analyze the touched file**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
flutter analyze lib/ui/registrations/open_registration_wizard_page.dart
```
Expected: No issues found.

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/registrations/open_registration_wizard_page.dart
git commit -m "feat(registration): enable the Stripe payment-method toggle in the Open Registration wizard (L1c)"
```

---

## Task 9 (OWNER-INTERACTIVE — secrets + deploy): Deploy the functions and configure Stripe

**This task requires the owner.** No secret value (Stripe secret key, webhook signing secret, or even the publishable key) is ever typed into chat or committed to git — the commands below are printed for the OWNER to run themselves in their own terminal, pasting the real values only when their own CLI prompts for them.

- [ ] **Step 1: Build + test one more time before deploying**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter\functions"
npm install
npm test
npm run build
```
Expected: install clean, all tests pass, build clean.

- [ ] **Step 2: Owner creates a Stripe account / API keys (test mode first)**

Owner steps (in the Stripe Dashboard, `https://dashboard.stripe.com`):
1. Toggle to **Test mode** (top-right switch) — everything in this step should be done in test mode until the owner explicitly says to go live.
2. Developers -> API keys: copy the **Publishable key** (`pk_test_...`) and the **Secret key** (`sk_test_...`). Keep this tab open.

- [ ] **Step 3: Owner sets the two function secrets**

Run these from `C:\Users\zayaa\StudioProjects\infinite_sports_flutter` (the `firebase-tools` CLI prompts for the value interactively — nothing is passed on the command line, so it never lands in shell history):

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
firebase functions:secrets:set STRIPE_SECRET_KEY
```
Paste the `sk_test_...` secret key when prompted.

```powershell
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
```
Leave this one for Step 5 (the webhook signing secret does not exist until the webhook endpoint below is created) — come back to it after Step 5. If the CLI requires a value now, paste any placeholder (e.g. `whsec_placeholder`) and re-run the same command in Step 5 with the real value; `secrets:set` overwrites, it does not append.

- [ ] **Step 4: Deploy the two new functions**

```powershell
firebase deploy --only functions:createRegistrationPaymentIntent,functions:stripeWebhook
```
Expected output includes the deployed HTTPS URL for `stripeWebhook`, e.g. `https://us-central1-infinite-sports-app.cloudfunctions.net/stripeWebhook`. Copy this URL — it's needed in Step 5.

- [ ] **Step 5: Owner creates the Stripe webhook endpoint**

In the Stripe Dashboard (still Test mode): Developers -> Webhooks -> **Add endpoint**.
- Endpoint URL: the `stripeWebhook` URL copied in Step 4.
- Events to send: select **`payment_intent.succeeded`** only.
- Save, then open the new endpoint's detail page and copy its **Signing secret** (`whsec_...`).

Now set (or re-set) the real value:
```powershell
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
```
Paste the `whsec_...` signing secret when prompted.

- [ ] **Step 6: Re-deploy so both functions pick up the (possibly updated) secrets**

```powershell
firebase deploy --only functions:createRegistrationPaymentIntent,functions:stripeWebhook
```
Expected: deploy succeeds; Firebase automatically restarts functions bound to a secret whose value changed.

- [ ] **Step 7: Owner writes the publishable key into RTDB**

The publishable key is not secret (Stripe ships it to every client by design) but still isn't hardcoded — it lives in `AppConfig/StripePublishableKey` so it can be rotated without a code change. Set it with the Firebase CLI's database:set (replace `pk_test_REPLACE_ME` with the real test-mode publishable key copied in Step 2):

```powershell
firebase database:set /AppConfig/StripePublishableKey --data '"pk_test_REPLACE_ME"' --project infinite-sports-app
```
Confirm the prompt with `y`. Verify:
```powershell
firebase database:get /AppConfig/StripePublishableKey --project infinite-sports-app
```
Expected: prints the same `pk_test_...` string.

- [ ] **Step 8: Sanity-check the deployed functions**

```powershell
firebase functions:list
```
Expected: `createRegistrationPaymentIntent` (callable) and `stripeWebhook` (https) both listed with status ACTIVE.

No commit in this task — it is pure infrastructure configuration outside git.

---

## Task 10: Builds + install (one app at a time)

**Files:** none (build-only task).

- [ ] **Step 1: Fan analyze (touched paths, then full pass)**

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
Set-Location "C:\Users\zayaa\StudioProjects\infinite_sports_flutter"
flutter analyze lib/registration/payment_screen.dart
```
Expected: No issues found.

```powershell
flutter analyze
```
(Generous timeout — this repo's full analyze can be slow.) Expected: No new issues introduced by this plan (pre-existing warnings elsewhere are out of scope).

- [ ] **Step 2: Fan full test suite**

```powershell
flutter test
```
Expected: all tests pass, including `test/registration_models_test.dart` (untouched by this plan) and `test/widget_test.dart`.

- [ ] **Step 3: Fan release build**

```powershell
flutter build apk --release
```
Expected: builds successfully (this is the real integration check for the `flutter_stripe` Android wiring from Task 6 under release/R8 — debug builds can mask ProGuard/R8 issues that only show up in release).

- [ ] **Step 4: Install the fan release build to the test device**

```powershell
flutter install --device-id GN434J02403404RL
```
Expected: installs without error.

- [ ] **Step 5: Manager analyze + debug build**

```powershell
Set-Location "C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter"
flutter analyze lib/ui/registrations/open_registration_wizard_page.dart
flutter build apk --debug
```
Expected: no issues; debug build succeeds (Manager gets no Stripe SDK, so a debug build is sufficient — only the toggle's persisted value changed).

- [ ] **Step 6: Install the Manager debug build to the test device**

```powershell
flutter install --device-id GN434J02403404RL
```
Expected: installs without error. Builds/installs are sequential (never run the fan and Manager Gradle builds in parallel) per the Conventions section.

No commit in this task — it only builds/installs previously committed code.

---

## Task 11 (OWNER, on-device): End-to-end Stripe test-mode walkthrough

**This task is for the owner to run on their phone**, after Task 9's secrets/webhook setup and Task 10's installs are both done. It exercises the whole L1c path with Stripe's official test card — no real money moves in test mode.

- [ ] **Step 1: Open (or reuse) a Stripe-enabled registration**

In the Manager app (the build installed in Task 10): Registrations -> Open Registration (or edit an existing open one if the wizard supports it) -> turn on the **Card (Stripe)** toggle from Task 8 alongside Venmo/Zelle -> set a small test fee (e.g. `$1`) -> Open registration.

- [ ] **Step 2: Register on the fan app**

In the fan app: open the registration from the drawer or the Matches banner -> pick **Individual** -> fill the form -> Submit. You should land on the payment screen (or reach it via "Complete payment" on the status page) showing Venmo, Zelle, AND a purple **Pay with card** button.

If the card button is missing but Venmo/Zelle show: the publishable key likely isn't set — re-check Task 9 Step 7 (`firebase database:get /AppConfig/StripePublishableKey`).

- [ ] **Step 3: Pay with Stripe's test card**

Tap **Pay with card**. In the PaymentSheet, enter:
- Card number: `4242 4242 4242 4242`
- Expiry: any future date (e.g. `12/34`)
- CVC: any 3 digits (e.g. `123`)
- ZIP: any 5 digits (e.g. `94105`)

Submit. Expected: a snackbar reads "Payment received — confirming...".

- [ ] **Step 4: Confirm Paid flips automatically (no admin action)**

Within a few seconds, the fan app's registration status screen should show **Paid** (via the live `RegistrationStatusPage` stream — no pull-to-refresh needed) with **Paid via card** styling. In the Manager's Submissions page for that registration, the same row should show Paid = Yes without anyone tapping "Mark Paid".

- [ ] **Step 5: Confirm the legacy dual-write moved too**

In the Manager's existing Sign Ups page for that league/season, the test account should appear under **Paid**, not **Not Paid** — proving the webhook's legacy move (mirroring the manual Mark-Paid flip) worked.

- [ ] **Step 6: Test the cancel path**

Submit a second test registration (or reopen the payment screen on an unpaid one), tap **Pay with card**, then dismiss the PaymentSheet without entering card details (back gesture / close button). Expected: no snackbar, no crash, the payment screen stays exactly as it was, Paid stays false.

- [ ] **Step 7: Test the decline path**

Retry with Stripe's decline test card `4000 0000 0000 0002` (any future expiry/CVC/ZIP). Expected: the PaymentSheet shows a decline message inline (Stripe's own UI) and/or a snackbar appears; Paid stays false; the payment screen remains usable to retry.

- [ ] **Step 8: Report back**

Owner confirms all six checks (card button shown, payment succeeds, auto-Paid, legacy dual-write, cancel is silent, decline is handled) before this phase is considered done. Any failure here means stopping and debugging BEFORE going live-mode — do not swap in production Stripe keys until test mode round-trips cleanly.

---

## Self-Review

**Spec §6 coverage** (`docs/superpowers/specs/2026-06-30-registration-redesign-design.md`):
- "`flutter_stripe` Payment Sheet (card + Apple Pay + Google Pay) as another method button" -> Task 7's `SetupPaymentSheetParameters` includes both `googlePay` and `applePay`, plus automatic card support via `automatic_payment_methods` on the PaymentIntent (Task 3).
- "Cloud Function creates the PaymentIntent" -> Task 3 (`createRegistrationPaymentIntent`).
- "success webhook sets `Paid: true, PaidVia: 'card'` + legacy move to Paid automatically" -> Task 4 (`stripeWebhook`), exact field values matched.
- "Stripe secret key + webhook secret live only in Cloud Functions config" -> `defineSecret` in Tasks 3/4, never referenced elsewhere; Task 9 has the owner set them interactively, no value ever appears in a file or chat message.
- "the publishable key ships in-app" -> read from RTDB at runtime (Task 7), not hardcoded, matching the fact sheet's explicit instruction over the spec's looser wording.
- "Physical-services app -> external payments permitted by Apple (no IAP)" -> no App Store IAP code introduced; Stripe is a standard payment processor call, consistent with the existing Venmo/Zelle external-payment pattern already shipped in L1a.
- Spec §2 "`flutter_stripe` added only in L1c" -> confirmed by grep before writing this plan: no `flutter_stripe`/`cloud_functions` reference exists anywhere in the fan repo outside the spec document itself.
- Spec §9 "L1c: Stripe auto-confirm. Ship. Each phase: tests + analyze + build/install + owner test before the next." -> Task 1 has TDD tests, Task 5 runs the full functions suite, Task 10 covers analyze + build + install for both apps, Task 11 is the owner test.

**Placeholder scan:** every code block in Tasks 1-8 is a complete, compilable file or a complete find/replace pair against real, previously-read file contents (no `// TODO`, no `...`, no `<your code here>`). The only intentional placeholders are literal secret values that must never be committed (Task 9's `pk_test_REPLACE_ME` example and the interactive `firebase functions:secrets:set` prompts) — these are infrastructure commands run by the owner outside the codebase, not code.

**Type consistency:**
- Dollars vs cents: the Dart layer (`amountOwed`, unchanged from L1a/L1b) stays dollars end-to-end through `PaymentScreen.amount`; the NEW TS layer (`owedCents`) works in cents because Stripe's API requires an integer minor-unit amount — the conversion (`toCents`, `Math.round(dollars * 100)`) happens once, inside `stripe_pay.ts`, and is unit-tested for fractional-cent rounding (Task 1's `19.99`/`12.345` cases). The Dart client never sends a dollar amount to the callable at all — `createRegistrationPaymentIntent` takes only `{regId}` and recomputes the amount server-side, so there is no cross-language amount to keep in sync/spoof.
- `PaidVia` values: Dart's `RegSubmission.paidVia` is an untyped free-form `String` (confirmed by reading `registration_models.dart`), so adding `'card'` as a new legal value (Task 4) requires no model change on either client.
- `RegistrationConfig.stripe`: already exists as a `bool` getter from L1a (confirmed by reading the model) — Task 7 reads `widget.config.stripe` directly, Task 8 just stops hardcoding `false` when writing it.
- Metadata round-trip: Stripe stores PaymentIntent metadata as `Record<string, string>`; `webhookMetadata`/`parseWebhookMetadata` (Task 1) are the single source of truth for that shape on both the write side (Task 3) and read side (Task 4), and are unit-tested for the round-trip plus three failure shapes (missing field, null, non-string).

**Deferred / explicitly out of scope for this plan:**
- Switching Stripe from test mode to live mode (owner decision, done by swapping the Dashboard mode + re-running Task 9 with live keys once Task 11 passes clean).
- iOS Apple Pay entitlement/merchant-ID setup (spec explicitly scopes L1c's device testing to the Android test device `GN434J02403404RL`; iOS Stripe wiring is not part of this plan's builds).
- A Manager-side view of individual Stripe payment records (Stripe's own Dashboard already gives the owner this; the Manager submissions page already shows Paid/PaidVia from L1a/L1b unchanged).
- Refunds/disputes handling (no `charge.refunded`/`charge.dispute.created` webhook branches — out of scope until the owner asks for it).
- Any change to `lib/registration/registration_form_page.dart`, `registration_path_page.dart`, `registration_entry_page.dart`, or `registration_status_page.dart` — none needed; confirmed by reading `registration_status_page.dart` in full, which already streams the submission live and calls `PaymentScreen` with a computed `amount`, so a webhook-driven Paid flip requires zero changes there.

**Risks:**
- `flutter_stripe: ^12.1.0` pinned from the fact sheet without a live `flutter pub get` resolution check in this planning pass — Task 6 Step 3 has an explicit `flutter pub add` fallback with instructions to record whatever version actually resolves.
- `stripe: ^18.0.0` (Node SDK) is a reasonable current major-version guess but unverified against npm at plan-writing time — Task 2 Step 3's `npm install` is the actual source of truth; if the resolved version differs materially, no code in this plan depends on Stripe SDK internals beyond `stripe.paymentIntents.create`, `stripe.webhooks.constructEvent`, and the `Stripe.Event`/`Stripe.PaymentIntent` types, which have been stable across the SDK's v14-v18 range.
- The Android theme change (`@android:style/Theme.*` -> `Theme.MaterialComponents.DayNight.NoActionBar`) touches app-wide chrome, not just the payment screen — Task 6 Step 7's full `flutter build apk --debug` and Task 10's release build are the guardrails; if any existing screen visually regresses (unlikely, since Flutter draws its own Material widgets over this native theme and only the splash/pre-Flutter-frame chrome is natively rendered), the owner will see it in Task 11's walkthrough and this should be reported back before going further.
- Webhook idempotency relies on checking `Paid !== true` before writing; this is a read-then-write (not a transaction), so two near-simultaneous webhook deliveries for the same PaymentIntent could theoretically both pass the check before either writes. Impact is limited to redundant identical writes (Paid stays true, PaidVia stays 'card', the legacy move re-runs harmlessly since `.set()`/`.remove()` are naturally idempotent) — no double-charge risk exists because Stripe only charges once per PaymentIntent regardless of webhook delivery count. Upgrading to an RTDB transaction is a reasonable future hardening but not required for correctness here.
- `automatic_payment_methods: { enabled: true }` on the PaymentIntent lets Stripe show whatever payment methods are enabled in the connected Stripe account's Dashboard settings (which may include more than card/Apple Pay/Google Pay, e.g. Link) — this matches spec intent ("card + Apple Pay + Google Pay") loosely rather than exactly; if the owner wants to restrict to exactly those three, Task 9's Stripe Dashboard has a Payment Methods settings page to narrow it without any code change.

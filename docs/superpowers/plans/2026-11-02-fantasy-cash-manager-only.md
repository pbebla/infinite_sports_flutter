# Fantasy Cash: Manager-only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cash stops being a fan-facing payment method. Fans only ever see Card, Venmo and Zelle. The owner records a cash payment himself in the Manager, which activates the fan's access as a PAID pass (receipt email, counts in revenue).

**Owner decision (2026-11-02, verbatim):** "provide the option only for me in the manager app so i can check it if someone paid cash but on the fan app, they only get card, venmo, and zelle option."

**Architecture:** Undo the fan-side half of the 2026-11-01 Cash round (fan "I paid cash" box, `Methods.Cash` switch, `cash` claim method) and add one Manager write, "Record cash payment", that creates an `Access/<uid>` record `{Status: active, Via: 'cash', AmountCents, PaidAt, By: <admin uid>}`. The server already treats `Via: cash` as paid (`PAID_VIAS`), so `onFantasyAccessStatusWritten` sends the `activatedPaid` receipt ("Method: cash") and the Manager revenue tile already counts it. No server code changes beyond reverting the claim method.

**Tech stack:** Flutter (fan app, Manager app, Riverpod in Manager), Firebase RTDB rules, Cloud Functions TS (vitest).

**Repos / branches:** fan repo `infinite_sports_flutter` branch `zaya-fantasy`; Manager repo `InfiniteSportsManagerFlutter` branch `zaya-fantasy`. Commit locally, never push.

---

## Why a fan without a team must be reachable

A gated fan cannot name a team (rules gate `Managers/$uid` on access), so someone who paid cash usually has NO fantasy profile page yet. The cash action therefore must work from the **Grant sheet's user picker** (any user account), not only from a fantasy profile. The profile access card gets the same action for fans who already have a team (a revoked or lapsed manager).

## What does NOT change

- `AccessVia.cash` stays on both sides (records, labels, `isPaid`, revenue).
- Templates: `activatedPaid` already renders `Method: {method}` → "cash".
- The pending-claims flow for Venmo/Zelle is untouched.
- Existing data: no live season has `Methods.Cash = true` (Futsal 15 Config/Access has no Cash key, checked 2026-11-02), and no `Via: cash` records exist. Nothing to migrate.

---

### Task 1: Fan app — remove the cash pay path

**Files:**
- Modify: `lib/fantasy/hub/access_pay_card.dart` (delete `_CashBox` and its `if (cfg.cash)` render; keys `access_pay_card_cash`, `access_pay_card_cash_sent` disappear)
- Modify: `lib/fantasy/data/fantasy_access.dart` (drop the `cash` field from `FantasyAccessConfig` and its `Methods.Cash` parse; drop `FantasyAccessMethod.cash`)
- Test: `test/fantasy/access_pay_card_test.dart`, `test/fantasy/fantasy_access_test.dart`

- [ ] Replace the two existing cash tests in `access_pay_card_test.dart` with ONE regression test: a config node with `'Methods': {'Venmo': true, 'Zelle': true, 'Cash': true, 'Card': true}` renders the card, Venmo and Zelle buttons and NO widget with key `access_pay_card_cash` and no text containing "cash" (case-insensitive). This pins that a stray `Cash: true` in the database can never show a cash option to fans.
- [ ] Remove `bool cash` from the test helper `passConfig` and the `'Cash': cash` map entry.
- [ ] In `fantasy_access_test.dart`, drop cash expectations; add `expect(FantasyAccessMethod.values.map((m) => m.db), ['venmo', 'zelle'])`.
- [ ] Delete the fan-side cash code. Run `flutter test test/fantasy` (expect all green) and `flutter analyze lib/fantasy test/fantasy` (0 new issues).
- [ ] Commit: `feat(fantasy): fans pay by card, Venmo or Zelle only (cash is Manager-only)`.

### Task 2: Server + rules — fans can no longer claim cash

**Files:**
- Modify: `functions/src/lib/fantasy/access.ts` (`ClaimMethod = 'venmo' | 'zelle'`; `claimFrom` rejects `'cash'`; `accessConfigFrom` drops `methods.cash`; keep `'cash'` in `AccessVia`, `PAID_VIAS` and `methodLabel`)
- Modify: `database.rules.json` AND `database.rules.stage1.json` (claim `Method` `.validate` regex back to `^(venmo|zelle)$`)
- Test: `functions/src/lib/fantasy/access.test.ts`, `functions/src/rules_contract.test.ts`

- [ ] Tests first: `claimFrom({Method: 'cash', ...})` returns null; `methodLabel('cash')` still returns `'cash'`; `PAID_VIAS` still contains `'cash'`; the rules contract test pins `^(venmo|zelle)$` in both rules files.
- [ ] Make them pass. Run `npx vitest run` (all green) and `npx tsc --noEmit -p .`.
- [ ] Probe the rules in the LOCAL emulator only (scratchpad `hardening/access_rules_check.js` pattern): a fan's own claim with `Method: 'cash'` is DENIED, `'venmo'` still allowed, and an ADMIN write of `Access/<uid>` with `Via: 'cash'` is ALLOWED (no `Via` pattern may reject it).
- [ ] Commit: `fix(fantasy-access): claims are venmo|zelle only; cash is recorded by an admin`.

### Task 3: Manager — the cash record and its write

**Files:**
- Modify: `lib/fantasy/data/fantasy_access_admin.dart`
  - add `Map<String, Object> cashRecord({required String by, required int nowMs, required int amountCents})` → `{Status: active, Via: cash, AmountCents: amountCents, PaidAt: nowMs, By: by}`
  - remove the `cash` field from `AccessConfig` (constructor, `copyWith`, `toMap` `Methods`, `==`, `hashCode`, parse) and restore the validate message "(Venmo, Zelle or Card)"
- Modify: `lib/services/fantasy_access_writes.dart`
  - add `TxDecision cashDecision(Object? current, {by, nowMs, amountCents})`: abort when already ACTIVE (never overwrite a live pass, same rule as grant); otherwise commit `cashRecord` keeping `Notified` (`_withNotified`), exactly like `grantOneDecision`
  - add `Future<AccessActionResult> recordCashGuarded(store, {sport, season, uid, by, nowMs, amountCents, String? actedClaimKey})` = transaction with `cashDecision`, then resolve that fan's open claims with `_resolveClaims` (the approve path's helper): with `actedClaimKey` (the "Paid in cash instead" row action, Task 4) that claim resolves `approved` and the others `superseded`; without it every open claim resolves `superseded`
- Modify: `lib/services/firebase/fantasy_access_service.dart` (`recordCash(...)` calling `recordCashGuarded`)
- Test: `test/fantasy/fantasy_access_admin_test.dart`, `test/fantasy/fantasy_access_writes_test.dart`

- [ ] Tests first: `cashRecord` shape; `cashDecision(null)` commits (an absent record: RTDB's first run can be an empty cache, so never abort on null); `cashDecision(active)` aborts; `cashDecision(pending)` commits and keeps `Notified`; `cashDecision(revoked)` commits; `recordCashGuarded` without `actedClaimKey` supersedes every open claim; with `actedClaimKey: 'k1'` claim k1 resolves `approved` and another open claim `superseded`; an already-active fan → `AccessActionResult.alreadyActive` and the acted claim resolves `superseded` (same as approve); `AccessConfig().toMap()['Methods']` has no `Cash` key.
- [ ] Implement. Run `flutter test test/fantasy` (green).
- [ ] Commit: `feat(fantasy-access): record a cash payment (admin-only Via cash)`.

### Task 4: Manager UI — "Paid in cash" in the Grant sheet and on the profile card; Cash switch removed

**Files:**
- Modify: `lib/ui/fantasy/access/access_mode_card.dart` (delete the Cash `SwitchListTile` and `_cash`)
- Modify: `lib/ui/fantasy/access/grant_access_sheet.dart`
  - in the **Pick users** source only, add a second choice under the picker: `SegmentedButton` "Free" / "Paid in cash" (default Free). "Paid in cash" shows an amount field prefilled with the season price (`AccessConfig.amountDollars`, whole dollars or .50, validated like the price field)
  - the confirm dialog says "Record a $5 cash payment for N people?" and the button "Record payment"
  - Team / All-registered sources stay grant-only (cash is per person)
- Modify: `lib/ui/fantasy/access/profile_access_card.dart` (next to Grant / Revoke: `OutlinedButton` "Paid in cash" when the fan is NOT active; same amount dialog; calls `recordCash`)
- Modify: `lib/ui/fantasy/access/pending_claims_card.dart` (copy back to "Fans who tapped "I sent it" for Venmo or Zelle."; each claim row gets a third action **"Paid in cash instead"** next to Approve / Reject: the same amount dialog prefilled with the season price, then `recordCash(uid, amountCents, actedClaimKey: claim.key)` — Fable review B, owner-approved 2026-11-03)
- Test: `test/ui/fantasy/fantasy_access_page_test.dart`, `test/ui/fantasy/grant_access_sheet_test.dart`, `test/ui/fantasy/fantasy_profile_detail_page_test.dart`

- [ ] Widget tests first: the mode card has no "Cash" switch; Pick users → "Paid in cash" → amount prefilled `5` → Record payment calls the fake's `recordCash` with 500 cents per picked uid; an already-active user is listed as "already active" and skipped (same preview as grant); the profile card shows "Paid in cash" only when not active; a pending claim row's "Paid in cash instead" → amount prefilled `5` → calls `recordCash` with 500 cents and that claim's key; both layouts at 360 px wide in light AND dark (project rule).
- [ ] Implement. Run `flutter test` (whole Manager suite) and `flutter analyze`.
- [ ] Commit: `feat(fantasy-access): Paid in cash in the Grant sheet + profile; Cash switch removed`.

### Task 5: Deploy, install, verify

- [ ] Deploy (owner has approved deploys of this feature line): `firebase deploy --only database,functions:onFantasyAccessClaimCreated,functions:onFantasyAccessStatusWritten,functions:createFantasyCheckoutSession,functions:sendFantasyAccessTest,functions:onRegistrationPaidGrantFantasy,functions:stripeWebhook --project infinite-sports-app`. Verify live rules == file.
- [ ] Build + install the fan APK on the emulator and the Manager APK on the emulator and the tablet `10.0.0.146:5555`.
- [ ] Live check on Futsal 15 (the test season), with the owner: Manager → Grant access → Pick users → the emulator's test account → Paid in cash $5 → the emulator unlocks, the receipt says "Method: cash", the revenue tile goes up by $5. Then Revoke it to restore the test state.
- [ ] iOS line for the PR: the Grant sheet's SegmentedButton + amount field on iPad (verify on simulator).
- [ ] Update memory `infinite_fantasy_plan.md` (cash is Manager-only).

## Self-review notes

- Spec coverage: fan sees card/Venmo/Zelle only (Task 1, plus a regression test against a stray `Cash: true`); owner can mark cash (Tasks 3-4, reachable for fans with no team via Pick users); receipts/revenue need no change (verified `PAID_VIAS`, `isPaid`).
- The new transaction never aborts on null (the 2026-11-02 refund bug class).
- Resolved by the Fable review (2026-11-03, `2026-11-03-fable-review-selling-rule-and-cash.md` §B): YES, "Paid in cash instead" on a pending claim row (Tasks 3-4).
- Do NOT touch the fan app's `Via` parsing: it is plain text (`fantasy_access.dart`), so a `Via: cash` record still reads as active after Task 1.

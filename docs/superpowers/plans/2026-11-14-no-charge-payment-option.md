# "No charge" Payment Option Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** written 2026-11-14 on Opus 5.5 for **Fable review before any code is written** (owner's rule). Part B (Task 6) was approved by the owner on 2026-11-14 ("yes"), so all six tasks are in scope.

**Goal:** Give the owner a "No charge" choice when recording a registration payment. The player counts as settled (team-eligible, never asked for money) but earns no Insiders referral credit.

**Architecture:** "No charge" is stored as an ordinary paid submission with `Paid: true`, `PaidVia: 'no charge'` and `PaidAmount: 0`. Everything that already treats `Paid: true` as settled keeps working unchanged: the season builder's "Paid players only" switch, the legacy `Sign Ups` Paid bucket, fantasy access, the fan's home banner and drawer. Only two things learn the new value:
- **Referral credit (server).** The Insiders watcher credits `Paid === true && PaidVia !== 'no charge'` instead of `Paid === true`.
- **Labels (both apps).** The Manager and fan apps show "No charge" instead of "Paid".

A small rules change stops a fan from editing the payment fields on their own submission, so nobody can turn their own "No charge" into credited payment.

**Tech Stack:** Flutter/Dart (fan app `infinite_sports_flutter`, Manager `InfiniteSportsManagerFlutter`), TypeScript Cloud Functions v2 (`functions/`, vitest), Firebase RTDB rules (`database.rules.stage1.json` deployed, `database.rules.json` target).

**Spec:** the "Owner decisions" section below (chat, 2026-11-14). There is no separate design doc; the design was proposed in chat and answered by the owner.

## Owner decisions (the spec)

1. Owner's request, verbatim: "Id like to have an option that says we are not going to charge them like its free but i dont want you to flip those guys to free because like i said some of them will pay and some of them wont and you dont know which one. so come up with that option and i will go back to the players and make the change myself afterward."
2. **Nobody is changed by code.** The 10 Futsal-16 players marked "Paid · Venmo · $0" stay exactly as they are. The owner edits each one himself.
3. Owner, verbatim: "setting someone no charge should not get credit for inside referral."
4. Owner, verbatim: "anyone with partial it is ok to get credit." The 9 partial payers ($50 to $220 of $255) stay Paid and keep counting. No partial-payment feature.
5. From the proposal the owner accepted:
   - "No charge" sits next to Venmo / Zelle / Cash / Other in the mark-paid dialog and sets the amount to $0.
   - The player counts as settled: usable with "Paid players only", no "You owe", no reminder banner.
   - The player sees "No charge" in the fan app.
   - Changing someone from Paid to "No charge" removes their referrer's credit. The credit comes back if they later pay.
6. **Free sign-ups start out "No charge" automatically.** This is Part B, Task 6. The question was "when a registration costs nothing, should the player start out as 'No charge' automatically, instead of 'Payment pending' until you mark them?" The owner answered "yes" on 2026-11-14.

Live facts checked 2026-11-14 (read-only, counts only):
- Futsal-16 is the only registration. Fee $255, team fee $0, status open.
- 56 submissions: 27 paid in full, 9 partial, 10 at $0, 10 unpaid.
- **None of the 56 carry an Insider code and none has a counted referral.** Changing the 10 to "No charge" removes no one's credit today.

## Global Constraints

- Stored value, exactly: `PaidVia: 'no charge'` (lowercase, one space), `PaidAmount: 0`, `Paid: true`.
- Display copy, exactly:
  - Manager row status: `No charge`
  - Manager method line: `No charge — not charged`
  - Fan chip: `No charge`
  - Fan status card: `No charge — nothing to pay`
  - Insiders void reason: `marked no charge`
- Dialog copy, exactly:
  - Helper when No charge is picked: `Not charged. Does not count as an Insiders referral.`
  - Hint for a $0 paid method: `Amount is $0. Pick No charge if this player is not paying.`
- No code, script or migration changes any existing submission. The owner edits the 10 by hand.
- Light and dark mode for every new color: use a brightness-conditional pair or the `colorScheme`, never a single light-palette color. Works at 360 px wide.
- Fan app: real-time `onValue` streams only. No RTDB `get()`, no bare `.once()`.
- Dialogs with text fields are StatefulWidgets that own and dispose their controllers. Never dispose right after `await showDialog`.
- Fix the whole bug class: every place that labels a paid submission learns "No charge", in both apps.
- Teammates and captains keep seeing only Paid / Not paid. "No charge" is shown only to the player and to admins, because it is a private arrangement. `RegistrationsPublic` stays `{DisplayName, Paid}`.
- PII never goes into commits, tests, logs or docs. Use made-up names in tests.
- iOS parity. Anything that can't be checked here gets a "verify on iPhone simulator" line in the PR.
- Branches:
  - Fan + functions + rules: `zaya-no-charge` from `zaya-review-fixes` @ `36e4b43`.
  - Manager: `zaya-no-charge` from `zaya-season-builder-2` @ `b2370f1` (it contains every other Manager branch).
- Do not push, deploy or install anywhere without the owner's go. The rollout order is at the end.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the executing model's own line).

## Review Focus

1. **The owner switches a credited player (Paid · Venmo) to No charge with "Edit payment".** `Paid` stays true and only `PaidVia` changes. The referral must be voided exactly once, and the Insider gets the normal "voided" push. Today's watcher returns early because `Paid` did not flip. Test in Task 1.
2. **A No charge player switched off (Not paid) and back on.** The record is kept on unmark, so the dialog reopens seeded on No charge. Confirming must still give no credit. No charge → Venmo must count exactly once. Tests in Task 1 (credit decision) and Task 4 (dialog seed).
3. **A rostered player marked Not paid keeps their team spot** and sees "You owe $255" with the pay button. Nothing may remove a player from `Line Ups` or teams on a Paid change. Verification step in Task 3.
4. **A No charge player with a $255 fee** must see no pay button and no "You owe", even though the fee is above 0. Test in Task 5.
5. **A fan rewrites their own submission to change `PaidVia` or `PaidAmount`.** Denied, including while sign-ups are open. Creating a new submission and the team-code born-paid path must keep working. Probes in Task 2.

---

### Task 1: Referral credit ignores "No charge" (functions)

**Files:**
- Modify: `functions/src/lib/insiders.ts` (pure decision, next to `decideOnPaidFlip`)
- Modify: `functions/src/insiders_watch.ts:301-322` (`onSubmissionPaidChange`), `handleVoid` (void reason)
- Test: `functions/test/insiders.test.ts`

**Interfaces:**
- Produces:
  - `export const NO_CHARGE = 'no charge';`
  - `export function isReferralCredited(sub: Record<string, unknown>): boolean`. True only when `sub['Paid'] === true` and `String(sub['PaidVia'] ?? '').trim().toLowerCase() !== NO_CHARGE`.
  - `export function creditChange(before: Record<string, unknown>, after: Record<string, unknown>): 'count' | 'void' | null`.

- [ ] **Step 1: Write the failing tests** in `functions/test/insiders.test.ts`, inside `describe('referral credit and No charge', ...)`:
  - `isReferralCredited({Paid:true, PaidVia:'venmo'})` → `true`
  - `isReferralCredited({Paid:true, PaidVia:'no charge'})` → `false`
  - `isReferralCredited({Paid:true, PaidVia:' No Charge '})` → `false`
  - `isReferralCredited({Paid:true})` → `true` (partial or unknown method still counts)
  - `isReferralCredited({Paid:false, PaidVia:'venmo'})` → `false`
  - `creditChange({Paid:true,PaidVia:'venmo'}, {Paid:true,PaidVia:'no charge'})` → `'void'` (Review Focus 1)
  - `creditChange({Paid:true,PaidVia:'no charge'}, {Paid:true,PaidVia:'zelle'})` → `'count'`
  - `creditChange({Paid:false,PaidVia:'no charge'}, {Paid:true,PaidVia:'no charge'})` → `null` (Review Focus 2)
  - `creditChange({Paid:true,PaidVia:'no charge'}, {Paid:false,PaidVia:'no charge'})` → `null`
  - `creditChange({}, {Paid:true,PaidVia:'team code'})` → `'count'` (unchanged behavior)
  - `creditChange({Paid:true,PaidVia:'cash',PaidAmount:50}, {Paid:true,PaidVia:'cash',PaidAmount:80})` → `null`
- [ ] **Step 2:** Run `cd functions && npx vitest run test/insiders.test.ts`. Expected: FAIL (functions not exported).
- [ ] **Step 3:** Implement both functions in `lib/insiders.ts`. In `onSubmissionPaidChange`:
  - Replace the `wasPaid`/`isPaid` early return with `const change = creditChange(before, after); if (!change) return;`.
  - Then `'count'` → `handleCount`, `'void'` → `handleVoid`.
  - Pass the void reason into `handleVoid`: `'marked no charge'` when `after.Paid === true`, else the existing `'payment reversed'`.
  - Update the file-header and function doc comments from "Paid flip" to "referral-credit change".
  - `decideOnPaidFlip` keeps its inputs; the watcher passes `wasPaid: true, isPaid: false` on void and `false, true` on count as today.
- [ ] **Step 4:** Run `npx vitest run test/insiders.test.ts`, then the whole suite with `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(insiders): a "No charge" registration earns no referral credit; switching to it voids the credit`

### Task 2: Fans cannot edit the payment fields of their own submission (rules)

**Files:**
- Modify: `database.rules.stage1.json` and `database.rules.json`, both at `Registrations/$regId/Submissions/$uid/.validate`
- Test: `functions/src/rules_contract.test.ts` (near line 830), `functions/tools/probe_rules.ts` (cases near lines 263-307)

**Interfaces:** none (rules only).

- [ ] **Step 1: Write the failing probe cases** in `probe_rules.ts`. Seed an existing fan submission `{Path:'individual', Paid:true, PaidVia:'no charge', PaidAmount:0, …}` on an open registration, then:
  - `'a paid fan cannot change their own PaidVia'`: fan PUTs the same body with `PaidVia:'venmo'` → **denied**
  - `'a paid fan cannot change their own PaidAmount'`: `PaidAmount:255` → **denied**
  - `'an unpaid fan cannot add a payment method to their own submission'`: seed `Paid:false`, PUT `PaidVia:'venmo'` → **denied**
  - `'a fan can rewrite their own submission when the payment fields are unchanged'`: same body, changed `Answers` → **allowed**
  - `'an admin can mark a submission No charge'`: admin PATCH `{Paid:true, PaidVia:'no charge', PaidAmount:0}` → **allowed**
  - The existing cases stay green: "a joiner of an admin-approved waiving team is born Paid" and "a plain individual submission (Paid:false) is allowed".
- [ ] **Step 2:** Add a `rules_contract.test.ts` case. Both files' `.validate` must contain the unchanged-payment clause, and the two files must stay textually identical for this node.
- [ ] **Step 3:** Run `npm test` and `npm run probe:rules` (local emulator only, never production). Expected: the new cases FAIL.
- [ ] **Step 4:** Implement. The new `.validate` is:

```
root.child('Admins').child(auth.uid).exists() || ((!data.exists() || (newData.child('Paid').val() == data.child('Paid').val() && newData.child('PaidVia').val() == data.child('PaidVia').val() && newData.child('PaidAmount').val() == data.child('PaidAmount').val())) && (<the current non-admin expression, unchanged>))
```

  Put it in both files.
- [ ] **Step 5:** Run `npm test` and `npm run probe:rules`. Expected: all pass.
- [ ] **Step 6:** Search the fan app. Confirm it never rewrites an existing submission: `guardNewSubmission` gates the three `.set()` calls in `lib/registration/registration_service.dart`. Note the result in the commit body.
- [ ] **Step 7: Commit** `fix(rules): a fan can never change Paid, PaidVia or PaidAmount on their own existing submission`

### Task 3: Manager model and labels learn "No charge"

**Files (Manager repo):**
- Modify: `lib/models/registration_models.dart`. Add `kPaidViaNoCharge` next to `RegSubmission`, and fix the stale `paidVia` comment at line 467.
- Modify: `lib/ui/registrations/widgets/submission_answers_sheet.dart`:
  - `paidViaLabel`, `paidViaTag`, and new status helpers
  - the Payment section (lines ~57-200): when `sub.isNoCharge`, hide the "Amount" tile and show Method `No charge — not charged`
- Modify: `lib/ui/registrations/registration_submissions_page.dart:344-353`. Use the new status text and color.
- Test: `test/paid_status_labels_test.dart` (new)

**Interfaces:**
- Produces:
  - `const String kPaidViaNoCharge = 'no charge';`
  - `bool get isNoCharge => paid && paidVia.trim().toLowerCase() == kPaidViaNoCharge;` (on `RegSubmission`)
  - `String paymentStatusText(RegSubmission sub)`: returns `'No charge'`, or `'Paid'` + `paidViaTag(sub)`, or `'Not paid'`.
  - `Color paymentStatusColor(BuildContext context, RegSubmission sub)` with these colors:

    | Status | Color |
    |---|---|
    | No charge, light mode | `Colors.blueGrey.shade700` |
    | No charge, dark mode | `Colors.blueGrey.shade200` |
    | Paid | `Colors.green` (as today) |
    | Not paid | `Colors.orange` (as today) |

- [ ] **Step 1: Write the failing tests:**
  - `paymentStatusText(paid no charge)` → `'No charge'`
  - `paymentStatusText(paid venmo)` → `'Paid · venmo'`
  - `paymentStatusText(unpaid with kept PaidVia 'no charge')` → `'Not paid'`
  - `paidViaLabel(paid no charge)` → `'No charge — not charged'`
  - `isNoCharge` is false when `paid` is false
  - A widget test pumps the color helper in light and dark themes and gets the two blueGrey shades.
- [ ] **Step 2:** Run `flutter test test/paid_status_labels_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement. The submissions row trailing `Text` uses `paymentStatusText` and `paymentStatusColor`. The answers sheet's status line also uses them. When `isNoCharge`, the Payment section shows only the Method line and "Edit payment". The "Last recorded payment" line for an unpaid submission with a kept `no charge` record reads `No charge — not charged`.
- [ ] **Step 4:** Run `flutter test` (whole Manager suite). Expected: all pass (baseline 2825).
- [ ] **Step 5 (Review Focus 3):** Run `grep -rn "\.paid\b\|'Paid'" lib`. Confirm no code removes a player from a team or `Line Ups` when Paid turns false. Only the season builder's `paidOnly` filter reads it, and only at build time. Write the finding in the commit body.
- [ ] **Step 6: Commit** `feat(registrations): "No charge" shows as its own status in the submissions list and payment details`

### Task 4: Manager payment dialog gets the "No charge" choice

**Files (Manager repo):**
- Modify: `lib/ui/registrations/widgets/submission_answers_sheet.dart:376-470`:
  - Replace `_paymentMethods` and `_promptPaymentDetails`.
  - Keep `promptAndSetPaid`'s signature and its `setPaymentDetails(paid: true, paidVia: method, paidAmount: amount)` call.
- Create: `lib/ui/registrations/widgets/payment_details_dialog.dart`
- Test: `test/payment_details_dialog_test.dart` (new)

**Interfaces:**
- Consumes: `kPaidViaNoCharge` (Task 3).
- Produces:
  - `class PaymentDetailsDialog extends StatefulWidget`, with constructor `PaymentDetailsDialog({required String initialMethod, required num initialAmount})`.
  - It pops a `(String, num)?`.
  - It owns its `TextEditingController` and disposes it in `dispose()`. This replaces today's `StatefulBuilder` + undisposed controller, which breaks the standing dialog rule.

- [ ] **Step 1: Write the failing widget tests:**
  - Chips read Venmo, Zelle, Cash, Other, No charge, in that order.
  - Tapping No charge sets the amount field to `0`, disables it, and shows `Not charged. Does not count as an Insiders referral.`. Confirm pops `('no charge', 0)`.
  - Tapping No charge and then Venmo restores the seeded amount (e.g. `255`) and enables the field.
  - Opened with `initialMethod: 'no charge'` (Review Focus 2) → No charge is selected and the field shows `0`.
  - Venmo with amount `0` shows `Amount is $0. Pick No charge if this player is not paying.`, and Confirm still pops `('venmo', 0)` (a hint, not a block).
  - Opened with `initialMethod: 'card'` → "Restore card payment" pops `('card', initialAmount)` as today, and the No charge chip is also offered.
  - A non-number amount on a paid method → Confirm does nothing (as today).
- [ ] **Step 2:** Run `flutter test test/payment_details_dialog_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement the dialog. Keep the "Restore card payment" behavior and its copy exactly as today. `_promptPaymentDetails` becomes a `showDialog<(String, num)>(builder: (_) => PaymentDetailsDialog(...))`.
- [ ] **Step 4:** Run `flutter test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(registrations): "No charge" in the payment dialog; the dialog owns its amount field`

### Task 5: Fan app shows "No charge"

**Files (fan repo):**
- Modify: `lib/registration/registration_models.dart`:
  - Add `kPaidViaNoCharge` and `RegSubmission.isNoCharge` (twins of Task 3).
  - Fix the `paidVia` comment at line 439.
  - `RegistrationChipKind` gains `noCharge`.
  - `registrationChipFor` (lines 895-940) gains the No charge rule.
- Modify: `lib/registration/registration_chip.dart`. `noCharge` uses the settled styling.
- Modify: `lib/registration/registration_status_page.dart:~500`. Add the No charge card, shaped like the existing "covered" card.
- Test: `test/registration_chip_decision_test.dart`, `test/my_registrations_test.dart`, `test/drawer_registration_row_test.dart`

**Interfaces:**
- Produces: `registrationChipFor` returns `(kind: RegistrationChipKind.noCharge, label: 'No charge', owed: 0, settled: true)` in two cases:
  - (a) `submission.isNoCharge`
  - (b) not paid, and no fee applies to this submission: `paymentOwed(config, submission, codeWaivesPayment) == false` and not `paymentCovered`. This fixes the known gap where a free registration says "Payment pending".
  - The existing paid, covered and pending answers are unchanged.

- [ ] **Step 1: Write the failing tests** in `registration_chip_decision_test.dart`:
  - Paid, no charge, fee 255 → `noCharge`, `'No charge'`, owed 0, settled (Review Focus 4)
  - Paid venmo → `paid`, `'Paid'`
  - Paid team code → `'Paid via team code'`
  - Unpaid individual, fee 0 → `noCharge`
  - Unpaid individual, `paymentMode: 'teamFee'` → `noCharge`
  - Unpaid individual, fee 255 → `pending`, owed 255
  - Comped to $0 → `covered` (unchanged)
  - Unpaid with a kept `PaidVia: 'no charge'` and fee 255 → `pending`, owed 255 (Review Focus 2)

  In `my_registrations_test.dart`: a No charge registration is never the `firstCurrentOwing`, so there is no home banner. In `drawer_registration_row_test.dart`: a lone No charge registration gives "All paid up".
- [ ] **Step 2:** Run `flutter test test/registration_chip_decision_test.dart test/my_registrations_test.dart test/drawer_registration_row_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement. On the status page, `noCharge` shows a card with `Icons.check_circle` (green) and the title `No charge — nothing to pay`. It shows no pay button, because `owes` is already false. The team member list keeps `member.paid ? 'Paid' : 'Not paid'` (privacy constraint).
- [ ] **Step 4:** Run `flutter test`. Expected: all pass (baseline 3428).
- [ ] **Step 5: Commit** `feat(registration): the player sees "No charge" and is never asked to pay; free sign-ups say "No charge" instead of "Payment pending"`

### Task 6 (Part B, owner approved 2026-11-14): free sign-ups start out "No charge"

**Files (fan repo, functions):**
- Create: `functions/src/lib/no_charge.ts`
- Create: `functions/src/no_charge_watch.ts`
- Modify: `functions/src/index.ts` (export)
- Modify: `functions/src/createRegistrationPaymentIntent.ts`. Export `parseConfig`, `parseSubmission` and `parseTeam`; do not copy them.
- Test: `functions/test/no_charge.test.ts`

**Interfaces:**
- Consumes: `owedCents`, `legacyTarget` from `src/lib/stripe_pay.ts`, and `NO_CHARGE` from Task 1.
- Produces:
  - `export function shouldStampNoCharge(config: RegistrationConfigLike, sub: SubmissionLike, team?: TeamLike): boolean`. True only when all three hold:
    - `!sub.paid`
    - `owedCents(config, sub, team) === 0`
    - not (`sub.path === 'joiner' && team?.codeWaivesPayment`)
  - `export const onSubmissionCreatedStampNoCharge = onValueCreated('/Registrations/{regId}/Submissions/{uid}', …)`.
    - It re-reads the submission.
    - If `shouldStampNoCharge`, it does one root multi-path update:
      - `Registrations/<reg>/Submissions/<uid>/{Paid: true, PaidVia: 'no charge', PaidAmount: 0}`
      - `Sign Ups/<league>/<season>/NotPaid/<uid>: null`
      - `Sign Ups/<league>/<season>/Paid/<uid>: <DisplayName>`
  - `export const onLegacyNotPaidCreated = onValueCreated('/Sign Ups/{league}/{season}/NotPaid/{uid}', …)`. It removes that NotPaid entry when `Sign Ups/{league}/{season}/Paid/{uid}` exists.
    - **Why:** the fan app writes the submission and then, as a second write, its legacy `NotPaid` entry (`registration_service.dart:460-466`). A warm function can stamp between the two writes and leave the person in both buckets.
    - Both buckets at once is never a legitimate state, because the Manager's `_setPaid` always moves the entry.

- [ ] **Step 1: Write the failing tests:**
  - Fee 0 individual → true
  - `paymentMode 'teamFee'` individual → true
  - Captain under `'perPlayer'` → true
  - Fee 255 individual → false
  - Already paid → false
  - Joiner on a waiving team → false
  - Joiner with no team → false (`owedCents` fails closed)
  - With an in-memory fake Reference (style of `src/merge_notice_watch.test.ts`):
    - A NotPaid entry created while the Paid entry exists → the NotPaid entry is removed.
    - A NotPaid entry with no Paid entry → untouched.
- [ ] **Step 2:** Run `npx vitest run test/no_charge.test.ts`. Expected: FAIL.
- [ ] **Step 3:** Implement. The stamp gives no referral credit, because Task 1's `creditChange` sees `'no charge'`. A fee changed later does not re-stamp anyone; an owner who wants a stamped player to pay marks them Not paid.
- [ ] **Step 4:** Run `npm test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(registration): sign-ups that owe nothing start out "No charge"`

---

## Rollout (each step needs the owner's go)

1. **Deploy the functions first.** Without Task 1 live, switching a credited player to No charge would keep the credit.

   ```
   "$APPDATA/npm/firebase" deploy --only functions:onSubmissionPaidChange --project infinite-sports-app --non-interactive
   ```

   Include Part B: add `,functions:onSubmissionCreatedStampNoCharge,functions:onLegacyNotPaidCreated`.
2. **Deploy the rules** (Task 2) from `database.rules.stage1.json`. Probe on the emulator first.
3. **Manager.** Install on the emulator for the owner to try first. It goes on his tablet only after he has tried it.
4. **Fan app.** It rides the next store release with Bronsin. iPhone simulator checks:
   - a No charge registration shows "No charge" with no pay button
   - a free sign-up shows "No charge"
5. **The owner edits the 10 himself:**
   - **Won't pay:** "Edit payment" → No charge.
   - **Will pay:** switch to Not paid. They keep their team spot and see "You owe $255".

## Build rulings (2026-11-14, during execution)

- **Task 6 race fix.** The Manager moves a legacy entry with two writes (`SignUpService.moveToNotPaid`: set NotPaid, then remove Paid), so both buckets briefly exist on every unmark. `onLegacyNotPaidCreated` therefore waits a short settle delay (5 s), re-reads, and removes NotPaid only if the Paid entry still exists.
- **Task 7 (Manager, added).** `moveToPaid` / `moveToNotPaid` become one atomic multi-path update each, so the new Manager never shows both entries.
- **Rollout.** Prefer deploying the two Part B functions after the new Manager is on the owner's tablet. With the settle delay it is safe either way.

## Not in this plan

- No partial-payment status ("paid $50 of $255"). Owner decision 4.
- The legacy roster-from-signups picker (`lib/ui/shared/signup_picker_sheet.dart`) still says "Paid" for a No charge player. It reads the legacy `Sign Ups` buckets, which carry no method.
- The other payment-safety rules items (self-stamped discounts, signed-out reads of `Users`) stay in their own plan.

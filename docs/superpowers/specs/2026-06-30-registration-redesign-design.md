# Registration Redesign (Leagues Epic L1) — Design Spec

**Date:** 2026-06-30
**Status:** Approved by owner (single flexible engine; individual + team-code + new-team paths; template+tweak forms; hybrid payments Option C in two phases; admin-approved teams gate code issuance; per-competition payment mode).
**Apps:** BOTH — fan (`infinite_sports_flutter`) renders forms + registers + pays; Manager (`InfiniteSportsManagerFlutter`) builds forms, opens/closes registrations, approves teams, tracks payment.
**Branches:** `zaya-registration` in each repo (off `zaya-features`). Commits local until owner says to push.
**Epic:** Leagues parity — sub-project **L1** of 6 (registration is foundational: feeds rosters L2, teams, and payments).

---

## 1. Overview

Replace the hardcoded, two-repo-drift sign-up system with **one data-driven registration engine** usable by ANY competition — a league season (Futsal/Basketball/Flag Football) or a tournament, any sport. Admin builds/edits the form in the Manager (no code changes to add/remove questions), opens/closes registration with a switch (no more editing Firebase by hand), and players register through one flow with three paths: **individual**, **join a team with a code**, or **register a new team (captain)**. Payments are hybrid (Venmo/Zelle links now, Stripe auto-confirm next), with a re-openable payment screen and the existing Paid/Not-Paid admin flip preserved.

## 2. Form engine (data-driven)

A form is a stored list of question definitions rendered dynamically by the fan app.

**Question types:** shortText, paragraph, number, phone (masked `(408) 693-9436`), email, date (picker), dropdown, singleChoice, multiChoice, yesNo, linkAcknowledge (waiver/rules: tappable link that must be opened before submitting; checkbox reflects read state).

**Per-question settings:** `label`, `type`, `required` (bool), `visibility` (all | individual | captain | joiner), `options[]` (choice types), `hint`, `key` (stable id; well-known keys like `firstName`, `phone`, `position` map into `Users/{uid}` profile fields on submit).

**Input hygiene (applies engine-wide):**
- Names/text: capitalize first letter of each word (`TextCapitalization.words`), trim + collapse trailing spaces on submit.
- Phone: live input mask, stored normalized (digits) + displayed formatted.
- Email: format-validated. Number/date: proper keyboards/pickers. Required questions gate the submit button.

**Packages:** `flutter_form_builder` + `form_builder_validators` (field widgets + validation), `mask_text_input_formatter` (phone), `pin_code_fields` (join-code entry), `qr_flutter` (optional: captain's code as QR), reuse `share_plus`, `url_launcher`. `flutter_stripe` added only in L1c.

## 3. Data model (RTDB, additive)

```
Registrations/{regId}                      # regId e.g. "Futsal-17" | "T-{tournamentId}"
  Config: { TargetType: "league"|"tournament", Sport, Season?, TournamentId?,
            Status: "open"|"closed", Fee, FeeNote,
            PaymentMode: "perPlayer"|"teamFee",
            Methods: { venmo: bool, zelle: bool, stripe: bool }, CreatedAt }
  Form: [ {key, type, label, required, visibility, options?, hint?} ]   # ordered list
  Submissions/{uid}: { Path: "individual"|"joiner"|"captain", Answers: {key: value},
                       TeamId?, Paid: bool, PaidVia?, SubmittedAt }
  Teams/{teamId}: { Name, CaptainUid, Status: "pending"|"approved"|"rejected",
                    JoinCode?, CodeWaivesPayment: bool, CreatedAt }
FormTemplates/{id}: [ question list ]      # "default" + optional per-sport templates
```

**Legacy compatibility (critical):** every submission ALSO dual-writes the existing `Sign Ups/{Sport}/{Season}/NotPaid/{uid} = displayName`, and Mark-Paid keeps moving entries NotPaid↔Paid via the existing `SignUpService`. This keeps the Manager Sign Ups page and the just-shipped **"Add from sign-ups" roster builder working unchanged**. Tournament-target registrations dual-write under `Sign Ups/{TournamentName}/...` equivalently for the picker's future use. The fan drawer's "sign-ups open" state now derives from any open registration (fallback: the legacy `Sign Ups/Sign Up Status` int remains readable but no longer requires console edits).

## 4. Manager: Registration Hub

New section (route `/registrations`, nav entry alongside Sign Ups):
- **List** of registrations (open/closed chips) + "Open registration" wizard: pick target competition → form starts from **template** ("copy last registration" alternative) → tweak questions (add/remove/edit/reorder via drag — `ReorderableListView`) → set Fee + FeeNote → toggle Methods (venmo/zelle/stripe) → pick PaymentMode (perPlayer | teamFee) → **Open**. A Status switch closes/reopens anytime.
- **Template editor:** maintain `FormTemplates/default` (and per-sport variants) with the same question editor.
- **Submissions view:** searchable list per registration — answers detail, Paid/Not-Paid flip (updates both new + legacy paths), path badge (individual/captain/joiner + team).
- **Team approvals:** pending teams queue. Approve → app **generates the join code** (6 chars, confusable-free alphabet, unique per registration, editable/regeneratable — reuses the tournament join-code pattern) and asks: **"Players joining with this code: skip payment (captain covers) or pay individually?"** → sets `CodeWaivesPayment`. Reject with optional note. Code is copyable for texting to the captain.

## 5. Fan: registration flow

Entry: drawer item (existing) + a banner on the Matches screen when any registration is open.
1. **Path question:** "How are you registering?" → Individual / I have a team code / Register a new team.
2. **Team code path:** code entry (pin boxes, auto-uppercase) → validated live against approved teams → shows "Joining {Team Name}". Invalid/pending-team codes → friendly error.
3. **Dynamic form** renders per template + path visibility; known fields pre-filled from `Users/{uid}` (name, phone, positions); answers write back to profile where keys map.
4. **Submit:** writes Submission (+ legacy dual-write). Captain path also writes the pending Team. Joiner path sets `TeamId` and, if `CodeWaivesPayment`, `Paid: true`, `PaidVia: "team code"` — payment skipped entirely.
5. **Payment screen** (when owed): enabled methods as buttons — **Venmo** deep-links to the app with amount + note ("{Competition} — {Player Name}") pre-filled (web fallback `venmo.com/infinite-sports`); **Zelle** shows the number 408-693-9436 + copy button + "confirm the recipient name shows {ZELLE_DISPLAY_NAME}" (owner to supply name before L1a ships); card button appears in L1c. Nothing auto-confirms in L1a — admin flips Paid.
6. **Re-openable:** until Paid, the player sees a persistent **"Complete payment"** button on the registration status screen + sign-up entry point; tapping reopens the payment screen. After approval, a captain's status screen shows **their team's join code** (+ share button, optional QR).

## 6. Payments (Option C, two phases)

- **L1a (this spec's build):** Venmo + Zelle as above; manual Paid flip; per-registration Fee/Methods/PaymentMode config; `teamFee` mode = captain owes the fee, joiners' payment governed by `CodeWaivesPayment`.
- **L1c (follow-on phase):** `flutter_stripe` Payment Sheet (card + Apple Pay + Google Pay) as another method button; Cloud Function creates the PaymentIntent; success webhook sets `Paid: true, PaidVia: "card"` + legacy move to Paid automatically. Stripe **secret key + webhook secret live only in Cloud Functions config** (owner sets them guided, never in chat/app); the publishable key ships in-app. Physical-services app → external payments permitted by Apple (no IAP).

## 7. Error / edge cases

- Register twice for the same registration → blocked ("already registered", shows status instead).
- Code for a pending/rejected team → clear error ("team awaiting approval — ask your captain").
- Closing a registration hides the form but keeps submissions/payment status intact and payable.
- Captain's team rejected → captain notified on status screen; submission stays (admin may move them individual).
- Malformed/legacy data reads → guarded, friendly empty states (no crashes).
- Duplicate team names within a registration → warned at approval.
- Join-code collision → generation retries; manual edits validated unique per registration.

## 8. Testing

- **Unit (pure):** question-model (de)serialization; visibility filtering per path; input formatters (phone mask, capitalization, trailing-space collapse); code generation (alphabet, uniqueness, length); payment-owed logic (perPlayer vs teamFee × CodeWaivesPayment); legacy dual-write mapping.
- **Widget:** dynamic form renders each question type; required gating; path branching; payment screen shows only enabled methods.
- **Manual (owner, on-device):** open a Futsal registration from template → register individually on the fan app → payment screen → Venmo/Zelle links work → re-open payment → Mark Paid in Manager → appears in Add-from-signups picker. Captain registers team → approve + code (waive payment) → joiner registers with code → lands on team, skips payment.

## 9. Build phases

- **L1a:** engine + templates + Registration Hub + individual path + payment screen (Venmo/Zelle) + legacy dual-write. Ship to phone.
- **L1b:** team paths — captain registration, approval queue, code issue (+waive rule), joiner flow, captain code display/share. Ship.
- **L1c:** Stripe auto-confirm. Ship.
Each phase: tests + analyze + build/install + owner test before the next.

## 10. Out of scope (later sub-projects)

- Materializing an approved team + its members into a season lineup / tournament roster in one tap (**L2** — the data here is shaped for it).
- Removing players from league rosters, team CRUD parity (**L2**); schedule/playoffs (**L3**); fan live league screens (**L4/L5**); per-sport stats/trophies (**L6**).
- Firebase Crashlytics adoption (app-wide, separate small task).
- Old `leagueform.dart`/`signup.dart` removal happens in L1a's wiring (replaced by the new flow), but AFC-style external "Form URL" web sign-ups remain supported as-is.

## 11. Review checklist (Paul + Bronsin)

Fan: new `registration/` module (dynamic form renderer, path flow, payment screen), drawer/banner wiring, profile pre-fill, dual-writes to legacy Sign Ups. Manager: new `registrations/` UI (hub, wizard, template editor, submissions, team approvals), services for registration CRUD + code issuance reusing the tournament join-code pattern. Additive RTDB schema (`Registrations/*`, `FormTemplates/*`) + legacy dual-write keeps every existing consumer working. Pure helpers unit-tested; no schema removal; both repos on `zaya-registration`.

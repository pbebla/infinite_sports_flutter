# Infinite Fantasy — paid access (season pass) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Three independent tracks (A functions+rules+hosting, B fan app, C Manager app) run in parallel from the shapes pinned in the spec `docs/superpowers/specs/2026-11-01-fantasy-paid-access-design.md`. Steps use `- [ ]` checkboxes. Commit per task with an explicit path list (other agents commit to the same fan checkout).

**Goal:** per-season Free / Season-pass gate for Infinite Fantasy with outside-the-app payments (Stripe Checkout link, Venmo, Zelle), automatic card activation, owner-approved Venmo/Zelle claims, silent owner grants, pushes + emails with editable templates, refund auto-revoke, revenue tile.

**Architecture:** `Config/Access` (mode/price/methods/copy) + `Access/<uid>` (server/admin-written status) + `AccessClaims/<uid>/<key>` (fan-written "I sent it"). Rules gate `Squads/$uid` and `Managers/$uid` on `Mode !== 'pass' || Access/$uid/Status === 'active'`. Functions: one callable (Checkout link), one admin test callable, three triggers, the webhook extended. Fan hub swaps the "Name your team" step for a pay card. Manager gets an "Access & payments" page.

**Tech:** TS functions (v2, vitest, `stripe@18`), RTDB rules (both files), Firebase Hosting (two static pages), Flutter fan (plain streams, `url_launcher`, `cloud_functions`), Flutter Manager (Riverpod, no `.get()`).

**Node paths (all under `Fantasy/<sport>/<season>/` unless noted):**
- `Config/Access` = `{Mode:'free'|'pass', AmountDollars:number, Methods:{Venmo,Zelle,Card}, RegisteredPlayersFree:bool, Copy:{Headline,Body,Button}, ChangedAt, ChangedBy}`
- `Access/<uid>` = `{Status:'active'|'pending'|'revoked', Via:'card'|'venmo'|'zelle'|'granted'|'player'|'grandfathered', AmountCents, PaidAt, By, Reason?, StripePaymentIntent?, RefundedAt?, RevokedBy?, RevokeReason?, Notified:{<key>:true}}`
- `AccessClaims/<uid>/<pushKey>` = `{Method:'venmo'|'zelle', AmountDollars, Note, At, Resolved?:'approved'|'rejected'|'superseded', ResolvedAt?, ResolvedBy?, Reason?, Notified?:true}`
- root `Fantasy/Templates/Access/<key>` = `{PushTitle, PushBody, EmailSubject, EmailBody}` for keys `claimReceived | claimAdmin | activatedPaid | activatedGranted | revoked`; plus `Fantasy/Templates/Access/AdminEmail` (string).
- Push data: `{type:'fantasyAccess', sport, season}`; metadata kind: `{kind:'fantasyAccess', sport, season, uid}`.

---

## Track A — functions, rules, hosting (fan repo `functions/`, `database.rules*.json`, `public/`, `firebase.json`)

### A1. Pure access module `functions/src/lib/fantasy/access.ts` (+ `access.test.ts`)
- [ ] `accessConfigFrom(raw): AccessConfig` — defaults: free mode, 0 dollars, Methods Venmo+Card on / Zelle off, RegisteredPlayersFree false, Copy defaults (spec §9 `Copy`). Bad types → defaults. `isPassMode(cfg)`.
- [ ] `accessRecordFrom(raw): AccessRecord | null`, `isActive(rec)`.
- [ ] `TEMPLATE_DEFAULTS` (spec §9 table, verbatim) and `templateFrom(key, raw)` — blank/absent field → default; `fillTemplate(text, vars)` replaces `{name} {teamName} {amount} {season} {method} {date} {reason}`; unknown placeholders untouched. `formatAmount(cents) → "$10.00"`, `seasonLabel(sport, season) → "Futsal Season 16"`, `methodLabel(via)` → "card" / "Venmo" / "Zelle".
- [ ] `activationFor(via, amountCents, nowMs, by, extra?)` → the Access node to write; `pendingFor(claim, nowMs)`; `revokedPatch(nowMs, by, reason?)`.
- [ ] `notifyKeyFor(status, record)` → `active_<PaidAt>` / `revoked_<RefundedAt>`.
- [ ] `checkoutLineItem(cfg, sport, season)` → `{name:"Infinite Fantasy — Futsal Season 16 season pass", unit_amount: cents, currency:'usd'}`; `checkoutUrls(hostingBase)`.
- [ ] Tests: every default, fill with missing vars, amount formatting (1050 → $10.50), isActive truth table, keys.

### A2. Metadata kind + webhook routing (`lib/stripe_pay.ts`, `stripeWebhook.ts`, tests)
- [ ] `WebhookMeta` becomes a union: `RegistrationMeta {kind?:'registration', regId, uid, league, season}` | `FantasyAccessMeta {kind:'fantasyAccess', sport, season, uid}`. `parseWebhookMetadata` returns the registration shape for metadata WITHOUT `kind` (byte-identical behaviour, existing tests untouched) and the fantasy shape when `kind === 'fantasyAccess'` with all three strings non-empty; anything else null. `webhookMetadata()` unchanged; add `fantasyAccessMetadata({sport, season, uid})`.
- [ ] `stripeWebhook`: on `payment_intent.succeeded` route by kind: registration → existing `markPaid`; fantasy → `activateFantasyAccess(meta, amountReceivedCents, intent.id)` = RTDB transaction on `Access/<uid>`: current active → return unchanged (log info "already active, replay"); else write `activationFor('card', cents, now, 'stripe', {StripePaymentIntent})` keeping an existing `Notified` map. After the transaction, mark every unresolved `AccessClaims/<uid>/*` as `Resolved:'superseded'`.
- [ ] `charge.refunded`: `charge.metadata` has the fantasy kind and `charge.refunded === true` → transaction: Status 'revoked', `RefundedAt now`, `RevokedBy 'stripe'`; not active → log and 200. Registration-kind refunds → log only (unchanged behaviour). Other events → 'ignored' as today.
- [ ] Tests (`stripeWebhook.test.ts` style with the fake db): registration event path identical; fantasy activation; replay idempotent (one write); refund revokes; partial refund (`refunded:false`) logs only; malformed fantasy metadata → 200 ignored.

### A3. Callables `functions/src/fantasy_access.ts`: `createFantasyCheckoutSession`, `sendFantasyAccessTest`
- [ ] `createFantasyCheckoutSession` (onCall, secrets `STRIPE_SECRET_KEY`): auth required (`unauthenticated`); args `{sport, season}` strings (`invalid-argument`); read `Config/Access` + `Access/<uid>` with `once()`-style admin reads; not pass mode / Card off / amount ≤ 0 → `failed-precondition` with a plain message; active → `{alreadyActive:true}`; else `stripe.checkout.sessions.create({mode:'payment', line_items:[{price_data:{currency:'usd', unit_amount, product_data:{name}}, quantity:1}], payment_intent_data:{metadata: fantasyAccessMetadata(...)}, customer_email: request.auth.token.email ?? undefined, success_url, cancel_url})` → `{url: session.url}`. Hosting base = `https://infinite-sports-app.web.app`. Inject the Stripe client through a seam (like `stripe_pay`) so tests assert the create() args.
- [ ] `sendFantasyAccessTest` (onCall, admin-gated the same way as `getUserContact`): `{sport, season, template}` → fills the template with sample vars (name = caller's display name or "Zaya", amount from Config, season label, method "Venmo", today) → push to the caller uid + email to the caller's auth email via `sendSupportMail`. Returns `{pushed:boolean, emailed:boolean}`.
- [ ] Tests: precondition matrix, args to `sessions.create`, alreadyActive, admin gate.

### A4. Triggers (`functions/src/fantasy_access.ts`, pure parts in `lib/fantasy/access.ts`)
- [ ] `onFantasyAccessClaimCreated` — `onValueCreated('/Fantasy/{sport}/{season}/AccessClaims/{uid}/{key}')`: claim parse (Method ∈ venmo|zelle else log+return); `Access/<uid>` transaction: active → leave; else `pendingFor(claim)` (keep `Notified`); once-only `Notified:true` on the claim (writeIfAbsent); then (a) push every `Admins` uid via the existing fantasy pusher with template `claimAdmin` (vars name/teamName/amount/method/season), (b) `sendSupportMail` to `AdminEmail` (default support inbox) with `claimAdmin` email, (c) `sendSupportMail` to the fan's auth email with `claimReceived`. Name = `Managers/<uid>/TeamName` → else `PublicProfiles/<uid>/Name` → else "a manager".
- [ ] `onFantasyAccessStatusWritten` — `onValueWritten('/Fantasy/{sport}/{season}/Access/{uid}/Status')`: after ∈ {'active','revoked'} and before ≠ after; read the record; key `notifyKeyFor`; writeIfAbsent `Access/<uid>/Notified/<key>`; 'active' → via ∈ card|venmo|zelle ? `activatedPaid` : `activatedGranted`; 'revoked' → `revoked`; push to uid (`type:'fantasyAccess'`) + email to the auth email (none → log info, push only).
- [ ] `onRegistrationPaidGrantFantasy` — `onValueWritten('/Registrations/{regId}/Submissions/{uid}/Paid')`: after === true only; read `Registrations/<regId>/Config` → `legacyTarget(config)` → `{league, season}`; read `Fantasy/<league>/<season>/Config/Access`; pass mode + `RegisteredPlayersFree` + not active → transaction write `activationFor('player', 0, now, 'system')`. Everything else → log info, no write.
- [ ] Export all five from `index.ts` (keep the existing export style). Add the new function names to the deploy list note in the plan's §Deploy.
- [ ] Tests (fake db seam like `orchestration_db`): claim → pending + 1 admin push per admin + 2 emails + once; active claim → no pending, still notifies admins? NO — active users can't claim from the app; a stray claim on an active record is logged and ignored (no mails). Status trigger: paid vs granted template, revoked, once per key, no email. Registration grant: toggle off / free mode / already active → nothing; happy path grants with Via player.

### A5. Rules (both files) + contract test + emulator probe
- [ ] `Fantasy/$sport/$season/Access`: `.read` admin; `$uid`: `.read` own-or-admin, `.write` admin only. `AccessClaims`: `.read`/`.write` admin; `$uid`: `.read` own-or-admin; `$key`: `.write` `auth.uid == $uid && !data.exists() && newData.exists()` (create-only), `.validate`: `newData.hasChildren(['Method','AmountDollars','At']) && Method matches /^(venmo|zelle)$/ && AmountDollars isNumber && >= 0 && At isNumber && (!newData.hasChild('Note') || Note isString && length <= 120)`. (Admins may also write Resolved fields through the admin `.write` above.)
- [ ] `Fantasy/Templates/Access`: `.read`/`.write` admin.
- [ ] Gate: append to `Squads/$uid` `.write` AND to `Managers/$uid` `.write`: `&& (root.child('Fantasy/' + $sport + '/' + $season + '/Config/Access/Mode').val() !== 'pass' || root.child('Fantasy/' + $sport + '/' + $season + '/Access/' + $uid + '/Status').val() === 'active')`. Keep every existing clause (the squad delete gate stays).
- [ ] `rules_contract.test.ts`: assert the gate text on both nodes, Access/AccessClaims/Templates grants, both files.
- [ ] Emulator probe (scratchpad `hardening/access_rules_check.js`, same harness as `squads_rules_check2.js`): free mode saves OK; pass mode without Access → Squads + Managers refused; pass + active → allowed; pass + pending → refused; fan creates a claim (OK), overwrites it (refused), writes another uid's claim (refused), writes Access (refused); admin writes Access (OK). Run both rules files; paste the summary into the report.

### A6. Hosting
- [ ] `firebase.json` add `"hosting": {"public": "public", "ignore": ["firebase.json", "**/.*", "**/node_modules/**"]}`; `public/fantasy/paid.html`, `public/fantasy/cancelled.html`, `public/index.html` (one-line redirect to infinitesports.org or a plain landing). Inline CSS only, light + dark via `prefers-color-scheme`, the Infinite Sports red `#D00000`, no scripts, mobile width.
- [ ] Deploy is the controller's step (`firebase deploy --only hosting`).

### A7. Verification + report
- [ ] `npm test` (all files), `npm run build`, rules probe output, `.superpowers/sdd/paid-access/report-functions.md` with every ruling + the exact deploy list: existing 14 + `createFantasyCheckoutSession, sendFantasyAccessTest, onFantasyAccessClaimCreated, onFantasyAccessStatusWritten, onRegistrationPaidGrantFantasy, stripeWebhook` + `database` + `hosting`.

---

## Track B — fan app (fan repo `lib/`, `test/`)

### B1. Data layer `lib/fantasy/data/fantasy_access.dart` (+ parsers in `fantasy_parsers.dart` style)
- [ ] `FantasyAccessConfig` (mode enum free|pass, amountDollars, venmo/zelle/card bools, copy headline/body/button with defaults) parsed from `Config/Access` — extend the existing Config stream's parser so the hub's `configState` carries `.access` (no second subscription).
- [ ] `FantasyAccessStatus` enum none|pending|active|revoked + `FantasyAccessRecord` parsed from `Access/<uid>` (tolerant). `FantasyService.watchMyAccess(sport, season)` — `onValue` on `Access/<uid>`, seeded by a session cache, error ≠ fact (an error keeps the last known value; first emission on error = none WITH a `degraded` flag so the card shows a retry line rather than the methods). Add the cache to `clearFantasySessionState()` (the scan test in `fantasy_session_test.dart` must pass).
- [ ] `FantasyService.submitAccessClaim(sport, season, method, amountDollars, note)` → `push()` under `AccessClaims/<uid>` with `At: ServerValue.timestamp`.
- [ ] `FantasyService.createCheckoutUrl(sport, season)` → `FirebaseFunctions.instance.httpsCallable('createFantasyCheckoutSession')` → `Uri?` (null when `alreadyActive`). Seam for tests.
- [ ] Tests: parsers (all defaults, bad types), claim shape, cache clear.

### B2. Pay card `lib/fantasy/hub/access_pay_card.dart`
- [ ] `AccessPayCard({config, status, record, displayName, onCard, onVenmo, onZelleSent, onClaimSent, onChangeMethod})` — states: `none` → headline/body/price + method buttons (Venmo blue like registration, card = primary, Zelle instructions card reusing `kZelleDisplayName`); after Venmo tap → "I sent it" row (+ amount shown) → `pending` → "Got it — Zaya will confirm your payment shortly; we'll let you know." + *Change payment method*; `revoked` → "Your access was removed. Pay again to keep playing." + methods; card tap → "Finish in your browser — this page updates by itself when Stripe confirms." + *Open again*; callable error → inline red line + retry. Theme-safe both modes, 360 px, keys `access_pay_card`, `access_pay_card_venmo`, `access_pay_card_card`, `access_pay_card_sent`, `access_pay_card_pending`.
- [ ] Venmo URI = the registration `_venmoUri` pattern (extract a shared `venmoPayUri(amount, note)` into `lib/registration/payment_links.dart` and use it from both screens — no copy). Note = `Fantasy <sport> S<season> <displayName>`.
- [ ] Nothing on the card mentions grants, free access, or admins.

### B3. Hub gate (`lib/fantasy/hub/fantasy_hub_page.dart`, `_HubBody`, My Team tab)
- [ ] `_HubBody` gets `access` + `accessStates`. Rule: `config.access.mode == pass && !access.isActive` → My Team shows the pay card where the name step is (manager == null) or ABOVE a read-only court (manager != null; builder locked, Save hidden, picker inert). Free mode → unchanged. Single fade reveal: the hub's `_ready` waits for the first Access emission too (seeded cache makes revisits instant).
- [ ] `url_launcher` external for the Checkout URL; on return (app resumed) nothing special — the stream flips the card.
- [ ] Push tap `type:'fantasyAccess'` → hub, My Team tab (extend the existing fantasy push routing in `lib/misc/pushnotifications.dart`).
- [ ] Tests (`fantasy_hub_page_test.dart`, `access_pay_card_test.dart`): free mode no card; pass+none → card, name step absent; pass+pending → pending copy; pass+active → normal name step; existing manager + revoked → card above read-only court; card tap calls the seam and launches the URL seam; I sent it writes the claim shape; light + dark + 360 px; session clear scan.

### B4. Verification
- [ ] `flutter test` (all), `flutter analyze lib/fantasy lib/registration lib/misc test/fantasy`, zero RTDB `.get()`, commit with explicit paths, report `.superpowers/sdd/paid-access/report-fan.md`.

---

## Track C — Manager app (`C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`, branch `zaya-fantasy`)

### C1. Paths + models + service
- [ ] `lib/core/constants/fantasy_paths.dart`: `accessConfig(sport, season)`, `access(sport, season)`, `accessOf(sport, season, uid)`, `accessClaims(...)`, `accessClaimsOf(...)`, `accessTemplates`, `accessTemplate(key)`, `accessAdminEmail`.
- [ ] `lib/fantasy/data/fantasy_access_admin.dart`: `AccessConfig`, `AccessRecord`, `AccessClaim`, `AccessTemplate` (+ the same defaults as the server, in one Dart constant map — document that functions/src/lib/fantasy/access.ts is the twin), `revenueSummary(records)` → `{activeByVia, pendingCount, grantedCount, paidCents}`.
- [ ] `lib/services/firebase/fantasy_access_service.dart` (Riverpod providers, `onValue` streams, `once()` never `.get()`): `watchConfig`, `watchAccess`, `watchClaims`, `watchTemplates`; `saveConfig(cfg, {grandfatherUids})` = one multi-path update (Config/Access + Access/<uid> grandfathered records); `approveClaim(uid, key)` / `rejectClaim(uid, key, reason)` = transaction on `Access/<uid>` + claim Resolved patch; `grant(uids, reason)` = multi-path update skipping active; `revoke(uid, reason)`; `saveTemplate(key, t)`, `resetTemplate(key)` (delete node), `saveAdminEmail`; `sendTest(sport, season, key)` → callable `sendFantasyAccessTest`.
- [ ] Tests: multi-path shapes (grandfather, grant skips active), transaction functions (approve on active = no-op), revenue math.

### C2. Page `lib/ui/fantasy/fantasy_access_page.dart` (+ `access/` widgets)
- [ ] Section tile in `fantasy_section_page.dart`: "Access & payments" / "Free or season pass, pending payments, grants" with a live pending-claims badge.
- [ ] Mode card (segmented Free | Season pass, price field validated > 0 in pass mode, method switches, Registered-players-free switch, Save). Free → Pass opens `GrandfatherDialog` ("N managers already play this season" + checked *Keep their access*). Pass → Free confirm dialog. Save guard pattern (`save_guard.dart`) like the other fantasy pages.
- [ ] Pending claims list (live; name = TeamName → real name via `publicProfiles`; method, amount, time ago, note) with Approve / Reject (reason sheet; dialogs with text fields are StatefulWidgets owning their controllers).
- [ ] Managers & access list: union of Managers uids and Access uids; status chip; search; tap → `fantasy_profile_detail_page.dart`, which gains **Grant access** / **Revoke access** buttons + reason field (admin-only wording OK here).
- [ ] Grant sheet: *Pick users* (reuse the search-gated picker from `assign_trophy_page.dart`), *A team's roster* (sport → season → team from `Line Ups`; linked UIDs via `FirebasePaths.lineUps`/player `UID`; unlinked names listed under "Not linked — link them in Trophies → Awards by competition"), *All registered players this season* (paid submissions of the registration whose Config League/Season match the fantasy sport/season — reuse `registration_service`). Preview "Grant to N (M already active)" → Confirm.
- [ ] Messages editor: one expandable per template key with push title/body + email subject/body fields, placeholder legend, Reset to default, Send me a test (snackbar with the callable result); paywall Copy fields; AdminEmail field.
- [ ] `fantasy_analytics_page.dart`: Revenue tile (active by via, pending, granted, `$` total).
- [ ] Light + dark; tablet widths; error ≠ fact (`hasError && !hasValue`) states on every stream.
- [ ] Tests: page renders each section from fake providers; mode save shapes; grandfather dialog; approve/reject; grant sheet preview math incl. unlinked split; template reset; revenue tile; no `.get()` (guard test).

### C3. Verification
- [ ] `flutter test`, `flutter analyze lib/ui/fantasy lib/services/firebase lib/fantasy`, commit on `zaya-fantasy`, report `.superpowers/sdd/paid-access/report-manager.md` (in the Manager repo).

---

## Deploy / install (controller)
1. Track A: `npm test`, `npm run build`, probe → `firebase deploy --only "functions:<14 existing>,functions:createFantasyCheckoutSession,functions:sendFantasyAccessTest,functions:onFantasyAccessClaimCreated,functions:onFantasyAccessStatusWritten,functions:onRegistrationPaidGrantFantasy,functions:stripeWebhook,database,hosting"`.
2. Verify live rules ≡ stage1 file (REST), hosting pages reachable, logs clean.
3. Fan APK → emulator-5554; Manager APK → tablet 10.0.0.146:5555 (USB re-arm if refused).
4. Owner: Stripe dashboard `charge.refunded` event; set S16 Access when ready. Memory update.

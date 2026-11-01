# Infinite Fantasy — paid access (season pass) — design

Owner decisions 2026-11-01: payment happens OUTSIDE the app (no store cut),
one-time season pass only (no monthly), unpaid users browse everything but
cannot play, flipping Free → Pass grandfathers existing managers, owner can
quietly grant access to any user / a team's roster / every registered player,
receipts + emails + refund auto-revoke + revenue tile + editable templates.

## 1. Goal

Per fantasy season the owner picks **Free** or **Season pass ($X)**. In pass
mode a fan can browse the whole hub (players, leaderboards, news, Team of the
week, rules) but cannot name a team, build a squad, transfer or play chips
until the owner has recorded them as paid. Paying by **card** activates them
automatically within seconds; paying by **Venmo/Zelle** puts them in
*pending* until the owner taps Approve; the owner can also **grant** access
for free, silently. Every step pushes and emails the right person with copy
the owner can edit.

## 2. Store policy (D1) — why nothing is bought inside the app

Apple/Google only take a cut of purchases made THROUGH the app (in-app
purchase). The fantasy fee is a digital feature, so an in-app card sheet
invites Apple to demand in-app purchase (30%). Under the 2025 US court orders
(Epic v. Apple injunction, April 2025; Epic v. Google, effective October
2025) an app on the US storefront may send the user to an outside web page
to pay, and Apple takes nothing on those. Infinite Sports is US-only.

So in pass mode the fan app offers only outside payments:

- **Card** → the app asks the server for a Stripe Checkout link and opens it
  in the phone's browser (Safari/Chrome, `url_launcher` external). Stripe's
  hosted page takes the card / Apple Pay / Google Pay; the existing
  `stripeWebhook` activates access; the app updates live. Stripe's own
  processing fee (2.9% + 30¢) still applies — that is a payment fee, not a
  store cut.
- **Venmo** → the existing deep link (`venmo.com/infinite-sports`, amount +
  note pre-filled) then an "I sent it" button.
- **Zelle** → the existing instructions card (switchable, default off).

The fee's name/wording is the owner's (templates §9); nothing in the app
calls it an in-app purchase. Nothing needed from the owner for this: the
Checkout link reuses the live Stripe keys and the existing webhook endpoint
(the link's PaymentIntent carries our metadata, so the current
`payment_intent.succeeded` subscription covers it). Refund auto-revoke (§7)
needs one dashboard click, listed in §12.

## 3. Modes and money (D2)

`Fantasy/<sport>/<season>/Config/Access`:

```
Mode: 'free' | 'pass'            absent = free (today's behaviour)
AmountDollars: 10                whole dollars or .50 allowed; > 0 in pass mode
Methods: { Venmo: true, Zelle: false, Card: true }
RegisteredPlayersFree: false     §8 auto-grant on registration Paid flip
Copy: { Headline, Body, Button } fan-visible paywall text (§9 defaults)
ChangedAt, ChangedBy
```

One season pass = access for that season. No renewals, no expiry. A new
season has its own Access block (Manager pre-fills it from the previous
season when creating the Config).

## 4. Access record (server/admin-written)

`Fantasy/<sport>/<season>/Access/<uid>`:

```
Status: 'active' | 'pending' | 'revoked'
Via: 'card' | 'venmo' | 'zelle' | 'granted' | 'player' | 'grandfathered'
AmountCents: 1000 (0 for granted/player/grandfathered)
PaidAt: ms                      the activation instant (also the receipt date)
By: 'stripe' | 'system' | <admin uid>
Reason: text                    admin-only (grant reason); never sent to the fan
StripePaymentIntent: pi_…       card only
RefundedAt, RevokedBy, RevokeReason   when Status 'revoked'
Notified/<key>: true            once-only claims for pushes/emails (§7)
```

`Status 'pending'` is written by the claim trigger (§6) and means "Venmo/Zelle
claim open". Approve → 'active'; Reject → the record is deleted (the fan is
back at the pay card) and the claim keeps `Resolved:'rejected'`.

Rules: `Access/<uid>` read = own uid or admin; write = admin only (the
server's Admin SDK bypasses rules). `Access` whole-node read = admin.

## 5. Gate (D3, D4)

- **Fan hub, pass mode, no active Access:** every tab works as today EXCEPT
  My Team, which shows the **pay card** (§6) in place of the "Name your team"
  step. An existing manager without active Access (not grandfathered, or
  revoked) sees the pay card above a read-only court (saves refused by rules
  anyway). Free mode: nothing changes.
- **Server-enforced:** `Squads/$uid` and `Managers/$uid` client writes also
  require `Config/Access/Mode !== 'pass' || Access/$uid/Status === 'active'`
  (added to the existing `.write` expressions; both rules files;
  `rules_contract.test.ts` pins it). Admin SDK writes are unaffected.
- **Flipping Free → Pass** in the Manager: the dialog shows "N managers
  already play this season" with a checked box *Keep their access*. Checked
  = the Manager writes `Access/<uid> {Status active, Via grandfathered,
  AmountCents 0, By <admin>, PaidAt now}` for every current `Managers` uid
  in the same multi-path update as the Config change. Unchecked = they all
  see the pay card next open. Flipping Pass → Free leaves Access records in
  place (they are history/receipts) and the gate simply stops applying.
- The fan app never shows or mentions grants, grandfathering or the
  Registered-players-free rule (owner: fans would ask). A granted fan just
  sees "You're in" (§9 `activatedGranted`).

## 6. Pay card and claims (fan)

Pay card (My Team tab) = headline, body, price line, then the enabled
methods:

1. **Pay by card** → callable `createFantasyCheckoutSession({sport, season})`
   → returns `{url}` → `launchUrl(mode: externalApplication)`. The card shows
   "Finish in your browser — this page updates by itself when Stripe
   confirms" until Access turns active (live stream). If the callable fails:
   friendly error + retry. Already active (race): the callable returns
   `{alreadyActive: true}` and the card dismisses.
2. **Pay with Venmo** → existing deep link with amount + note
   `Fantasy <sport> S<season> <display name>` → the button row then shows
   **I sent it** → writes `AccessClaims/<uid>/<pushKey>
   {Method:'venmo', AmountDollars, Note, At: ServerValue.timestamp}` → the
   card flips to **Pending**: "Got it — Zaya will confirm your payment
   shortly; we'll let you know." with *Change payment method* (opens the
   methods again; a second claim replaces the pending one for the admin).
3. **Zelle** (if on) → the existing instructions card + the same I sent it.

Rules: `AccessClaims/<uid>/$key` create-only by the owner uid, `.validate`
Method ∈ {venmo, zelle}, AmountDollars number ≥ 0, At number, Note string ≤
120; admin read/write all (Resolve). `AccessClaims/<uid>` read = own or admin.

States the card renders (all live): `none` (methods), `pending` (waiting),
`revoked` ("Your access was removed. Pay again to keep playing." + methods),
`active` → the card is gone and the normal Name-your-team / court shows.

Session caches: `FantasyService` caches Access + Config as today's nodes do;
`clearFantasySessionState()` clears them (the scan test enforces it).

## 7. Server (functions)

`functions/src/fantasy_access.ts` (exports) + pure `lib/fantasy/access.ts`:

- **`createFantasyCheckoutSession`** (callable, auth required): reads
  `Config/Access` (pass mode, Card on, amount > 0 else `failed-precondition`),
  `Access/<uid>` (active → `{alreadyActive:true}`), creates a Stripe Checkout
  Session: `mode:'payment'`, one line item "Infinite Fantasy — <Sport> Season
  <N> season pass" at the SERVER's amount, `payment_intent_data.metadata =
  {kind:'fantasyAccess', sport, season, uid}`, `customer_email` from the
  auth token when present, `success_url`/`cancel_url` = the hosting pages
  (§10). Returns `{url}`. Secrets: the existing `STRIPE_SECRET_KEY`.
- **`stripeWebhook`** (existing): `parseWebhookMetadata` keeps today's
  registration shape and additionally recognises `{kind:'fantasyAccess',
  sport, season, uid}` (a `kind` absent = registration, unchanged). On
  `payment_intent.succeeded` with the fantasy kind → `activateFantasyAccess`:
  transaction on `Access/<uid>`: if already active → no-op (idempotent
  replay); else write `{Status active, Via card, AmountCents, PaidAt now,
  By 'stripe', StripePaymentIntent}` and mark any open claim
  `Resolved:'superseded'`. New: on **`charge.refunded`** with the fantasy
  kind in `charge.metadata` and `refunded === true` (full refund) → Status
  'revoked', `RefundedAt`, `RevokedBy 'stripe'`. Partial refunds only log.
- **`onFantasyAccessClaimCreated`** (`AccessClaims/{sport}/{season}/{uid}/{key}`
  created): writes `Access/<uid> {Status pending, Via <method>, AmountCents,
  By 'system', PaidAt null}` unless already active; pushes every `Admins` uid
  (fan-app tokens, `type:'fantasyAccess'`, body from template `claimAdmin`),
  emails the admin address (template `claimAdminEmail`), emails the fan
  (`claimReceived`) via `sendSupportMail`. Once-only: `Notified` on the claim.
- **`onFantasyAccessStatusWritten`** (`Access/{sport}/{season}/{uid}/Status`
  written): → 'active': push + email `activatedPaid` (Via card/venmo/zelle;
  the email is the receipt: amount, method, date, season) or
  `activatedGranted` (granted/player/grandfathered; no amount). → 'revoked':
  push + email `revoked`. Once-only via `Access/<uid>/Notified/<status>_<PaidAt
  or RefundedAt>`. The fan's email = `admin.auth().getUser(uid).email`; no
  email on file = push only + log.
- **`onRegistrationPaidGrantFantasy`** (`Registrations/{regId}/Submissions/{uid}/Paid`
  written → true): resolves the registration's league/season
  (`legacyTarget(config)`), and if `Fantasy/<league>/<season>/Config/Access`
  is pass mode with `RegisteredPlayersFree:true` and the uid is not active →
  grant `{Status active, Via player, AmountCents 0, By 'system'}`. Unpaid
  flips do nothing (access is never removed automatically for this).
- **`sendFantasyAccessTest`** (callable, admin-gated like getUserContact):
  `{sport, season, template}` → sends that template's push + email to the
  CALLER with sample values. The Manager's "Send me a test" button.
- Pushes use the existing fantasy pusher (Users/<uid>/Token); data
  `{type:'fantasyAccess', sport, season}`; the fan app routes the tap to the
  hub's My Team tab (existing `type:'fantasy'` routing extended).
- Templates come from `Fantasy/Templates/Access/<key>` with code defaults
  when a key or field is absent/blank (§9). `fillTemplate` replaces
  `{name} {teamName} {amount} {season} {method} {date} {reason}`; unknown
  placeholders stay literal; `{reason}` is only available in admin-facing
  templates.
- Logging: every grant/activation/revoke `log.info` with uid/via/by; every
  skipped duplicate `log.info`; every template fallback `log.warn` once.

## 8. Manager app — "Access & payments"

Fantasy section → new tile **Access & payments** ("Free or season pass,
pending payments, grants") with a live badge of pending claims. Page
(Riverpod, live streams, no `.get()`):

1. **Mode card:** Free / Season pass segmented control; price field; method
   switches Venmo / Zelle / Card; switch *Registered players play free*;
   Save. Flipping Free → Pass opens the grandfather dialog (§5). Pass →
   Free confirms "Managers keep their records; the gate turns off."
2. **Pending claims:** live list (team name or real name, method, amount,
   when, note) with **Approve** (writes Access active, Via from claim,
   AmountCents, By admin, PaidAt now; claim `Resolved:'approved'`) and
   **Reject** (reason sheet; deletes Access pending; claim
   `Resolved:'rejected', Reason`). Approve/Reject are transactions on the
   Access node so two tablets can't double-act.
3. **Managers & access:** every `Managers` uid + every Access uid, status
   chip (Active · card / venmo / granted…, Pending, Revoked, None), search,
   tap → Fantasy profile page (existing) which gains a **Grant access** /
   **Revoke access** button with a Reason field.
4. **Grant access…** button → sheet with three sources: *Pick users* (the
   existing search-gated user picker), *A team's roster* (league team →
   linked player UIDs via `Line Ups/<team>/<player>/UID`; unlinked players
   listed as "not linked — link them in Trophies → Awards by competition"),
   *All registered players this season* (paid submissions of the season's
   registration). Preview count → Confirm → one multi-path update of
   `Access/<uid>` records `{active, granted, By admin, Reason}` skipping
   uids already active. Everything on this sheet is admin-only; the fan
   app never mentions it.
5. **Messages:** one editor per template key (§9): push title, push body,
   email subject, email body (plain text; blank lines = paragraphs), the
   placeholder legend, **Reset to default**, **Send me a test** (callable).
   The paywall copy (`Config/Access/Copy`) is edited here too.
6. **Analytics page** gains a Revenue tile: active passes by Via, pending
   count, `$` total of `AmountCents` for card/venmo/zelle, and granted count.

## 9. Templates (defaults; `{placeholders}`)

| key | push title / body | email subject / body |
|---|---|---|
| `claimReceived` (fan) | "Payment noted" / "Thanks {name} — we'll confirm your {method} payment shortly." | "Infinite Fantasy — payment noted" / "Hi {name}, we received your note that you paid {amount} by {method} for {season}. Zaya will confirm it shortly and you'll get a message the moment you're in." |
| `claimAdmin` (admins) | "Fantasy payment to confirm" / "{name} says they paid {amount} by {method} for {season}." | "Fantasy payment to confirm — {name}" / same + "Open the Manager → Fantasy → Access & payments to approve." |
| `activatedPaid` (fan, receipt) | "You're in!" / "Your {season} season pass is active. Build your team!" | "Receipt — Infinite Fantasy {season}" / "Hi {name}, your season pass is active.\n\nAmount: {amount}\nMethod: {method}\nDate: {date}\nSeason: {season}\n\nOpen the app → Fantasy → My Team to name your team and build your squad. Good luck!" |
| `activatedGranted` (fan) | "You're in!" / "Your {season} fantasy access is active. Build your team!" | "You're in — Infinite Fantasy {season}" / "Hi {name}, your access to Infinite Fantasy for {season} is active. Open the app → Fantasy → My Team to build your squad." |
| `revoked` (fan) | "Fantasy access removed" / "Your {season} fantasy access was removed. Pay again in the app to keep playing." | "Infinite Fantasy — access removed" / "Hi {name}, your access to Infinite Fantasy for {season} was removed on {date}. You can pay again from the app's Fantasy tab to keep playing. Reply to this email if you think this is a mistake." |
| `Copy` (paywall) | Headline "Join Infinite Fantasy" · Body "A season pass for {season} is {amount}. Pay once, play the whole season." · Button "Get my season pass" | — |

Admin email address: `Fantasy/Templates/Access/AdminEmail` (default
`support@infinitesports.org`). From-address = the support SMTP user.

## 10. Hosting pages (Checkout return)

Add Firebase Hosting (`firebase.json` `hosting.public = "public"`), two
static pages, Infinite Sports styling, light + dark, no scripts:

- `public/fantasy/paid.html` — "Payment received. Head back to the Infinite
  Sports app — your fantasy access activates within a few seconds."
- `public/fantasy/cancelled.html` — "No charge was made. Head back to the
  app to try again or pay with Venmo."

Deployed with `firebase deploy --only hosting` to
`https://infinite-sports-app.web.app/fantasy/…`. The app itself updates
live from the Access stream; the page is only the browser's landing spot.

## 11. Testing

- functions (vitest): metadata parse both kinds; Checkout session builder
  (amount from Config, metadata, URLs, refuses free mode / Card off /
  already active); webhook routing (registration path byte-identical;
  fantasy activation idempotent on replay; refund revokes; partial refund
  logs only); claim trigger (pending written, admin push + 2 emails, once);
  status trigger (paid vs granted template, revoked, once per PaidAt, no
  email on file → push only); registration Paid auto-grant (toggle off →
  nothing; already active → nothing); template fill + defaults; rules
  contract (gates on Squads/Managers, Access/AccessClaims grants).
- rules: local RTDB emulator probe (scratchpad) — Squads/Managers writes
  refused in pass mode without active Access, allowed in free mode or when
  active; AccessClaims create-only own; Access admin-only.
- fan (flutter_test): pay card states (none/pending/revoked/active) light +
  dark + 360 px; card button calls the callable seam and launches the URL
  seam; I sent it writes the claim shape; free mode = no card; existing
  manager without access = card + read-only court; session clear scan.
- Manager (flutter_test): mode save + grandfather dialog multi-path shape;
  approve/reject transaction shapes; grant sheet preview counts (users /
  team roster with unlinked split / registered players); template editor
  reset + placeholders; revenue tile math.

## 12. What the owner does (once)

1. Stripe dashboard → Developers → Webhooks → the existing endpoint → *Add
   events* → tick **`charge.refunded`** → Save. (Needed only for automatic
   revoke on refund; everything else works with today's subscription.)
2. After the build: Manager → Fantasy → Access & payments → set Season pass
   + price + methods for Futsal Season 16 before the GW1 window opens.
   Flip only when the S15 fill is cleared / S16 Config exists.

## 13. Out of scope

Monthly/auto-renew passes (declined), in-app purchase, promo codes,
partial refunds, non-US storefront rules, Manager-app push notifications
(the Manager app has no FCM; admins get pushes on their fan-app phone).

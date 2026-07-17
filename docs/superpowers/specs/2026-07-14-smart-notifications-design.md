# Smart Notifications & Targeting (Epic P4) — Design Spec

**Date:** 2026-07-14
**Epic:** Calendar & Events (piece 4 of 5)
**Repos:** infinite_sports_flutter (fan + functions), InfiniteSportsManagerFlutter (manager)
**Owner decisions captured:** hybrid targeting (topics + tokens), send-now + schedule, favorite-sports for new AND existing users (opt-out per sport, auto-subscribe), per-category off switches, phased build (A then B), Claude preps backend / owner deploys.

## Problem

Today notifications only fire for automated match events (goal/kickoff/fulltime) via topic-condition sends. Follows live only on-device (SharedPreferences) so the server can't enumerate audiences. There is no way for the owner to send a targeted message, and no favorite-sports concept. Goal: let the owner reach the right people (by sport, by event, by hand-picked list, or everyone) without annoying anyone, and let users choose what they hear about.

## Key architecture decision

Notification preferences move **server-side**: written under `Users/<uid>/...` so the backend can target by them, AND mirrored to FCM topic subscriptions so the existing topic-condition send path can be reused for big audiences. Two disjoint send mechanisms, both needed:
- **Topic conditions** — broadcast to `all_users`, `sport_<Sport>`, `event_<id>` (fast, unbounded scale).
- **Per-uid token multicast** — hand-picked lists (reads `Users/<uid>/Token`, prunes stale).

## Categories (reuse P2 seed list)

Futsal, Basketball, Flag Football, Soccer, Volleyball, Pickleball, Tournaments, Community.

---

## Phase A — Fan app: favorites, settings, remind-me (no backend deploy needed)

**A1. Favorite-sports onboarding**
- New page after `createDatabaseLocation` succeeds in `createaccountpage.dart::_signUp`: "What are you into?" grid of the 8 categories (multi-select), Skip allowed.
- Existing users: one-time prompt (checked on app start when `Users/<uid>/FavoriteSports` is absent and signed in) — same picker, dismissible.
- Persist to `Users/<uid>/FavoriteSports/<Category> = true`. For each chosen category, subscribe FCM topic `sport_<Category>` and record via `FollowStore` so it shows in settings.
- All installs subscribe to `all_users` on launch (main.dart), enabling the "Everyone" audience.

**A2. Notification settings (per-category off switches)**
- Extend `lib/settings.dart`: a "Notifications" section listing the 8 categories with individual toggles (on = subscribed to `sport_<Category>` + `Users/<uid>/NotifPrefs/<Category>=true`), plus the existing master pause-all. Toggling off unsubscribes the topic and sets the pref false. Master off still unsubscribes everything (existing behavior).

**A3. Remind-me on events**
- Event page gets a "Remind me" toggle (next to Attend). On = subscribe topic `event_<id>` + write `EventsV2/<id>/Reminders/<uid>=true`; off = reverse. This feeds the "event subscribers" audience in Phase B. (Legacy events without an id: hide the button.)

**A4. Payload routing prep**
- Extend `notification_router.dart` to handle `data['type']=='event'` (deep-link to EventPage by `eventId`/`v2Id`) and `data['type']=='campaign'` (open a target if present, else show the message). Handle foreground display in `main.dart::onMessage` for these types (they carry a `notification` block so they show; add tap routing).

**Phase A testing:** onboarding writes FavoriteSports + subscribes topics; settings toggles subscribe/unsubscribe; remind-me writes Reminders; all light/dark; existing match alerts unaffected. Fan tests + analyze clean. Installs & owner sign-off before Phase B.

---

## Phase B — Manager campaigns + cloud sender (backend deploy at the end)

**B1. Campaign compose screen (manager)**
- New `lib/ui/notifications/campaign_page.dart` (replaces/augments the current DB-only notifications page): Title, Message, Audience picker:
  - Everyone → `{type:'all'}`
  - Sport → `{type:'sport', sport:'Futsal'}`
  - Event → pick from EventsV2 → `{type:'event', eventId}`
  - Hand-picked → search `Users` by name, check people → `{type:'users', uids:[...]}`
- Optional deep-link target (an event) so taps open it.
- Send timing: "Send now" or a date/time picker (scheduled).
- Reach estimate + confirm dialog ("This will reach about N people. Send?"). N computed client-side: all=user count, sport=count of FavoriteSports/<sport>, event=Reminders+Attendees count, users=list length.
- Writes a trigger doc `Campaigns/<pushId>`:
  ```
  { Title, Body, Audience:{type,sport?,eventId?,uids?},
    Data:{type:'campaign', eventId?}, SendAt:<ms|0 for now>,
    Status:'pending', CreatedBy, CreatedAt }
  ```
- Campaign history list (past/scheduled) with status.

**B2. Cloud function sender (fan repo functions/)**
- `onCampaignWrite` (RTDB `onValueCreated` on `/Campaigns/{id}`): if `SendAt<=now` send immediately, else leave pending.
- `processScheduledCampaigns` (scheduled function, every 1–5 min): sweep `Status=='pending' && SendAt<=now`, send, set `Status:'sent'` (+ `SentAt`, `Reached`).
- Sending: topic audiences (`all`→`all_users`, `sport`→`sport_<Sport>`, `event`→`event_<id>`) via `admin.messaging().send({condition/topic})`; `users` audience via `sendEachForMulticast` over `Users/<uid>/Token`, pruning `registration-token-not-registered`.
- Reuses channel `infinite_sports_notifications`; payload carries `Data` for tap routing.
- Emulator dry-runs (mirror existing `fcm.ts` behavior).

**B3. Deploy**
- Claude writes + tests; owner (or Paul/Bronsin) runs `firebase deploy --only functions`. Nothing live until then. Document the exact command + new topics.

**Phase B testing:** create each audience type in manager → confirm reach count → send-now delivers to the right phones (test on emulator + device with different favorites) → scheduled fires at time → tap opens target. Then deploy.

## Out of scope

Quiet hours, multi-device tokens, rich media pushes, in-app notification inbox (the manager's legacy `Notifications/<index>` DB list stays as-is for now).

## Delivery

Branch `zaya-notifications` (fan) + a matching manager branch for Phase B, own worktrees. Phase A merges to `zaya-features` on sign-off; Phase B merges after backend is tested (deploy owner-run).

# Infinite Fantasy — Automation round + News desk 2.0

**Status:** owner-approved 2026-10-28 (all five proposals + autopilot + edit/delete of
published posts). Extends `2026-10-26-infinite-fantasy-design.md` (§3 pricing, §12
pushes, §13 news, §15 Manager). Governing rule: automation-first
(memory `feedback_automate_first.md`) — the engine does the work, the owner overrides.

Repos/branches: fan repo `infinite_sports_flutter` (app + `functions/`) and Manager
`InfiniteSportsManagerFlutter`, both on `zaya-fantasy`. House rules apply everywhere:
no RTDB `get()` in Flutter clients (streams / `once()` only), light+dark via
colorScheme, wrap don't ellipsize, no underlined names, dialogs with TextFields are
StatefulWidgets owning their controllers, destructive actions confirm.

---

## 1. Position price: keeper rule + a visible reason (Manager)

Today `suggestedPriceTenths` re-scores the player's season at the new position and
percentiles him inside that position. Into GK that is wrong: outfield goals re-score at
10 pts (Adorin Tuman ATT 7.5M → GK 14.5M: 13 goals → 114 GK pts, 2nd of 8 keepers whose
season totals are mostly negative because S15 recorded no saves).

New rule (pure, `lib/fantasy/logic/suggested_price.dart`):

| Move | Suggested price | Reason line (examples) |
|---|---|---|
| DEF/ATT → GK | median of the prices of everyone currently listed GK (excluding him), snapped to the step and clamped; no keeper peers → `rookiePriceTenths` | "Moving into goal: priced like a typical keeper (middle of 8 keepers). Weekly price updates move him if he outscores them." |
| any other change | unchanged re-score + percentile math | "Re-scored as DEF: 57 pts this season — 9th of 21 defenders." |
| no season stats | unchanged (no suggestion, price stays) | existing copy |

`suggestedPrice(...)` returns `PriceSuggestion {int priceTenths, String reason}`; the
dialog shows the reason under the new price. Rank text = 1-based rank by season points
within the peer group including the player ("9th of 21 defenders"; position plural
keepers/defenders/attackers).

## 2. Lock override: auto-return + "engine paused" banner

- New `Config/lockOverrideUntil` (epoch ms, optional). Switching to Open or Locked in
  the Manager asks "Return to Auto after" with choices 1 hour · 6 hours · 24 hours
  (default) · 3 days · Never (testing). Switching to Auto removes `lockOverrideUntil`.
- **Effective override** (server + fan + Manager): `lockOverride` when it is open/locked
  AND (`lockOverrideUntil` absent OR now < until); otherwise `auto`. Every server
  stand-down check uses the effective value (sweep, finalize, void, reprice).
- The 15-minute sweep, on finding an expired override, writes `lockOverride:'auto'` and
  removes `lockOverrideUntil` (logged "lock override expired — back to auto"), then runs
  the season normally in the same sweep.
- Manager: a banner directly under the season bar on every Fantasy page whenever the
  effective override is not auto: "Fantasy engine paused — LOCKED. Nothing scores,
  reprices or sends until it's back on Auto." + "Returns to Auto Sun, Nov 2 · 3:00 PM" or
  "No automatic return set." + a **Resume Auto** button (confirm dialog). errorContainer
  colors (both themes).

## 3. Message managers (custom fantasy push)

Manager → Reminder & pushes page, new top card **Message managers**:

- Title (≤ 40) + message (≤ 140) fields, live lock-screen preview.
- One-tap starters that fill both fields: Deadline moved · Match day postponed ·
  Prices updated · Custom (clears). A **Generate** button polishes/writes the message
  from whatever is typed (AI, §4.5 `writeFantasyCopy` mode `message`).
- Audience: All fantasy managers (default) · Unchanged squads · Owners of a player
  (player picker, search by name).
- When: Send now (callable, result dialog "N in audience, M delivered") or Schedule
  (date + time, league time) → a row in `ScheduledPushes`; the card lists pending
  scheduled messages with Cancel (confirm). Sent within 15 minutes of the chosen time.

Server: callable `sendFantasyMessage` and the sweep's scheduled-push step share one
core (`sendManagerMessage`). Scheduled pushes are processed by the sweep **before** the
lock-override stand-down (owner messages are not engine jobs). Data payload
`{type:'fantasy', sport, season, gw}`.

`Fantasy/<sport>/<season>/ScheduledPushes/<id>` =
`{Title, Body, Audience:'all'|'unchanged'|'owners', Player?, SendAt:int, CreatedAt:int,
SentAt?:int, Sent?:int}`; claim = transaction on `SentAt` before sending.
A row found more than 3 h past its `SendAt` is claimed with `Error:'expired'` and not sent.

Audience resolution (shared helper, pure): managers = keys of `Managers` ∪ `Squads`;
unchanged = existing `reminderAudience`; owners = managers whose current squad contains
the named player (any slot, starters or bench).

## 4. News desk 2.0

### 4.1 Post/draft shape (additive; old rows stay valid)

`News/Drafts/<id>` and `News/Published/<id>` gain:

```
Template: 'spotlight'|'star'|'price'|'h2h'|'free'|'dreamteam'|'ai'   (absent = 'free')
Gw: int                                   (optional on owner posts)
Players: { "0": PlayerCard, "1": ... }    (0–5 tagged players, display order)
Push: { Title, Body, Audience:'managers'|'owners'|'everyone' }   (optional)
PushedAt: int, PushSent: int              (server-written, Published only)
PhotoUrl: string                          (existing)
EditedAt: int                             (Manager edits)
```

Drafts additionally: `Source:'ai'|'dreamteam'|'owner'`, `AutoPublishAt?:int`,
`CreatedAt`.

`PlayerCard` = a snapshot taken when the post/draft is built (posts read correctly
forever; the fan feed needs no extra listeners):

```
{ name, position:'GK'|'DEF'|'ATT', team, photoUrl?, priceTenths, priceDeltaTenths?,
  gw?, gwPoints?, seasonPoints?, ownershipPct?, goals, assists }
```

Sources: Players node (position/team/photo/price), latest `PriceChanges/<gw>/<name>`
delta, latest finalized `PlayerWeeks/<gw>/<name>` (gw points), `PlayerTotals/<name>`
(season points, ownership), season goals/assists tallied from the season's game nodes
(Goal + PenGoal; Assist). Built by the Manager (Dart, compose/templates) and by the
server (TS, autopilot drafts) — same shape, tested per side.

### 4.2 Fan app rendering

- Card header line: `<label> · GW<n>` — Spotlight / Star of the week / Price watch /
  Head to head / Team of the week / News (free, ai).
- 1–2 tagged players → full player cards under the body (photo or initials, name,
  `POS · team · 15.0M +0.5`, four stats: GW pts · goals · assists · owned %; a missing
  stat renders "–"), button **View player** → opens the same market player sheet the
  Players tab uses (the hub passes an `onOpenPlayer(name)` callback into the News tab).
- 3+ tagged players (Team of the week) → compact rows (photo, name, position, GW pts).
- Push taps: payload `{type:'fantasy', sport, season, gw?, postId?}` opens
  `FantasyHubPage(sport, season, initialTab: news|myTeam, focusPostId)` — News when a
  postId is present (scrolls to the post, brief highlight), My Team otherwise (deadline
  reminder, recap, message, position alert — these taps did nothing before). A postId
  that is gone after the first feed emit → SnackBar "This post was removed."

### 4.3 Manager compose / edit / publish

**Compose post** (full-screen dialog):
1. Story template chips: Player spotlight · Star of the week · Price watch · Head to
   head · Free write.
2. Tagged players: chips + **Tag player** (search picker over the market, max 5).
3. Title + body auto-fill from the template + snapshots the moment players/template
   change, until the owner types in a field (then no more auto-overwrite; a "Refill
   from template" text button restores). **Write it for me** → AI version
   (`writeFantasyCopy` mode `post`); **Another version** re-asks.
4. Optional photo (existing).
5. **Send a push** switch (default ON when players are tagged, else OFF). Audience:
   Fantasy managers (default) · Owners of tagged players (only when tagged) · Everyone.
   Push text fields auto-fill (title = post title ≤ 40, body = first sentence of body
   ≤ 110), **Generate** (`writeFantasyCopy` mode `push`), lock-screen preview.
6. Actions: **Publish now** · **Schedule** (date+time → draft `Source:'owner'` with
   `AutoPublishAt`) · **Save draft** (queue, no schedule).

**Draft editor**: same layout as compose (template, players, title/body, push section)
plus an **Auto-publish** switch + time, pre-filled with the draft's current schedule.
Saving uses exactly what the switch says (decision 2026-10-28: the switch replaces the
old "any edit cancels the schedule" rule — the schedule is always visible and
owner-controlled). Buttons: Save · Publish now.

**Published list**: each post shows template label, GW, tagged player names, "Pushed to
N" when sent; actions **Edit** (title/body/players/photo; never re-pushes) and
**Delete** (confirm: "Removes the post from the fan feed. A push that already went out
can't be recalled — tapping it will say the post was removed.") — deletes the row and
its Storage photo (`FantasyNews/<sport>/<season>/<id>.jpg`, ignore not-found).

Publishing a draft copies every field above (minus Source/AutoPublishAt/CreatedAt) to
Published in one multi-path update and removes the draft (existing pattern).

### 4.4 Autopilot (server)

`Config/NewsAutopilot = {Enabled:bool, Weekday:string, Hour:int}` — **Enabled defaults
to TRUE when absent** (automation-first); Weekday default 'tuesday', Hour 10 (league
time). Legacy `Config/DreamTeamPost` is read as a fallback when NewsAutopilot is absent
(AutoPublish→Enabled). Manager card "Autopilot" replaces the Dream Team schedule card.

After each finalized (non-voided) gameweek (existing NewsDrafted guard):
- Dream Team draft: `Template:'dreamteam'`, `Players` = the 5 Dream Team snapshots,
  default `Push {Title:'Team of the Week is out', Body:'GW<n>'s best five are in — see
  who made it.', Audience:'managers'}`.
- AI drafts (2–4): the model also returns `players` (names, must be from the stats it
  was given; unknown names dropped; max 3) → snapshots; `Template:'ai'`; no push.
- When Enabled: every new draft gets `AutoPublishAt` = next Weekday Hour league time, or
  now + 12 h if that is later (the owner always gets ≥ 12 h to review).
- **Admin heads-up push** (to every uid in `Admins`), once per gameweek with the drafts:
  Enabled → "Fantasy stories ready" / "N posts publish Tue 10:00 AM unless you change
  them in the Manager." (the drafts' actual `AutoPublishAt`); disabled → "N fantasy
  stories are waiting for your approval in the Manager." Payload `{type:'fantasy', sport,
  season, gw}`.
- Sweep auto-publish: ANY draft whose `AutoPublishAt` is due publishes (all Source
  values), copying the §4.1 fields; voided-week drafts stay held (existing rule).
  A due draft whose `Published/<id>` already exists never overwrites it: its
  `AutoPublishAt` is cleared and it stays in the queue.

### 4.5 Server pieces

- **Trigger `onFantasyNewsPublished`** (`onValueWritten`
  `/Fantasy/{sport}/{season}/News/Published/{postId}`): when the row exists, has `Push`
  and no `PushedAt` → transaction-claim `PushedAt` → resolve audience → send → write
  `PushSent`. Audiences: managers / owners (owners of ANY tagged player) / everyone
  (FCM topic `all_users`, same as campaigns). Payload adds `postId`. Edits never
  re-push (PushedAt stays). This one path covers Manager publish, draft publish and
  autopilot publish. A post whose `At` is over 60 min old when first seen never pushes.
- **Callable `writeFantasyCopy`** (admin-only, Anthropic `claude-haiku-5-5`, secret
  ANTHROPIC_API_KEY, 8s timeout, same playful-never-mean / stats-only rules):
  `{sport, season, mode:'post'|'push'|'message', template?, players?:string[], title?,
  body?, hint?}` → `{title, body}`. Limits: post 60/400, push 40/110, message 40/140.
  Server builds the facts from the same snapshot builder (players) — the model never
  sees anything else. Failure → HttpsError `unavailable`; the Manager shows "Couldn't
  write it right now — try again."
- **Callable `sendFantasyMessage`** (admin-only): `{sport, season, title, body,
  audience:'all'|'unchanged'|'owners', player?}` → `{audience, sent}`.
- `FantasyPusher` gains `sendToTopic(topic, title, body, data)`.

### 4.6 Rules

Add under `Fantasy/$sport/$season`: `PlayerWeeks` (.read admin) and `ScheduledPushes`
(.read/.write admin). Config/News already cover the rest. Regenerate
`database.rules.stage1.json` from `database.rules.json` and deploy.

## 5. Out of scope / notes

- Season 16 scorers must record **Save** events (capture screens have the button) —
  keeper points and prices depend on it. Owner action, not code.
- No re-push on edit; no unsend of a delivered push (OS limitation).
- Manager has no FCM token: the admin heads-up lands in the owner's fan app.
- iOS: callables, topic push and push-tap routing need a "verify on simulator" line in
  the PRs.

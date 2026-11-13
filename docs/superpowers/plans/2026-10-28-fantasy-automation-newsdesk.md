# Fantasy automation round + News desk 2.0 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the owner-approved spec `docs/superpowers/specs/2026-10-28-fantasy-automation-newsdesk-design.md` (read it first — it is the contract; section numbers below refer to it).

**Architecture:** Server logic stays pure in `functions/src/lib/fantasy/*` behind the existing `FantasyDb` / `FantasyPusher` seams (in-memory tests via `test_support.ts`), thin firebase wrappers in `functions/src/*.ts`. Fan app reads only `News/Published` (snapshots make posts self-contained). Manager computes snapshots + deterministic templates in pure Dart, AI copy via an admin callable.

**Tech Stack:** TypeScript Cloud Functions v2 + vitest (`cd functions && npm test`, `npm run build`); Flutter fan app (`C:\src\flutter\bin\flutter.bat test`); Flutter Manager app with Riverpod (same flutter).

**Repos / branches (both already checked out on `zaya-fantasy`, work in the main checkouts, NOT worktrees):**
- Fan + functions: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`
- Manager: `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`

**House rules (every task):** no RTDB `.get()` in Flutter clients (streams/`once()` only — a guard test fails the Manager build otherwise); colors via `Theme.of(context).colorScheme` and must work in light AND dark; text wraps (`softWrap: true`), never ellipsize names; tappable names never underlined; any dialog with a `TextField` is a StatefulWidget that owns and disposes its controllers (never dispose right after `await showDialog`); destructive actions confirm; integer tenths for money; commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; stage files explicitly (never `git add -A` — both repos have untracked files that must stay untracked). Baselines: functions 561 tests, fan 1430, Manager 1157 — all green before you start; keep them green.

---

## Task 1 — Server: lock-override expiry (spec §2)

**Files:** modify `functions/src/lib/fantasy/orchestration_db.ts` (`lockOverrideOf`), every caller in `functions/src/lib/fantasy/orchestration.ts` (sweep ~l.959, finalize ~l.795, void ~l.850, reprice ~l.1186, line ~352) and any other caller (`grep -rn lockOverrideOf functions/src`); tests in `functions/src/lib/fantasy/orchestration_db.test.ts` + a new `lock_override_expiry.test.ts` next to `orchestration.test.ts` (copy its setup style).

- [ ] Change signature to `lockOverrideOf(configNode: unknown, nowMs?: number)`. If raw is open/locked AND `configNode.lockOverrideUntil` is a finite number AND `nowMs !== undefined && nowMs >= until` → `'auto'`. Absent until / no nowMs → old behaviour.
- [ ] Unit tests: open+no until → 'open'; open+until in future → 'open'; open+until past → 'auto'; locked+until==now → 'auto'; junk until ('x') → treated as absent; auto stays auto.
- [ ] Every caller passes the job's `nowUtc.getTime()`.
- [ ] Sweep (`sweepSeason`): BEFORE the stand-down check, if the raw override is open/locked and `lockOverrideOf(config, now) === 'auto'` (expired) → `db.write(root/Config/lockOverride, 'auto')`, `db.write(root/Config/lockOverrideUntil, null)`, `log.info('fantasy sweep: lock override expired — back to auto', ctx)`, and continue the sweep with a config copy whose lockOverride is 'auto'.
- [ ] Orchestration test: season with `lockOverride:'locked', lockOverrideUntil: now-1` → after `runLifecycleSweep` the Config shows 'auto', no until, and GwState was written (sweep ran). Same with until in the future → still 'locked', GwState untouched.
- [ ] `npm test` + `npm run build` green. Commit `feat(fantasy-fn): lock override auto-returns to auto after lockOverrideUntil`.

## Task 2 — Server: player cards + audiences (pure helpers, spec §3, §4.1)

**Files:** create `functions/src/lib/fantasy/news_cards.ts` + `news_cards.test.ts`, `functions/src/lib/fantasy/audiences.ts` + `audiences.test.ts`.

`news_cards.ts`:
```ts
export interface PlayerCard {
  name: string; position: 'GK' | 'DEF' | 'ATT'; team: string;
  photoUrl?: string; priceTenths: number; priceDeltaTenths?: number;
  gw?: number; gwPoints?: number; seasonPoints?: number;
  ownershipPct?: number; goals: number; assists: number;
}
/** Season Goal(+PenGoal) / Assist tallies per player name across every game
 *  under `<sport>/<season>/Date` (reuse the activity parsing the TS stats
 *  mapper already uses — same case-insensitive keys; do NOT re-invent). */
export function seasonGoalsAssists(dateNode: unknown): Record<string, { goals: number; assists: number }>;
/** One card; null when the name is not in the Players node. Latest = the
 *  highest gw key present in each node. PlayerTotals rows are
 *  {points, ownershipPct} (or a bare number = points). PriceChanges rows are
 *  {delta} (skip the `Manual` flag key). Optional fields are OMITTED (not
 *  undefined) when unknown — RTDB rejects undefined. */
export function buildPlayerCard(name: string, src: {
  playersRaw: unknown; playerTotalsRaw: unknown; playerWeeksRaw: unknown;
  priceChangesRaw: unknown; goalsAssists: Record<string, { goals: number; assists: number }>;
}): PlayerCard | null;
/** Cards in input order, unknown names dropped, max 5, as an RTDB-safe
 *  {"0": card, "1": card} map (empty → null). */
export function cardsNode(cards: PlayerCard[]): Record<string, PlayerCard> | null;
```
Tests: goals/assists tallied from a 2-date fixture incl. PenGoal and List-coerced games; card fields from fixtures (latest gw chosen = max key; Manual flag ignored; totals as number and as map); unknown player → null; cardsNode caps at 5 and returns null for [].

`audiences.ts`:
```ts
/** Keys of Managers ∪ Squads, sorted. */
export function allManagers(managersRaw: unknown, squadsRaw: unknown): string[];
/** Managers whose CURRENT squad (Squads/<uid>, any slot incl. bench) holds
 *  any of [names]; read squad.ts for the stored squad shape and reuse its
 *  parser. Sorted. */
export function ownersOf(squadsRaw: unknown, names: string[]): string[];
```
Tests: union + sort; owners by starter and by bench; malformed squads skipped; empty names → [].

- [ ] Write tests first, run (fail), implement, run (pass), build. Commit `feat(fantasy-fn): news player-card snapshots + audience helpers`.

## Task 3 — Server: autopilot + upgraded drafts (spec §4.4)

**Files:** modify `functions/src/lib/fantasy/news.ts`, `orchestration.ts` (Phase G ~l.683-745, sweep step 2b ~l.991-1011), `pushes.ts` (admin heads-up copy), tests `news.test.ts`, `news_orchestration.test.ts`, `void_week.test.ts` (adjust expectations only where shapes legitimately grew).

- [ ] `newsAutopilotConfigFrom(newsAutopilotRaw, legacyDreamTeamPostRaw): {enabled, weekday, hour}` — NewsAutopilot wins when it is a map; else legacy DreamTeamPost (`AutoPublish`→enabled); else defaults **enabled TRUE**, weekday 2 (tuesday), hour 10. `Enabled === false` is the only off. Tests for all three sources. Remove `dreamTeamPostConfigFrom` usage (keep export only if other code needs it).
- [ ] AI prompt: each item now `{"title","body","players":[names]}`; prompt says players must be names from the provided stats JSON, 0–3. `parseNewsDrafts` returns `players: string[]` (non-strings dropped, max 3). Tests: players parsed; missing players → []; >3 cut.
- [ ] `buildDreamTeamDraft` adds `Template:'dreamteam'`, `Players` (cardsNode of the Dream Team names in stored order — caller passes cards), `Push: {Title:'Team of the Week is out', Body:`GW${gw}'s best five are in — see who made it.`, Audience:'managers'}`. Keep Title/Body/Gw/CreatedAt/Source/AutoPublishAt.
- [ ] Phase G: build `goalsAssists` once (Date node) + cards via Task 2 helpers (PlayerTotals/PlayerWeeks/PriceChanges are already written earlier in finalize — read them fresh). AI drafts get `Template:'ai'`, `Players` (only names that exist in Players; null node omitted), and `AutoPublishAt` when autopilot enabled. Dream Team draft gets AutoPublishAt the same way.
- [ ] Admin heads-up: after drafts are written, if ≥1 draft was written and a pusher exists → uids = keys of `Admins` whose value is `true` → one push each: enabled: title `Fantasy stories ready`, body `${n} posts publish ${formatWhen} unless you change them in the Manager.` where formatWhen = `Tue 10:00 AM` (weekday short + h:mm AM/PM of the autopilot instant, league time); disabled: body `${n} fantasy stories are waiting for your approval in the Manager.`. Payload `fantasyPushData(sport, season, gw)`. Guarded by the same NewsDrafted claim (never twice).
- [ ] `shouldAutoPublish(draft, now)`: ANY Source with numeric `AutoPublishAt <= now`.
- [ ] Sweep 2b publish copies: Title, Body, At(now), and when present Template, Gw, Players, Push, PhotoUrl. Voided-week hold unchanged. Log text `fantasy news: draft auto-published`.
- [ ] Tests: drafts carry Template/Players/AutoPublishAt (enabled default) and no AutoPublishAt when NewsAutopilot.Enabled false; admin pushes captured with exact copy; an 'ai' and an 'owner' draft due → published with Players/Push copied; not-due stays. `npm test`, build. Commit `feat(fantasy-fn): news autopilot — tagged players, scheduled publish for all drafts, admin heads-up`.

## Task 4 — Server: push on publish (spec §4.5)

**Files:** create `functions/src/lib/fantasy/news_push.ts` + `news_push.test.ts`; create `functions/src/fantasy_news.ts`; modify `pushes.ts` (FantasyPusher gains `sendToTopic(topic: string, title: string, body: string, data: Record<string,string>): Promise<number>`), `fantasy_adapter.ts` (real impl: `admin.messaging().send({topic, notification, data, android:{priority:'high', notification:{channelId:'infinite_sports_notifications', sound:'default', color:BRAND_COLOR}}, apns:{payload:{aps:{sound:'default'}}}})` → 1 on success; emulator dry-run logs and returns 1), `test_support.ts` (fake pusher records topic sends), `index.ts` export.

- [ ] `pushPublishedPost(db, pusher, {sport, season, postId, nowUtc, log}): Promise<{sent:number}|null>` — reads `News/Published/<postId>`; returns null when absent, no `Push` map, or `PushedAt` present. Claims via `db.writeIfAbsent(root/News/Published/<id>/PushedAt, nowMs)`; lost claim → null. Audience: 'managers' → `allManagers`; 'owners' → `ownersOf(squads, Players names)`; 'everyone' → `sendToTopic('all_users', …)`; unknown → 'managers'. Data = `{...fantasyPushData(sport, season, gw ?? 0), postId}`. Writes `PushSent` = delivered count.
- [ ] `onFantasyNewsPublished = onValueWritten({ref:'/Fantasy/{sport}/{season}/News/Published/{postId}'}, …)` → skip when `event.data.after` doesn't exist → `pushPublishedPost` with `rtdbFantasyDb`/`rtdbFantasyPusher`.
- [ ] Tests: managers audience sends to Managers∪Squads with postId in data; owners audience; everyone → one topic send; second call is a no-op (claim); row without Push → null and no PushedAt written. Commit `feat(fantasy-fn): push fantasy news posts on publish (managers/owners/everyone)`.

## Task 5 — Server: callables, scheduled messages, rules (spec §3, §4.5, §4.6)

**Files:** create `functions/src/lib/fantasy/messages.ts` + test, `functions/src/lib/fantasy/copywriter.ts` + test, `functions/src/fantasy_messages.ts` (both callables); modify `orchestration.ts` (sweep), `index.ts`, `database.rules.json`, regenerate `database.rules.stage1.json`.

- [ ] `sendManagerMessage(db, pusher, {sport, season, title, body, audience:'all'|'unchanged'|'owners', player?, nowUtc}) → {audience:number, sent:number}` — 'all' = allManagers, 'unchanged' = reminderAudience for the current gameweek (throw like sendReminderNow when no Config / no current gw), 'owners' = ownersOf(squads,[player]) (missing player → throw). Title/body trimmed, title ≤40, body ≤140 (cut, no throw), empty title → throw.
- [ ] Sweep step 0 (BEFORE the lock-override stand-down, after the expiry revert): for each `ScheduledPushes/<id>` with numeric `SendAt <= now` and no `SentAt`: claim `SentAt` via writeIfAbsent, then `sendManagerMessage`, write `Sent`; a throw logs a warning and writes `Error` (string) so it never retries forever.
- [ ] `copywriter.ts`: `writeCopy({mode, template?, cards, title?, body?, hint?, apiKey, fetchImpl?, timeoutMs?}) → {title, body} | null` — Anthropic call exactly like `generateNewsDrafts` (same model constant, headers, abort, parse-first-text-block), system prompt = playful-never-mean, stats-only, plus per-mode limits (post 60/400, push 40/110, message 40/140) and "Reply with ONLY a JSON object {"title","body"}". User content = JSON of {mode, template, players: cards, currentTitle, currentBody, hint}. Clamp lengths; garbage → null. Tests with a fake fetch (ok JSON, fenced JSON, garbage, non-ok, blank key).
- [ ] `fantasy_messages.ts`: `writeFantasyCopy = onCall({secrets:[anthropicApiKey]}, …)` admin-gated exactly like `sendFantasyReminderNow` (auth → `Admins/<uid> === true`); builds cards from the request's player names via Task 2 helpers (reads Players, PlayerTotals, PlayerWeeks, PriceChanges, `<sport>/<season>/Date`); null result → `HttpsError('unavailable', 'Could not write copy')`. `sendFantasyMessage = onCall(…)` admin-gated → `sendManagerMessage`; errors → `failed-precondition`. Export both from `index.ts`.
- [ ] Rules: under `Fantasy/$sport/$season` add `"PlayerWeeks": {".read": "<admin expr>"}` and `"ScheduledPushes": {".read": "<admin expr>", ".write": "<admin expr>"}` (admin expr = the existing `auth != null && root.child('Admins').child(auth.uid).exists()`). Regenerate stage-1: read how `database.rules.stage1.json` differs from `database.rules.json` (root `.read: true`) and apply the same transform (do not hand-merge other drift). Validate both files parse as JSON.
- [ ] Tests for messages + sweep step 0 (due sent once, future untouched, failing one gets Error and isn't retried, runs even when lockOverride is 'locked'). `npm test`, `npm run build`. Commit `feat(fantasy-fn): writeFantasyCopy + sendFantasyMessage callables, scheduled manager messages, rules`.

## Task 6 — Fan app: tagged-player posts, push routing (spec §4.2, §2 fan side)

**Files:** modify `lib/fantasy/data/fantasy_parsers.dart` (FantasyNewsPost + lockOverride expiry), `lib/fantasy/hub/news_tab.dart`, `lib/fantasy/hub/fantasy_hub_page.dart` (initialTab, focusPostId, onOpenPlayer wiring), `lib/misc/notification_router.dart`; create `lib/fantasy/hub/news_player_card.dart`; tests under `test/fantasy/` (follow existing news_tab / parser tests).

- [ ] Parser: `FantasyNewsPost` gains `template` (String, default 'free'), `gw` (int?), `players` (List<NewsPlayerCard>, from a Map or List node, sorted by key), `pushed` not needed. `NewsPlayerCard` mirrors the spec PlayerCard (nullable optionals). Malformed entries skipped. Label helper: spotlight→'Spotlight', star→'Star of the week', price→'Price watch', h2h→'Head to head', dreamteam→'Team of the week', else 'News'; header text `'$label · GW$gw'` or just label when gw null.
- [ ] `FantasyLockOverride.parse` stays; `configStateFromNode` applies expiry: open/locked with numeric `lockOverrideUntil` ≤ `DateTime.now()` ms → auto. Parser test with a fixed past/future until.
- [ ] News card: header line (primary color, 11px w700), title/body as today, then 1–2 cards → `NewsPlayerCard` widget (photo via CachedNetworkImage circle 40px or initials, name w800, `POS · team · 15.0M` + delta in green/red (`+0.5`/`−0.5`, colorScheme-safe pairs that work in dark), four stat tiles GW pts / goals / assists / owned % with '–' for null, full-width tonal button **View player** calling `onOpenPlayer(name)`); 3+ → compact rows (photo/initials 28px, name, position chip, `N pts`). Never ellipsize names.
- [ ] Hub: `FantasyHubPage({sport, season, initialTab, focusPostId})` (`initialTab` enum or int: news vs myTeam; default existing first tab). Hub passes `onOpenPlayer` to the News tab; it opens the same market player sheet the Players tab opens (find how players_tab calls `showMarketPlayerSheet` and reuse the hub's draft/totals/stats feeds; when the player is no longer in the market, SnackBar `That player isn't in the market anymore.`).
- [ ] News tab `focusPostId`: after the first emit, if present → `Scrollable.ensureVisible` + a 1.2s highlight border (zero animation under reduced motion); absent → SnackBar `This post was removed.` once.
- [ ] Router: in `openMatchFromNotification`, BEFORE the league-watcher `sport` branch, handle `type == 'fantasy'`: push `FantasyHubPage(sport, season, initialTab: postId != null ? news : myTeam, focusPostId: postId)` on the root navigator; missing sport/season → return.
- [ ] Widget tests: card renders header label, both player stats and '–' for nulls; 3 players → compact rows; View player invokes callback with the name; focus on missing post shows the SnackBar; router test (if a router test exists, extend it; else unit-test a pure `fantasyRouteFromPayload(data)` helper you extract). Full `flutter test` green, `flutter analyze` on touched files clean. Commit `feat(fantasy): tagged-player news cards + fantasy push taps open the hub/post`.

## Task 7 — Manager: keeper price rule + reason (spec §1)

**Files:** modify `lib/fantasy/logic/suggested_price.dart`, `lib/ui/fantasy/fantasy_players_page.dart` (dialog), tests `test/fantasy/suggested_price_test.dart`.

- [ ] Add `class PriceSuggestion { final int priceTenths; final String reason; }` and `PriceSuggestion suggestedPrice({required String player, required FantasyPosition currentPosition, required FantasyPosition newPosition, required Map<String, FantasyPosition> currentPositions, required Map<String, int> currentPrices, required Map<String, List<PlayerGameStats>> statsByPlayer, required FantasyConfig cfg})`.
  - Into GK from DEF/ATT: peers = names with currentPositions == GK excluding player that have a price; median as a double (odd → middle value; even → (a+b)/2) → snapped = `((median / step) + 0.5).floor() * step` → clamp min/max; no peers → `rookiePriceTenths`. Reason: `Moving into goal: priced like a typical keeper (middle of N keepers). Weekly price updates move him if he outscores them.` (N=peer count; no peers → `Moving into goal: no other keepers to compare, so he starts at the new-player price.`)
  - Otherwise: price = existing `suggestedPriceTenths(...)`; reason `Re-scored as DEF: 57 pts this season — 9th of 21 defenders.` (points = his `seasonPointsAt` at the new position rounded to int; rank 1-based by points desc among the same group `suggestedPriceTenths` uses, ties share the better rank; plural: keepers/defenders/attackers; ordinal 1st/2nd/3rd/4th/11th/12th/13th/21st/22nd/23rd correct).
  - Keep `suggestedPriceTenths` (used by tests/other code).
- [ ] Tests (hand-computed, show the math in comments): GK median odd (keepers 40/55/90 → 55); even = the real S15 keepers 40,45,50,50,55,80,90,150 → (50+55)/2 = 52.5 → 52.5/5 = 10.5, +0.5 = 11, floor 11 × 5 = **55** (5.5M); a move where the moving player is himself already GK is not "into GK" (no change → no suggestion); no peers → 60; DEF→ATT reason text with rank; ordinal helper cases (1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd 101st 111th).
- [ ] Dialog: show the reason (bodySmall, onSurfaceVariant, softWrap) under the "New price" line; button labels unchanged; loading/no-stats paths unchanged. Widget test: moving an ATT into GK shows the keeper reason and the median price on the primary button.
- [ ] `flutter test` green (all 1157+), commit `feat(fantasy-admin): keeper price rule + visible price reason on position moves`.

## Task 8 — Manager: lock-override auto-return + paused banner (spec §2)

**Files:** `lib/fantasy/data/fantasy_admin_models.dart` (FantasyConfigState gains `lockOverrideUntilMs` (int?) + `effectiveLockOverride(DateTime now)`), `lib/core/constants/fantasy_paths.dart` (`lockOverrideUntil`), `lib/services/firebase/fantasy_admin_service.dart` (`setLockOverride(sport, season, value, {Duration? returnAfter})` — one `update` on Config: `{lockOverride: value.db, lockOverrideUntil: auto||returnAfter==null ? null : now+returnAfter ms}`), `lib/ui/fantasy/fantasy_section_page.dart` (`_LockOverrideSelector`), `lib/ui/fantasy/fantasy_season_bar.dart` (banner in `FantasySeasonScaffold`), tests.

- [ ] Selector: choosing Open/Locked opens a StatefulWidget dialog with the existing explanation + a "Return to Auto after" radio list: 1 hour · 6 hours · 24 hours (default) · 3 days · Never (testing). Choosing Auto keeps the existing confirm and clears until.
- [ ] Banner (`FantasyPausedBanner`, own file `lib/ui/fantasy/fantasy_paused_banner.dart`) inserted under `FantasySeasonBar` in `FantasySeasonScaffold` when the selected season's effective override != auto: errorContainer/onErrorContainer, icon pause_circle, text `Fantasy engine paused — LOCKED. Nothing scores, reprices or sends until it's back on Auto.` (OPEN variant: `Fantasy engine paused — OPEN (testing). …` same tail), second line `Returns to Auto Sun, Nov 2 · 3:00 PM` (league-local, reuse the existing deadline formatting helper used by the reminder page) or `No automatic return set.`, and a **Resume Auto** FilledButton.tonal → confirm `Turn the fantasy engine back on?` / `Scoring, prices, reminders and news resume on their normal schedule.` → `setLockOverride(auto)`. A periodic rebuild is NOT required (expiry also flips the DB within 15 min).
- [ ] Tests: effectiveLockOverride (future/past/none); banner shows for locked, hidden for auto and for expired-locked; Resume Auto writes auto (fake service like other fantasy page tests). Commit `feat(fantasy-admin): lock override auto-return + engine-paused banner`.

## Task 9 — Manager: news data layer (spec §4.1, §4.3, §4.4)

**Files:** `lib/fantasy/data/fantasy_admin_models.dart` (or a new `lib/fantasy/data/fantasy_news_models.dart` if cleaner — then re-export), `lib/fantasy/logic/news_cards.dart` + `news_templates.dart` (pure), `lib/services/firebase/fantasy_admin_service.dart`, `lib/providers/fantasy_admin_provider.dart`, `lib/core/constants/fantasy_paths.dart`; tests `test/fantasy/news_cards_test.dart`, `news_templates_test.dart`, model parse tests.

- [ ] Models: `NewsPlayerCard` (spec PlayerCard; `toMap()` omits nulls; `fromMap`), `NewsPush {title, body, audience: NewsPushAudience.managers|owners|everyone}` (db 'managers'|'owners'|'everyone'), `FantasyNewsDraft` + `FantasyNewsPost` gain `template`, `players`, `push`, (post) `pushedAt`, `pushSent`, `photoUrl`; draft gains `source` ('ai'|'dreamteam'|'owner'). `NewsAutopilotConfig {enabled (default TRUE when absent), weekday 'tuesday', hour 10}` parsing NewsAutopilot with legacy DreamTeamPost fallback (mirror Task 3).
- [ ] Pure `buildNewsCard(name, {players, totals, weeks, priceChanges, goalsAssists})` (latest gw = max key) and `seasonGoalsAssists(statsByPlayer)` from `fantasySeasonStatsProvider` data. Tests with fixtures.
- [ ] Pure templates `NewsTemplateText fillTemplate(NewsTemplate t, List<NewsPlayerCard> cards)` → `{title, body}` with EXACT formats (use `formatTenths` for prices; omit clauses whose stat is null):
  - spotlight (first card): title `Spotlight: {name}`; body `{name} ({POS}, {team}) has {seasonPoints} fantasy points this season with {goals} goals and {assists} assists. Price: {price}[, owned by {pct}% of managers].`
  - star: title `{name} is the star of GW{gw}` (no gw → `{name} is the star of the week`); body `{name} scored {gwPoints} points in GW{gw}, with {goals} goals and {assists} assists on the season. Price: {price}.`
  - price (all cards): title `Price watch` (+ ` — GW{gw}` when the first card has gw); body one line per card: `{name}: up 0.5M to 8.0M` / `down 0.5M to 6.5M` / `holds at 7.0M`.
  - h2h (first two): title `{a} vs {b}`; body `{a}: {pts} pts, {g} goals, {as} assists, {price}.\n{b}: …\nWho's in your team?`
  - free: empty title/body (no auto-fill).
  - `defaultPushText(title, body)` → push title = title cut at a word boundary to ≤40; push body = first sentence of body (split on `. `/`! `/`? `) cut at a word boundary to ≤110. Tests for every template incl. nulls and cutting.
- [ ] Service methods (streams only, no get): `watchPlayerTotals`, `watchPlayerWeeks` (Map<int, Map<String,int>>), `watchPriceChanges` (Map<int, Map<String,int>>, skip Manual) + providers; `publishDraft` copies template/players/push/photoUrl/gw; `saveDraft(sport, season, draftId?, {...all fields, autoPublishAtMs})` (create when id null with `Source:'owner'`, CreatedAt; update otherwise; `AutoPublishAt` exactly as given incl. null; `EditedAt`); `composePost(... template, players, push, photoBytes)`; `updatePublishedPost(id, {title, body, players, photoBytes?, removePhoto})` (never touches Push/PushedAt); `deletePublishedPost(id)` (row remove + Storage photo delete ignoring object-not-found); `watchNewsAutopilot`/`saveNewsAutopilot` (`Config/NewsAutopilot`); `writeCopy({sport, season, mode, template, players, title, body, hint})` → callable `writeFantasyCopy` → `{title, body}`.
- [ ] Tests for parse/serialize + templates + cards. Commit `feat(fantasy-admin): news data layer — player cards, templates, push + autopilot models`.

## Task 10 — Manager: News desk UI (spec §4.3, §4.4)

**Files:** `lib/ui/fantasy/fantasy_news_page.dart` (split into `lib/ui/fantasy/news/` files if it grows past ~600 lines: `news_compose_dialog.dart`, `news_player_picker.dart`, `news_push_section.dart`, `news_autopilot_card.dart`), widget tests `test/ui/fantasy/fantasy_news_page_test.dart` (follow existing Manager fantasy page tests for fakes/overrides).

- [ ] One `NewsComposeDialog` (full-screen dialog, StatefulWidget owning all controllers) used for compose AND draft edit: template chips; tagged-player chips + **Tag player** picker (search over `fantasyPlayersProvider`, max 5, shows position/team); title/body fields auto-filled from `fillTemplate` until the user types in that field (track `_titleTouched/_bodyTouched`; a **Refill from template** TextButton resets); **Write it for me** / **Another version** (callable mode post; spinner on the button; failure SnackBar `Couldn't write it right now — try again.`); photo add/remove; push section (switch default ON when ≥1 player tagged at open-time for new posts; audience SegmentedButton Fantasy managers / Owners of tagged players (disabled when no tags) / Everyone; push title/body fields auto-filled via `defaultPushText` until touched; **Generate** (mode push); lock-screen preview card); edit mode adds an **Auto-publish** switch + date/time pickers prefilled from the draft.
- [ ] Actions — compose: **Publish now** (confirm summarising audience: `Goes live now and pushes to fantasy managers.` / `…to owners of Bruno Siva.` / `…to everyone in the app.` / `Goes live now (no push).`) · **Schedule** (date+time pickers, league-local; must be in the future) · **Save draft**. Edit: **Save** · **Publish now**.
- [ ] Draft cards: label chip (DREAM TEAM / AI DRAFT / YOUR POST), GW, tagged names, push summary, schedule line `Publishes Tue, Nov 4 · 10:00 AM` or `Waiting for you`, actions Discard (confirm) · Edit · Publish.
- [ ] Published list: template label, GW, tagged names, `Pushed to N` when `pushSent` set; Edit (compose dialog in published mode: title/body/players/photo; no push section; footnote `Edits never send another push.`) and Delete (confirm with the spec §4.3 copy).
- [ ] Autopilot card (replaces `_DreamTeamConfigCard`): switch **Autopilot** (subtitle `After each gameweek the stories write themselves and publish at the time below unless you change or discard them.`), weekday + hour dropdowns → `saveNewsAutopilot`. Turning OFF confirms (`Stories will wait in the queue for you to publish.`).
- [ ] Remove the campaign-based Notify fans path from compose (server now pushes on publish).
- [ ] Widget tests: compose spotlight with one player fills title/body; typing stops auto-fill; Publish now writes a post with players + push (fake service capture); schedule creates an owner draft with AutoPublishAt; draft edit keeps the schedule when the switch stays on and clears when switched off; published Delete confirm calls delete; autopilot toggle. Full `flutter test` green. Commit `feat(fantasy-admin): News desk 2.0 — tagged players, templates, AI copy, push audiences, edit/delete, autopilot`.

## Task 11 — Manager: Message managers (spec §3)

**Files:** `lib/ui/fantasy/fantasy_reminder_page.dart` (new top card; consider `lib/ui/fantasy/message_managers_card.dart`), service (`sendManagerMessage` callable, `scheduleManagerMessage`, `watchScheduledMessages`, `cancelScheduledMessage`), `fantasy_paths.dart` (`scheduledPushes`), providers, tests.

- [ ] Card (StatefulWidget owning controllers): title (≤40, counter) + message (≤140, counter); starter chips fill both: **Deadline moved** → `Deadline moved` / `This week's fantasy deadline is now {deadline}. Make your changes before then.` (fill {deadline} with the current gameweek deadline text the page already computes); **Match day postponed** → `Match day postponed` / `This week's games are postponed. Your squad and deadline move with the new date.`; **Prices updated** → `Prices updated` / `Player prices just changed. Check the market before the deadline.`; **Custom** clears. **Generate** (callable mode message, hint = current text). Audience SegmentedButton All fantasy managers / Unchanged squads / Owners of a player (+ player picker reused from Task 10). Preview card. **Send now** (confirm → callable → result dialog `N in the audience, M delivered.`) and **Schedule** (future date+time → `ScheduledPushes` row `{Title, Body, Audience, Player?, SendAt, CreatedAt}`).
- [ ] Scheduled list under the card: pending rows (`SentAt` absent) with time + title + Cancel (confirm → remove); sent rows show `Sent to M` (last 5).
- [ ] Tests: starters fill text; schedule writes the row shape; cancel removes; owners audience requires a player (button disabled with helper text `Pick a player first.`). Commit `feat(fantasy-admin): Message managers — custom fantasy pushes now or scheduled`.

## Final — verify, deploy, install

- [ ] All suites green: functions `npm test` + `npm run build`; fan `flutter test`; Manager `flutter test` (incl. no-get guard).
- [ ] Deploy (from fan repo): functions `firebase deploy --only functions` (or the targeted list: fantasyLifecycleSweep, fantasyMondayReprice, onFantasyFinalize trigger(s), onFantasyVoidWritten, onFantasyPositionWritten, onFantasySquadWritten, sendFantasyReminderNow, onFantasyNewsPublished, writeFantasyCopy, sendFantasyMessage); rules via the existing stage-1 deploy path (firebase.json points database at the stage-1 file).
- [ ] Build + install fan APK on the emulator and Manager APK on the tablet (`adb connect 10.0.0.146:5555`; USB fallback).
- [ ] Update memory `infinite_fantasy_plan.md`.

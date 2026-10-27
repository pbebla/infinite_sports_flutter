# Infinite Fantasy P3 — Fan Fantasy Hub Implementation Plan

> **For agentic workers:** execute per slice as briefed by the coordinator.
> Specs: `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md`
> (§1–§6, §9–§10a) and the engine in `lib/fantasy/engine/` (P1, 83 tests).
> Checkboxes track progress. NOT STARTED.

**Goal:** the fan-app Fantasy Hub — My Team (court squad builder), Players
(market), Leaderboards, News, Rules — reachable from the league page's new
Fantasy tab, running on live Fantasy/<sport>/<season> data.

**Repo/branch:** fan `infinite_sports_flutter`, `zaya-fantasy`.

**Test bed strategy:** `Fantasy/Futsal/15` seeded by the coordinator from real
Season 15 rosters/stats using the engine's own opening-price math
(`tool/seed_fantasy.dart`, slice P3a task 0). Launch data for season 16 is a
re-run of the same tool later; test squads get wiped before launch.
`Config.lockOverride: 'open' | 'locked' | 'auto'` (test bed seeds `'open'`)
lets the owner edit squads even though all S15 dates are past; `'auto'` is
the production behavior (engine gameweek lock).

**House rules (hard gates):** streams/`once()` only — RTDB `.get()` banned;
light+dark via colorScheme (fantasy accent = gold in dark, primary red in
light, hub banner card is a dark gradient in BOTH themes with the gold
wordmark `assets/fantasy/fantasy_logo.png`); tappable names never underlined;
names wrap, never ellipsize; content scrolls clear of the glass navbar
(`base + MediaQuery.paddingOf(context).bottom`); single fade reveal, no
piecemeal loading pops; session caches for instant revisits; photos never
gate content (initials avatar fallback); celebrations/counters 150–350ms,
respect reduced motion, never replay on stream reconnect.

---

## P3a — Data layer, hub scaffold, Rules tab, entry points

- [ ] **0 (coordinator).** `tool/seed_fantasy.dart`: pure-Dart CLI (imports the
  engine only) that reads S15 lineups + per-game stats via REST, computes
  per-position opening prices with `openingPrices()` (rookies → 6.0), maps
  registration positions (GK→GK, D→DEF, M/S→ATT), marks guests ineligible,
  and PUTs `Fantasy/Futsal/15/{Config, Players}` (admin token arg).
  Config = `FantasyConfig.futsalDefault().toMap()` + `lockOverride: 'open'`.
- [ ] **1. Models + service** (`lib/fantasy/data/`): FantasyPlayer
  (id=name, position, priceTenths, eligible, teamName), FantasyService —
  watchConfig (→ engine `FantasyConfig`), watchPlayers, watchMySquad /
  saveMySquad (`Squads/<uid>`, engine `FantasySquad.toMap`), gameweeks from
  the season's schedule dates via engine `deriveGameweeks` + lockOverride.
  Pure parsers + tests (RTDB Map/List coercion as always).
- [ ] **2. Hub scaffold** (`lib/fantasy/hub/fantasy_hub_page.dart`): banner
  (dark gradient + gold logo), 5 tabs (My Team · Players · Leaderboards ·
  News · Rules), deadline countdown chip in the header (league timezone,
  absolute time shown), placeholder bodies for not-yet-built tabs, single
  fade-in once config+players arrive.
- [ ] **3. Rules tab**: rendered FROM the live `FantasyConfig` (never
  hard-coded numbers): how-to-play, per-position scoring table, BPS weights
  list ("published formula"), deadlines + countdown, transfers (2 free, bank
  7, −4 worked example), chips, pricing explainer, eligibility, short FAQ.
- [ ] **4. First-open walkthrough**: 3–4 swipeable cards (court art mock not
  needed — use `fantasy_logo_regal.png` + text), shared_preferences flag,
  skippable, never reshown.
- [ ] **5. Entry point**: league page gains a **Fantasy** tab (futsal, when
  `Fantasy/<sport>/<season>` config exists — stream-gated) opening the hub.
- [ ] **6. Verify:** analyze clean, full suite green, no `.get(`, owner build.

## P3b — My Team: court squad builder (the centerpiece)

- [ ] Court view drawn in code (CustomPaint, theme-aware dark/light court):
  5 starter slots (1 GK / 2 DEF / 2 ATT) + bench strip ("Bench · 50%
  points"); player chips with initials-fallback avatar, name (wraps), price,
  and week points once live.
- [ ] Budget bar ($50.0M, tenths math from the engine), live remaining.
- [ ] Pick flow: tap empty slot → position-filtered picker (price sort);
  tap filled chip → bottom sheet (Make Captain / Make Vice / Swap / Remove /
  Details). Captain = gold ring + C badge ×2; vice = V badge.
- [ ] Validation via engine `validateSquad` — issues shown inline (over
  budget, formation, captain), Save disabled until clean; saves to
  `Squads/<uid>` and re-renders from the stream (self-echo safe).
- [ ] Locked state (lock passed and lockOverride auto/locked): same layout,
  controls swap to the compact live strip placeholder (live points wiring
  lands in P4/P6).
- [ ] Chips row (4 medallion assets): visual + "one per week, two sets"
  states data-modeled (TripleCaptain/BenchBoost selectable pre-lock;
  Wildcard/FreeHit full flows land with transfers in P3c).
- [ ] Transfers state (2 free, bank to 7, −4 each extra) shown once a saved
  squad exists and the week rolls — engine `transferCost` preview before
  confirming any post-first-save change.

## P3c — Players market + player detail

- [ ] Market list: search, position filter chips (All/GK/DEF/ATT),
  persistent sort (price/points/name), rows = avatar, name, team · pos,
  price, (points once finalized weeks exist), add/remove button honoring
  budget + formation.
- [ ] Player detail bottom sheet: photo, price, position, eligibility,
  season stats (from existing league stats), buy/sell.
- [ ] Risers & fallers strip (reads price-change log node; empty until P4
  repricing runs — graceful empty state).

## P3d — Leaderboards, mini-leagues, transparency

- [ ] Leaderboards tab: overall / gameweek scopes reading
  `Leaderboards` (functions-written; shows friendly empty state until P4)
  + gameweek podium top-3 design; current user's row pinned.
- [ ] Mini-leagues: create/join with 6-char codes under
  `Fantasy/<sport>/<season>/MiniLeagues/<id>` {Name, Owner, Code,
  Members/<uid>} — **needs a rules addition** (coordinator: members write
  own membership, creator writes league meta, public read; update both
  rules files + redeploy stage-1).
- [ ] Manager (user) profile squad view: others' current week only after
  lock (`PublishedPicks`), previous weeks from `History`; own squad always.
- [ ] News tab: card feed reading published news (empty state until P4/P5).

**Owner test moments:** after P3a → hub + Rules on phone; after P3b → build a
real squad against S15 players (the big one); P3c/P3d → market + leagues.

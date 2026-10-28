# Infinite Fantasy P4 — Server Functions Implementation Plan

> **For agentic workers:** execute per phase as briefed by the coordinator.
> Specs: `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md`
> (§4–§8, §12–§14), engine contract = `test/fantasy/fixtures/golden_gameweek.json`.
> NOT STARTED. TypeScript in `functions/` (fan repo), vitest, firebase-functions
> v2 — follow the styles of `insiders_watch.ts` / `support_*.ts` / `index.ts`.

**Goal:** the automatic heartbeat — locks, weekly finalization (points, BPS,
leaderboards, history, dream team), Monday repricing, pushes, and AI news
drafts. Everything recomputes from match data (self-correcting; attendance or
score edits re-settle automatically).

**The cross-engine contract:** Phase A ports the pure engine to TS
(`functions/src/lib/fantasy/`): config, scoring, BPS + tie-share, squad-week
(armband/bench tenths/auto-subs/chips), transfers rollover, gameweeks +
Pacific lock instants, repricing, stats mapper. The vitest suite MUST replay
`test/fantasy/fixtures/golden_gameweek.json` and reproduce every expected
number byte-for-byte — that file is the law; any mismatch is a port bug,
never a fixture edit.

**Phases**
- **A. TS engine port + golden replay** (pure lib + vitest; no triggers).
- **B. Gameweek lifecycle** — scheduled job (every 15 min): derive gameweeks
  from the schedule stream of `<Sport>/<season>/Date`, honor
  `Config.lockOverride` ('auto' only; 'open'/'locked' freeze the machine),
  persist `Fantasy/<sport>/<season>/GwState` {current, status, lockAtUtc};
  **at lock:** snapshot every `Squads/<uid>` → `PublishedPicks/<gw>/<uid>`
  (spec §9 anti-copy transparency).
- **C. Finalization** — triggered by match-day completion (all games of the
  gameweek's date reach Final status; listen like `index.ts` onMatchStatus
  does, plus a scheduled sweep as backstop): map games → PlayerGameStats
  (attendance node, default-present), score players, award BPS, score every
  manager's squad-week (chips honored; chip-set windows via `chipSet1EndGw`),
  apply transfer costs from the week's recorded transfer usage, then write:
  `History/<gw>/<uid>` (squad snapshot + totalTenths + breakdown),
  `Leaderboards` (the exact shape P3d documented), `PlayerTotals/<name>`
  {points, ownershipPct}, `DreamTeam/<gw>` (top GK+2DEF+2ATT, admin-
  overridable — never overwrite an existing admin edit), Dream Team news
  DRAFT (§13; auto-publish only per owner schedule config),
  `Analytics` counters (§14). Finalization is IDEMPOTENT and re-runnable:
  a score/attendance edit re-fires it and re-settles everything downstream.
- **D. Monday repricing** — scheduled (Monday 10:00 league time): per
  position, `repriceDeltas` from the finalized week's points (absents = 0),
  apply with floor/ceiling to `Players/<name>/priceTenths`, log
  `PriceChanges/<gw>` (risers/fallers strip feeds from it). Skips weeks the
  owner already repriced manually (flag).
- **E. Transfers accounting** — on squad save after the first gameweek
  completes: compute used transfers vs the previous locked squad, maintain
  `TransferState/<uid>` {free, used, chipPlayed}, rollover at lock
  (engine rules; wildcard/freeHit unlimited; freeHit squad restore after the
  week). Rules files gain TransferState (read own+admin, functions write).
- **F. Pushes** — deadline reminder (scheduled; config
  `Fantasy/.../Config/Reminder` {enabled, hoursBefore|fixed time, template} —
  owner-editable, Manager UI in P5; FCM via `lib/fcm.ts` patterns; send-now
  callable, admin-gated via /Admins) and the weekly recap push after
  finalization ("GW3: you scored 41, moved to #4, top score 52") to each
  manager with a squad.
- **G. AI news drafts** — after finalization, generate 2–4 short stories
  (hot/cold streaks, price movers, dream team) via ANTHROPIC_API_KEY
  (claude-haiku, same call pattern as `support_joke.ts`; playful-never-mean
  enforced in the system prompt; bank fallback = skip drafting, never block
  finalization) → `News/Drafts` queue for Manager approval (P5). Nothing
  auto-publishes except the owner-scheduled Dream Team post (§13).
- **H. Deploy + live rehearsal** — coordinator deploys; rehearse against the
  S15 sandbox by flipping `lockOverride` to 'auto' on a COPY season node
  (never the owner's live sandbox while he tests), replaying finalization
  over the real S15 games, and comparing spot totals to the Dart engine.

**Ground rules:** Admin SDK only (no rules exposure beyond the documented
read nodes); every number in tenths ints; league timezone math identical to
Dart (goldens cover DST edges); all jobs log through `firebase-functions/logger`
with enough context to debug a disputed score; secrets via defineSecret.

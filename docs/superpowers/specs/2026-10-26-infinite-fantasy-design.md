# Infinite Fantasy — Design (owner-locked)

**Date:** 2026-10-26 · All decisions made with the owner across planning sessions.
FPL-style fantasy for the futsal league first; the engine is config-driven so
Basketball and Flag Football are later scoring tables, not rebuilds.

## 1. Format

- Open to every signed-in user, free. Brand name: **Infinite Fantasy**.
- Each fantasy manager builds a squad of **real futsal players across all teams**;
  shared ownership (no draft). Points come from real per-game stats (the box-score
  pipeline), **live during games**.
- Season-long overall leaderboard + weekly leaderboards + **private mini-leagues**
  with join codes.

## 2. Squad & formation

- **7 players**: starters = 1 GK + 2 DEF + 2 ATT; bench = **1 DEF + 1 ATT** (fixed).
- **Captain ×2 points; Vice-captain** inherits the armband when the captain has no
  appearance.
- **Bench scores HALF points** normally. **Auto-substitution:** a starter with no
  appearance is replaced by the matching-position bench player, who then scores
  FULL that week (instead of half).
- No bench GK by design — the keeper pick is a weekly bet.

## 3. Fantasy positions

- Every league player carries a fantasy position: **GK / DEF / ATT** (no midfield).
- Defaults from registration position (GK→GK, Defender→DEF, Striker→ATT,
  **Midfielder→ATT by default** — owner-overridable per player).
- Manager can reassign any player pre-season or mid-season ("protest" flow); the
  change applies **at the next unlock**. Squads invalidated by a reassignment are
  flagged and their owners pushed to fix before lock.
- **Price on reassignment (owner Q, 2026-10-28): unchanged at the switch.**
  The position-relative Monday repricing then adjusts them against their NEW
  position's peers automatically, and the owner can override instantly. The
  Manager position editor (P5) shows a **suggested price** for the new
  position (their stats re-scored and re-percentiled, same math as openers)
  next to the current one — one tap to apply or keep. No automatic jumps:
  predictability for the people already holding the player.
- **Guests:** eligibility flag per player. Guests play and their real stats count,
  but they are **not selectable** in fantasy. A one-tap **Promote** makes them
  permanent → they enter the market next gameweek with a starting price.

## 4. Budget & prices

- Budget **$50M** per manager. Prices **$4.0M–$15.0M** in **$0.5M** steps.
- Opening prices computed from historical seasons' stats; true rookies ≈ **$6.0M**.
  Tuned so $50M ≈ two stars + solid middle + one bargain — never five stars.
- **Weekly repricing (Mondays), performance-based** — not transfer-demand-based:
  movement derives from the player's fantasy points that week, weighted by where
  the points came from for their position, and **relative to peers in the same
  position** (an ATT's price move considers how other ATTs scored). ±$0.5M steps
  within floor/ceiling.
- Buying and selling always at **current price** (no FPL profit-split accounting).
- **Owner override:** Manager can edit any price at any time; play continues.

## 5. Gameweeks, lock, transfers

- Gameweeks derive automatically from the real schedule (one per match day).
- Editing window **Monday → Sunday 3:00 PM** (configurable constant); locked
  through the games; reopens Monday. Late joiners start scoring from their first
  completed gameweek.
- Deadline is anchored to the **league's timezone** (America/Los_Angeles,
  stored in config) — never the phone's timezone. Countdowns everywhere also
  show the absolute lock time ("Sun, Oct 19 · 3:00 PM").
- **Transfers: 2 free per gameweek, bankable up to 7; −4 points per extra
  transfer** beyond the allowance (applied to that week's score).

## 6. Chips (one per gameweek; two sets per season)

| Chip | Effect |
|---|---|
| Triple Captain | Captain ×3 that week |
| Bench Boost | Bench earns FULL points (instead of half) that week |
| Wildcard | Unlimited free transfers, permanent rebuild |
| Free Hit | Unlimited transfers for one week; previous squad returns after |

Set 1 is usable **GW1 through a configurable gameweek (default GW6)**; unused
set-1 chips expire. Set 2 runs **from the next gameweek through the end of the
season INCLUDING playoffs** (quarterfinals/semis/final count as gameweeks) —
owner decision 2026-10-27. UI shows per-chip availability counts ("1 left")
rather than only the one-active-per-gameweek rule, to avoid confusion.

## 7. Scoring (futsal — FINAL, owner-approved)

| Action | GK | DEF | ATT |
|---|---|---|---|
| Plays (appearance) | +1 | +1 | +1 |
| Goal | **+10** | +6 | +4 |
| Assist | +5 | +4 | +3 |
| Clean sheet | +8 | +5 | +2 |
| Every 2 saves | +1 | — | — |
| Penalty save | +5 | — | — |
| Penalty miss | −2 | −2 | −2 |
| Every 2 goals conceded | −1 | −1 | — |
| Yellow / Red | −1 / −3 | −1 / −3 | −1 / −3 |
| Own goal | −2 | −2 | −2 |
| DPL threshold bonus | — | 5+ DPL → +2 | 7+ DPL → +2 |

- **Clean sheet eligibility (explicit):** a player earns the clean sheet when
  they are **present (Plays)** and their team concedes 0 in that game — same
  definition the league's real Clean Sheets stat already uses. Futsal has no
  per-minute tracking, so presence is the whole condition; the Rules page
  states exactly this and nothing more.
- **Bonus points 3/2/1** to the top three performers per match, ranked by a
  published deterministic formula (weighted goals/assists/saves/DPL/CS, cards
  negative). The formula appears on the Rules page — no black box.
- All scoring recomputes from match data (same self-correcting model as Clean
  Sheets): score edits after a game automatically re-settle fantasy points.

## 8. Attendance (new Live Scoring step — prerequisite for Plays/auto-sub/VC)

- Live Scoring shows the game roster, **everyone defaulted to PRESENT**; the admin
  taps who is absent. Players can be re-presented anytime ("arrived out of nowhere").
- **Guard prompt:** recording a stat for a player marked absent asks:
  *"<Name> is marked not present."* → **[He's here — mark present & record]** /
  **[My mistake — cancel]** (cancel returns to the player picker).

## 9. Transparency & social

- Everyone's points and ranks are public.
- A manager's **current-week picks are visible to others only after lock**
  (anti-copying); before lock, visitors see the previous week.
- **Full history:** every manager's week-by-week squads (GW1, GW2, …) browsable
  from their profile, forever.

## 10. Fantasy Hub (fan app)

Tabs: **My Team** (squad builder: formation slots, budget bar, captain/vice,
chips, transfer state) · **Players** (market: prices, ownership %, risers &
fallers feed) · **Leaderboards** (overall / weekly / mini-leagues + join codes)
· **News** · **Rules** (see §10a).
Entry: the league page gains a **Fantasy tab** (alongside Fixtures / Table /
Playoffs / Player Stats / Teams) whose content is the hub entry card; plus the
Search hub and a home banner in season. **Dream Team of the Week** (the
gameweek's top-scoring 1 GK + 2 DEF + 2 ATT on a golden court) displayed in the
hub — same data node as the weekly News post (§13), admin-overridable.

UI decisions adopted from the design round (2026-10-27):
- **My Team, editable vs locked = same layout.** When games go live, the
  budget/transfer controls swap for a compact live strip (live points ·
  overall rank · places gained) — players never learn two screens.
- **Bench on its own surface** labeled "Bench · 50% points"; during a boosted
  or auto-subbed week a bench player shows raw → counted ("7 → 3.5") so the
  math is never mysterious.
- Captain assignment via a bottom sheet on any player tile (Make Captain /
  Make Vice / Swap / Details); captain gets a gold ring + ×2 badge.
- **Market sort is persistent** across filter changes; player detail opens as
  a large bottom sheet for quick compare-and-buy.
- **Leaderboards top out with a gameweek podium** (top 3), current user's row
  pinned/highlighted wherever they rank; join-code entry has a paste button
  and shows a league preview before joining.
- The futsal court is **drawn in code (theme-aware)**, dark subtly-lit court in
  dark mode / light equivalent in light mode — never a baked image that only
  works on one theme.

## 10b. Fantasy team names & moderation (owner add, 2026-10-27)

- Every manager names their fantasy team (3–30 chars, stored at
  `Fantasy/<sport>/<season>/Managers/<uid>` with `NameFlagged`); shown on
  leaderboards and profiles. A basic bad-word check runs at save.
- **Owner moderation:** flagging a name (Manager section, P5) **freezes that
  user's fantasy** — the hub gates My Team behind "your team name was flagged;
  choose a new name." Renaming (an actual change, enforced by rules) clears
  the flag and unlocks; the owner can re-flag if the new name is still bad.
- Rules tab carries a **"Spotted an issue? Send feedback"** button into the
  existing support-ticket form.
- Hub entries: league-page Fantasy tab (home) + Search hub card + in-season
  home banner.

## 10a. Rules page & player education (owner requirement)

Players must always have one obvious place to learn and re-check how everything
works. The **Rules tab** is that place:

- **Rendered from the live engine config, not hand-written text** — the scoring
  tables, chip list, transfer allowance, budget, price range, and deadline time
  shown to players come from the same config the engine scores with. If a value
  is ever tuned, the Rules page updates itself; it can never drift from reality.
- Contents, in plain language with examples:
  - **How to play** — build 7 within $50M, 1 GK + 2 DEF + 2 ATT start,
    DEF+ATT bench at half points, pick captain (×2) and vice.
  - **Scoring** — the full per-position points table (§7), the BPS 3/2/1
    formula spelled out, clean-sheet and conceded rules, DPL bonus thresholds.
  - **Deadlines** — the weekly lock schedule (Mon open → Sun 3 PM lock), with
    the **next deadline countdown** shown right on the page.
  - **Transfers** — 2 free/week, bank to 7, −4 per extra, worked example.
  - **Chips** — what each of the four does, one per week, two sets, set-1
    expiry date shown once configured.
  - **Prices** — how Monday repricing works in plain words ("play well versus
    other players in your position and your price rises"), buy/sell at current
    price.
  - **Auto-subs, captain & vice, bench** — when the bench scores full vs half.
  - **Eligibility** — guests aren't selectable until promoted; position
    changes apply at the next unlock.
  - **Short FAQ** — late joiners, absent players, voided weeks, mini-leagues.
- **First-open walkthrough:** the first time a user enters the Fantasy Hub they
  get a short swipeable intro (3–4 cards: build your 7 → captain ×2 → deadline
  Sunday 3 PM → points come from real games), skippable, never shown again;
  Rules tab is always a tap away afterward.
- **Contextual help everywhere it matters:** deadline countdown pinned in My
  Team; a "How scoring works" link next to points displays; the transfer
  screen states remaining free transfers and the −4 cost before confirming.

## 11. Match-page Fantasy tab

Live match pages gain a **Fantasy** tab: real-time fantasy points earned in that
game ("+6 — player (D)"), the viewer's own squad members highlighted with a
running "you're earning +N" chip, and a button to the Hub.

## 12. Pushes & comms (all automated, all owner-controllable)

- **Deadline reminder** (default Sunday noon to managers with unchanged squads):
  time, message template, and on/off editable in Manager; **Send now** manual
  push always available.
- **Weekly recap** push + screen: "GW3: you scored 41, moved to #4, top score 52."
- Lock/unlock + price-change notices as lightweight hub badges, not pushes.

## 13. News feed (AI-drafted, owner-published)

- After each gameweek the AI drafts 2–4 short stories from real stats (hot
  streaks, cold streaks, price movers) — **tone: playful, never mean** (enforced
  in the generation prompt).
- Drafts land in a **Manager approval queue**: publish / edit / discard. Nothing
  auto-publishes (except the scheduled Dream Team post below, which the owner
  explicitly opts into).
- Owner can compose posts directly (injuries, rumors, announcements) with photo
  and optional "notify fans" push. Uses the existing ANTHROPIC_API_KEY secret.
- **Dream Team of the Week post (owner add, 2026-10-27):** after each gameweek
  finalizes, the system builds a **Team of the Week** post automatically — the
  top fantasy scorers in formation (**1 GK + 2 DEF + 2 ATT**) on a **golden
  court graphic**, with each player's week points. It is a structured post the
  app renders natively (crisp in both themes), not a server-generated image.
  - The post and the hub's Dream Team display read the **same stored node**,
    so a correction fixes both.
  - **Owner control:** the draft sits in the approval queue where the owner
    can swap any player (error correction), edit the text, publish now, or
    discard. Optionally, a **schedule** can be set (e.g. "auto-publish Tuesday
    10 AM") — the post publishes itself at that time unless the owner already
    acted on it; the schedule, like everything else, is owner-editable in the
    Manager Fantasy section, and auto-publish can be turned off entirely.

## 14. Analytics (Manager dashboard card)

Custom in-house counters (no external console): fantasy sign-ups, weekly active
managers, squads set per week, edits per week, inactive-manager count. Live.

## 15. Manager app — ONE Fantasy section

Single drawer section containing: positions & eligibility editor (incl. guest
Promote), price table with overrides, gameweek controls (lock status, finalize,
void-a-week), reminder/push config + send-now, news composer + approval queue,
analytics dashboard.

## 16. Engineering ground rules

- Engine is a pure, heavily-tested library; per-sport scoring/pricing config
  (futsal ships; Basketball/FF = new tables later).
- iOS parity: streams/`once()` only, no RTDB `get()`; iOS-risky items get a
  "verify on simulator" PR line. Realtime-everywhere; light+dark; wrap-don't-
  ellipsize; navbar scroll clearance; dialog-controller rule.
- Motion: celebrations/counters in the 150–350ms range, respect the OS
  reduced-motion setting, and **never replay a celebration on stream reconnect
  or widget rebuild** — animate only on a genuine value change.
- **Ships alongside the database security lockdown** (separate workstream):
  fantasy data (squads, picks, history) is born under locked-down rules —
  per-user write, public read where the design says public, admin override.
- Prizes: nothing hardcoded; owner announces whatever, whenever.

## 17. Build phases

- **P0** Security rules lockdown (parallel epic, own spec).
- **P1** Pure engine: scoring, BPS, pricing, gameweek derivation, transfer/chip
  state machine — exhaustive tests.
- **P2** Attendance capture in Manager Live Scoring (+ guard prompt).
- **P3** Fan Hub: squad builder, market, leaderboards, history, profiles,
  config-rendered Rules page + first-open walkthrough (§10a).
- **P4** Functions: lock/unlock jobs, weekly finalization, repricing, pushes,
  recaps, news drafting.
- **P5** Manager Fantasy section (admin + news + analytics).
- **P6** Match-page Fantasy tab, Dream Team, home banner, polish.

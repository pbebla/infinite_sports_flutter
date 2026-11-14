# Fantasy follow-ups carried over from the build notes (2026-11-04)

The working notes from every fantasy build (`.superpowers/sdd/*`, never in git) were deleted on the owner's OK on 2026-11-04. These are the leftover items they recorded, copied verbatim, so nothing is lost.

- Each item was judged minor or out of scope at the time. Some may have been fixed since by a later plan, so check the code before acting on one.
- The big decisions live in the committed plan, spec and rulings docs under `docs/superpowers/`.

## Most important (security / launch)

- **Stage-2 rules flip:** under the stage-1 root read, user data is world-readable (pre-existing, confirmed live), and new fantasy nodes inherit it, so draft `Squads/<uid>` are public before the lock. The fix is the stage-2 flip with the Phase-B store build. (Live audit C1/I1)
- **S15 test fill vs S16:** fake S15 data is visible to all fans once S16 exists without a Fantasy Config. Before launch, run `--clear` with the latest backup, or create `Fantasy/Futsal/16/Config` before the league flips. (Live audit I2)
- ~~**Firestore ruleset** is the 2018 allow-all default.~~ **Closed 2026-11-05** (owner OK): `firestore.rules` denies every client; ruleset 81ce9361 released and verified (anonymous read → 403). The database was empty and neither app ever used it. Rollback ruleset: c512b5df-3d3d-443f-89ce-9fbe37e6ea38. (Live audit M1)
- **App Check:** callables accept invalid tokens only because enforcement is off, and neither app ships firebase_app_check. Don't enable enforcement without a provider. (Live audit I4)
- **Dead code still awaiting an OK:** `watchPriceChanges` / `latestPriceChangesFromNode` / `FantasyPriceChange`, plus two stale comments. (`market_player_sheet.dart` was deleted 2026-11-04.) (Live audit M3)

## .superpowers

- Task 10: minor (deferred): fantasyManagerSquadProvider rebuilds on any GwState write — use selectAsync(publishedGwForCurrentWeek) (fantasy_admin_provider.dart:151)
- Task 10: minor (deferred): myUserFromNode bare catch → add debugPrint (user_service.dart:775-782)
- Task 10: minor (deferred): Free-transfer fallback hard-codes futsalDefault — take season config (fantasy_profile_models.dart:314) — carried into T11 dispatch
- Task 10: minor (deferred): combineLatest2 placement in 950-line service + sequential onCancel (fantasy_admin_service.dart:680,743)
- Task 10: minor (deferred): UserContact.== hand-rolled list compare; 'locked'/'finalized' literals; test file >80 cols
- Task 1: minor (deferred): finalize_core.ts:763 team match uses === vs mapper's String(...) — align
- Task 1: minor (deferred): Games (team schedule) vs GP (stats by name) can disagree for guests/team changes — fan parser must not assume Games.length == GP (carried into T4/T5)
- Task 1: minor (deferred): roundTenths Math.round vs Dart round on negative halves (server-only today)
- Task 1: minor (deferred): finalize reads whole PlayerWeekStats for GP (fine at season scale)
- Task 2: minor (deferred): Watchlists/$uid whole-node writes unvalidated (scalar/unbounded map) — add hasChildren()/cap at $uid
- Task 2: minor (deferred): writeIfAbsent concurrency path untested (repo pattern)
- Task 2: minor (deferred): map auth/invalid-uid to empty answer (defensive)
- Task 2: minor (deferred): user_contact.test.ts:52 `as never` cast on request
- Task 11: minor (deferred): flagged pill + _pending duplicated across list/detail; header recomputes realName
- Task 11: minor (deferred): free transfers left ignores FreeSwaps + active Wildcard/FreeHit (informational label)
- Task 11: minor (deferred): case-insensitive tie test doesn't bite (all names uppercase)
- Task 11: minor (deferred): email row grows after the fade reveal (fixed-height placeholder)
- Task 11: minor (deferred): hidden footer "no match" item; 930-line detail page; FantasyTeamNamesPage name misleading
- Task 11: minor (deferred, out-of-scope): ~36 other .valueOrNull uses in Manager lib/ui/fantasy pages may show errors as facts — candidate bug-class sweep (separate task)
- Follow-up twin sync: complete (Manager 9257ff7..3d8b1d4, review clean). minor (deferred): added scoring_twin_test.dart (kept — it pins the twin); run `flutter analyze lib test` before merge. (saves/conceded <2 emit no line by design — 0 points.)
- Task 3: minor (deferred): --clear doesn't check TestFill marker still matches the backup (late second clear reverts later edits)
- Task 3: minor (deferred): apply window — Players not re-checked vs snapshot; pause not re-checked during PUTs
- Task 3: minor (deferred): token in URL query (prefer Bearer header); JSON.parse error could echo refresh-token snippet; hard-coded public client secret (scanner)
- Task 3: minor (deferred): duplicated types FillWeekPlan/FakeManagerDef/FillMarketEntry vs rehearse_s15
- Task 3: minor (deferred): determinism test is on buildWritePlan not the replay; realManagersOf untested
- Task 3: minor (deferred): late-skipped real manager's TransferState still written; hard-coded "never written" line; rehearse_s15.ts ~1970 lines
- Task 3: minor (deferred, worth fixing before --clear is ever used): path guard is a denylist — restrict --apply/--clear to EXPECTED_NODES + test-NN children + TestFill (Watchlists/MiniLeagues/ScheduledPushes/Analytics currently pass)
- Task 3: minor (deferred): GET guard no '..' normalisation (reads only); takeSnapshot readOnly wiring untested (manual runs only)
- Task 4: minor (deferred): NextGame.timeText doc wrong + test hides "0 PM" legacy case — callers MUST pass startHour to watchGames (carried into T5/T6)
- Task 4: minor (deferred): resolver has no negative memo (31 reads per call when current sport has no Fantasy)
- Task 4: minor (deferred): watchPlayerWeekStatsFor merge logic untested; cache keyed by name only (subset overwrite → mild pop-in)
- Task 4: minor (deferred): setWatchlisted writes untrimmed name; sync vs async failure modes
- Task 4: minor (deferred): _int vs _optInt duplicate coercion; nextGameForTeam untrimmed compare; 3 hand-rolled season resolvers (point search hub at resolver later)
- Task 5: minor (deferred): star pops in before the hero fade; single week-listener error leaves page empty (stream waits all weeks); untested onError/config-null paths; no offline timeout; 'No game' string coupling (add MatchRow.hadGame); tab state resets on switch; 1032-line page + circular import with hub (use builder seam); weak underline test; rosterRowFor first-match vs ambiguous-null.
- Task 5: minor (deferred, fix before merge): N1 games session cache written while start hour unknown → stale "0 PM" briefly after a failed-then-successful hour read (gate _gamesSession on a real hour); session-cache path untested
- Task 5: minor (deferred): getStartHour is a once() read (pre-existing); nav-bar icon contrast now platform default (verify on Android dark)
- Task 6: minor (deferred): sort pills' InkWell splash hidden under opaque container (wrap in transparent Material)
- Task 6: minor (deferred): "All" + ★ can both look selected (★ is a combinable toggle) — tell owner
- Task 6: minor (deferred): sort arrow ↓ vs mockup "Price ↑" (one-line flip if owner wants)
- Task 6: minor (deferred): reveal has no ceiling (non-essential feed never emitting holds skeleton) — same as profile page
- Task 6: minor (deferred): start-hour/games logic duplicated with profile page + separate session caches; no test that hour reaches watchGames
- Task 6: minor (deferred): isDark?black:onPrimary copied 8+ times (extract fantasyOnAccent); stale comment fantasy_parsers.dart:277; PriceMovers.isEmpty test-only; players_tab ~1185 lines; format churn
- Task 8: minor (deferred, cheap — fix in final wave): secondaryName repeats when team name == real name (suppress case-insensitively)
- Task 8: minor (deferred): light-mode own-row red text on 20% red wash ~3.9:1 (check on phone); viewer title = team name vs row real name; loose own-row/pinned assertions; managerDisplayName semantics changed (mini-league only); movement cell no a11y label
- Ruling: (a) cross-file extraction of the gameweek wiring (banner, hub, profile page, profile source) is deferred to the final whole-branch fix wave — it spans files owned by Tasks 5/7 — this round only adds tests for the real branch — cost if wrong: duplication survives one more review step.
- Task 9: minor (deferred): cold serial first open (pre-warm resolver; move none-cache into resolver); _runResolve sync-throw ordering latent bug; failed resolve cached as "no season" 5 min; watchRosters fan-out + whole-node streams per open; manager-only gated on gameweeks; _viewTeam silent on null config; line >80 cols profile_page.dart:829; clearSessionCaches not wired to sign-out (all fantasy caches)
- Task 9: minor (deferred, one-line — final wave): _recompute re-caches decision after a real null Config (guard `real && !_configAbsent`)
- Task 9: minor (deferred): seeded decision only refreshes when all 3 feeds real; log-test substring weakness; decision-wait timeout unlogged
- Parked (final, no second wave): banner stays visible on Config error → hub could sit on skeleton (Config is public-read; needs a bad rules deploy) — Ruling: accept, low likelihood — cost if wrong: hub skeleton until Config readable.
- Parked: stale doc fill_test_season_logic.ts:46-47 ("other nodes written" — now refused) — Ruling: doc-only — cost: misleading comment.
- Parked: FantasyLeagueGamesFeed caches seam data (test-only) — Ruling: production unaffected — cost: possible test cross-talk.
- Task 7: minor (deferred): past-week viewer departed player → SnackBar (consistent with News); _NeedsNewSpotStrip names not tappable; three opener typedef shapes; stale comment fantasy_hub_route.dart:39; hub↔profile circular import; _openPendingPlayer side effect in build; pre-existing analyzer info mini_leagues_test.dart
- Ruling: park "starter stored as Manual before the lock can't be restored" — unreachable: the catalog has never existed live and no Manager build with the Badges page was ever installed before the lock — cost if wrong: a starter stuck Manual, fixable by editing Fantasy/BadgeCatalog/<id>/Kind in the DB.

## .superpowers

- Task 1: minor (deferred): no test pins "Via: 'cash' still reads active" (add accessRecordFromNode({'Status':'active','Via':'cash'}).isActive)
- Task 1: minor (deferred): process-chatter comment at test/fantasy/fantasy_access_test.dart:350 ("The brief spells the accessor db")
- Task 1: minor (deferred): allText test helper ignores Text.rich spans (pre-existing helper)
- Task 2: minor (deferred): probe has no case for an ADMIN writing an AccessClaims row with Method cash (now rejected by .validate; pinned statically)
- Task 3: minor (deferred -> carried into Task 4): amountCents not validated in recordCashGuarded/cashRecord; Task 4's dialog must reject <= 0
- Task 3: minor (deferred): recordCashGuarded passes resolution 'approved' even with no actedClaimKey (unused; documented)
- Task 4: minor (deferred): _seedAmount sets controller text during build (works, tested)
- Task 4: minor (deferred): show-error-once rule duplicated (cash_payment.dart / grant_access_sheet.dart); two near-identical FilledButton.icon blocks in the sheet
- Task 4: minor (deferred): blank prefill with no hint while config loads/errors
- Task 4: minor (deferred): formatAccessDollars(0) returns "$"
- Task 4: out-of-scope (deferred): price > $1,000 already stored must be lowered before any other mode-card save; Grant sheet success text omits the amount (its confirm shows it)
- Task 4: out-of-scope (deferred): registration money parsers (adjust_payment_dialog.dart, registration_models.dart) use plain double.tryParse ("1e3" accepted) — different feature
- Final: out-of-scope (deferred): Manager Analytics "Fantasy sign-ups" stat-tile grid overflows at 360 px under the test font (childAspectRatio 1.9); the new 360 px test tolerates only bottom overflow

## .superpowers

- Task 1: minor (deferred): Dart saleBaselineFromNode .toInt() on NaN/Infinity would throw (TS guards isFinite); RTDB can't store these
- Task 1: minor (deferred): TS validateSquad with NaN realizedTenths never flags overBudget (callers must pass realizedOf-derived ints)
- Task 1: minor (deferred): saleBaselineFromNode treats non-numeric ForGw as missing (stricter than brief; undocumented)
- Task 1: minor (deferred): squad.dart comment / squad_test spending() line > 80 cols (files were not format-clean before)
- Task 3: implementer notes: baselineNodeOf in squad_integrity.ts (circular import otherwise); existing Baselines keys are a 4th uid source; Dart realizedNowTenths must treat current <= 0 as missing (carry into Task 6); pre-existing (deferred, for final review): after a first finalize from live Squads, a sweep within 24h could still claim PublishedPicks/<gw> from squads already restored after a Free Hit; stage1 world-readable Baselines (same as TransferState).
- Task 3: minor (deferred): isRtdbKey drops ids the server treats as held while the app treats them as new (forged/legacy ids only); extra full-node reads in publishSaleBaselines; no save-trigger test with a carried total; finiteIntOf duplicates realizedOf logic; ragged header line orchestration.ts:24; probe "PASS … allowed (HTTP 200)" wording
- Task 3: minor (deferred): no lock-sweep test seeding GwState {gw,'open'|'locked'} with Baselines assertions (guard proven by trace)
- Task 4: minor (deferred): no test for writeIfAbsent returning false after the pre-read; no test for forged+overBudget getting the preview; banner OverTenths may be stale up to 15 min after a still-over save
- Ruling: fold in review minors: correct the rules_contract comment (trigger also stands down under a 'locked' override; counts under the open override only while GwState says open) and tighten the .validate pin to an exact toBe; the 'locked'-override-not-in-rules gap, no recount after an Invalid week, no orchestration-level wiring test → deferred (ledgered).
- Task 5: minor (deferred): rules don't enforce an effective 'locked' override (REST-only, pre-existing); no recount after an Invalid week (ruling-mandated); no orchestration-level test of the recounted cost into TransferCosts/<gw>; support_mail.test.ts stderr noise (pre-existing)
- Task 5: minor (deferred): reopen clause has no upper end (GwState stuck non-open past the NEXT lock → REST saves accepted after lockN+1; season end: accepted, uncounted, harmless); unprobed 'locked'/no-lockAtUtc + open override case (fails closed); gap saves don't stamp SavedGw (reminder may misfire); test comment nit in transfers_orchestration.test.ts ("untouched" alpha)
- Task 5: out-of-scope (deferred, for final review): late first finalize prices this week's cost from max(next week's stored count, mixed recount) → can overcharge; pre-existing ChipPlayed trigger-vs-lock race; late finalize can overwrite gap saves (pre-existing)
- Task 6: implementer notes (deferred): an existing-but-unreadable Baselines node → degraded (can't save until the next lock rewrites it; only the server writes it); no retry after a baseline read error (reopening the hub re-subscribes); standalone squad builder gets no sale context.
- Task 6: minor (deferred): lock-boundary Timer re-feed and "baseline before draft" order untested
- Task 7: implementer notes (deferred): market rows show the market price (only the add/disabled state follows the draft); lib/fantasy/hub/market_player_sheet.dart is unreachable in the app (deleting needs the owner's OK — deletion rule); ruling 2 tested on the draft only; ruling 5 — no seam to test watchSaleBaseline without Firebase (none added); the standalone builder acts as a first squad.
- Task 7: minor (deferred / owner): market_player_sheet.dart unreachable in the app — deletion needs the owner's OK; ruling-2 hub wiring has no sabotage check (draft-level only)
- Task 7: minor (deferred, for final triage): market sheet / market list / profile still show the "Over budget — free up some money first." add-verdict (red price, disabled Add) from unready money (no figure); picker rows price via addCostOf and dim from unready room (no figure printed); picker header snapshot stays "— left" if money becomes ready while open; debug assert could fire if a stream adoption makes a listed candidate owned while the picker is open (debug only); "— left" placeholder uses the same weight as the real figure
- Task 8: minor (deferred): Prices ("Every Monday prices move") and Selling ("Prices change on Monday morning") overlap (brief-mandated); 'current price' findsNothing assertion is broad
- Task 9a: minor (deferred): fill tool's SquadAlerts allowlist — a future replay producing a PREVIEW alert would let --apply replace the whole live SquadAlerts node (backup + --clear recover); emulator scenario uses owner edits not the Monday reprice job; client_draft_money.ts is a third copy of the draft money (parity test is the guard)
- Ruling: no final fix wave — the reviewer requires no code change; Important 1-4 are rollout/process items carried to the owner; minors (guest re-add via picker, watchSaleBaseline retry, preview from the Players write trigger, delete-before-lock forfeits losses, public realizedTenths note, "$-0.5M" formatting, finiteIntOf duplication, gap-save reminder) deferred — cost if wrong: a rare UX gap until a follow-up.

## .superpowers

- Task 1: minor (deferred): tautological "finalize publishes exactly the core's…" test (only the junk pass-through is real content)
- Task 1: minor (deferred): double-game test comment has a literal "[firstStatus]" placeholder
- Task 2: minor (deferred): kickoff Board check partly circular (expected O uses live's own W; R/M unchecked at kickoff); contract lacks a manager-only-in-a-voided-week case and a player-missing-from-a-form-week case; BreakdownRow defined twice (export from finalize_core)
- Task 3: minor (deferred): stale LiveBase race during an older-week correction (tiny window; documented); void toggle on a settled week rebuilds LiveBase twice; whole-season Date read per scoring event; clock-skew note for coalescing header
- Task 3: minor (deferred): heal could tombstone a few seconds early in a <0.1%/match-day race (finalize's own settle rewrites it; no data harm) — optional "finalize done" marker would remove it; comment "outlasts any in-flight finalize" overstates
- Task 3: minor (deferred): widened 2c does a full recompute every 15-min sweep on a partly-final match day (eventAtMs=now defeats coalescing) — bounded to match days
- Task 4: minor (deferred): combineLatest2 never completes after an official-side error (harmless for .listen); per-subscriber re-parse of Players; service wrappers untested (repo convention)
- Task 4: minor (deferred): coalescing is best-effort across native-message turns — a one-frame new-Meta/old-Board mix is still possible (heals next frame); a full fix needs a Gw stamp on Live/Board checked by the overlay
- Task 5: minor (deferred): auto-sub not rendered (no copy in brief); _revealed set inside build (idempotent); dark-mode movement colours not asserted
- Task 5: minor (deferred): live-feed partial failure reads as pre-kickoff (add `|| sources.liveSquad != null` to started); formation-mismatched locked picks dropped from the court (read-only "not placed" strip later); PublishedPicks week cache seeds a known-absent null (one-frame draft court)
- Task 6: minor (deferred): no fling test; stale home-banner header comment ("NO per-user state"); home banner opens 4 Live listeners + Voided for every signed-in user even without fantasy Config (start only once Config exists); hub vs home banner treat a failed Voided feed differently; pending pill can linger after a list shrink clamps to top; tint hue lerp; >80-col lines; no pending-order + pinned-row test; tab reopen not exercised with a real TabBarView
- Task 8: minor (deferred): no value equality/distinct on Manager live models (redundant rebuilds); failed Manager live feed never retries (non-autoDispose; fan feed retries); "never waits forever" comment overstates (per-manager reads unbounded); service wiring untested (repo pattern); per-manager live listeners kept for the session; raw official providers are a naming trap
- Task 7: minor (deferred): players_tab.dart:574 comment says "appended in its true place" (it's appended at the end); SteadyScrollTracker has no direct unit test; match-tab cold open starts FantasyScheduleFeed (whole Date node) — PR note
- Final: minor (deferred): 4 inline pt/pts copies in Manager prediction pages + fan transfer_dialogs pointsHitBody (correct, not routed through the helper); _listenSoft is a 5th listen variant; settle() on a sync-delivering stream (unreachable today); failed Meta with no own live squad still reads "waiting"

## .superpowers

- Task 1: minor (deferred): workingOn computed for every uid; guard boundary (SavedGw == gw+1) and unscored+firstWeek combo not pinned by a test
- Task 1: minor (deferred): settle gated on historyByUid non-empty — a week with nobody scored never runs the D1b union (pre-existing gate; known limit)
- Task 1: minor (deferred): rehearse_s15 ledger defines first week as lastLocked===null vs pipeline effectiveSquadAfterWeek(gw-1)===null — diverge for a gap-week manager; add a comment
- Task 1: minor (deferred): recordSquadSave catch path (unreadable prev squad) counts 0 but publishes tolerant pickIdsOf ids as CountFrom — app could count against ids the server didn't; publish ids:null there or soften the doc claim
- Task 1: minor (deferred): test (c) seeds post-GW1 TransferState instead of rolling GW1 then GW2
- Task 2: minor (deferred): rules_contract it() mixes the chip validate and the TransferState no-write guarantee — split for clearer failures
- Task 2: minor (deferred): contract test pins rule text only; regex behaviour proven by the uncommitted scratchpad emulator probe
- Task 3: minor (deferred): parity test doesn't pin the first-team link or Map-shaped nodes (Dart tests cover); draft getter's unplaced-pick inclusion unpinned
- Task 4: minor (deferred): feed error retracts a prior good answer and never re-subscribes (line reads "updating…" for that hub session; Save unaffected)
- Task 4: minor (deferred): squad_draft.dart:37-38 ~140-char comment line; chip_row _asksFirst reused as first-team gate (rename helper); 360px test never renders the longer Free Hit line; no test that the transfer subscription cancels on dispose
- Task 4: minor (deferred): hold checked only at tap time — if the count goes unknown while the Wildcard/Free Hit confirm dialog is open, "yes" still arms
- Final review (fable): With fixes — I1 `hidden` (pre-feature node) lets Wildcard/Free Hit arm on a possible first team; I2 chip-history read failure reads as "1 left" so a replayed spent Wildcard/Free Hit shows free while the lock voids it and charges transfers. Minors taken in the same wave: M1 no retry after feed error (copy claims activity), M2 silent workingOn skip (add log), M3 usedThisGw parsed but unused (note it). All deferred task minors triaged "leave".
- Final: parked — History-read hold has no retry (WC/FH held until reopen/next week; caption says "Checking…") — Ruling: conservative hold accepted; follow-up = History retry or "Chip history unavailable" copy — cost if wrong: a fan waits for a reopen to arm WC/FH after a rare History read failure
- Final: parked — transfer-feed retry replays the session-cache seed every 30s during a persistent failure (line/hold can flicker); no backoff — Ruling: cosmetic edge, accepted — cost if wrong: flicker during an outage
- Final: out-of-scope — lib/profile/fantasy_profile_source.dart:401 treats a failed per-week feed as no data (display-only, same error≠fact class) — follow-up candidate

## Opus audit fix reports: residuals not fixed

### fix-manager-report.md


1. **Owner-visible change: a forfeit now leaves `resultApplied = true`.** Before, it left the guard as it found it. The task asked for "guard true like a Final". The fan app and the fantasy server never read the guard. The old pure-builder tests in `game_finalize_test` still pass unchanged, because the builders don't touch the guard; the guarded applier does.
2. **Extra write per change.** Forfeit, undo, reopen and Reset now cost one claim transaction plus the update (and a release when refused), instead of a single update. `fantasy_finalize` fires on any write to a game that is Final (it is idempotent). So a forfeit, undo or reopen of a Final game now triggers one extra idempotent recompute.
3. **A finalize blocked by someone else's claim still says "This game was already ended on another device."** That is the existing message, kept per the brief. If the claim belongs to a reopen or Reset in flight, the wording is a little off. Adding a new `FinalizeOutcome` was out of scope.
4. **Residual, not fixed: the clean-sheet builders still rewrite `StatLog` as a dense list inside the guarded end-game, forfeit and reopen update.** A non-score stat recorded on another tablet in the milliseconds between that fresh read and the update would be dropped from the journal. Making those builders write per-child would change their snapshot-tested maps. It now happens only under the claim, from a fresh read.
5. **Residual, not fixed: activity *removals and edits* are still read-then-rewrite of a minute bucket.** This covers `removeLastActivity`, `removeActivityAt` and `reassignActivityPlayer` (league), and `removeMatchActivity` (tournament). They address an entry by index, so making them concurrency-safe needs an entry identity (e.g. the `_t` stamp) — a design change. Only the appends were fixed.
6. **Same failed-stream class elsewhere.** About 60 other `.valueOrNull ?? default` sites exist outside the audited screens (registrations, tournaments, events, the fantasy gameweeks page). They were not reviewed one by one.
7. **iOS verification.** All the transactions use the same `runTransaction` the finalize claim already used, so this is not new iOS ground. Still, on a simulator, check with two devices: a kickoff on a forfeited game refuses, and an undo of a goal lands on both.


### fix-squad-hardening-report.md

1. **Owner decision:** the trusted-price rule (deviation 1) and keeping held guests (deviation 2) differ from the brief's literal wording, to avoid zeroing legitimate squads. Worth a one-line confirmation.
2. **Run `fill:s15 -- --clear` before any new `--apply`.** Over the already-filled season, the real manager's squad is now skipped rather than replayed. The tool already warns about this state.
3. **Not covered: a REST writer marking all 7 picks as starters (`bench:false`).** That is a `formation` issue, which is tolerated as instructed, but it would score the two bench players at full points instead of half. The rules can't count booleans. Making "more starters than the formation" an integrity issue would close it; position re-labels never change bench flags, so holder protection wouldn't be affected.
4. **Not covered: saves made while GwState is `'locked'` or `'finalized'`** are allowed by the owner's rule expression but never counted (that is existing behaviour). A REST-only writer could get free transfers by saving only during that state. The fan UI blocks edits then.
5. **Fan app:** the manager squad viewer (being edited concurrently by another agent) doesn't yet label a week whose PublishedPicks or History carry `Invalid`. The leaderboard already shows 0 for that week.
6. **Deploy order:** the rules and functions should ship together. The rule is safe to ship on its own, because the fan app's existing catch shows "Couldn't save" until this app version is out.


### fix-functions-report.md


- **None of this is live yet.** The rules and functions take effect only after the owner deploys them; nothing was deployed. The C1 rules have to reach `database.rules.stage1.json` (the file `firebase.json` deploys) before the Manager's VOID and Manual buttons work. Both files now carry the fix.
- **The I5 stand-down covers only the four named entry points.** Two other triggers still act on a TestFill season after a Resume Auto:
  - The position-change trigger (`position_changes.ts` `handlePositionWrite`) stands down only on lockOverride, not on TestFill.
  - The badge-push trigger (`badge_push.ts`) also checks only lockOverride; it pushes when a new award row is created.
  
  The engine no longer creates award rows for a TestFill season. A Resume Auto plus an owner position change on S15 could still relabel squads and push a squad alert to the one real replayed manager. Gating these two would be a small follow-up if wanted.
- **I4 also re-enables holder protection under 'open'.** The rest of `recordSquadSave` now runs too: pick re-labels while the position window is open and clearing a squad alert once the formation is legal. That matches "stand down only for 'locked'", and both actions are idempotent. As before, counting still needs `GwState.status === 'open'`. If the owner opens the market while a stale GwState says 'locked' or 'finalized' (the sweep is paused), saves in that window are still not counted. That ties into I3 and I7 and is left alone.
- **M2 caveat.** A week that locked before PriceHistory existed but whose first finalize happens after this change would record finalize-time prices. This is the same accepted trade-off LockedPositions already makes. It is practically unreachable now, since S15 is filled and S16 has not started.
- **The live S15 dry run refreshed a gitignored cache.** It overwrote `functions/tools/rehearsal_out/fill_snapshot.json` with a fresh admin-read snapshot (dry-run behaviour; nothing was written to the database).


(fix-functions-report concern 2 was closed by commit 382c081.)

## Season setup + schedule build (2026-11-05)

Copied verbatim from that build's ledger (owner-facing decisions are in `2026-11-05-rulings-season-setup-and-schedule.md`). The final Fable-level review judged all of these fine to defer.

- Task 1: minor (deferred): friendlies-count-toward-kickoff not pinned by a doc comment + Stage:'friendly' test in either twin (orchestration_db.ts firstKickoffByDateOf, fantasy_parsers.dart firstKickoffByDateFromNode)
- Task 1: minor (deferred): H:mm parse duplicated (gameweeks kickoff parser vs lib/misc/schedule_display.dart gameTimeText vs Manager normalizeTimeString) — cross-reference or share fan-side
- Task 1: minor (deferred): TS Record lookups firstKickoffUtc[d]/deadlineOverrides[d] (gameweeks.ts) not hasOwn-guarded (junk 'constructor' key) — practically unreachable
- Task 1: minor (deferred): new Dart test lines > 80 cols (dart format not run)
- Task 2: minor (deferred): real kickoff Times + Start Time now feed live locks (S2 by design) — a season open at deploy whose first game is earlier than lockHour−60 moves its lock earlier; S15 'open', S16 has no Config, so no live impact
- Task 2: minor (deferred): refreshLiveWeek does 3 reads per live write (+refreshLiveGw loads twice); rehearsal reads +6.4%
- Task 2: minor (deferred): no per-job behavioural test that finalize/live/void/badges/messages honour a skip/override (guard can't catch a future site passing {} as configNode)
- Task 2: minor (deferred): guard whitelists by basename, misses aliased imports / destructured lockHour; tools/rehearse_s15.ts:882 still derives directly without overrides/LockedWeeks
- Task 2: minor (deferred): badges.ts imports leagueWallClock via news.ts re-export (point at league_time, drop re-export)
- Task 2: minor (deferred): position-change alert deadline uses GwState.lockAtUtc → one sweep stale after an override (acceptable per brief)
- Task 3: minor (deferred): guardedSnapshotClaim self-delete is an unconditional write(null) (orchestration.ts:2131) — compare-and-delete transaction would close a near-unreachable window
- Task 3: minor (deferred): goOn('Baselines') at orchestration.ts:2350 sits outside the best-effort try/catch — a read failure now throws out of sweep step 1
- Task 3: minor (deferred): no test pins the goOn('SquadAlerts') / goOn('Baselines') guards individually
- Task 3: minor (deferred): claim "another date" common path (pre-read finds other date) untested; "frozen on another date" warn logs frozenDate:null on a concurrent delete; gw (Gameweek) vs gw (number) naming inconsistency
- Task 3: minor (deferred): freezeLockTransferState / per-manager baseline transactions have 2N round-trip windows after a single check (healed by T3c/T3d at the next sweep / real lock)
- Task 4: minor (deferred): Prev chain cut at 8 levels silently (squad_integrity.ts:377) — add a log.warn when cutting / when a restore finds no Prev
- Task 4: minor (deferred): Voided/L deleted in rewind step 1 (schedule_rewind.ts:407) before the second scoredMeanwhile check (:439) — move after it so a finalize-wins race keeps the owner's void
- Task 4: minor (deferred): T4e log says "not marked locked" also for 'finalized' (schedule_rewind.ts:209)
- Task 4: minor (deferred): FakeDb.write(null) on an absent child creates empty parents (test_support.ts:47), unlike RTDB — production code adapted (LiveBase read-first)
- Task 4: minor (deferred, from first review): cascading reorder/dup code — Live-removal + baseline-restore transactions duplicated (schedule_rewind.ts:382-390/466-475, 400-406/477-488), snapshot list twice; lockStopped broadened to claim-refused-other-date (orchestration.ts:2497); reason (a) counts map children vs derivation date keys; PlayerWeeks/L left by a finalize that died before History; no test of two concurrent rewinds or array-shaped LockedWeeks; open-week deadline moved into the past leaves GwState open ≤15 min (Manager picker is future-only)
- Task 5: minor (deferred): late gate runs before Voided/Manual checks → a voided/Manual week finalized late is stamped Skipped:'late' (same outcome, different badge)
- Task 5: minor (deferred): ONE attempt per window — a transient read error at the single 10:00 run leaves the week permanently Skipped:'late'; consider cron '0 10-14 * * *' (done-check + claim make repeats no-ops) — DECIDE BEFORE TASK 14
- Task 5: minor (deferred): a History week missing from the schedule warns daily (unstamped); stale "Monday" comments in orchestration.ts/squad_integrity.ts/pricing.ts/finalize_core.ts; no PST-season or void+late tests; tools/rehearse_s15.ts reprices Mondays only
- Task 6: minor (deferred): marketEntriesOf (market_entry.ts:67-102) unused in production + duplicates marketPlayersOf/marketPricesOf; position try/catch pattern duplicated vs positionOrNull (position_changes.ts:79) — Task 7 should reuse or remove
- Task 6: minor (deferred): season_start.test.ts:322 uses toEqual after JSON clone — use not.toHaveProperty('uid') to pin no-undefined
- Task 6: minor (deferred): pre-existing target Players (half-seed, no Config/StartedAt) overwritten then deleted on rollback; writeIfAbsent claim outside try; name-on-two-teams dedupe untested; clampPrice dup of pricing clamp; second seasonOf helper; access.ts TWINS note doesn't list the new validator
- Task 7: minor (deferred): no retry on a failed roster trigger — joiner missing until the next shape change on that team (retry:true replays a stale `after`; better: reconcile rosters from the lifecycle sweep) — TRIAGE AT FINAL REVIEW
- Task 7: minor (deferred): write phase not all-or-nothing (Promise.all writeIfAbsent; idempotent on next sync); Guest keys pass the gate (3 wasted reads)
- Task 7: minor (deferred, plan-mandated): a uid-linked player renamed in Line Ups keeps the old market key (finalize joins by name → scores nothing until the Players key is renamed; only a warn log); trigger also runs for finished seasons with a Config
- Task 7: minor (deferred): shared FakeDb.writeIfAbsent non-atomic (test_support.ts:60) — local CountingDb workaround
- Task 8: minor (deferred): guard read → PUT gap is tens of seconds (2×N photo/position reads) — re-run seedRefusal right before the first _put; header examples Futsal 15 now refuse; dry run needs --force-reseed (owner-irrelevant dev tool); raw stack trace on failed read; CLI wiring untested; StartedAt not consulted
- Task 9: minor (deferred): schedule session cache keyed sport|season can paint pre-override deadlines briefly on revisit; dead 'GW{n} opens soon' branch (deadline_chip.dart:142); fantasy_format.dart:84 comment wrong for Nov 1; tolerantInt accepts 0x11 vs server regex; stale "Monday repricing" comments (fantasy_service.dart:205,222, fantasy_parsers.dart:201); every live Date write re-derives + notifies (pre-existing)
- Task 10: minor (deferred): Retry gives no in-progress feedback (error stays while reloading); Void/Mark-manual unavailable while the schedule errors; absent Config → spinner (pre-existing, check scaffold gating); optInt weaker second int reader; overview "locks …" text may swap once after load (un-gated)
- Task 11: minor (deferred): stale tap after kickoff passes with no DB event → silent no-op; failed History shows no controls and no explanation (retry only invalidates schedule sources); per-card kickoff map re-parse on every Date emission; formatGameDay splits the display string; service guards untested; showNewsScheduleDialog doc still says "Schedule disabled"
- Task 12: minor (deferred, pre-existing): Manager Add/Edit game form Stage dropdown overflows at 360 px (410 px); "Regenerate playoffs"/"Recompute bracket" row overflows 101–135 px with a bracket (tablet-only app today)
- Task 12: minor (deferred): Replace→Generate repeats the unknown line (cosmetic); schedule_manager_page.dart:24 81 cols; pre-existing 360 px overflows (Stage dropdown, playoff button row) → candidate follow-up task
- Task 12: minor (deferred, pre-existing): schedule row of a FINAL playoff game overflows 64 px at 360 px
- Task 12: minor (deferred, pre-existing): _generate sets unfinished=0 when the games stream has no value (hides the not-Final banner) — same error≠fact class, not fantasy
- Task 13: minor (deferred): _optInt toInt() throws on NaN/Infinity (unreachable via JSON); start card pops above the season bar when the pointer arrives (layout shift, no reveal gate in the scaffold); stepper steps an off-grid carried price (62 → 6.7) — server snaps
- - Ruling R1 (parked): a finalize spanning a finished rewind plus a stale re-claim can still score the called-off day. Why: it needs three overlapping runs, and the proper fix (a claim id on every LockedWeeks entry) is a follow-up. Cost if wrong: on that rare overlap the cancelled day counts, and the owner Voids it.
- - Ruling R2 (parked): moving the last game of the latest locked week to an EARLIER past day still says "won't count", though that day becomes the reopened week and locks at once. Why: the server is consistent; only the wording is wrong, in a rare edit. Cost if wrong: misleading warning text; follow-up uses emptiedDates.
- - Ruling R3: keep the blanket "games have started → Bring back disabled" (it overrides T11a for started days). Why: allowing it would race an in-flight rewind. Cost if wrong: a mistaken Skip of a played day can't be undone in the app, so the owner is told.
- - Ruling R4: the reprice window vs morning-kickoff deadlines (≤10:00 → never repriced) stays as T5a. Why: Sunday-evening futsal is unaffected. Cost if wrong: morning-game weeks need hand price edits, so the owner is told.

## From the scale-fixes build (2026-11-06)

Left alone on purpose: each is small at league size (about 60 managers) and sits outside the scale-fixes plan. Only the engine's own reads were measured (the load test and the `healOpenWeek` figures below); the Manager-screen and fan `Leaderboards` items are judged small, not measured. The Scale T<N> minors are copied from that build's ledger; the review of each task judged them fine to defer.

- Manager owner screens (one device) still stream the whole `History`, `TransferCosts`, `Squads` and `TransferState` nodes. Cheap for one owner at league size; the Manager app was out of scope for the scale fixes.
- Fans still stream the whole `Leaderboards` node (one listener per viewer). Small at league size.
- Once-per-week whole reads that need the contents stay whole: finalize, the lock snapshot, `liveBaseFor`, `publishSaleBaselines`, and `settleSeasonBadges` when it actually settles. At 1,000 managers these are the biggest reads left (the 17.36 MB max in the load test below), but they run once a week, not per sweep.
- `healOpenWeek` (functions/src/lib/fantasy/schedule_rewind.ts ~542) reads the whole `Baselines` node on most open-week sweeps: about 45 KB per sweep at 250 managers, about 179 KB at 1,000 (measured by `npm run loadtest`). Extrapolated from the 250-manager run, not measured: about 11 KB per sweep at league size (60 managers), roughly 1 MB a day per active season at the 15-minute sweep cadence.
- Load test after the fixes (`npm run loadtest -- <N> --offline`): 250 managers, median 0.11 MB per sweep (the pre-fix engine, same harness: 5.65 MB, with a whole-`Fantasy` read on every sweep). 1,000 managers, median 0.25 MB per sweep, max 17.36 MB (the weekly whole reads above), with 0 crashes, 0 invariant failures and 0 whole-`Fantasy` reads.
- Scale T1: childKeys builds URL from admin.app() databaseURL, ignores the `root` passed to rtdbFantasyDb (fantasy_adapter.ts:62-91)
- Scale T1: AbortSignal.timeout covers fetch only, not getAccessToken (fantasy_adapter.ts:69-73)
- Scale T1: FakeDb.reads `quiet` flag around inner reads relies on synchronous read (test_support.ts:512-528)
- Scale T1: no committed test for shallowChildKeys (header/no-token-in-URL/status-only error) — stubbed-fetch test suggested
- Scale T1: child_keys.test.ts:183 local `db` shadows describe helper at :139
- Scale T1: nodeExists dropped explicit null/undefined guard (relies on childEntries returning [] for undefined) — orchestration_db.ts:123-125
- Scale T2: BADGE_CATALOG_KEY duplicates badges.ts BADGE_CATALOG_PATH literal (orchestration_db.ts:~318 vs badges.ts:133)
- Scale T2: (plan-mandated D2/D3) if shallow fails everywhere, fallback reads Fantasy whole + each Fantasy/<sport> whole ≈ 2× today's bytes, with a warn per call — FIXED in the final fix wave: the seasons now come from that one whole read (one warning), and a failed season Config read skips only that season
- Scale T2: BadgeCatalog read outside the try in runLifecycleSweep — a failing read aborts every season (not a regression)
- Scale T2: Config reads sequential in listFantasySeasons
- Scale T2: fantasySeasonsOf no longer test-only (the listing fallback uses it); reprice comment "History week not in schedule" wording
- Scale T2: latestScoredWeek name now means "latest week with History"; reprice skips an unrepriced N when N+1 finalizes (pre-existing, same as old code)
- Scale T3: schedule_rewind.ts:518 healOpenWeek loop stays read() (null in steady state; T3d test hooks read) — needs an in-code comment saying why
- Scale T3: live_orchestration.test.ts:45 positive exists assertion is decoration (other steps also emit it); orchestration.test.ts:139-140 exact exists counts brittle by design
- Scale T3: snapshotPriceHistory (orchestration.ts:2419) same existence shape on PriceHistory/<n> (player-scale)
- Scale T3: stale comment above healOpenWeek ("one small read for History/<n>")
- Scale T4: no test for a stamp/cabinet write failure (badges.ts:428-429 comment relies on it); harmless null write to an absent marker on re-settles with removals (badges.ts:405)
- Scale T4: a crash between marker delete and stamp with one surviving auto award → next sweep backfills and won't retry the removal (same as pre-Task-4 behaviour); comments badges.ts:776-778 / orchestration.ts:2666-2667 overstate the retry — comment FIXED in the final fix wave (badges.ts now says only a finalize rerun retries the removal)
- Scale T5: no test pins 0b/lockOverride/TestFill ordering vs the stand-down; marker-before-LockedWeeks order unpinned; step 2a comment "season-over return below" now ambiguous (say "step 3's"); 2b throw on stand-down path double-logs (same as normal path)
- Scale T6: fingerprint skips numeric-string prices / doesn't see position-invalid market drops; finalize-time baseline heal not seen by the gate; untested uids.size===0 stamp path, failing stamp write, no-pusher sweep
- Scale T6: a reopened week does not re-arm PreviewPushed/<gw>/<uid> (no second over-budget push) — pre-existing; pricesFingerprint doc may still describe the 2-field stamp
- Scale T7: History cache seed never tested as a hit; didUpdateWidget ignores uid/sport/season changes (always pushed fresh today)
- Scale T7: stale comments — manager_squad_viewer.dart:614 "or stayed silent past the bound"; feeds_test.dart:13-14 header "adds one listener per feed" — FIXED in the final fix wave
- Scale T7: error-then-recover while the other feed is silent flashes failure → skeleton → content (rare); own page's "Now" face also blocked by an unreadable squad feed
- Scale T8: gate passes vacuously if sweeps===0 (add a check); finishedAtEnd on-state untested; header "never writes anywhere" (online mode writes the local snapshot cache); saveSpacingMs comment loose about extras; transaction/writeIfAbsent exclusions only in a comment; gate trips only on exact read('Fantasy')

### Owner notes

What this build means for running the league, in plain words:

- A season badge you switch on after a season has already been settled is not handed out by the automatic 15-minute check. Re-running the finalize of a week hands it out.
- If you remove an automatic season award by hand in the Manager, it stays removed: the automatic check will not put it back (re-scoring a week decides it again).
- A brand-new squad save that goes over budget is not re-checked straight away. It is checked again when a price or the budget changes, when a new week opens or a week is reopened, or at the lock — and the lock check always has the final say.
- A new game day added to a season already marked Finished now works by itself: the season goes back to its full checks, opens and locks that day like any week, scores it, and then goes quiet again. You no longer need to un-mark Finished first.

## From the account-deletion build (2026-11-10)

- Insider referral rows (`Referrals/<id>` where the deleted person is the Insider) still hold the invitees' names (`ReferredName`). They must join the account deletion when Insiders launches (today only the row where the deleted person was the one invited loses its name).
- A mini-league's free-text `Name` survives the ownership hand-off when its owner deletes their account (the league passes to the next member with the name the old owner typed). Decide whether a hand-off should offer a rename or reset it.
- `DeletedAccounts/<uid>` is readable by any client while the stage-1 rules keep the root `.read: true` (read grants cascade, so its own `.read: false` has no effect). It holds only opaque ids (`By` admin uid, `PendingAuth`, `MergedInto`) and timestamps — no free text by design (the admin "reason" was dropped 2026-11-10 for this reason). The stage-2 rules lockdown must remove the root read; re-check this node then.
- A kept account whose deletion run fails after the first `PendingAuth` marker is written keeps a read-only profile (the new `Users/$uid` write guard) until a retry finishes the run — acceptable (the account is half-deleted anyway), but the retry is Claude's job once the kept account has left the Manager's list.

## From the Insiders approval fix (2026-11-13) — two findings that need their own plans

- **OPEN READS (highest priority).** The live rules are still "stage 1": the root `.read: true` answers ANY request, signed out included. Checked 2026-11-13 from a signed-out request: the top level lists 31 nodes and `Users` lists 582 accounts (names, emails, phones, birthdates live under them). The Oct-27 lockdown planned to close this in stage 2 once the fan release that reads `PublicProfiles` instead of `Users` is on people's phones. Until then the Privacy Policy must not claim reads are restricted (§12 was corrected the same day to claim only what is true: writes are restricted). Plan needed: either ship the release and flip to `database.rules.json`, or an interim posture (drop the root read, give every public node its own read, `Users` readable only when signed in) tested against the current store build first.
- **Registrants can stamp their own discount.** `Registrations/<id>/Submissions/<uid>` is written by the registrant's own client and the rules only protect `Paid`. `createRegistrationPaymentIntent` charges `effectiveCharge(...)` from the submission's own `DiscountSource` / `AdjustedFee` / `DiscountPct` / `EligibleFee`. Emulator-verified 2026-11-13: an ordinary user can save a submission with `DiscountSource: 'manual', AdjustedFee: 1` or a 100% `insider_tier` discount (marking itself Paid is refused). Needs a design, not a drive-by rule: the store build legitimately stamps `first_timer_promo` / `insider_tier` itself. Direction: the server re-derives the allowed discount when it creates the payment (first-timer check + promo config; the payer's own `Insiders/<uid>` tier; `manual` only when an admin wrote it), and the rules refuse `manual` from non-admins.
- Insiders under the target rules: the fan's code check reads `Insiders/<otherUid>/Status` and its dashboard queries `/Referrals` — both owner/admin-only once the root read goes. The lockdown already records "move code validation + referral queries server-side" as the prerequisite; it now also blocks the open-reads fix above for Insiders.

## From the pre-merge review of PR #17 (2026-11-13) — plans still owed

Six independent reviewers went over the branch before it was merged. Everything they found that could be fixed safely was fixed the same day (branch `zaya-review-fixes`; the database rules and twelve functions are already deployed). What is left needs design, not a patch:

- **Payment integrity (one plan).** (a) A registrant can still write their own discount fields on their submission and the card charge trusts them. (b) Naming the id of any approved team that waives payment is enough to be written Paid — the rule never checks the join code, and team ids are readable while the root read is open (no waiving team exists today; checked 2026-11-13: 1 open registration, 0 teams, 46 submissions, 0 paid by team code, 0 discount stamps). (c) The legacy `Sign Ups/<league>/<season>/Paid/<uid>` list is self-writable. (d) A second card payment for an already-paid registration is kept silently (no reuse of an open PaymentIntent, no duplicate flag for the owner); same for the dormant fantasy pass. (e) A refunded registration card payment stays Paid. (f) The webhook does not compare the amount received with what is owed. (g) `checkFirstTimer` answers for any email/phone and downloads every registration per call. Direction: the server derives and stamps discounts and creates joiner submissions; rules then refuse those fields from clients.
- **Open reads / stage-2 rules.** Unchanged from the entry above; the review added the migration checklist: `Insiders/<other uid>/Status` + `Name` reads and the `Referrals` query in `lib/misc/insider_service.dart`, and `Sign Ups` staying public-read (uid → full name, comments).
- **Prediction backdating.** `Predictions/$match/$uid` has no validation and scoring trusts the client's `UpdatedAt`; the installed build sends phone-clock time, so a strict server-time rule has to wait for a client that sends `ServerValue.timestamp` (or use a tolerance window).
- **Abuse hardening.** Mini-league creators can list other people as members and league codes are public; legacy sign-up comments are keyed by display name and create-only (a namesake is refused silently); no size limits on `CategorySuggestions`, ticket messages or per-user Storage; a deleted `Awards`/`Played`/`Merged*` key is not blocked (a `.validate` never runs on a delete); full user ids remain in many function log lines outside the support files.
- **Performance.** The fantasy live trigger reads the whole season schedule on every scoring entry before its stale check (`functions/src/lib/fantasy/orchestration.ts` ~2022-2040); the front-page fantasy banner streams the live board to every signed-in fan, players or not.
- **Smaller app items left as they were.** "Change Password" always reports success and can resend on rebuild; About You's Continue spins with no exit while offline; the Terms/Privacy pages show a raw Android error page offline; a new Google sign-up whose push-token fetch throws skips About You for that session; a personal fantasy push has no switch of its own (the master switch now stops it).

## From the pre-release report fixes and the live-data clean-up (2026-11-13, evening) — plans still owed

- **One-shot reads serve the phone's saved copy (needs its own plan; recommended before the store build).** The normal build keeps the database's on-disk cache on (`lib/misc/rtdb_emulator.dart`, `enableRtdbPersistenceUnlessEmulator`). With it on, a `once()` read answers from the saved copy and does not refresh it; only a live `onValue` stream on the same path does. Proven on the emulator: after three players were renamed in the live database, the top-bar stats leaderboard (`getAllFutsalLineUps`, `lib/misc/utility.dart`) kept the old names through five cold starts and a device reboot while online, until the Leagues → Season 15 → Player Stats screen (a stream) was opened. Any edit (a score fix, a roster change, registration settings) can therefore show late on every screen still on a one-shot read: 88 `.once()` calls in 20 files under `lib/`. In season the live screens mask it. `get()` stays banned (iOS). Options to weigh per call site: move the screen to a stream, or one shared "fresh read" helper built on `onValue`; do not switch the disk cache off without measuring cold start and offline behaviour.
- **Season 16 fantasy start needs a manual step now.** `Fantasy/Futsal/15` holds only `Players` (the Season 15 test data and its `Config` were removed on the owner's instruction, so fantasy is hidden). Season Start copies its settings from the newest earlier season's `Config`; with none it uses the built-in defaults (budget $50M, not the agreed $60M). Before Start: combine the duplicate accounts, write the final prices into Season 15 `Players`, restore the Season 15 `Config` from the local backup (budget 600, `lockOverride: "locked"`, free; never "auto"), Start, then remove that `Config` again. A small code change would remove the manual step: let Start read its template from a non-gating node (or accept the settings in the Start call).
- **Renaming a player is a data migration, not an edit.** A name is a key in `<Sport>/<S>/Line Ups/<team>`, `AFC San Jose/Seasons/<S>/Roster` and `Fantasy/<sport>/<S>/Players`, and a value in game activity under `Date/**`; careers link by the roster row's `UID`. Done once by script on 2026-11-13 (one atomic multi-path update with a backup of every before-value). A Manager "Rename player" action with the same guards (collision, row linked to another account, season without a live fantasy `Config`) would make the next one safe without a script.
- **Two mistyped AFC San Jose game entries were left alone:** "Pedro Vasconselos" (1 goal) and "Pedro Siva Vasconselos" (1 assist) never matched his roster row. Correcting them changes his stat line, so it is the owner's call.
- **Fantasy pitch art stretches at large text sizes** (Team of the Week / My Team court: about +3% at normal text, +16% at 1.3x, +46% at 2x) — the trade-off taken so name boxes never overlap the next row's photos.
- **AI news copy "$" guard** adds "$" to any `d.dM` token; a same-shaped non-price ("3.5M views") would get one too. Not seen in fantasy copy so far.
- **Insiders, Manager side (branch `zaya-insider-referral-picker`):** (a) `ReferredUsers/<uid>` is not create-only in the rules, so two admins adding the same person in the same second could both pass the pre-save check (rules live in this repo; add a create-only validate + probe checks). (b) The Manager's `voidReferral` still reads the counters and writes them back rather than using increments, and does not stamp `LastReferralAt` like the server's void. (c) A queued manual-referral save is lost if the app is force-quit while offline (nothing half-saves).

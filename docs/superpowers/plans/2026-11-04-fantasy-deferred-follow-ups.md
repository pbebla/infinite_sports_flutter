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


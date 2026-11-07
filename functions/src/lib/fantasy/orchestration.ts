// Fantasy server jobs (P4 Phases B–D), database-injected and emulator-free:
// the 15-minute lifecycle sweep (gameweek state + lock snapshots + finalize
// backstop), the match-day finalize entry the RTDB trigger calls, and the
// Monday repricing job. All math lives in the pure engine
// (finalize_core.ts + the ported lib); this file only loads inputs through
// the FantasyDb seam, decides WHEN, and applies the outputs.
//
// NODES THIS FILE OWNS (all under Fantasy/<sport>/<season>):
//
// - GwState = { current:int, status:'open'|'locked'|'finalized',
//   lockAtUtc:int (epoch ms of the engine lock instant), date:'MMDDYYYY' }.
//   Server truth for the jobs — the fan countdown still derives locally from
//   the schedule stream; no client reads this node. Written only through
//   upsertGwState (schedule_rewind.ts) — by the sweep, the rewind of a
//   called-off week (null when no later game day exists) and the Config
//   trigger (an OPEN week only) — and only when a field actually changed
//   (idempotent no-op otherwise); an open week whose deadline moved later
//   or whose date changed also loses ReminderSent/<gw> (the reminder fires
//   again).
//   'finalized' means the CURRENT gameweek is locked and its History exists;
//   when the next gameweek opens, current advances and status returns to
//   'open'. The engine's 'upcoming' can never be the current gameweek's
//   status (opens <= previous lock + 24h always), but is mapped to 'open'
//   defensively.
//
// - PublishedPicks/<gw> = the judged Squads snapshot (uid -> squad map; a
//   valid squad at its judged prices + `realizedTenths`, an invalid one
//   verbatim + `Invalid` — below), the spec §9 anti-copy reveal. Written
//   ONCE via a set-if-absent claim the
//   first time the sweep sees the current gameweek locked — never
//   overwritten, so late sweeps after downtime still snapshot exactly once.
//   Never claimed once History/<gw> exists: a FIRST finalize that outran
//   every sweep scored the week from live Squads, and that History is the
//   law for the week (a late claim would snapshot post-settle Squads).
//   SQUAD INTEGRITY (audit I2, 2026-11-01): the same claim judges every
//   squad (squad_integrity.ts — too many players, duplicates, unknown /
//   guest NEW picks, over budget at TRUSTED prices + the FPL selling rule's
//   realizedTenths); a valid one is snapshotted at its judged prices with
//   its `realizedTenths` (every other key kept); an invalid one is
//   snapshotted verbatim plus `Invalid: [issues]` and the baseline's
//   `realizedTenths` (no sale credited), scores zero (finalize),
//   and its manager gets SquadAlerts/<uid> = { Gw, Kind:'invalid', Issues,
//   CreatedAt } (the fan banner — it replaces an over-budget preview, step
//   3c; cleared by the next clean save or the next clean lock, which clears
//   a preview too). A FIRST finalize reading live Squads (no snapshot) judges
//   them the same way. Snapshots and History rows are never re-judged.
//
// - LockedPositions/<gw> = { <name>: 'GK'|'DEF'|'ATT' } — every market
//   player's position at the lock (spec §3 revision 2026-10-28: positions
//   are locked per gameweek). Written ONCE alongside the PublishedPicks
//   claim (set-if-absent; a FIRST finalize that outran every sweep claims
//   it too, from the positions at that moment). Finalize and the Monday
//   reprice of <gw> read positions from it, so a score-edit rerun of an old
//   week never uses a later position; weeks locked before this snapshot
//   existed fall back to the live Players positions. Public read.
//
// - LockedWeeks/<n> = { Date:'MMDDYYYY', LockAtUtc:int (epoch ms),
//   Scored?:true, Rewinding?:true, Finalizing?:int (epoch ms) } — the
//   frozen-week ledger (season setup + schedule plan
//   2026-11-05; parsed by orchestration_db.ts lockedWeeksOf, honoured by
//   loadSeasonGameweeks): once a week locks, its date and deadline no
//   longer follow the match calendar or the config, so a later schedule
//   edit can never renumber or re-time it. Claimed set-if-absent as the
//   lock's FIRST write (claimLockedWeek: sweep step 1, and a first finalize
//   that outran every sweep — marketForGameweek); a claim lost to ANOTHER
//   date takes no snapshot (warned) — and a first finalize then stands down
//   (final review I4) — one lost to the same date (an earlier or concurrent
//   claim) carries on. The sweep's rewind of a called-off
//   week MARKS the entry `Rewinding: true` first and deletes it last; a
//   marked entry freezes nothing (freezesWeek) — no claim, no re-check, no
//   Scored mark accepts it. [M2] A sweep that started before a rewind must
//   not leave a stale lock write behind (a stale PublishedPicks/<n> would
//   silently become the week's picks): every lock write re-reads the entry
//   right before writing and stops the lock step once it no longer freezes
//   the week's date (stillFrozen), and each snapshot write (LockedPositions,
//   PriceHistory, the PublishedPicks claim) re-reads it AGAIN once ours
//   landed and deletes itself when a rewind got in between
//   (guardedSnapshotClaim). Every finalize run that wrote History marks it
//   Scored:true (markWeekScored; a week locked before the ledger existed
//   gets the full node then). Finalize stands down for a marked week at
//   entry, and its last check before its first official write is a
//   TRANSACTION on the entry (stampFinalizing — final review I1): it stamps
//   `Finalizing: <now>`, which the rewind's mark refuses while younger than
//   10 minutes, and refuses itself — writing nothing — when the entry is
//   marked, gone since the run began, or re-dated. Scored replaces the
//   stamp (markWeekScored); a run that scores nobody removes its own. So
//   finalize and rewind never overlap on a week. A first finalize of a
//   SKIPPED day stands down (I2). Readers ignore both coordination keys.
//   A sweep whose lock step stopped on a week no longer frozen writes no
//   GwState. The
//   rewind itself, its CalledOff/<gw>/<date> push claim and the heal of
//   stale lock writes on an open week live in schedule_rewind.ts. Rules:
//   signed-in read, no client write.
//
// - Repriced/<gw> = { At:int, Manual?:true, Voided?:true, Skipped?:'late' } —
//   the reprice job's done-flag (it runs every morning, not only Mondays —
//   hourly attempts 10:00-15:00 league time, final review I5).
//   Manual:true records "admin had set
//   PriceChanges/<gw>/Manual, the job stood down"; Voided:true records "the
//   week was owner-voided, the job skipped it" (un-voiding later does NOT
//   reprice retroactively — prices have moved on); Skipped:'late' records
//   "the week was finalized after teams had reopened (lockUtc + 24 h), so
//   its prices were not moved" — the owner can still adjust them by hand per
//   player. While a run works the row is its claim { At, Pending:true }; a
//   Pending row over an hour old is a dead run (warned on every later run,
//   never taken over — audit M5).
//   PriceChanges/<gw> itself holds only the client contract rows: <name>:
//   { delta:int EFFECTIVE tenths } (post-clamp; zero moves omitted — a
//   ceiling-clamped riser is not a riser) plus the owner's Manual flag.
//
// - PlayerWeeks/<gw>/<name> = int (functions-internal; see finalize_core.ts).
//
// - PlayerWeekStats/<gw>/<name> = per-player weekly record (public read, no
//   client write): Pts/Played/GP/Games/Lines — the shape lives in
//   finalize_core.ts. Written as the whole <gw> node next to PlayerWeeks;
//   other weeks' GP feed PlayerTotals games/ppg on every (re)run.
//
// - TransferState/<uid> = { Free:int, UsedThisGw:int, ChipPlayed?:string,
//   SavedGw?:int, RolledGw?:int, CountFromGw?:int, CountFrom?:[playerId] }
//   — the Phase E transfer ledger plus the transfer baseline the fan app
//   counts against; the field-by-field contract lives in transfer_state.ts.
//   Written by the Squads/<uid> trigger (recordSquadSave), the lock step
//   (ChipPlayed freeze) and the post-finalize rollover. Rules: read own +
//   admin, no client write (functions only).
//
// - Baselines/<uid> = { ForGw:int, RealizedTenths:int, Prices: { <playerId>:
//   tenths } } — FPL selling (spec §4): the manager's effective squad after
//   the last lock (effectiveSquadAfterWeek, Free Hit aware) as the fan app
//   prices it — a held player's price and the running sale total. Written
//   by publishSaleBaselines for EVERY manager (Managers ∪ Squads ∪
//   PublishedPicks/<gw> ∪ existing Baselines) at the lock of gw (ForGw =
//   gw + 1) and re-checked by every finalize run (never backwards: nothing
//   is written for a week before the next lock's, a stored node for a later
//   week is kept; no-op when unchanged). No squad, or an unreadable one,
//   carries the previous
//   RealizedTenths with Prices {}. The lock judge reads RealizedTenths back
//   when ForGw is the week it judges (loadIntegrityInputs). The LOCK-time
//   write also stashes the node it replaced as Prev: { ForGw,
//   RealizedTenths, Prices } (squad_integrity.ts THE PREV STASH) — the
//   rewind's exact undo; a finalize that wrote History drops it (a scored
//   week is never rewound), one that wrote none keeps it like the lock.
//   Every reader ignores Prev. Rules: read own + admin, no client write
//   (like TransferState).
//
// - TransferCosts/<gw>/<uid> = int points (functions-internal, like
//   PlayerWeeks): the week's transfer charge frozen at lock — the
//   transferCostPointsByUid seam's source on every finalize (re)run, so a
//   score-edit rerun recharges exactly what was charged the first time.
//   The sweep's lock always writes it (null when nobody owes anything), so
//   a node left by a rewound lock never survives a re-lock.
//
// - ReminderSent/<gw> = { At:int } and RecapSent/<gw> = { At:int }
//   (functions-internal): once-only claims for the Phase F pushes. Claimed
//   via writeIfAbsent BEFORE sending, and only when a pusher was injected —
//   a sweep without one (tests) leaves them unclaimed.
//
// - PreviewPushed/<gw>/<uid> = { At:int } (functions-internal, no rules
//   entry: server-only): the once-only claim for the over-budget PREVIEW
//   push (sweep step 3c — FPL selling, spec §4): one per manager per
//   gameweek, claimed the same way. The preview's banner node is
//   SquadAlerts/<uid> { Gw, Kind:'preview', Issues:['overBudget'],
//   OverTenths, CreatedAt } — contract in squad_integrity.ts THE
//   OVER-BUDGET PREVIEW.
//
// - NewsDrafted/<gw> = { At:int } (functions-internal): once-only claim for
//   the Phase G news step (the Dream Team post + the AI drafts + the admin
//   heads-up push). The News/Drafts, News/Published and Config/NewsAutopilot
//   (legacy Config/DreamTeamPost) shapes live in news.ts; News/PushClaims
//   (the push-on-publish once-only claim) in news_push.ts.
//
// - ScheduledPushes/<id> (Manager-written owner messages; the sweep sends
//   the due ones — even while lockOverride freezes the engine): the shape
//   and the SentAt claim live in messages.ts.
//
// - Badges/<uid>/<awardId>, BadgePushClaims/<uid>/<awardId> and the global
//   Fantasy/BadgeCatalog (achievement badges, spec 2026-10-30): shapes, the
//   rerun-exact reconcile, the season-end rule and the trophy-cabinet copy
//   live in badges.ts, the once-only push in badge_push.ts. Finalize settles
//   week N's auto awards and then the season end; the sweep seeds the
//   catalog and checks the season end (sweep mode).
//
// - Voided/<gw> = true (READ-only here; the Manager's "VOID week" toggle
//   writes true or removes it — spec §15). A voided week settles to zero
//   (finalize_core.ts VOIDED GAMEWEEKS), its transfer cost is waived (the
//   lock still freezes TransferCosts/<gw> so an un-void recharges exactly
//   that), chips played in it are refunded at later locks, the Free Hit
//   restore + rollover run as normal, the Monday job skips it, and its
//   news drafts never auto-publish while the flag stands. Its settle
//   claims RecapSent/<gw> and NewsDrafted/<gw> as { At, Voided:true }
//   WITHOUT sending or drafting — regardless of whether a pusher/news dep
//   was injected, since there is nothing to deliver. Toggling the flag
//   re-runs the finalize entry (resettleVoidToggle, fantasy_void.ts
//   trigger). DOCUMENTED CHOICE: un-voiding a week whose guards the void
//   path already claimed re-settles every score but sends NO late recap and
//   drafts NO late news — days-late "GW n" pushes after an owner flip-flop
//   are noise, and the guards are once-only by design.
//
// - Live = the live gameweek (live design 2026-11-03,
//   docs/superpowers/specs/2026-11-03-fantasy-live-design.md §4; node
//   shapes in live_core.ts): Meta/Board/Players/Squads/TeamOfWeek of the
//   locked week while its games are played — recomputed on every scoring
//   write to a game of its date (fantasy_live.ts trigger -> maybeRefreshLive
//   -> refreshLiveWeek) and by the sweep backstop (step 2c). Written ONLY
//   through a transaction on the whole node (LIVE ORDERING below). When the
//   week settles, finalize — after every official node — replaces it with
//   the Meta-only TOMBSTONE { Meta: { Gw, State: 'settled', UpdatedAt } }
//   (Fable L1: no settled mirror), which a new week's first live run
//   replaces. A live run never writes an official node (History,
//   Leaderboards, PlayerTotals, PlayerWeeks, PlayerWeekStats, DreamTeam,
//   TransferState, TransferCosts, PublishedPicks, Baselines, SquadAlerts).
//   It stands down exactly where finalize does (no Config, a frozen
//   lockOverride, TestFill, before the lock) and without the lock snapshot
//   (PublishedPicks/<gw> or LockedPositions/<gw>). A settle lost to a
//   finalize that died before its hand-over is healed by the sweep (step
//   2d). Rules: signed-in read, no client write.
//
// - LiveBase/<gw> (functions-internal; admin read, no client write): the
//   settled base a live run resums against (live_core.ts buildLiveBase,
//   from the stored History/PlayerWeeks/PlayerWeekStats of the weeks before
//   gw), built by the week's first live run and reused after. The WHOLE
//   node is removed by every finalize run and every void toggle (either
//   may have changed a settled week); a live week still showing is then
//   refreshed at once (Fable L4), which rebuilds it.
//
// LIVE ORDERING: a live run stamps ReadAt with the wall clock (deps.clock,
// Date.now in production) taken BEFORE its first game read, so a stamp
// never claims a fresher view than the run had. The Live transaction writes
// over an absent node, an older week's, or this week's when the stored
// ReadAt is not after its own — a run that read older games and lands
// after a newer one aborts, so older numbers never end on top — and never
// over a newer week or this week's tombstone. A run whose event is not
// after the stored ReadAt of its week (a newer run already read past it),
// and one whose week has PlayerWeeks/<gw> (finalize's first write: the
// week settled — never resurrected), stand down before any heavy read.
// The settle and void refreshes take a fresh clock reading after removing
// LiveBase, so they win over every run that read the old base.
//
// Finalize manager-source precedence (documented contract): the lock
// snapshot PublishedPicks/<gw> is the law; a rerun without one re-reads the
// squads stored in History/<gw> (deterministic reruns); only a FIRST run of
// the LATEST lock-passed gameweek may fall back to live Squads (so enabling
// fantasy mid-season can never fabricate history for weeks nobody played).
//
// Config.lockOverride: anything but absent/'auto' freezes the machine —
// sweep, finalize and repricing all stand down for that season (the owner's
// sandbox escape hatch; the H rehearsal flips a COPY season to 'auto'). The
// squad-save counter (recordSquadSave) is the one exception: it stands down
// only for 'locked' and keeps counting under 'open' (audit I4).
// An optional Config.lockOverrideUntil (epoch ms) bounds it: every check
// reads the EFFECTIVE value at its job's now (lockOverrideOf), and the sweep
// reverts an expired override to 'auto' in the DB (spec §2 auto-return) —
// a compare-and-set on Config, so an owner change made after the sweep's
// read is never wiped.
//
// TestFill (audit I5): a season carrying Fantasy/<sport>/<season>/TestFill
// (the marker tools/fill_test_season.ts writes with a replayed fake season)
// stands the same jobs down — sweep, finalize (so the void re-settle too),
// Monday reprice and the squad-save counter — EVEN when lockOverride is
// 'auto' (a Resume Auto on the filled test season), logging
// TEST_FILL_STAND_DOWN. Its fake History holds the real managers' replayed
// squads, so any rerun could otherwise write fake podiums into real trophy
// cabinets (badges.ts TEST SEASONS). The replay itself never sees the
// marker (its in-memory overlay is seeded from READ_PATHS only).
//
// A finished, settled season (scale fixes D7): the league flagged Finished,
// the SeasonBadgesSettledAt marker in place, every LockedWeeks entry Scored
// and neither Finalizing nor Rewinding, GwState 'finalized' and no match day
// (bar a skipped one) after the last locked week — the 15-minute sweep
// stands the season down by itself (logging "season over — standing down"),
// running only the news auto-publish and the lost-settle heal. Any of those
// conditions failing (the owner un-marks Finished, a week is rewound, a game
// day is added) = the full sweep again.

import { createHash } from 'crypto';
import {
  configFromMap, FANTASY_POSITIONS, FantasyConfig,
} from './fantasy_config';
import { FetchLike } from '../support';
import {
  BADGE_CATALOG_PATH, seedBadgeCatalog, settleSeasonBadges, settleWeeklyBadges,
} from './badges';
import {
  computeGameweekFinalize, FinalizeGame, MarketPlayer,
} from './finalize_core';
import { currentGameweek, Gameweek, gameweekStatusAt } from './gameweeks';
import { leagueWallClock, parseDbDate } from './league_time';
import {
  buildLiveBase, computeLiveWeek, LiveBase, LiveGameStatus, LiveOutput,
  liveWriteMatters,
} from './live_core';
import {
  autopilotPublishAtUtc, buildDreamTeamDraft, buildNewsStats, dreamTeamNames,
  formatLeagueWeekdayTime, generateNewsDrafts, newsAutopilotConfigFrom,
  publishedRowFromDraft, shouldAutoPublish,
} from './news';
import {
  buildPlayerCard, cardsNode, PlayerCard, seasonGoalsAssists,
} from './news_cards';
import { sendDueScheduledMessages } from './messages';
import {
  allGamesFinal, childEntries, childKeysOf, FantasyDb, fantasyRoot,
  freezesWeekDate, fullAttendance, gamesOfDate, isPlainMap, isRewinding,
  isServerSquadWrite, isTestFillSeason, isVoidFlag, keyedGamesOfDate,
  latestScoredWeek, listFantasySeasons, loadSeasonGameweeks,
  lockedPositionsOf, lockedWeeksOf, lockOverrideOf,
  marketPlayersOf, marketPricesOf, markServerSquadWrite, parseAbsentMap,
  positionsSnapshotOf, rosterNamesOf, scheduleOverridesOf,
  SEASON_BADGES_SETTLED_NODE, SERVER_WRITE_KEY, TEST_FILL_STAND_DOWN,
  toIntLoose, updateIfPresent, voidedWeeksOf, withLockedPositions,
} from './orchestration_db';
import { applyDelta, repriceDeltas } from './pricing';
import {
  adminUidsOf, FantasyPusher, fantasyPushData, fillReminderTemplate,
  formatDeadlineInstant, NEWS_READY_TITLE, newsReadyBody,
  OVER_BUDGET_PREVIEW_TITLE, overBudgetPreviewBody, RECAP_TITLE, recapBody,
  REMINDER_TITLE, reminderAudience, reminderConfigFrom, reminderInstantMs,
} from './pushes';
import {
  applyPendingPositionChanges, positionWindowOf,
} from './position_changes';
import {
  healOpenWeek, rewindCancelledWeek, upsertGwState,
} from './schedule_rewind';
import {
  FantasySquad, squadFromMap, squadToMap, validateSquad,
} from './squad';
import {
  baselineForGwOf, baselineNodeOf, baselineRealizedTenthsOf,
  integrityMarketOf, IntegrityInputs, integrityVerdictOf, invalidAlertNode,
  isIntegrityAlert, isPreviewAlert, judgeSquad, lockTimePrevOf,
  overBudgetTenthsOf, previewAlertNode, priceSnapshotOf, sameBaselineNode,
  sameInvalidAlert,
  samePreviewAlert, SquadIntegrityIssue,
} from './squad_integrity';
import { parseForfeitedBy } from './stats_mapper';
import {
  annotateSquadIntegrity, LockAccounting, lockAccounting, parseTransferState,
  pickIdsOf, rolloverState, transferStateToNode, usedAfterFreeSwaps,
} from './transfer_state';

/** Injected logging seam (firebase-functions/logger in production, a spy or
 *  nothing in tests). */
export interface FantasyLogger {
  info(message: string, context?: Record<string, unknown>): void;
  warn(message: string, context?: Record<string, unknown>): void;
}

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

/** Impure capabilities injected into the jobs. Everything is optional: a
 *  caller without one (tests, a misconfigured deploy) skips that side
 *  effect — and its once-only guard stays unclaimed, so a later properly
 *  equipped run still delivers. */
export interface FantasyJobDeps {
  /** FCM (Phase F): deadline reminders + weekly recaps. */
  pusher?: FantasyPusher;
  /** Anthropic (Phase G): AI news drafting after finalize. A blank apiKey
   *  (or an API failure) skips the AI drafts with a log — the deterministic
   *  Dream Team post still builds, and finalize never blocks. */
  news?: { apiKey: string; fetchImpl?: FetchLike; timeoutMs?: number };
  /** Wall clock (epoch ms) stamping the live node's ReadAt (LIVE ORDERING
   *  in the header). Date.now when absent — tests pin it. */
  clock?: () => number;
}

// GwState's writer (the sweep's step 3, shared with the rewind and the
// Config trigger) lives in schedule_rewind.ts with the node's shape.
export { upsertGwState } from './schedule_rewind';
export type { GwStateNode } from './schedule_rewind';

/** Map-shaped children only (a squad/history uid node must be a map). */
function mapChildren(node: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of childEntries(node)) {
    if (isPlainMap(v)) out[k] = v;
  }
  return out;
}

// ── Phase E: transfer accounting ───────────────────────────────────────────

/** Merge the lock's frozen results into each manager's TransferState
 *  (read-modify-write, not a transaction — it runs inside the lock's
 *  once-only claim, or a first finalize):
 *  - ChipPlayed = the effective chip; a no-chip week clears any stale one
 *    (so a crashed earlier lock can never leak a Free Hit restore).
 *  - UsedThisGw raised to the lock's recount when that is higher (FPL
 *    selling plan Task 5 — lockAccounting usedByUid, max against the value
 *    re-read here), so the rollover banks from the transfers really made,
 *    not from a count a missed save never updated. Logged. Skipped when
 *    the manager already saved for a LATER gameweek (SavedGw > gw — a late
 *    first finalize): that counter is next week's and survives the
 *    rollover.
 *  Every other field survives. usedByUid's uids are a subset of
 *  chipPlayedByUid's (both are the parseable squads). */
async function freezeLockTransferState(
  db: FantasyDb, root: string, cfg: FantasyConfig, gw: number,
  acc: Pick<LockAccounting, 'chipPlayedByUid' | 'usedByUid'>,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  for (const [uid, chip] of Object.entries(acc.chipPlayedByUid)) {
    const state = parseTransferState(
      await db.read(`${root}/TransferState/${uid}`), cfg);
    let usedThisGw = state.usedThisGw;
    const recounted = acc.usedByUid[uid];
    const laterWeek = state.savedGw !== null && state.savedGw > gw;
    if (recounted !== undefined && recounted > usedThisGw && !laterWeek) {
      log.info('fantasy transfers: lock recount raised the count',
        { ...ctx, uid, gw, stored: usedThisGw, recounted });
      usedThisGw = recounted;
    }
    await db.write(`${root}/TransferState/${uid}`,
      transferStateToNode({ ...state, chipPlayed: chip, usedThisGw }));
  }
}

/** The squad a manager effectively HELD coming out of gameweek [week]: the
 *  locked squad of [week] (PublishedPicks/<week>/<uid>, else
 *  History/<week>/<uid>) — except after a Free Hit week, whose squad lasts
 *  ONE week (spec §6): then it is the effective squad of the week before,
 *  recursively (a set-2 Free Hit right after a set-1 Free Hit still returns
 *  to the last real squad). A Free Hit with nothing before it (a GW1 Free
 *  Hit) keeps its own squad — there was nothing to restore. null = no locked
 *  squad for [week]. Voided chips were stripped from the snapshot at lock,
 *  so only an HONORED Free Hit ever redirects.
 *
 *  The ONE baseline shared by the Free Hit restore (what goes back into
 *  Squads/<uid>) and the transfer counter (what a save is compared
 *  against), so the two can never disagree — the S15 rehearsal's Bug 1 was
 *  exactly that disagreement (the counter compared against the Free Hit
 *  squad while the restore had already put the old squad back). */
async function effectiveSquadAfterWeek(
  db: FantasyDb, root: string, uid: string, week: number,
): Promise<Record<string, unknown> | null> {
  if (week <= 0) return null;
  const locked = (await db.read(`${root}/PublishedPicks/${week}/${uid}`)) ??
    (await db.read(`${root}/History/${week}/${uid}`));
  if (!isPlainMap(locked)) return null;
  if (locked['chip'] === 'freeHit') {
    return (await effectiveSquadAfterWeek(db, root, uid, week - 1)) ?? locked;
  }
  return locked;
}

// ── Squad integrity (audit I2, squad hardening 2026-11-01) ─────────────────

/** Everything squad_integrity.ts needs to judge the squads of [uids] for
 *  gameweek [gw]: the market (Players), each manager's EFFECTIVE previous
 *  squad (effectiveSquadAfterWeek(gw-1) — the transfer counter's baseline,
 *  so "held" means the same thing to both), the prices during gw-1
 *  (PriceHistory/<gw-1>), and the running sale total of every manager whose
 *  Baselines/<uid> was written FOR this gameweek (ForGw === gw — the one
 *  source the fan app shows; squad_integrity.ts baselineRealizedFor). */
async function loadIntegrityInputs(
  db: FantasyDb, root: string, uids: string[], gw: number,
  /** A Players node the caller already read (null = read and absent): used
   *  as the market instead of reading it again. */
  playersNode?: unknown,
): Promise<IntegrityInputs> {
  const previousByUid: Record<string, unknown> = {};
  const baselineRealizedByUid: Record<string, number> = {};
  for (const uid of uids) {
    const prev = await effectiveSquadAfterWeek(db, root, uid, gw - 1);
    if (prev !== null) previousByUid[uid] = prev;
    const baseline = await db.read(`${root}/Baselines/${uid}`);
    if (baselineForGwOf(baseline) === gw) {
      baselineRealizedByUid[uid] = baselineRealizedTenthsOf(baseline);
    }
  }
  return {
    market: integrityMarketOf(playersNode !== undefined
      ? playersNode : await db.read(`${root}/Players`)),
    previousByUid,
    previousWeekPrices: gw > 1
      ? priceSnapshotOf(await db.read(`${root}/PriceHistory/${gw - 1}`)) : {},
    baselineRealizedByUid,
  };
}

/** Writes Fantasy/<sport>/<season>/Baselines/<uid> (squad_integrity.ts
 *  baselineNodeOf) = the manager's effective squad after gameweek [gw]
 *  (effectiveSquadAfterWeek — a Free Hit week's is the week before), FOR
 *  gameweek gw + 1, for EVERY manager: Managers ∪ Squads ∪
 *  PublishedPicks/<gw> ∪ the uids that already have a Baselines node (so
 *  a manager who deletes his Managers row and his squad still has his
 *  running total rolled forward). A manager with no squad at the lock gets
 *  {ForGw: gw + 1, RealizedTenths: carried (0 for a first-timer), Prices:
 *  {}} — the judge treats his next squad as a fresh start, and the app can
 *  still save.
 *
 *  Called by the lock (snapshotPublishedPicks, after its claim) and by
 *  EVERY finalize run after History/<gw> (self-heals a lost lock-time
 *  write). Never backwards: nothing at all is written when gw + 1 is
 *  before the next lock's gameweek (nextLockGwOf(GwState) — a score-edit
 *  rerun of an old week), a stored node FOR a later gameweek than gw + 1
 *  is left alone, and a stored node that already says the same is not
 *  rewritten (reruns write nothing). The per-node check runs again inside
 *  a transaction, so a newer baseline landing in between survives. One
 *  manager's failure is logged and never stops the others.
 *
 *  THE PREV STASH ([M3], squad_integrity.ts): the lock-time call
 *  ([opts.stashPrev], from snapshotPublishedPicks) gives every node it
 *  writes `Prev` = the node it replaces (lockTimePrevOf: none when there
 *  was none), so the sweep's rewind of a called-off week restores it
 *  exactly; its equality check ignores Prev, so a second lock-time run — a
 *  concurrent one too, whose transaction re-runs on the fresh node — writes
 *  nothing and keeps the stash. A finalize that wrote History calls it
 *  without: its nodes carry no Prev and a stored one is dropped (a scored
 *  week is never rewound); a finalize that wrote none stashes like the lock
 *  (its week can still be rewound). */
export async function publishSaleBaselines(
  db: FantasyDb, root: string, gw: number,
  log: FantasyLogger = silent, ctx: Record<string, unknown> = {},
  opts: { stashPrev?: boolean } = {},
): Promise<void> {
  const stashPrev = opts.stashPrev === true;
  const forGw = gw + 1;
  // A node FOR a week before the next lock is never read (the app sees it
  // as stale and blocks the Save; the judge reads only ForGw === the week
  // it judges), so an older week's rerun writes nothing at all — it must
  // not CREATE a stale node for a manager who has none (absent = "first
  // squad, ready"). At the lock of gw the floor is gw (GwState still 'open'
  // — the sweep flips it after the snapshot) or gw + 1; at the finalize of
  // gw it is gw + 1; a stale GwState (sweep down) only lowers it; no
  // GwState = 1 (nothing skipped).
  if (forGw < nextLockGwOf(await db.read(`${root}/GwState`))) return;
  const uids = new Set<string>();
  for (const node of [
    await db.read(`${root}/Managers`),
    await db.read(`${root}/Squads`),
    await db.read(`${root}/PublishedPicks/${gw}`),
    await db.read(`${root}/Baselines`),
  ]) {
    for (const [uid] of childEntries(node)) uids.add(uid);
  }
  let written = 0;
  for (const uid of [...uids].sort()) {
    const path = `${root}/Baselines/${uid}`;
    try {
      const effective = await effectiveSquadAfterWeek(db, root, uid, gw);
      // undefined = leave the stored node alone (newer, or already equal).
      // A first (cold) run sees null and proposes the node (no Prev) —
      // never aborts; RTDB re-runs it on the real node, which decides.
      const next = (stored: unknown): unknown => {
        const storedFor = baselineForGwOf(stored);
        if (storedFor !== null && storedFor > forGw) return undefined;
        const node = baselineNodeOf(effective, forGw, stored);
        if (stashPrev) {
          const prev = lockTimePrevOf(stored, forGw);
          if (prev !== null) node.Prev = prev;
        }
        return sameBaselineNode(stored, node, { stashPrev }) ? undefined : node;
      };
      if (next(await db.read(path)) === undefined) continue;
      if ((await db.transaction(path, next)).committed) written++;
    } catch (err) {
      log.warn('fantasy baselines: write failed — retried by the next ' +
        'finalize or lock',
        { ...ctx, gw, uid, error: String(err) });
    }
  }
  if (written > 0) {
    log.info('fantasy baselines: published', { ...ctx, gw, forGw, written });
  }
}

/** After an integrity pass for gameweek [gw]: each invalid squad's manager
 *  gets the SquadAlerts/<uid> Invalid alert (rewritten only when it
 *  differs — reruns write nothing; a standing over-budget PREVIEW, even for
 *  the same week and issue, is replaced by it) and a warn; a clean squad
 *  whose manager still carries an integrity alert of either kind (an
 *  earlier week's Invalid, or this week's preview) has it cleared (this
 *  week counts). A position-change alert is never touched here. */
async function settleIntegrityAlerts(
  db: FantasyDb, root: string, gw: number,
  verdict: {
    invalid: Array<{ uid: string; issues: SquadIntegrityIssue[] }>;
    valid: string[];
  },
  nowMs: number, log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  if (verdict.invalid.length === 0 && verdict.valid.length === 0) return;
  const alertsNode = await db.read(`${root}/SquadAlerts`);
  const alerts: Record<string, unknown> = isPlainMap(alertsNode) ? alertsNode : {};
  for (const { uid, issues } of verdict.invalid) {
    log.warn('fantasy lock: invalid squad — scored zero this week',
      { ...ctx, gw, uid, issues });
    if (sameInvalidAlert(alerts[uid], gw, issues)) continue;
    await db.write(`${root}/SquadAlerts/${uid}`,
      invalidAlertNode(gw, issues, nowMs));
  }
  for (const uid of verdict.valid) {
    if (!isIntegrityAlert(alerts[uid])) continue;
    await db.write(`${root}/SquadAlerts/${uid}`, null);
    log.info('fantasy lock: squad valid again — integrity alert cleared',
      { ...ctx, gw, uid });
  }
}

/** Own-key lookup (a uid is never an Object.prototype name). */
function hasKey(m: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(m, key);
}

/** The market's price fingerprint (scale fixes D8): the sha1 hex of the
 *  sorted `name:priceTenths` lines (joined with "\n") of every Players entry
 *  that carries a numeric priceTenths — the one input of the over-budget
 *  preview that moves between sweeps. Key order never matters; any price
 *  change, a listing added or removed, changes it. Everything else on a
 *  player (position, eligibility, team) is ignored, as are entries with no
 *  numeric price. A missing or malformed node fingerprints as the empty
 *  market. */
export function pricesFingerprint(playersNode: unknown): string {
  const lines: string[] = [];
  for (const [name, player] of childEntries(playersNode)) {
    if (!isPlainMap(player)) continue;
    const tenths = player['priceTenths'];
    if (typeof tenths === 'number' && Number.isFinite(tenths)) {
      lines.push(`${name}:${tenths}`);
    }
  }
  return createHash('sha1').update(lines.sort().join('\n')).digest('hex');
}

/** Sweep step 3c — THE OVER-BUDGET PREVIEW (FPL selling, spec §4; the
 *  contract lives in squad_integrity.ts): while gameweek [gw] is open,
 *  re-judge every saved squad with the inputs its lock will use
 *  (loadIntegrityInputs for [gw]) so a fan whose saved team drifted over
 *  budget (a reprice or owner edit after a sale) hears about it before the
 *  deadline:
 *  - issues include overBudget → SquadAlerts/<uid> = the preview (written
 *    only when Gw or OverTenths moved) and, the first time this gameweek,
 *    ONE push: the PreviewPushed/<gw>/<uid> claim lands set-if-absent
 *    BEFORE the send (the reminder's pattern — concurrent sweeps never
 *    double-push); no [pusher] = no claim, no push;
 *  - otherwise (clean, forged-but-not-over, malformed, or no squad any
 *    more) → a standing preview is cleared;
 *  - an Invalid or position-change alert in the slot wins: that manager is
 *    skipped (no write, no push) and re-checked on the next full pass (see
 *    THE GATE: a price or budget change, a standing preview, a new week, or
 *    a reopened week).
 *  One manager's failure is logged and never stops the others.
 *
 *  THE GATE (scale fixes D8): the pass above reads the whole Squads node, so
 *  a sweep runs it only when the market's prices or the budget differ from
 *  the ones stamped by the last full pass of this gameweek
 *  (<root>/SquadAlertsCheck = {Gw, PricesHash, BudgetTenths};
 *  pricesFingerprint; an older stamp without BudgetTenths never matches) or
 *  any preview alert is standing (re-judged every sweep so a fixed squad's
 *  alert clears). The stamp is written after a pass that handled every
 *  manager — a pass that throws, or one manager's failed write, leaves it
 *  for the next sweep to retry. A rewind of the week removes it
 *  (schedule_rewind.ts), so the reopened week runs one full pass. */
async function previewOverBudget(
  db: FantasyDb, root: string, cfg: FantasyConfig,
  args: {
    sport: string; season: string; gw: number; lockUtcMs: number;
    nowMs: number; pusher?: FantasyPusher;
  },
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  const { gw, nowMs, pusher } = args;
  // THE GATE (scale fixes D8): the full pass reads every saved squad, so it
  // runs only when something it judges may have moved — the market's prices
  // or the budget (they differ from the ones stamped after the last full
  // pass, or no pass of this gameweek ran yet) — or a preview alert is
  // standing (a fixed squad's alert must clear, so it is re-judged every
  // sweep). The three reads below (SquadAlerts, Players, the stamp) are all
  // small.
  const alertsNode = await db.read(`${root}/SquadAlerts`);
  const alerts: Record<string, unknown> = isPlainMap(alertsNode) ? alertsNode : {};
  const playersNode = await db.read(`${root}/Players`);
  const pricesHash = pricesFingerprint(playersNode);
  const stored = await db.read(`${root}/SquadAlertsCheck`);
  const stamped = isPlainMap(stored) && stored['Gw'] === gw &&
    stored['PricesHash'] === pricesHash &&
    stored['BudgetTenths'] === cfg.budgetTenths;
  const standingPreview = Object.values(alerts).some(isPreviewAlert);
  if (stamped && !standingPreview) return;
  // The stamp is written only after a pass that handled every manager, with
  // the very prices it judged (Players is read once above): a pass that
  // throws, or one manager whose write failed, leaves the old stamp so the
  // next sweep retries.
  const stampPass = async (): Promise<void> => {
    if (stamped) return; // a standing-preview pass at unchanged prices
    await db.write(`${root}/SquadAlertsCheck`, {
      Gw: gw, PricesHash: pricesHash, BudgetTenths: cfg.budgetTenths,
    });
  };
  const squads = mapChildren(await db.read(`${root}/Squads`));
  // Every saved squad, plus every standing preview (a squad deleted since
  // the preview was written still has it cleared).
  const uids = new Set(Object.keys(squads));
  for (const [uid, node] of Object.entries(alerts)) {
    if (isPreviewAlert(node)) uids.add(uid);
  }
  if (uids.size === 0) {
    await stampPass();
    return;
  }
  const inputs = await loadIntegrityInputs(
    db, root, Object.keys(squads), gw, playersNode);
  const claimsNode = pusher ? await db.read(`${root}/PreviewPushed/${gw}`) : null;
  const claimed: Record<string, unknown> = isPlainMap(claimsNode) ? claimsNode : {};
  const deadline = formatDeadlineInstant(args.lockUtcMs);
  const data = fantasyPushData(args.sport, args.season, gw);
  let alerted = 0;
  let cleared = 0;
  let pushed = 0;
  let failed = 0;
  for (const uid of [...uids].sort()) {
    const path = `${root}/SquadAlerts/${uid}`;
    try {
      const standing = hasKey(alerts, uid) ? alerts[uid] : null;
      if (standing != null && !isPreviewAlert(standing)) continue;
      const verdict = hasKey(squads, uid)
        ? integrityVerdictOf(squads[uid], uid, cfg, inputs) : null;
      const over = verdict !== null && verdict.issues.includes('overBudget')
        ? overBudgetTenthsOf(verdict, cfg) : 0;
      if (over <= 0) {
        if (standing != null) {
          await db.write(path, null);
          cleared++;
        }
        continue;
      }
      if (!samePreviewAlert(standing, gw, over)) {
        await db.write(path, previewAlertNode(gw, over, nowMs));
        alerted++;
      }
      if (!pusher || hasKey(claimed, uid)) continue;
      if (!(await db.writeIfAbsent(
        `${root}/PreviewPushed/${gw}/${uid}`, { At: nowMs }))) {
        continue; // a concurrent sweep claimed (and sends) it
      }
      pushed += await pusher.sendToUsers([{
        uid, title: OVER_BUDGET_PREVIEW_TITLE,
        body: overBudgetPreviewBody(over, deadline), data,
      }]);
    } catch (err) {
      failed++;
      log.warn('fantasy preview: over-budget check failed for one manager — ' +
        'the others go on', { ...ctx, gw, uid, error: String(err) });
    }
  }
  if (alerted + cleared + pushed > 0) {
    log.info('fantasy preview: over-budget alerts settled',
      { ...ctx, gw, alerted, cleared, pushed });
  }
  if (failed === 0) await stampPass();
}

/** Chips are ONE-WEEK (S15 rehearsal Bug 2, owner decision 2026-10-28):
 *  once a gameweek settles, whatever chip the live squad still carries is
 *  switched off (Squads/<uid>/chip removed), so next week starts chipless.
 *  A chip may still be played again in set 2 — by a FRESH activation; a
 *  forgotten chip can no longer sit armed and auto-fire at the first set-2
 *  lock. Every chip type, honored or voided at lock.
 *
 *  One guard for a DELAYED finalize (the next window already open and the
 *  manager already saved for it, SavedGw > gw): a live chip that differs
 *  from the one locked this week is a deliberate activation for next week
 *  and stays. (Documented limit: in that delayed case a chip that was
 *  VOIDED at this week's lock stays too — it is voided again at the next
 *  lock inside the same set.) */
async function switchOffSpentChip(
  db: FantasyDb, root: string, uid: string, gw: number,
  savedGw: number | null, nowMs: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  const live = await db.read(`${root}/Squads/${uid}`);
  if (!isPlainMap(live) || live['chip'] == null) return;
  const chip = live['chip'];
  if (savedGw !== null && savedGw > gw) {
    const locked = (await db.read(`${root}/PublishedPicks/${gw}/${uid}`)) ??
      (await db.read(`${root}/History/${gw}/${uid}`));
    const lockedChip = isPlainMap(locked) ? (locked['chip'] ?? null) : null;
    if (chip !== lockedChip) return; // a fresh activation for next week
  }
  // A server write, not a manager save (orchestration_db.ts SERVER_WRITE_KEY):
  // the marker lands first so the Squads trigger never stamps SavedGw.
  await markServerSquadWrite(db, root, uid, nowMs);
  await db.write(`${root}/Squads/${uid}/chip`, null);
  log.info('fantasy chips: spent chip switched off', { ...ctx, gw, uid, chip });
}

/** Once per gameweek, right after a finalize wrote History/<gw> (RolledGw is
 *  the guard — reruns from score/attendance edits never re-settle): restore
 *  a Free Hit manager's previous squad, switch off any chip still armed on
 *  the live squad (chips are one-week), then roll free transfers for next
 *  week. The restored squad is the engine round-trip of the manager's
 *  effective squad before the Free Hit (effectiveSquadAfterWeek(gw-1)) with
 *  NO chip — a restore never re-arms a chip. A GW1 Free Hit has nothing to
 *  restore (logged); its chip is still switched off.
 *
 *  THE ROLLOVER AUDIENCE: [scoredUids] (this finalize's History/<gw> keys)
 *  UNION every manager who already has a TransferState node. A manager who
 *  was not scored this week — his squad was deleted before the lock — still
 *  needs next week's Free and baseline; leaving him out froze his Free and
 *  left his stale CountFrom for the app to count against. He rolls as if he
 *  used nothing (nothing was charged), and the Free Hit restore and chip
 *  switch-off below stay scored-only (they act on a locked squad he does not
 *  have). An unscored manager already working on a week beyond gw + 1
 *  (a manager who joined after this week, reached by a rerun of an old week)
 *  is skipped: rolling him for gw would overwrite his own baseline.
 *
 *  Per manager: [firstWeek] = no effective squad the week before (his first
 *  team: free to build, so nothing banks — rolloverFreeTransfers), and the
 *  published baseline for next week is the effective squad AFTER this week
 *  (a Free Hit week's is the week before — the one the restore put back, so
 *  the two can never disagree). RolledGw is checked first so a rerun never
 *  re-rolls. */
async function settleTransfersAfterFinalize(
  db: FantasyDb, root: string, cfg: FantasyConfig, gw: number,
  scoredUids: string[], nowMs: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  const scored = new Set(scoredUids);
  const uids = new Set(scoredUids);
  for (const [uid] of childEntries(await db.read(`${root}/TransferState`))) {
    uids.add(uid);
  }
  for (const uid of uids) {
    const state = parseTransferState(
      await db.read(`${root}/TransferState/${uid}`), cfg);
    if (state.rolledGw !== null && state.rolledGw >= gw) continue;
    const wasScored = scored.has(uid);
    // A latecomer an old week's rerun reaches: his own baseline stands.
    const workingOn = Math.max(state.savedGw ?? 0, state.countFrom?.gw ?? 0);
    if (!wasScored && workingOn > gw + 1) {
      log.info('fantasy transfers: rollover skipped — manager already ' +
        'working on a later week', { ...ctx, uid, gw, workingOn });
      continue;
    }
    const before = await effectiveSquadAfterWeek(db, root, uid, gw - 1);
    if (wasScored && state.chipPlayed === 'freeHit') {
      let restored: Record<string, unknown> | null = null;
      if (isPlainMap(before)) {
        try {
          restored = squadToMap({ ...squadFromMap(before), chip: null });
        } catch { /* unreadable previous squad — warn below */ }
      }
      if (restored !== null) {
        // Server-originated (SERVER_WRITE_KEY): the restore is not the
        // manager saving, so it must not satisfy the deadline reminder.
        await db.write(`${root}/Squads/${uid}`,
          { ...restored, [SERVER_WRITE_KEY]: nowMs });
        log.info('fantasy freeHit: previous squad restored', { ...ctx, gw, uid });
      } else {
        log.warn('fantasy freeHit: no previous locked squad to restore',
          { ...ctx, gw, uid });
      }
    }
    if (wasScored) {
      await switchOffSpentChip(db, root, uid, gw, state.savedGw, nowMs, log, ctx);
    }
    const after = await effectiveSquadAfterWeek(db, root, uid, gw);
    await db.write(`${root}/TransferState/${uid}`,
      transferStateToNode(rolloverState(state, cfg, gw, {
        firstWeek: !isPlainMap(before),
        countFromIds: pickIdsOf(after),
        scored: wasScored,
      })));
  }
}

/** The gameweek the NEXT lock will judge, from GwState: the current one
 *  while it is 'open', else the one after it; no GwState = GW1. */
function nextLockGwOf(gwState: unknown): number {
  if (!isPlainMap(gwState)) return 1;
  const current = toIntLoose(gwState['current']);
  if (current <= 0) return 1;
  return String(gwState['status'] ?? '') === 'open' ? current : current + 1;
}

export interface SquadSaveArgs {
  sport: string;
  season: string;
  uid: string;
  log?: FantasyLogger;
  /** When the save happened (the trigger passes the event time —
   *  writeTimeOf): the position-window, lockOverride and post-lock checks
   *  all judge it. Default: real now. */
  nowUtc?: Date;
  /** The triggering write's after-value (event.data.after.val()) — WHO
   *  wrote is judged on it (SERVER_WRITE_KEY), so a manager save that races
   *  a server write is still counted. Absent (tests, the rehearsal's
   *  replay) = judged on the node as read now. */
  after?: unknown;
}

/** The Squads/<uid> trigger entry (Phase E + spec §3 holder protection).
 *
 *  1. Holder protection, on every save of a fantasy-enabled 'auto' season:
 *     - while position changes apply live (positionWindowOf 'open'), any
 *       pick whose label differs from the player's LIVE market position is
 *       re-labelled (child write) — so a save from a stale draft (an old
 *       app, or a draft dirty since before the change) can never quietly
 *       revert a position change or dodge its alert;
 *     - a standing SquadAlerts/<uid> is cleared once the (re-labelled)
 *       squad's formation is legal — or, for an integrity alert (Kind
 *       'invalid' or the over-budget 'preview'), once the squad would pass
 *       the next lock's judge.
 *  2. Transfer counting, while the current gameweek is open: recompute the
 *     used-transfer count against the manager's EFFECTIVE previous squad
 *     (effectiveSquadAfterWeek(gw-1): the squad locked last week — or,
 *     after a Free Hit week, the squad the restore put back), minus any
 *     alerted player sold this week (FreeSwaps — free by spec §3), and
 *     stamp SavedGw. Counting needs a baseline, so a first-ever squad (GW1,
 *     or a mid-season joiner) records UsedThisGw 0 — the initial build is
 *     free — but still stamps SavedGw so the deadline reminder knows the
 *     manager acted this week. Recomputed (not incremented) on every save:
 *     undoing a transfer before the deadline un-counts it. Saves while the
 *     gameweek is locked, under a 'locked' lockOverride, and squad
 *     deletions are never counted. Deleting a squad and saving a new one
 *     inside the open week is NOT a first team: last week's locked squad is
 *     still the baseline, so every new player counts.
 *     THE BASELINE the count used is published in the same write
 *     (CountFromGw = this gameweek, CountFrom = the baseline squad's player
 *     ids; ids absent = no baseline squad, the "first team" marker) — the
 *     fan app counts its live draft against exactly it.
 *     POST-LOCK SAVES (audit I3, 2026-11-01): a save at or after
 *     GwState.lockAtUtc is not counted even while GwState still says
 *     'open' (the sweep flips it up to 15 minutes later) — logged at info.
 *     Belt-and-braces: the Squads/<uid> rule already rejects such a client
 *     write by the server clock; this catches a write that slipped past a
 *     stale GwState. [nowUtc] is the WRITE's time (the trigger passes the
 *     event time), so a save accepted at 2:59:59 whose trigger runs at
 *     3:00:02 still counts. Under an effective 'open' lockOverride the
 *     owner has extended the window, so it keeps counting (I4 below).
 *     PAUSED-OPEN WINDOW (audit I4, 2026-10-31): an EFFECTIVE 'open'
 *     lockOverride (the owner's "Open for 24 h" with an auto-return) does
 *     NOT stand this down — the sweep and the lock are paused, but managers
 *     are trading, and the recount is pure (the lock is what charges, from
 *     this ledger). Standing down here lost every transfer made in the
 *     window (charged from a stale UsedThisGw at the next lock) and left
 *     SavedGw unstamped (a wrong "untouched squad" reminder). Only 'locked'
 *     (and a non-fantasy or TestFill season) stands it down.
 *     SERVER-ORIGINATED writes (the node carries SERVER_WRITE_KEY — chip
 *     switch-off, Free Hit restore, position re-labels, incl. this
 *     function's own) are recounted the same way but NEVER stamp SavedGw:
 *     only the manager's own save means "acted this week" for the deadline
 *     reminder. A SavedGw from an earlier manager save is kept as is. */
export async function recordSquadSave(
  db: FantasyDb, args: SquadSaveArgs,
): Promise<void> {
  const { sport, season, uid } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, uid };
  const nowMs = (args.nowUtc ?? new Date()).getTime();

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  // A 'locked' override freezes the market: nothing to count. An 'open' one
  // (the owner's routine "Open for 24 h") keeps counting — see the doc.
  if (lockOverrideOf(configNode, nowMs) === 'locked') return;
  if (await isTestFillSeason(db, root)) { // fake data: never recount it
    log.info(TEST_FILL_STAND_DOWN, { ...ctx, job: 'squadSave' });
    return;
  }
  const cfg = configFromMap(configNode);

  const gwState = await db.read(`${root}/GwState`);
  const raw = await db.read(`${root}/Squads/${uid}`);
  if (!isPlainMap(raw)) return; // deletion: nothing to count
  const serverWrite =
    isServerSquadWrite(args.after !== undefined ? args.after : raw);
  let squad: FantasySquad;
  try {
    squad = squadFromMap(raw);
  } catch {
    log.warn('fantasy transfers: malformed squad save — not counted', ctx);
    return;
  }

  // ── 1. Holder protection ──
  if (positionWindowOf(gwState, nowMs) === 'open') {
    const market = marketPlayersOf(await db.read(`${root}/Players`));
    let relabels = 0;
    for (const [k, pick] of childEntries(raw['picks'])) {
      if (!isPlainMap(pick)) continue;
      const live = market[String(pick['playerId'] ?? '')]?.position;
      if (live !== undefined && pick['position'] !== live) {
        // Our own re-label is a server write: mark first (once), so its
        // trigger re-run never counts as a manager save.
        if (relabels === 0) await markServerSquadWrite(db, root, uid, nowMs);
        await db.write(`${root}/Squads/${uid}/picks/${k}/position`, live);
        relabels++;
      }
    }
    if (relabels > 0) {
      squad = {
        ...squad,
        picks: squad.picks.map((p) =>
          ({ ...p, position: market[p.playerId]?.position ?? p.position })),
      };
      log.info('fantasy positions: stale labels on a save re-labelled',
        { ...ctx, relabels });
    }
  }
  const alertNode = await db.read(`${root}/SquadAlerts/${uid}`);
  if (isIntegrityAlert(alertNode)) {
    // An integrity alert ("your GW n team didn't count", audit I2 — or the
    // open window's over-budget preview, squad_integrity.ts) clears once
    // the saved squad would pass the NEXT lock's judge — the same inputs
    // the lock will use (its gameweek's baseline and prices). A save that
    // is still over budget keeps the preview (the next sweep re-prices it).
    const target = nextLockGwOf(gwState);
    const inputs = await loadIntegrityInputs(db, root, [uid], target);
    if (judgeSquad(squad, uid, cfg, inputs).issues.length === 0) {
      await db.write(`${root}/SquadAlerts/${uid}`, null);
      log.info('fantasy integrity: clean squad saved — alert cleared',
        { ...ctx, gw: target });
    }
  } else if (alertNode != null &&
    !validateSquad(squad, cfg).includes('formation')) {
    await db.write(`${root}/SquadAlerts/${uid}`, null);
    log.info('fantasy positions: formation legal — squad alert cleared', ctx);
  }

  // ── 2. Transfer counting (open gameweek only) ──
  if (!isPlainMap(gwState) || String(gwState['status'] ?? '') !== 'open') return;
  const gw = toIntLoose(gwState['current']);
  if (gw <= 0) return;
  // Audit I3: the lock instant is the deadline, whatever the stale status.
  const lockAt = toIntLoose(gwState['lockAtUtc']);
  if (lockAt > 0 && nowMs >= lockAt &&
    lockOverrideOf(configNode, nowMs) === 'auto') {
    log.info('fantasy transfers: save after the lock — not counted',
      { ...ctx, gw, lockAtUtc: lockAt, savedAtMs: nowMs, serverWrite });
    return;
  }

  const state = parseTransferState(
    await db.read(`${root}/TransferState/${uid}`), cfg);
  let used = 0;
  const prevRaw = await effectiveSquadAfterWeek(db, root, uid, gw - 1);
  if (isPlainMap(prevRaw)) {
    try {
      used = usedAfterFreeSwaps(squad, squadFromMap(prevRaw), state, gw);
    } catch {
      log.warn('fantasy transfers: unreadable previous squad — counted 0',
        { ...ctx, gw });
    }
  }

  await db.write(`${root}/TransferState/${uid}`, transferStateToNode({
    ...state, usedThisGw: used, savedGw: serverWrite ? state.savedGw : gw,
    countFrom: { gw, ids: pickIdsOf(prevRaw) },
  }));
  log.info(serverWrite
    ? 'fantasy transfers: server squad write recounted (not a manager save)'
    : 'fantasy transfers: squad save counted', { ...ctx, gw, used });
}

// ── Phase C: finalization ──────────────────────────────────────────────────

/** The most recent PriceChanges rows at or before [gw] — the risers/fallers
 *  the managers are currently looking at (the news inputs; null = the
 *  season has not repriced yet). */
async function latestPriceChanges(
  db: FantasyDb, root: string, gw: number,
): Promise<unknown> {
  let best = -1;
  for (const [w] of childEntries(await db.read(`${root}/PriceChanges`))) {
    const week = Number(w);
    if (Number.isInteger(week) && week <= gw && week > best) best = week;
  }
  return best < 0 ? null : await db.read(`${root}/PriceChanges/${best}`);
}

const NO_CARDS_MSG = 'fantasy news: player cards unavailable — drafts without Players';

/** The news step's player-card builder: the card sources read once, fresh
 *  (finalize just wrote PlayerWeeks/PlayerTotals; goals/assists tally the
 *  whole season's Date node). Best-effort (review 2026-10-28): a source
 *  read or a card build that throws is logged and yields NO cards, so the
 *  drafts still go out — without Players — instead of not at all. */
async function newsCardBuilder(
  db: FantasyDb, sport: string, season: string,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<(names: string[]) => Array<PlayerCard | null>> {
  const root = fantasyRoot(sport, season);
  let sources: Parameters<typeof buildPlayerCard>[1] | null = null;
  try {
    sources = {
      playersRaw: await db.read(`${root}/Players`),
      playerTotalsRaw: await db.read(`${root}/PlayerTotals`),
      playerWeeksRaw: await db.read(`${root}/PlayerWeeks`),
      priceChangesRaw: await db.read(`${root}/PriceChanges`),
      goalsAssists: seasonGoalsAssists(await db.read(`${sport}/${season}/Date`)),
    };
  } catch (err) {
    log.warn(NO_CARDS_MSG, { ...ctx, error: String(err) });
  }
  const src = sources;
  return (names) => {
    if (src === null) return [];
    try {
      return names.map((name) => buildPlayerCard(name, src));
    } catch (err) {
      log.warn(NO_CARDS_MSG, { ...ctx, error: String(err) });
      return [];
    }
  };
}

/** One match-day game as the scorer takes it: roster-derived full
 *  attendance maps (spec §8 default-present) with the absent-only
 *  team{n}attendance node applied on top. [onNoRoster] hears each team
 *  without a Line Ups roster. Finalize and the live week both compose
 *  through here, so they score the same attendance. */
function scorableGame(
  node: Record<string, unknown>, lineups: unknown,
  onNoRoster: (team: string) => void,
): FinalizeGame {
  const attendance: Record<string, Record<string, boolean> | null> = {};
  (['team1', 'team2'] as const).forEach((key, i) => {
    const team = node[key];
    if (typeof team !== 'string' || team.length === 0) return;
    const roster = rosterNamesOf(lineups, team);
    if (roster.length === 0) onNoRoster(team);
    attendance[team] =
      fullAttendance(roster, parseAbsentMap(node[`team${i + 1}attendance`]));
  });
  return { node, attendance };
}

/** Stored per-week results other than week [skipGw] (finalize replaces its
 *  own week; the live base reads only earlier weeks anyway), as the pure
 *  engine takes them — shared by finalize and the live base:
 *  PlayerWeeks week -> name -> points. */
function playerWeeksByWeekOf(
  raw: unknown, skipGw: number,
): Record<number, Record<string, number>> {
  const out: Record<number, Record<string, number>> = {};
  for (const [w, byName] of childEntries(raw)) {
    const week = Number(w);
    if (!Number.isInteger(week) || week === skipGw) continue;
    const m: Record<string, number> = {};
    for (const [name, v] of childEntries(byName)) m[name] = toIntLoose(v);
    out[week] = m;
  }
  return out;
}

/** PlayerWeekStats week -> name -> games played (GP) — PlayerTotals
 *  games/ppg (see playerWeeksByWeekOf). */
function playedGamesByWeekOf(
  raw: unknown, skipGw: number,
): Record<number, Record<string, number>> {
  const out: Record<number, Record<string, number>> = {};
  for (const [w, byName] of childEntries(raw)) {
    const week = Number(w);
    if (!Number.isInteger(week) || week === skipGw) continue;
    const m: Record<string, number> = {};
    for (const [name, entry] of childEntries(byName)) {
      if (isPlainMap(entry)) m[name] = toIntLoose(entry['GP']);
    }
    out[week] = m;
  }
  return out;
}

/** History week -> uid -> net TotalTenths — the Overall board (see
 *  playerWeeksByWeekOf). */
function historyTenthsByWeekOf(
  raw: unknown, skipGw: number,
): Record<number, Record<string, number>> {
  const out: Record<number, Record<string, number>> = {};
  for (const [w, byUid] of childEntries(raw)) {
    const week = Number(w);
    if (!Number.isInteger(week) || week === skipGw) continue;
    const m: Record<string, number> = {};
    for (const [uid, entry] of childEntries(byUid)) {
      if (isPlainMap(entry)) m[uid] = toIntLoose(entry['TotalTenths']);
    }
    out[week] = m;
  }
  return out;
}

/** A first finalize this long after the lock with no PublishedPicks
 *  snapshot warns (the sweep runs every 15 minutes, so two missed sweeps). */
export const FIRST_FINALIZE_SNAPSHOT_GRACE_MS = 30 * 60 * 1000;

export interface FinalizeArgs {
  sport: string;
  season: string;
  cfg: FantasyConfig;
  /** The raw Config node the caller derived its week list from
   *  (SkippedDates — final review I2: a skipped day is never scored for the
   *  first time). */
  configNode: Record<string, unknown>;
  gw: Gameweek;
  nowUtc: Date;
  log?: FantasyLogger;
  deps?: FantasyJobDeps;
}

/** Loads one gameweek's inputs, runs the pure pipeline, writes every output
 *  node. Deterministic and rerunnable: whole-node sets of recomputed values
 *  (DreamTeam excepted — an admin-edited node is left alone). Returns a
 *  summary for the caller's log, or null when the date held no final games. */
export async function finalizeGameweek(
  db: FantasyDb, args: FinalizeArgs,
): Promise<{ managers: number; source: string } | null> {
  const { sport, season, cfg, gw } = args;
  const log = args.log ?? silent;
  const ctx = { sport, season, gw: gw.number, date: gw.date };
  const root = fantasyRoot(sport, season);

  // A week the sweep is rewinding (its day was called off) is never scored:
  // every entry point — the match-day trigger, the sweep's backstop, the
  // void re-settle — stands down here, and again right before the first
  // official write, where the run STAMPS the ledger entry by transaction
  // (stampFinalizing — final review I1: a mark, or a whole rewind, that
  // landed while this run computed). The entry as seen here is kept: one
  // that existed now and is gone then was rewound.
  const ledgerAtEntry = await db.read(`${root}/LockedWeeks/${gw.number}`);
  if (isRewinding(ledgerAtEntry)) {
    log.info(FINALIZE_REWINDING, ctx);
    return null;
  }

  const dateNode = await db.read(`${sport}/${season}/Date/${gw.date}`);
  const gameNodes = gamesOfDate(dateNode)
    .filter((g) => toIntLoose(g['status']) === 2);
  if (gameNodes.length === 0) {
    log.warn('fantasy finalize: no final games on date', ctx);
    return null;
  }

  // Attendance: roster-derived full maps (spec §8 default-present) with the
  // absent-only team{n}attendance node applied on top.
  const lineups = await db.read(`${sport}/${season}/Line Ups`);
  const games: FinalizeGame[] = gameNodes.map((node) =>
    scorableGame(node, lineups, (team) => {
      // On a forfeit (spec §8a) events are ignored, so a missing roster
      // means nobody on this team gets the appearance point — say so.
      log.warn('fantasy finalize: no roster for team — scoring activity ' +
        'players only', {
        ...ctx, team, forfeit: parseForfeitedBy(node['forfeitedBy']) !== null,
      });
    }));

  // Owner voids (spec §15): this week and every other voided week resum as
  // zero; chips from voided weeks are refunded in the lock accounting.
  const voidedWeeks = voidedWeeksOf(await db.read(`${root}/Voided`));
  const voided = voidedWeeks.includes(gw.number);

  // Manager squads: PublishedPicks (the lock snapshot) -> History (squad
  // part, for deterministic reruns) -> live Squads (first-run fallback; the
  // callers gate WHICH gameweeks may use it).
  const historyRaw = await db.read(`${root}/History`);
  const historyThisGw = childEntries(historyRaw)
    .find(([w]) => Number(w) === gw.number)?.[1] ?? null;
  const firstRun = historyThisGw == null;

  // A skipped game day is never scored for the FIRST time (final review
  // I2): a frozen week keeps its place in the week list after its day is
  // skipped, and the match-day trigger / the sweep's backstop would
  // otherwise score it before the sweep's rewind (or, for a week that is
  // not the latest locked one, ever). A rerun of a week already scored
  // still re-settles (a late score correction keeps counting).
  if (firstRun && scheduleOverridesOf(args.configNode).skippedDates.has(gw.date)) {
    log.info('fantasy finalize: game day skipped — not scored', ctx);
    return null;
  }

  // The market at this week's LOCKED positions (LockedPositions/<gw>); a
  // first run that outran every sweep freezes the week (LockedWeeks/<gw>)
  // and claims the snapshot itself. null = that claim was refused (the
  // ledger froze this number on another date, or a rewind marked it) or the
  // week stopped being frozen under the claim: scoring this date now would
  // write a History no ledger entry stands behind (final review I4) — the
  // run stands down before its first write.
  const players = await marketForGameweek(db, root, gw, firstRun, log, ctx);
  if (players === null) {
    log.warn('fantasy finalize: week frozen on another date — standing down',
      ctx);
    return null;
  }
  let source = 'publishedPicks';
  let squadsByUid = mapChildren(await db.read(`${root}/PublishedPicks/${gw.number}`));
  if (Object.keys(squadsByUid).length === 0) {
    squadsByUid = mapChildren(historyThisGw);
    source = 'history';
  }
  if (Object.keys(squadsByUid).length === 0) {
    squadsByUid = mapChildren(await db.read(`${root}/Squads`));
    source = 'squadsFallback';
  }
  // Audit I3: live Squads are only trustworthy as "the locked squads" when
  // read right at the lock (the rule freezes client saves from the lock
  // instant until a sweep opens the next week, or — once a sweep marked
  // the week locked — until lock + 24 h; the owner's 'open' override and
  // the server's own writes still move them). A FIRST finalize long after
  // the lock with no snapshot means the sweep was down through the lock —
  // say so loudly rather than silently scoring whatever is live now.
  const sinceLockMs = args.nowUtc.getTime() - gw.lockUtc.getTime();
  if (firstRun && source === 'squadsFallback' &&
    Object.keys(squadsByUid).length > 0 &&
    sinceLockMs > FIRST_FINALIZE_SNAPSHOT_GRACE_MS) {
    log.warn('fantasy finalize: first finalize without a lock snapshot — ' +
      'squads read live', {
      ...ctx, minutesAfterLock: Math.round(sinceLockMs / 60000),
      squads: Object.keys(squadsByUid).length,
    });
  }

  // ── Phase E: the week's frozen transfer costs. The lock step persisted
  // TransferCosts/<gw>; a FIRST finalize that outran every sweep (or the
  // live-Squads first run of a mid-season enablement) does the lock
  // accounting now, over whatever squad source resolved above, and persists
  // it so reruns stay deterministic. Reruns of weeks with no persisted
  // costs (pre-accounting weeks) read zeros, exactly as they settled. ──
  //
  // Squad integrity (audit I2): a FIRST run reading LIVE squads (no lock
  // snapshot, no History) judges them exactly as the lock would have — an
  // invalid squad scores zero, its verdict lands in History, its manager is
  // alerted. A snapshot or History source is never re-judged (its marker,
  // if any, is the law), so reruns are deterministic.
  const integrity = firstRun && source === 'squadsFallback'
    ? await loadIntegrityInputs(db, root, Object.keys(squadsByUid), gw.number)
    : undefined;
  let costsRaw = await db.read(`${root}/TransferCosts/${gw.number}`);
  if (costsRaw == null && firstRun) {
    const acc = lockAccounting({
      squadsByUid,
      statesByUid: mapChildren(await db.read(`${root}/TransferState`)),
      historyRaw,
      cfg,
      gw: gw.number,
      voidedWeeks,
      integrity,
    });
    squadsByUid = acc.cleanSquads;
    for (const v of acc.voided) {
      log.warn('fantasy lock: chip voided — already used in this set',
        { ...ctx, ...v });
    }
    if (Object.keys(acc.costPointsByUid).length > 0) {
      await db.write(`${root}/TransferCosts/${gw.number}`, acc.costPointsByUid);
    }
    await freezeLockTransferState(db, root, cfg, gw.number, acc, log, ctx);
    costsRaw = acc.costPointsByUid;
    if (integrity !== undefined) {
      await settleIntegrityAlerts(
        db, root, gw.number, acc, args.nowUtc.getTime(), log, ctx);
    }
  } else if (integrity !== undefined) {
    const judged = annotateSquadIntegrity(squadsByUid, cfg, integrity);
    squadsByUid = judged.squads;
    await settleIntegrityAlerts(
      db, root, gw.number, judged, args.nowUtc.getTime(), log, ctx);
  }
  const transferCostPointsByUid: Record<string, number> = {};
  for (const [u, v] of childEntries(costsRaw)) {
    transferCostPointsByUid[u] = toIntLoose(v);
  }

  // Other weeks' stored results (this week's are replaced by the compute):
  // points, games played (PlayerWeekStats.GP — PlayerTotals games/ppg) and
  // History net tenths.
  const playerWeeksByWeek =
    playerWeeksByWeekOf(await db.read(`${root}/PlayerWeeks`), gw.number);
  const playedGamesByWeek =
    playedGamesByWeekOf(await db.read(`${root}/PlayerWeekStats`), gw.number);
  const historyTenthsByWeek = historyTenthsByWeekOf(historyRaw, gw.number);

  // Ownership is a "right now" figure: a rerun of an OLDER week (a late
  // score correction) keeps PlayerTotals ownership on the latest finalized
  // week's squads (S15 rehearsal 2.5c) — History holds them squad-shaped.
  let ownershipSquadsByUid: Record<string, unknown> | undefined;
  const laterWeeks = childEntries(historyRaw)
    .map(([w]) => Number(w))
    .filter((w) => Number.isInteger(w) && w > gw.number);
  if (laterWeeks.length > 0) {
    const latest = Math.max(...laterWeeks);
    ownershipSquadsByUid = mapChildren(childEntries(historyRaw)
      .find(([w]) => Number(w) === latest)?.[1] ?? null);
  }

  const dreamRaw = await db.read(`${root}/DreamTeam/${gw.number}`);
  const dreamTeamAuto = dreamRaw == null
    ? null
    : isPlainMap(dreamRaw) && dreamRaw['Auto'] === true;

  const out = computeGameweekFinalize({
    cfg,
    gw: gw.number,
    games,
    players,
    squadsByUid,
    transferCostPointsByUid,
    playerWeeksByWeek,
    playedGamesByWeek,
    historyTenthsByWeek,
    dreamTeamAuto,
    voidedWeeks,
    ownershipSquadsByUid,
    nowMs: args.nowUtc.getTime(),
  });

  for (const uid of out.skippedSquadUids) {
    log.warn('fantasy finalize: malformed squad skipped', { ...ctx, uid, source });
  }

  // The last check, right before the first official write (see the entry):
  // a transaction on LockedWeeks/<gw> that stamps `Finalizing` — the
  // rewind's mark refuses a fresh stamp — or refuses (nothing more written)
  // when the entry is marked Rewinding, was there at our entry (or claimed
  // by this first run) and is gone now, or holds another date.
  const stamp = await stampFinalizing(db, root, gw,
    ledgerAtEntry != null || firstRun, args.nowUtc.getTime(), log, ctx);
  if (stamp === null) return null;
  if (Object.keys(out.playerWeeks).length > 0) {
    await db.write(`${root}/PlayerWeeks/${gw.number}`, out.playerWeeks);
  }
  if (Object.keys(out.playerWeekStats).length > 0) {
    await db.write(
      `${root}/PlayerWeekStats/${gw.number}`, out.playerWeekStats);
  }
  if (Object.keys(out.historyByUid).length > 0) {
    await db.write(`${root}/History/${gw.number}`, out.historyByUid);
    await db.write(`${root}/Leaderboards/Gameweek/${gw.number}`, out.gameweekBoard);
    await db.write(`${root}/Leaderboards/Overall`, out.overallBoard);
    await db.write(`${root}/Leaderboards/RankHistory`, out.rankHistory);
    // The week's points are final: LockedWeeks/<gw>.Scored (the rewind
    // never touches a scored week). Every run — a rerun of a scored week
    // writes nothing. Logged, never fails the finalize (History itself is
    // the other "scored" fact).
    try {
      await markWeekScored(db, root, gw, log, ctx);
    } catch (err) {
      log.warn('fantasy finalize: Scored mark failed — the next finalize ' +
        'run retries', { ...ctx, error: String(err) });
    }
  } else {
    log.warn('fantasy finalize: no manager squads to score', { ...ctx, source });
    // Nothing scored: the week stays rewindable, so our stamp goes now
    // (only ours — a later run's stamp stays until that run is done).
    if (stamp.stampMs !== null) {
      await clearFinalizingStamp(db, root, gw.number, stamp.stampMs, log, ctx);
    }
  }

  // FPL selling (spec §4): Baselines/<uid> for gw + 1, on EVERY run — the
  // lock wrote them already; this heals a lost lock-time write (and a FIRST
  // finalize on the live-Squads fallback writes them here, from the History
  // just written). Never backwards (a rerun of an old week leaves the newer
  // baselines alone) and a no-op when nothing changed. The Prev stash
  // ([M3]) goes only with History: a run that scored nobody leaves the week
  // unscored — still rewindable — so it keeps (or, like the lock, takes)
  // the stash. Like the badges, a failure is logged and never fails the
  // finalize.
  try {
    await publishSaleBaselines(db, root, gw.number, log, ctx,
      { stashPrev: Object.keys(out.historyByUid).length === 0 });
  } catch (err) {
    log.warn('fantasy baselines: publish failed', { ...ctx, error: String(err) });
  }

  // Achievement badges (spec 2026-10-30 §4; badges.ts), right after the
  // scores they are judged on (History + the boards) — so a later step
  // failing (totals, Dream Team, rollover, recap, news) can never leave a
  // finalized week without its badges: week N's auto awards re-settled from
  // THIS run's outputs (rerun-exact — added and removed; a voided week keeps
  // none; manual awards never touched), then the season-end awards whenever
  // the season is over (a late score correction re-settles the placements +
  // the trophy cabinet). The Team of the Week is this run's (not stored
  // yet) or, when ours was not computed, the admin-edited node read above;
  // a voided week has none. A badge failure is logged and never fails the
  // finalize; the week's next rerun re-settles.
  if (Object.keys(out.historyByUid).length > 0) {
    try {
      await settleWeeklyBadges(db, {
        sport, season, gw: gw.number,
        squadsByUid: out.historyByUid,
        playerWeeks: out.playerWeeks,
        playedByName: Object.fromEntries(Object.entries(out.playerWeekStats)
          .map(([name, e]) => [name, e.Played])),
        dreamTeamNames: dreamTeamNames(voided ? null : out.dreamTeam ?? dreamRaw),
        gameweekBoard: out.gameweekBoard,
        voided,
        nowMs: args.nowUtc.getTime(),
        log,
      });
      await settleSeasonBadges(db, { sport, season, cfg, nowUtc: args.nowUtc, log });
    } catch (err) {
      log.warn('fantasy badges: settle failed', { ...ctx, error: String(err) });
    }
  }

  if (Object.keys(out.playerTotals).length > 0) {
    await db.write(`${root}/PlayerTotals`, out.playerTotals);
  }
  if (out.dreamTeam !== null) {
    await db.write(`${root}/DreamTeam/${gw.number}`, out.dreamTeam);
  } else if (out.removeAutoDreamTeam) {
    await db.write(`${root}/DreamTeam/${gw.number}`, null);
    log.info('fantasy finalize: voided week — auto DreamTeam removed', ctx);
  } else if (dreamTeamAuto === false) {
    log.info('fantasy finalize: DreamTeam admin-edited — preserved', ctx);
  }

  // Phase E epilogue: Free Hit squad restore + free-transfer rollover,
  // once per gameweek (RolledGw-guarded — score-edit reruns skip it).
  if (Object.keys(out.historyByUid).length > 0) {
    await settleTransfersAfterFinalize(
      db, root, cfg, gw.number, Object.keys(out.historyByUid),
      args.nowUtc.getTime(), log, ctx);
  }

  // Live hand-over (live design 2026-11-03 §4, Fable L1), after EVERY
  // official node above and before the recap push: this week's (or an
  // older week's) live node becomes the settled tombstone, so phones fall
  // back to the official nodes — received in write order on their one
  // connection, so the hand-over has no gap. The whole LiveBase goes (this
  // run may have changed a settled week) and a NEWER week still live is
  // refreshed at once with the corrected Overall. Best-effort like the
  // badges: a failure is logged and never fails the finalize.
  try {
    await settleLiveWeek(db, {
      sport, season, gw: gw.number, nowUtc: args.nowUtc, log, ctx,
      clock: args.deps?.clock,
    });
  } catch (err) {
    log.warn('fantasy live: settle failed', { ...ctx, error: String(err) });
  }

  // Owner-voided week: claim both once-only guards WITHOUT pushing or
  // drafting (pusher or not — nothing to deliver), so neither fires later,
  // not even after an un-void (documented choice; see header).
  if (voided) {
    for (const guard of ['RecapSent', 'NewsDrafted']) {
      const path = `${root}/${guard}/${gw.number}`;
      if ((await db.read(path)) != null) continue;
      if (await db.writeIfAbsent(path,
        { At: args.nowUtc.getTime(), Voided: true })) {
        log.info('fantasy finalize: voided week — guard claimed, nothing sent',
          { ...ctx, guard });
      }
    }
  }

  // Phase F: weekly recap push, once per gameweek (RecapSent-guarded — the
  // recap tells the FIRST settle's story; score-edit reruns never re-push).
  const pusher = args.deps?.pusher;
  if (!voided && pusher && Object.keys(out.historyByUid).length > 0 &&
    (await db.read(`${root}/RecapSent/${gw.number}`)) == null) {
    const won = await db.writeIfAbsent(`${root}/RecapSent/${gw.number}`,
      { At: args.nowUtc.getTime() });
    if (won) {
      const topScore = Math.max(
        ...Object.values(out.gameweekBoard).map((r) => r.points));
      const data = fantasyPushData(sport, season, gw.number);
      const messages = Object.keys(out.historyByUid).sort().map((uid) => ({
        uid,
        title: RECAP_TITLE,
        body: recapBody({
          gw: gw.number,
          points: out.gameweekBoard[uid]?.points ?? 0,
          rank: out.overallBoard[uid]?.rank ?? 0,
          topScore,
        }),
        data,
      }));
      const sent = await pusher.sendToUsers(messages);
      log.info('fantasy recap pushed',
        { ...ctx, managers: messages.length, sent });
    }
  }

  // Phase G: news drafts, once per gameweek (NewsDrafted-guarded). The
  // Dream Team post always builds — deterministic, from the SAME stored
  // DreamTeam node the hub reads — while the 2–4 AI drafts land only when
  // the Anthropic call succeeds: an API failure or blank key writes NOTHING
  // (logged) and never blocks the finalize (spec §13). News desk 2.0 (spec
  // 2026-10-28 §4.4): every draft carries player-card snapshots of the
  // players it tags, the autopilot (ON unless Config/NewsAutopilot says
  // Enabled:false) schedules every draft — never sooner than 12 h out
  // (autopilotPublishAtUtc) — and the admins get one heads-up.
  //
  // Review 2026-10-28: every read the step needs happens BEFORE the claim,
  // so a transient read error throws with NewsDrafted still free instead of
  // spending the week's only drafting run; and the player cards are
  // best-effort on top (newsCardBuilder) — a card failure drafts without
  // Players rather than not at all.
  if (!voided && (await db.read(`${root}/NewsDrafted/${gw.number}`)) == null) {
    const nowMs = args.nowUtc.getTime();
    const news = args.deps?.news;
    const dreamTeamRaw =
      out.dreamTeam ?? await db.read(`${root}/DreamTeam/${gw.number}`);
    const autopilot = newsAutopilotConfigFrom(
      await db.read(`${root}/Config/NewsAutopilot`),
      await db.read(`${root}/Config/DreamTeamPost`));
    const priceChangesRaw = news?.apiKey
      ? await latestPriceChanges(db, root, gw.number) : null;
    const admins = pusher ? adminUidsOf(await db.read('Admins')) : [];
    const cardsFor = await newsCardBuilder(db, sport, season, log, ctx);

    const wonNews = await db.writeIfAbsent(`${root}/NewsDrafted/${gw.number}`,
      { At: nowMs });
    if (wonNews) {
      const publishAt = autopilot.enabled
        ? autopilotPublishAtUtc(args.nowUtc, autopilot.weekday, autopilot.hour)
        : null;
      const schedule = publishAt !== null
        ? { AutoPublishAt: publishAt.getTime() } : {};

      let drafted = 0;
      const dtDraft = buildDreamTeamDraft({
        gw: gw.number,
        dreamTeamRaw,
        nowMs,
        autoPublishAtMs: publishAt?.getTime() ?? null,
        cards: cardsFor(dreamTeamNames(dreamTeamRaw)),
      });
      if (dtDraft !== null) {
        await db.write(`${root}/News/Drafts/gw${gw.number}dreamteam`, dtDraft);
        drafted++;
        log.info('fantasy news: dream team post drafted', ctx);
      }

      if (news?.apiKey) {
        const drafts = await generateNewsDrafts({
          stats: buildNewsStats({
            gw: gw.number,
            playerWeeksThisGw: out.playerWeeks,
            playerWeeksPrevGw: playerWeeksByWeek[gw.number - 1] ?? null,
            players,
            dreamTeamRaw,
            priceChangesRaw,
          }),
          apiKey: news.apiKey,
          fetchImpl: news.fetchImpl,
          timeoutMs: news.timeoutMs,
        });
        if (drafts === null) {
          log.info('fantasy news: AI drafting skipped — API failure or ' +
            'unusable reply', ctx);
        } else {
          for (let i = 0; i < drafts.length; i++) {
            // Only market players become cards (unknown names drop out).
            const tagged = cardsNode(cardsFor(drafts[i].players));
            await db.write(`${root}/News/Drafts/gw${gw.number}ai${i + 1}`, {
              Title: drafts[i].title,
              Body: drafts[i].body,
              Gw: gw.number,
              CreatedAt: nowMs,
              Source: 'ai',
              Template: 'ai',
              ...(tagged !== null ? { Players: tagged } : {}),
              ...schedule,
            });
            drafted++;
          }
          log.info('fantasy news: AI drafts queued',
            { ...ctx, drafts: drafts.length });
        }
      } else {
        log.info('fantasy news: no Anthropic key — AI drafting skipped', ctx);
      }

      // Admin heads-up (spec §4.4): once per gameweek — inside this claim —
      // and only when something was drafted. The Manager has no FCM token,
      // so it lands in each admin's fan app. It names the drafts' actual
      // AutoPublishAt instant.
      if (drafted > 0 && pusher && admins.length > 0) {
        const body = newsReadyBody(drafted,
          publishAt !== null ? formatLeagueWeekdayTime(publishAt) : null);
        const data = fantasyPushData(sport, season, gw.number);
        const sent = await pusher.sendToUsers(admins.map((uid) => ({
          uid, title: NEWS_READY_TITLE, body, data,
        })));
        log.info('fantasy news: admin heads-up pushed',
          { ...ctx, admins: admins.length, sent, drafted });
      }
    }
  }

  const managers = Object.keys(out.historyByUid).length;
  log.info('fantasy gameweek finalized', {
    ...ctx, source, managers, games: gameNodes.length,
    skipped: out.skippedSquadUids.length, voided,
  });
  return { managers, source };
}

/** First-run guard: without a lock snapshot or existing History, only the
 *  LATEST lock-passed gameweek may finalize from live Squads — enabling
 *  fantasy mid-season must never fabricate history for earlier weeks. */
async function mayFinalizeFirstRun(
  db: FantasyDb, root: string, gws: Gameweek[], gw: Gameweek, nowUtc: Date,
): Promise<boolean> {
  if (await db.exists(`${root}/History/${gw.number}`)) return true;
  if (await db.exists(`${root}/PublishedPicks/${gw.number}`)) return true;
  const lockPassed = gws
    .filter((g) => g.lockUtc.getTime() <= nowUtc.getTime());
  return lockPassed.length > 0 &&
    lockPassed[lockPassed.length - 1].number === gw.number;
}

export interface MaybeFinalizeArgs {
  sport: string;
  season: string;
  dateKey: string;
  nowUtc: Date;
  log?: FantasyLogger;
  deps?: FantasyJobDeps;
}

/** The trigger entry: a game under <sport>/<season>/Date/<dateKey> was
 *  written while Final. Finalizes (or re-finalizes) that date's gameweek
 *  when the season is fantasy-enabled and auto, the gameweek's lock has
 *  passed (History is public — finalizing a pre-lock final would leak
 *  picks), every non-friendly game of the date is Final, and the first-run
 *  guard allows it. Reruns on later edits recompute everything downstream —
 *  idempotence IS the debounce. */
export async function maybeFinalizeGame(
  db: FantasyDb, args: MaybeFinalizeArgs,
): Promise<void> {
  const { sport, season, dateKey, nowUtc } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  const ctx = { sport, season, dateKey };
  if (lockOverrideOf(configNode, nowUtc.getTime()) !== 'auto') {
    log.info('fantasy finalize: lockOverride frozen — standing down', ctx);
    return;
  }
  if (await isTestFillSeason(db, root)) {
    log.info(TEST_FILL_STAND_DOWN, { ...ctx, job: 'finalize' });
    return;
  }
  const cfg = configFromMap(configNode);

  const { gws } = await loadSeasonGameweeks(db, sport, season, cfg, configNode);
  const gw = gws.find((g) => g.date === dateKey);
  if (!gw) return;
  if (gw.lockUtc.getTime() > nowUtc.getTime()) {
    log.info('fantasy finalize: date final before lock — waiting for lock',
      { ...ctx, gw: gw.number });
    return;
  }
  const games = gamesOfDate(await db.read(`${sport}/${season}/Date/${dateKey}`));
  if (!allGamesFinal(games)) return; // another game still running
  if (!(await mayFinalizeFirstRun(db, root, gws, gw, nowUtc))) {
    log.warn('fantasy finalize: old gameweek without a lock snapshot — ' +
      'skipped (no fabricated history)', { ...ctx, gw: gw.number });
    return;
  }
  await finalizeGameweek(db, {
    sport, season, cfg, configNode, gw, nowUtc: args.nowUtc, log,
    deps: args.deps,
  });
}

export interface VoidToggleArgs {
  sport: string;
  season: string;
  /** The gameweek number whose Voided/<gw> flag flipped. */
  gw: number;
  nowUtc: Date;
  log?: FantasyLogger;
  deps?: FantasyJobDeps;
}

/** The Voided/<gw> trigger entry (spec §15 owner void): the flag flipped
 *  (voided <-> counts), so re-settle that gameweek through the SAME
 *  match-day finalize entry — every gate applies unchanged (frozen
 *  lockOverride stands down, pre-lock waits, an incomplete match day waits,
 *  the first-run guard holds). finalize re-reads the flag itself, so voiding
 *  and un-voiding are both just a deterministic rerun. A flip on a week that
 *  has not settled yet changes nothing now: its eventual finalize reads the
 *  flag. Rollover/Free Hit restore stay RolledGw-guarded (never re-run).
 *
 *  Live (Fable L4): the flip changes the live week itself (voided: 0 for
 *  everyone, "Voided") or a settled week under it, so the whole LiveBase
 *  goes and the week Live is showing refreshes at once — no game write
 *  needed. A TestFill season stands down here too (zero writes). */
export async function resettleVoidToggle(
  db: FantasyDb, args: VoidToggleArgs,
): Promise<void> {
  const { sport, season } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, gw: args.gw };

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // not fantasy-enabled: stay silent
  if (lockOverrideOf(configNode, args.nowUtc.getTime()) !== 'auto') {
    log.info('fantasy void: lockOverride frozen — standing down', ctx);
    return;
  }
  // The finalize entry is keyed by match date; map the gameweek onto it.
  const { gws } = await loadSeasonGameweeks(
    db, sport, season, configFromMap(configNode), configNode);
  const gw = gws.find((g) => g.number === args.gw);
  if (!gw) {
    log.warn('fantasy void: gameweek not in the schedule — nothing to settle',
      ctx);
    return;
  }
  const voided = isVoidFlag(await db.read(`${root}/Voided/${args.gw}`));
  log.info('fantasy void: flag flipped — re-settling',
    { ...ctx, date: gw.date, voided });
  await maybeFinalizeGame(db, {
    sport, season, dateKey: gw.date, nowUtc: args.nowUtc, log, deps: args.deps,
  });

  if (await isTestFillSeason(db, root)) return; // maybeFinalizeGame logged it
  // Best-effort like finalize's settle: the next game write or sweep
  // refreshes anyway.
  try {
    await removeLiveBase(db, root);
    const meta = liveMetaOf(await db.read(`${root}/Live/Meta`));
    if (meta === null || !meta.live) return; // nothing live to refresh
    await refreshLiveGw(db, {
      sport, season, configNode, liveGw: meta.gw,
      nowUtc: args.nowUtc, log, clock: args.deps?.clock,
    }, { ...ctx, reason: 'void' });
  } catch (err) {
    log.warn('fantasy live: void refresh failed', { ...ctx, error: String(err) });
  }
}

// ── The live gameweek (live design 2026-11-03 §4) ──────────────────────────

/** Sweep step 2d's margin: a 'live' node of a week whose History exists is
 *  a LOST settle only once it is this much older than its last live write —
 *  longer than any function run (an in-flight finalize must still land
 *  every official node before its own tombstone). */
export const LIVE_SETTLE_HEAL_MS = 10 * 60 * 1000;

/** What a live run did:
 *  - 'written'   — Live holds this run's numbers;
 *  - 'skipped'   — no game of the date has started (this week's live node,
 *                  if one is left from an undone kickoff, is removed);
 *  - 'stale'     — a newer read already published, or a newer week owns
 *                  Live (nothing written);
 *  - 'settled'   — the week is finalized (PlayerWeeks/<gw> or the
 *                  tombstone): never resurrected;
 *  - 'standDown' — not a live week of a running season: no Config, a
 *                  frozen lockOverride, TestFill, before the lock, a date
 *                  off the schedule, or no lock snapshot. */
export type LiveRefreshResult =
  'written' | 'skipped' | 'stale' | 'settled' | 'standDown';

export interface LiveRefreshArgs {
  sport: string;
  season: string;
  /** The match date (Date/<dateKey>) to recompute. */
  dateKey: string;
  /** When the write that asked for this run happened — the trigger's event
   *  time; the run's own now for the sweep and the settle/void refreshes.
   *  A stored ReadAt of the same week at or after it = already covered. */
  eventAtMs: number;
  nowUtc: Date;
  log?: FantasyLogger;
  /** Wall clock for ReadAt (FantasyJobDeps.clock); Date.now when absent. */
  clock?: () => number;
}

export interface LiveWriteArgs extends LiveRefreshArgs {
  /** The written game node before and after (the trigger's payload). */
  before: unknown;
  after: unknown;
}

/** Live/Meta as the live jobs read it; null = no usable Meta. */
interface LiveMeta {
  gw: number;
  live: boolean;
  settled: boolean;
  readAt: number;
  updatedAt: number;
}

function liveMetaOf(meta: unknown): LiveMeta | null {
  if (!isPlainMap(meta)) return null;
  return {
    gw: toIntLoose(meta['Gw']),
    live: meta['State'] === 'live',
    settled: meta['State'] === 'settled',
    readAt: toIntLoose(meta['ReadAt']),
    updatedAt: toIntLoose(meta['UpdatedAt']),
  };
}

/** The Meta of a whole Live node (a transaction's current value). */
function liveMetaOfNode(live: unknown): LiveMeta | null {
  return liveMetaOf(isPlainMap(live) ? live['Meta'] : null);
}

/** Removes the WHOLE LiveBase node (every settled week it summed may have
 *  changed) — only when there is one, so a season that never went live
 *  sees no write. */
async function removeLiveBase(db: FantasyDb, root: string): Promise<void> {
  if ((await db.read(`${root}/LiveBase`)) != null) {
    await db.write(`${root}/LiveBase`, null);
  }
}

/** LiveBase/<gw>: the stored one (as RTDB hands it back — computeLiveWeek
 *  normalises it), else built ONCE from the settled weeks before gw (the
 *  same stored maps finalize reads) and stored for the week's later runs. */
async function liveBaseFor(
  db: FantasyDb, root: string, gw: number, voidedWeeks: number[],
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<LiveBase> {
  const stored = await db.read(`${root}/LiveBase/${gw}`);
  if (isPlainMap(stored) && toIntLoose(stored['Gw']) === gw) {
    return stored as unknown as LiveBase;
  }
  const base = buildLiveBase({
    gw,
    historyTenthsByWeek: historyTenthsByWeekOf(await db.read(`${root}/History`), gw),
    playerWeeksByWeek: playerWeeksByWeekOf(await db.read(`${root}/PlayerWeeks`), gw),
    playedGamesByWeek:
      playedGamesByWeekOf(await db.read(`${root}/PlayerWeekStats`), gw),
    voidedWeeks,
  });
  await db.write(`${root}/LiveBase/${gw}`, base);
  log.info('fantasy live: settled base built', {
    ...ctx, managers: Object.keys(base.Managers).length,
    players: Object.keys(base.Players).length,
  });
  return base;
}

/** The one Live write (LIVE ORDERING): a transaction on the whole node —
 *  writes over nothing, an older week, or this week's node read no later
 *  than [readAtMs]; aborts on a newer week or this week's tombstone. The
 *  cold first run (null) always writes, never aborts (FantasyDb). */
async function publishLive(
  db: FantasyDb, root: string, gw: number, readAtMs: number, out: LiveOutput,
): Promise<LiveRefreshResult> {
  let refused = 'stale' as LiveRefreshResult;
  const res = await db.transaction(`${root}/Live`, (cur) => {
    const meta = liveMetaOfNode(cur);
    if (meta !== null && meta.gw > gw) {
      refused = 'stale'; // a newer week owns Live
      return undefined;
    }
    if (meta !== null && meta.gw === gw && meta.settled) {
      refused = 'settled';
      return undefined;
    }
    if (meta !== null && meta.gw === gw && meta.readAt > readAtMs) {
      refused = 'stale'; // a run that read later already landed
      return undefined;
    }
    return out;
  });
  return res.committed ? 'written' : refused;
}

/** No game of the week's date has started (an undone kickoff): this week's
 *  live node — and only one this run reads past — is removed, so phones
 *  show the official nodes again. Anything else is left alone. */
async function clearUnstartedLive(
  db: FantasyDb, root: string, gw: number, readAtMs: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  let removed = false as boolean;
  const res = await db.transaction(`${root}/Live`, (cur) => {
    removed = false; // every (re-)run decides afresh
    if (cur === null || cur === undefined) return null; // see FantasyDb
    const meta = liveMetaOfNode(cur);
    if (meta === null || meta.gw !== gw || !meta.live || meta.readAt > readAtMs) {
      return undefined;
    }
    removed = true;
    return null;
  });
  if (res.committed && removed) {
    log.info('fantasy live: no game started any more — live node removed', ctx);
  }
}

/** Recomputes the live gameweek of [args.dateKey] and publishes it to Live
 *  (live design §4; LIVE ORDERING in the header). Read-only on every
 *  official node: inputs are loaded exactly as finalizeGameweek loads them
 *  (one read of the date's games builds both the game nodes and the status
 *  table; attendance through the same roster composition; the market at
 *  the week's locked positions without claiming anything; the lock
 *  snapshot PublishedPicks/<gw>; TransferCosts/<gw>; Voided) plus the
 *  settled base LiveBase/<gw> (built once, liveBaseFor). Cheap reads first:
 *  a covered event ('stale') or a settled week ('settled') stops before
 *  any heavy read. */
export async function refreshLiveWeek(
  db: FantasyDb, args: LiveRefreshArgs,
): Promise<LiveRefreshResult> {
  const { sport, season, dateKey, nowUtc } = args;
  const log = args.log ?? silent;
  const clock = args.clock ?? Date.now;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, dateKey };

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return 'standDown'; // not fantasy-enabled: silent
  if (lockOverrideOf(configNode, nowUtc.getTime()) !== 'auto') {
    log.info('fantasy live: lockOverride frozen — standing down', ctx);
    return 'standDown';
  }
  if (await isTestFillSeason(db, root)) {
    log.info(TEST_FILL_STAND_DOWN, { ...ctx, job: 'live' });
    return 'standDown';
  }
  const cfg = configFromMap(configNode);

  // ReadAt BEFORE the first game read (LIVE ORDERING). The schedule loader
  // reads the season's Date node — the schedule AND this date's games, from
  // the SAME read — with the two tiny schedule nodes (LockedWeeks, Start
  // Time) alongside it.
  const readAtMs = clock();
  const { gws, dateNode: datesNode } = await loadSeasonGameweeks(
    db, sport, season, cfg, configNode);
  const gw = gws.find((g) => g.date === dateKey);
  if (!gw) return 'standDown'; // not a scheduled match day
  if (gw.lockUtc.getTime() > nowUtc.getTime()) {
    log.info('fantasy live: date before its lock — standing down',
      { ...ctx, gw: gw.number });
    return 'standDown';
  }
  const lctx = { ...ctx, gw: gw.number };

  // Coalescing + never resurrect (Fable L1), before any heavy read.
  const meta = liveMetaOf(await db.read(`${root}/Live/Meta`));
  if (meta !== null && meta.gw > gw.number) return 'stale';
  if (meta !== null && meta.gw === gw.number) {
    if (meta.settled) return 'settled';
    if (meta.readAt >= args.eventAtMs) return 'stale';
  }
  if ((await db.read(`${root}/PlayerWeeks/${gw.number}`)) != null) return 'settled';

  // The status table and the game nodes, from the SAME read.
  const dateNode = childEntries(datesNode).find(([k]) => k === dateKey)?.[1] ?? null;
  const gameStatus: Record<string, LiveGameStatus> = {};
  const startedNodes: Array<[string, Record<string, unknown>]> = [];
  for (const [key, node] of keyedGamesOfDate(dateNode)) {
    const s = toIntLoose(node['status']);
    const S: LiveGameStatus['S'] = s === 1 || s === 2 ? s : 0;
    gameStatus[key] = {
      S, T1: String(node['team1'] ?? ''), T2: String(node['team2'] ?? ''),
    };
    if (S !== 0) startedNodes.push([key, node]);
  }
  if (startedNodes.length === 0) {
    await clearUnstartedLive(db, root, gw.number, readAtMs, log, lctx);
    return 'skipped';
  }

  const squadsByUid =
    mapChildren(await db.read(`${root}/PublishedPicks/${gw.number}`));
  if (Object.keys(squadsByUid).length === 0) {
    log.warn('fantasy live: no lock snapshot (PublishedPicks) — standing down',
      lctx);
    return 'standDown';
  }
  // The locked positions (plan constraint: no snapshot, no live week) — the
  // one read marketForGameweek's read-only path (claim false) makes, made
  // here so the stand-down comes before any heavy read.
  const lockedRaw = await db.read(`${root}/LockedPositions/${gw.number}`);
  if (lockedRaw == null) {
    log.warn('fantasy live: no lock snapshot (LockedPositions) — standing down',
      lctx);
    return 'standDown';
  }

  const lineups = await db.read(`${sport}/${season}/Line Ups`);
  const games: Record<string, FinalizeGame> = {};
  // A missing roster is finalize's warning to give, once — not every event's.
  for (const [key, node] of startedNodes) {
    games[key] = scorableGame(node, lineups, () => undefined);
  }
  // marketForGameweek(…, claim false), from the snapshot read above.
  const players = withLockedPositions(
    marketPlayersOf(await db.read(`${root}/Players`)),
    lockedPositionsOf(lockedRaw));
  const transferCostPointsByUid: Record<string, number> = {};
  for (const [u, v] of childEntries(
    await db.read(`${root}/TransferCosts/${gw.number}`))) {
    transferCostPointsByUid[u] = toIntLoose(v);
  }
  const voidedWeeks = voidedWeeksOf(await db.read(`${root}/Voided`));
  const base = await liveBaseFor(db, root, gw.number, voidedWeeks, log, lctx);

  const out = computeLiveWeek({
    cfg,
    gw: gw.number,
    games,
    players,
    squadsByUid,
    transferCostPointsByUid,
    voided: voidedWeeks.includes(gw.number),
    base,
    gameStatus,
    readAtMs,
    nowMs: nowUtc.getTime(),
  });
  const result = await publishLive(db, root, gw.number, readAtMs, out);
  log.info('fantasy live: week refreshed', {
    ...lctx, result, readAtMs, started: startedNodes.length,
    managers: Object.keys(out.Squads).length,
  });
  return result;
}

/** The live trigger's entry (fantasy_live.ts): a game under
 *  <sport>/<season>/Date/<dateKey> was written. The payload gate runs
 *  first — zero reads unless the game counts or counted (status 1 or 2,
 *  after or before) AND a key the scorer reads changed (live_core.ts
 *  liveWriteMatters; Fable L2) — then refreshLiveWeek. 'ignored' = the gate said no. */
export async function maybeRefreshLive(
  db: FantasyDb, args: LiveWriteArgs,
): Promise<LiveRefreshResult | 'ignored'> {
  if (!liveWriteMatters(args.before, args.after)) return 'ignored';
  return refreshLiveWeek(db, args);
}

/** Refreshes live gameweek [liveGw] right away (eventAtMs = a fresh clock
 *  reading, so it never coalesces into a run that read before the caller's
 *  change): the settle of an older week, a void toggle. */
async function refreshLiveGw(
  db: FantasyDb,
  a: {
    sport: string; season: string; configNode: Record<string, unknown>;
    liveGw: number; nowUtc: Date; log: FantasyLogger; clock?: () => number;
  },
  ctx: Record<string, unknown>,
): Promise<void> {
  const { gws } = await loadSeasonGameweeks(
    db, a.sport, a.season, configFromMap(a.configNode), a.configNode);
  const live = gws.find((g) => g.number === a.liveGw);
  if (!live) return;
  const clock = a.clock ?? Date.now;
  const result = await refreshLiveWeek(db, {
    sport: a.sport, season: a.season, dateKey: live.date,
    eventAtMs: clock(), nowUtc: a.nowUtc, log: a.log, clock,
  });
  a.log.info('fantasy live: live week refreshed', {
    ...ctx, liveGw: a.liveGw, result,
  });
}

/** Finalize's live hand-over for [gw] (the TOMBSTONE, Fable L1): one
 *  transaction replaces a live node of gw or an older week — or none —
 *  with { Meta: { Gw: gw, State: 'settled', UpdatedAt } } and leaves a
 *  newer week's alone; then the whole LiveBase goes; then a newer week
 *  still live is refreshed at once (its settled base just changed). */
async function settleLiveWeek(
  db: FantasyDb,
  a: {
    sport: string; season: string; gw: number;
    nowUtc: Date; log: FantasyLogger; ctx: Record<string, unknown>;
    clock?: () => number;
  },
): Promise<void> {
  const root = fantasyRoot(a.sport, a.season);
  let newerLiveGw = null as number | null;
  const res = await db.transaction(`${root}/Live`, (cur) => {
    newerLiveGw = null; // every (re-)run decides afresh
    const meta = liveMetaOfNode(cur);
    if (meta !== null && meta.gw > a.gw) {
      if (meta.live) newerLiveGw = meta.gw;
      return undefined; // a newer week owns Live
    }
    return { Meta: { Gw: a.gw, State: 'settled', UpdatedAt: a.nowUtc.getTime() } };
  });
  if (res.committed) a.log.info('fantasy live: week settled', a.ctx);
  await removeLiveBase(db, root);
  if (newerLiveGw === null) return;
  // The schedule the refresh needs reads the raw Config (overrides); this
  // is the rare path, so the one extra read is fine.
  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return; // Config removed meanwhile
  await refreshLiveGw(db, {
    sport: a.sport, season: a.season, configNode, liveGw: newerLiveGw,
    nowUtc: a.nowUtc, log: a.log, clock: a.clock,
  }, { ...a.ctx, reason: 'older week settled' });
}

// ── Frozen weeks (LockedWeeks — season setup + schedule plan 2026-11-05) ──

/** The LockedWeeks/<n> node that freezes [gw] as it is now. */
function lockedWeekNode(gw: Gameweek): { Date: string; LockAtUtc: number } {
  return { Date: gw.date, LockAtUtc: gw.lockUtc.getTime() };
}

/** Whether a stored LockedWeeks/<n> value freezes [gw]'s date: a map with
 *  that Date and NOT marked `Rewinding: true` (the rewind's first step — a
 *  week being rewound is no claim to keep or to write under). */
function freezesWeek(node: unknown, gw: Gameweek): boolean {
  return freezesWeekDate(node, gw.date);
}

/** finalize's stand-down line for a week being rewound. */
const FINALIZE_REWINDING = 'fantasy finalize: week being rewound — standing down';
/** finalize's stand-down line for a ledger entry gone or re-dated under it. */
const FINALIZE_UNFROZEN = 'fantasy finalize: week no longer frozen — standing down';

/** [I1] The finalize's last check before its first official write: ONE
 *  transaction on LockedWeeks/<n>, the node it shares with the rewind
 *  (schedule_rewind.ts), so the two exclude each other.
 *  - Marked `Rewinding` → refused (the rewind got there first).
 *  - Absent → refused when [expected] (it existed at the finalize's entry,
 *    or this first run claimed it: a rewind completed meanwhile — scoring
 *    now would resurrect the entry through markWeekScored); otherwise (a
 *    week locked before the ledger existed) the run goes on, unstamped.
 *  - Another Date, or junk → refused.
 *  - Already `Scored` → goes on, unstamped (the rewind never marks a scored
 *    week; reruns write nothing here).
 *  - Otherwise → `Finalizing: <nowMs>` stamped: the rewind's mark refuses
 *    the week until markWeekScored replaces the stamp with Scored, the run
 *    clears its own stamp (clearFinalizingStamp), or it goes stale
 *    (FINALIZING_STALE_MS — a run that died).
 *  null = refused (warned/logged; the caller writes nothing more); else
 *  the stamp written (null = none). Cold-first safe: a null first run
 *  proposes "no change" and RTDB re-runs it on the real value. */
async function stampFinalizing(
  db: FantasyDb, root: string, gw: Gameweek, expected: boolean, nowMs: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<{ stampMs: number | null } | null> {
  type Verdict = 'stamped' | 'unstamped' | 'rewinding' | 'unfrozen';
  let verdict: Verdict = 'unfrozen';
  let seenDate: unknown = null;
  await db.transaction(`${root}/LockedWeeks/${gw.number}`, (current) => {
    seenDate = null; // every (re-)run decides afresh
    if (current === null || current === undefined) {
      verdict = expected ? 'unfrozen' : 'unstamped';
      return null; // see FantasyDb: never abort on null
    }
    if (isRewinding(current)) {
      verdict = 'rewinding';
      return undefined;
    }
    if (!freezesWeek(current, gw)) {
      verdict = 'unfrozen';
      seenDate = isPlainMap(current) ? current['Date'] ?? null : null;
      return undefined;
    }
    const node = current as Record<string, unknown>;
    if (node['Scored'] === true) {
      verdict = 'unstamped';
      return undefined;
    }
    verdict = 'stamped';
    return { ...node, Finalizing: nowMs };
  });
  switch (verdict as Verdict) {
    case 'stamped':
      return { stampMs: nowMs };
    case 'unstamped':
      return { stampMs: null };
    case 'rewinding':
      log.info(FINALIZE_REWINDING, ctx);
      return null;
    case 'unfrozen':
      log.warn(FINALIZE_UNFROZEN, { ...ctx, frozenDate: seenDate });
      return null;
  }
}

/** [I1] Removes this run's own `Finalizing` stamp ([stampMs]) from
 *  LockedWeeks/<n> — a later run's stamp (another value) is left alone. A
 *  failure is logged: the stamp then goes stale on its own. */
async function clearFinalizingStamp(
  db: FantasyDb, root: string, n: number, stampMs: number,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  try {
    await updateIfPresent(db, `${root}/LockedWeeks/${n}`, (cur) => {
      if (cur['Finalizing'] !== stampMs) return undefined;
      const next = { ...cur };
      delete next['Finalizing'];
      return next;
    });
  } catch (err) {
    log.warn('fantasy finalize: Finalizing stamp not cleared — it goes stale ' +
      'on its own', { ...ctx, error: String(err) });
  }
}

/** The lock's FIRST write: freezes gameweek [gw] as LockedWeeks/<n> =
 *  { Date, LockAtUtc }, set-if-absent (one read when it is already there —
 *  every sweep of the locked window). True when the ledger now freezes
 *  gw's date: our claim, or an earlier / concurrent one on the same date (a
 *  lost claim with the SAME Date is normal). False — warned, and the caller
 *  takes no snapshot — when it holds ANOTHER date for this number (a
 *  schedule the caller did not derive from: a stale sweep, or a week left
 *  unfrozen by a gap in a pre-ledger season), junk, or an entry a rewind
 *  marked `Rewinding` (same Date or not: it is being undone). */
async function claimLockedWeek(
  db: FantasyDb, root: string, gw: Gameweek,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<boolean> {
  const path = `${root}/LockedWeeks/${gw.number}`;
  let stored = await db.read(path);
  if (stored == null) {
    if (await db.writeIfAbsent(path, lockedWeekNode(gw))) {
      log.info('fantasy lock: week frozen', {
        ...ctx, gw: gw.number, date: gw.date, lockAtUtc: gw.lockUtc.getTime(),
      });
      return true;
    }
    stored = await db.read(path); // lost the claim: to whom?
  }
  if (freezesWeek(stored, gw)) return true;
  log.warn(isRewinding(stored)
    ? 'fantasy lock: week being rewound — lock step skipped'
    : 'fantasy lock: week frozen on another date — lock step skipped', {
    ...ctx, gw: gw.number, date: gw.date,
    frozenDate: isPlainMap(stored) ? stored['Date'] ?? null : null,
  });
  return false;
}

/** The warn of a lock write refused by the [M2] re-check BEFORE it. */
const SNAPSHOT_SKIPPED = 'fantasy lock: week no longer frozen — snapshot skipped';
/** The warn of a lock write after the PublishedPicks claim refused by it. */
const LOCK_STEP_STOPPED = 'fantasy lock: week no longer frozen — lock step stopped';

/** [M2] The re-check right before a lock write: true while LockedWeeks/<n>
 *  still freezes [gw]'s date. False — warned ([message], [step] in the
 *  context), and the caller writes nothing more for this lock — once it is
 *  marked Rewinding, gone, or holds another date: the sweep's rewind of a
 *  called-off week got there after this run derived its weeks, and nothing
 *  stale may survive the rewind. One small read per write. */
async function stillFrozen(
  db: FantasyDb, root: string, gw: Gameweek,
  log: FantasyLogger, ctx: Record<string, unknown>,
  step: string, message: string = SNAPSHOT_SKIPPED,
): Promise<boolean> {
  const node = await db.read(`${root}/LockedWeeks/${gw.number}`);
  if (freezesWeek(node, gw)) return true;
  log.warn(message, {
    ...ctx, gw: gw.number, date: gw.date, step, rewinding: isRewinding(node),
  });
  return false;
}

/** [M2] One lock snapshot claim under the frozen-week guard: the re-check
 *  right before the set-if-absent write (stillFrozen), the write, and —
 *  when ours won — the re-check AFTER it: a rewind that marked (or removed,
 *  or re-dated) the week between our pre-check and our write may already
 *  have cleared the snapshots, so we delete the node we just wrote
 *  ourselves. 'won' = ours stands; 'lost' = a concurrent claim won (it
 *  guards itself); 'unfrozen' = nothing of ours is left — the caller stops
 *  the lock step. */
async function guardedSnapshotClaim(
  db: FantasyDb, root: string, gw: Gameweek, path: string, value: unknown,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<'won' | 'lost' | 'unfrozen'> {
  if (!(await stillFrozen(db, root, gw, log, ctx, path))) return 'unfrozen';
  if (!(await db.writeIfAbsent(path, value))) return 'lost';
  const node = await db.read(`${root}/LockedWeeks/${gw.number}`);
  if (freezesWeek(node, gw)) return 'won';
  await db.write(path, null);
  log.warn('fantasy lock: week no longer frozen — snapshot removed', {
    ...ctx, gw: gw.number, date: gw.date, step: path, rewinding: isRewinding(node),
  });
  return 'unfrozen';
}

/** After History/<gw> lands: LockedWeeks/<n>.Scored = true. Absent (a week
 *  locked before the ledger existed) -> the full node { Date, LockAtUtc,
 *  Scored: true }; already Scored -> nothing written; a node a rewind
 *  marked `Rewinding`, or one freezing ANOTHER date (or junk), is left
 *  alone, warned — it is not this week's to settle. [I1] The finalize's
 *  `Finalizing` stamp goes in the same write (Scored now keeps the rewind
 *  away for good). One transaction: its
 *  cold first run sees null and proposes the full node, and RTDB re-runs it
 *  on the real value when one exists. */
async function markWeekScored(
  db: FantasyDb, root: string, gw: Gameweek,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<void> {
  let refused: { rewinding: boolean; frozenDate: unknown } | null = null;
  await db.transaction(`${root}/LockedWeeks/${gw.number}`, (current) => {
    refused = null; // every (re-)run decides afresh
    if (current === null || current === undefined) {
      return { ...lockedWeekNode(gw), Scored: true };
    }
    if (!freezesWeek(current, gw)) {
      refused = {
        rewinding: isRewinding(current),
        frozenDate: isPlainMap(current) ? current['Date'] ?? null : null,
      };
      return undefined;
    }
    // [I1] Scored replaces the finalize's Finalizing stamp (the rewind never
    // marks a scored week, so the stamp has done its job).
    const node: Record<string, unknown> = { ...(current as Record<string, unknown>) };
    const stamped = 'Finalizing' in node;
    delete node['Finalizing'];
    if (node['Scored'] === true) return stamped ? node : undefined;
    return { ...node, Scored: true };
  });
  const why = refused as { rewinding: boolean; frozenDate: unknown } | null;
  if (why !== null) {
    log.warn(why.rewinding
      ? 'fantasy finalize: week being rewound — not marked Scored'
      : 'fantasy finalize: LockedWeeks holds another date — not marked Scored',
    { ...ctx, frozenDate: why.frozenDate });
  }
}

// ── Positions locked per gameweek (spec §3 revision 2026-10-28) ────────────

/** Claims LockedPositions/<gw> from the live market positions, exactly once
 *  (set-if-absent, like PublishedPicks), under the [M2] frozen-week guard
 *  (guardedSnapshotClaim). [frozen] false = the week is no longer frozen:
 *  nothing of ours stands and the lock step stops. [stored] = the snapshot
 *  now stored (ours or a concurrent winner's), null when the market is
 *  empty or the week is no longer frozen. */
async function snapshotLockedPositions(
  db: FantasyDb, root: string, week: Gameweek,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<{ frozen: boolean; stored: unknown }> {
  const gw = week.number;
  const path = `${root}/LockedPositions/${gw}`;
  const existing = await db.read(path);
  if (existing != null) return { frozen: true, stored: existing };
  const snap = positionsSnapshotOf(marketPlayersOf(await db.read(`${root}/Players`)));
  if (Object.keys(snap).length === 0) return { frozen: true, stored: null };
  const claim = await guardedSnapshotClaim(db, root, week, path, snap, log, ctx);
  if (claim === 'unfrozen') return { frozen: false, stored: null };
  if (claim === 'won') {
    log.info('fantasy lock: positions locked',
      { ...ctx, gw, players: Object.keys(snap).length });
    return { frozen: true, stored: snap };
  }
  return { frozen: true, stored: await db.read(path) };
}

/** The market as gameweek [gw] is scored: live membership/eligibility with
 *  positions from LockedPositions/<gw>. [claim] (a first finalize) freezes
 *  the week exactly as the lock does (claimLockedWeek — a ledger holding
 *  another date takes no snapshot) and takes the snapshot when the lock
 *  sweep never did; otherwise a week without a snapshot (locked before this
 *  existed) falls back to live positions.
 *
 *  The same first-finalize backstop claims PriceHistory/<gw> (audit M2): a
 *  sweep outage spanning the lock AND the first finalize used to leave the
 *  week without recorded prices forever (the sweep only snapshots the
 *  CURRENT gameweek at its lock). The finalize-time market prices are the
 *  best available then — the Monday reprice of this week cannot have run
 *  yet (it needs this week's History). Set-if-absent like the sweep's
 *  claim, so a week the lock sweep already recorded is never touched; a
 *  rerun (claim false) never writes it. */
async function marketForGameweek(
  db: FantasyDb, root: string, gw: Gameweek, claim: boolean,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<Record<string, MarketPlayer> | null> {
  const players = marketPlayersOf(await db.read(`${root}/Players`));
  let locked: unknown;
  if (claim) {
    // [I4] A refused claim (another date, junk, a rewind's mark) or a week
    // that stopped being frozen right under it = null: the finalize stands
    // down — never History for a date the ledger does not freeze.
    if (!(await claimLockedWeek(db, root, gw, log, ctx))) return null;
    const positions = await snapshotLockedPositions(db, root, gw, log, ctx);
    if (!positions.frozen) return null;
    locked = positions.stored;
    if (!(await snapshotPriceHistory(db, root, gw, log, ctx))) return null;
  } else {
    locked = await db.read(`${root}/LockedPositions/${gw.number}`);
  }
  return withLockedPositions(players, lockedPositionsOf(locked));
}

// ── Phase B: lifecycle sweep ───────────────────────────────────────────────

/** Records the price (tenths) every market player has DURING gameweek [gw]
 *  into PriceHistory/<gw>/<name> (round 3 spec §3.2), exactly once at the
 *  week's lock — so owner manual price edits are captured too; the move
 *  AFTER a week stays in PriceChanges/<gw>. A FIRST finalize that outran
 *  every sweep claims it too (marketForGameweek), from the prices at that
 *  moment. Its OWN set-if-absent claim,
 *  deliberately independent of PublishedPicks: a week with no squads (which
 *  returns early in snapshotPublishedPicks) still records its prices. Every
 *  Players entry is recorded, guests (ineligible) included; an empty market
 *  writes nothing (RTDB would treat {} as a removal anyway). Under the [M2]
 *  frozen-week guard (guardedSnapshotClaim): false = the week is no longer
 *  frozen — nothing of ours stands and the lock step stops. */
async function snapshotPriceHistory(
  db: FantasyDb, root: string, week: Gameweek,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<boolean> {
  const gw = week.number;
  const path = `${root}/PriceHistory/${gw}`;
  if (await db.read(path) != null) return true; // cheap re-check every sweep
  const prices = marketPricesOf(await db.read(`${root}/Players`));
  if (Object.keys(prices).length === 0) return true;
  const claim = await guardedSnapshotClaim(db, root, week, path, prices, log, ctx);
  if (claim === 'won') {
    log.info('fantasy lock: prices recorded',
      { ...ctx, gw, players: Object.keys(prices).length });
  }
  return claim !== 'unfrozen';
}

/** Snapshot every saved squad into PublishedPicks/<gw>, exactly once (spec
 *  §9). The existence check keeps rereads cheap; the set-if-absent claim is
 *  what actually guarantees once-only under concurrent sweeps. Phase E's
 *  lock accounting rides the same claim: a chip replayed within its set is
 *  VOIDED (stripped from the snapshot itself, so finalize and the public
 *  reveal agree), the effective chip is frozen into
 *  TransferState.ChipPlayed (UsedThisGw raised to the lock's recount when
 *  that is higher — freezeLockTransferState), and the week's transfer
 *  cost points are persisted to TransferCosts/<gw> for finalize. The
 *  integrity pass rides it too (audit I2): every squad is judged
 *  (squad_integrity.ts), an invalid one is published with its `Invalid`
 *  verdict and its manager alerted. Squads are read LIVE here, which is
 *  right: the Squads/<uid> rule rejects client saves from the lock instant
 *  (server clock) until lock + 24 h (the app's reopen), and the sweep
 *  writes the snapshot BEFORE it flips GwState to 'locked' (step 3) —
 *  keep that order. [M2] The claim runs under the frozen-week guard
 *  (guardedSnapshotClaim: the week's LockedWeeks entry re-read right before
 *  it — after the judging, so the window is as small as it gets — and again
 *  once ours landed, deleting it when a rewind got in between), and every
 *  later lock write re-reads the entry first (TransferCosts, TransferState,
 *  SquadAlerts, Baselines): a week no longer frozen stops the rest of the
 *  lock step. The baselines are published with the Prev stash
 *  (publishSaleBaselines). TransferCosts/<gw> is ALWAYS written (ruling
 *  T3c) — the cost map, or null when nobody owes anything — so a stale node
 *  a cancelled lock left behind can never survive a re-lock and be charged
 *  at finalize. Resolves false only when the step stopped because the week
 *  is no longer frozen (the sweep then writes no GwState this run). */
async function snapshotPublishedPicks(
  db: FantasyDb, root: string, cfg: FantasyConfig, week: Gameweek,
  nowMs: number, log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<boolean> {
  const gw = week.number;
  if (await db.exists(`${root}/PublishedPicks/${gw}`)) return true;
  // A FIRST finalize that outran every sweep already scored this week from
  // the live Squads (finalizeGameweek's fallback): its History/<gw> is the
  // law for the week (effectiveSquadAfterWeek falls back to it; the fan
  // squad viewer reads it). A late claim here would snapshot Squads as they
  // are NOW (after the Free Hit restore and chip switch-off), re-judge them
  // from a fallback sale total (Baselines/<uid> is already FOR gw + 1) and
  // overwrite the week's baselines — so it never happens.
  if (await db.exists(`${root}/History/${gw}`)) {
    log.info('fantasy lock: History already written — snapshot skipped',
      { ...ctx, gw });
    return true;
  }
  const squads = mapChildren(await db.read(`${root}/Squads`));
  if (Object.keys(squads).length === 0) {
    log.info('fantasy lock: no squads to snapshot', { ...ctx, gw });
    return true;
  }
  const acc = lockAccounting({
    squadsByUid: squads,
    statesByUid: mapChildren(await db.read(`${root}/TransferState`)),
    historyRaw: await db.read(`${root}/History`),
    cfg,
    gw,
    // Chips from owner-voided weeks are refunded (spec §15).
    voidedWeeks: voidedWeeksOf(await db.read(`${root}/Voided`)),
    // Audit I2: judge every squad before it becomes the law.
    integrity: await loadIntegrityInputs(db, root, Object.keys(squads), gw),
  });
  const claim = await guardedSnapshotClaim(
    db, root, week, `${root}/PublishedPicks/${gw}`, acc.cleanSquads, log, ctx);
  // 'lost': a concurrent sweep won the claim and does the rest; 'unfrozen':
  // the week is being rewound — nothing more for this lock.
  if (claim !== 'won') return claim === 'lost';
  // [M2] Every later lock write re-checks the week first; a refusal stops
  // the rest of the lock step.
  const goOn = (step: string) =>
    stillFrozen(db, root, week, log, ctx, step, LOCK_STEP_STOPPED);
  for (const v of acc.voided) {
    log.warn('fantasy lock: chip voided — already used in this set',
      { ...ctx, gw, ...v });
  }
  if (!(await goOn('TransferCosts'))) return false;
  await db.write(`${root}/TransferCosts/${gw}`,
    Object.keys(acc.costPointsByUid).length > 0 ? acc.costPointsByUid : null);
  if (!(await goOn('TransferState'))) return false;
  await freezeLockTransferState(db, root, cfg, gw, acc, log, ctx);
  // Alerts next: the snapshot + accounting above are what scoring needs.
  if (!(await goOn('SquadAlerts'))) return false;
  await settleIntegrityAlerts(db, root, gw, acc, nowMs, log, ctx);
  log.info('fantasy lock: picks published', {
    ...ctx, gw, managers: Object.keys(acc.cleanSquads).length,
  });
  // FPL selling (spec §4): every manager's Baselines/<uid> for gw + 1, from
  // the snapshot just claimed, each stashing the node it replaces as Prev
  // ([M3] — the rewind's exact undo). Best-effort here — every finalize of
  // this week re-checks it — so a failure never fails the sweep.
  if (!(await goOn('Baselines'))) return false;
  try {
    await publishSaleBaselines(db, root, gw, log, ctx, { stashPrev: true });
  } catch (err) {
    log.warn('fantasy baselines: lock-time publish failed — finalize heals',
      { ...ctx, gw, error: String(err) });
  }
  return true;
}

/** The stand-down line of a finished, settled season (sweepSeason). */
const SEASON_OVER_STAND_DOWN = 'fantasy sweep: season over — standing down';

/** D7 of the 2026-11-06 scale fixes: whether a season is over AND settled,
 *  so the full sweep provably has nothing left to do —
 *  - the league flagged `<sport>/<season>/Finished`;
 *  - the badge marker (SEASON_BADGES_SETTLED_NODE: every scoreable week
 *    finalized, badges settled) is in place;
 *  - every `LockedWeeks/<n>` is a map marked `Scored: true` and carries no
 *    `Finalizing` or `Rewinding` stamp (a week still being scored or rewound
 *    is work);
 *  - the stored GwState is 'finalized' or absent (final review I1b: a league
 *    flagged Finished before its last finalize leaves GwState 'locked' until
 *    the full sweep's step 3 flips it);
 *  - no league match day (`<sport>/<season>/Date` keys, keys only) falls
 *    after the latest dated LockedWeeks entry, compared as calendar dates
 *    the way deriveGameweeks does, except a day Config/SkippedDates skips
 *    (final review I1a: a game day added after the season settled must open
 *    and lock like any week, or the Date trigger scores it from live Squads
 *    with no lock). No dated entry = nothing to measure against = work.
 *  Asked cheapest first: most seasons are mid-season and stop at the one
 *  scalar Finished read. The marker is a scalar too, so it is read
 *  (`!= null`), never `exists()`; LockedWeeks may list-coerce
 *  (childEntries). Any stamp counts, stale or fresh: in doubt the season
 *  sweeps in full, exactly as before. A failed read is the same doubt —
 *  warned once, then the full sweep, so a blip here never skips a season. */
async function isSeasonOverAndSettled(
  db: FantasyDb, sport: string, season: string,
  configNode: Record<string, unknown>,
  log: FantasyLogger, ctx: Record<string, unknown>,
): Promise<boolean> {
  const root = fantasyRoot(sport, season);
  try {
    if ((await db.read(`${sport}/${season}/Finished`)) !== true) return false;
    if ((await db.read(`${root}/${SEASON_BADGES_SETTLED_NODE}`)) == null) {
      return false;
    }
    const lockedNode = await db.read(`${root}/LockedWeeks`);
    for (const [, week] of childEntries(lockedNode)) {
      if (!isPlainMap(week) || week['Scored'] !== true) return false;
      if (isRewinding(week) || week['Finalizing'] != null) return false;
    }
    const gwState = await db.read(`${root}/GwState`);
    if (gwState != null &&
      !(isPlainMap(gwState) && gwState['status'] === 'finalized')) {
      return false;
    }
    const lockedDates = Object.values(lockedWeeksOf(lockedNode))
      .map((w) => parseDbDate(w.date).getTime());
    if (lockedDates.length === 0) return false;
    const lastLockedMs = Math.max(...lockedDates);
    const { skippedDates } = scheduleOverridesOf(configNode);
    for (const day of await childKeysOf(db, `${sport}/${season}/Date`, log)) {
      if (skippedDates.has(day)) continue;
      if (parseDbDate(day).getTime() > lastLockedMs) return false;
    }
    return true;
  } catch (err) {
    log.warn('fantasy sweep: stand-down check failed — sweeping in full',
      { ...ctx, error: String(err) });
    return false;
  }
}

/** What the sweep steps shared by the normal path and the finished-season
 *  stand-down (publishDueNewsDrafts, healLostLiveSettle) are handed. */
interface StandingSweepArgs {
  sport: string;
  season: string;
  nowUtc: Date;
  log: FantasyLogger;
  /** Test seam: the settle tombstone's clock (deps.clock). */
  clock?: () => number;
}

/** Sweep step 2b — news draft auto-publish (spec 2026-10-28 §4.4): ANY
 *  draft — autopilot 'dreamteam'/'ai' or an owner-scheduled 'owner' post —
 *  whose AutoPublishAt is due publishes itself to News/Published (the §4.1
 *  post fields, news.ts publishedRowFromDraft) and leaves the queue. A draft
 *  without AutoPublishAt waits for the owner (autopilot off or the Manager's
 *  Auto-publish switch off); a discard deleted it. It runs on the normal
 *  path AND while a finished season stands down (sweepSeason), so the last
 *  gameweek's posts still ship. A draft for an owner-VOIDED week is held
 *  (never deleted — it is the owner's queue): its week no longer counts; an
 *  un-void releases it. The row lands set-if-absent (review 2026-10-28): a
 *  due draft whose key is ALREADY published (a resurrected draft, a failed
 *  draft delete) never overwrites the live post — that wiped its push stamps
 *  and re-pushed it. Its AutoPublishAt is cleared instead, so it waits in
 *  the owner's queue as a visible duplicate (never deleted). */
async function publishDueNewsDrafts(
  db: FantasyDb, a: StandingSweepArgs,
): Promise<void> {
  const { sport, season, nowUtc } = a;
  const ctx = { sport, season };
  const root = fantasyRoot(sport, season);
  const log = a.log;
  const voidedNow = voidedWeeksOf(await db.read(`${root}/Voided`));
  for (const [key, draft] of childEntries(await db.read(`${root}/News/Drafts`))) {
    if (!shouldAutoPublish(draft, nowUtc.getTime())) continue;
    const d = draft as Record<string, unknown>;
    if (voidedNow.includes(toIntLoose(d['Gw']))) continue;
    const published = await db.writeIfAbsent(`${root}/News/Published/${key}`,
      publishedRowFromDraft(d, nowUtc.getTime()));
    if (!published) {
      await db.write(`${root}/News/Drafts/${key}/AutoPublishAt`, null);
      log.warn('fantasy news: draft already published — schedule cleared',
        { ...ctx, key });
      continue;
    }
    await db.write(`${root}/News/Drafts/${key}`, null);
    log.info('fantasy news: draft auto-published',
      { ...ctx, key, source: String(d['Source'] ?? '') });
  }
}

/** Sweep step 2d — lost settle (live design §4): a finalize that died after
 *  History but before its live hand-over (the settle is its last step and
 *  best-effort) leaves Live 'live' for a settled week — and no live run ever
 *  writes again (PlayerWeeks/<gw> stands them down), so phones would show
 *  LIVE until the next week. On EVERY sweep, whatever GwState says (step 3
 *  flips it to 'finalized' right away) and also while a finished season
 *  stands down: a 'live' node of week N whose History/N exists and whose
 *  UpdatedAt is older than LIVE_SETTLE_HEAL_MS gets the tombstone
 *  (settleLiveWeek). The margin outlasts any in-flight finalize, which must
 *  land every official node before the tombstone. One small read (Live/Meta)
 *  per season when nothing is wrong. Logged; never throws, never blocks the
 *  steps after it. */
async function healLostLiveSettle(
  db: FantasyDb, a: StandingSweepArgs,
): Promise<void> {
  const { sport, season, nowUtc, log } = a;
  const ctx = { sport, season };
  const root = fantasyRoot(sport, season);
  const nowMs = nowUtc.getTime();
  try {
    const meta = liveMetaOf(await db.read(`${root}/Live/Meta`));
    if (meta !== null && meta.live &&
      nowMs - meta.updatedAt > LIVE_SETTLE_HEAL_MS &&
      (await db.exists(`${root}/History/${meta.gw}`))) {
      log.warn('fantasy sweep: settled week still live — healing the hand-over',
        { ...ctx, gw: meta.gw });
      await settleLiveWeek(db, {
        sport, season, gw: meta.gw, nowUtc, log,
        ctx: { ...ctx, gw: meta.gw }, clock: a.clock,
      });
    }
  } catch (err) {
    log.warn('fantasy sweep: live settle heal failed — retried by the next sweep',
      { ...ctx, error: String(err) });
  }
}

async function sweepSeason(
  db: FantasyDb,
  ref: { sport: string; season: string; configNode: Record<string, unknown> },
  nowUtc: Date, log: FantasyLogger, deps?: FantasyJobDeps,
): Promise<void> {
  const { sport, season } = ref;
  const ctx = { sport, season };
  const root = fantasyRoot(sport, season);
  const nowMs = nowUtc.getTime();

  // 0. Lock-override auto-return (spec §2): an open/locked override whose
  //    Config.lockOverrideUntil has passed is reverted in the DB (back to
  //    'auto', until removed) and the season then runs normally in THIS
  //    sweep, on the reverted config. The revert is a compare-and-set on
  //    Config (review 2026-10-28): it lands only while Config still holds
  //    the SAME override and until this sweep read — an owner re-lock (or a
  //    new until, or Resume Auto) that raced in after the read is never
  //    wiped; the sweep then runs on the fresh config instead (still
  //    expired = reverted by the next sweep).
  let configNode = ref.configNode;
  if (lockOverrideOf(configNode) !== 'auto' &&
    lockOverrideOf(configNode, nowMs) === 'auto') {
    const expiredOverride = configNode['lockOverride'];
    const expiredUntil = configNode['lockOverrideUntil'];
    const reverted = await updateIfPresent(db, `${root}/Config`, (cur) => {
      if (cur['lockOverride'] !== expiredOverride ||
        cur['lockOverrideUntil'] !== expiredUntil) {
        return undefined;
      }
      const next: Record<string, unknown> = { ...cur, lockOverride: 'auto' };
      delete next['lockOverrideUntil'];
      return next;
    });
    if (reverted !== null) {
      log.info('fantasy sweep: lock override expired — back to auto', ctx);
      configNode = reverted;
    } else {
      const fresh = await db.read(`${root}/Config`);
      if (!isPlainMap(fresh)) return; // Config removed meanwhile
      log.info('fantasy sweep: lock override changed since read — ' +
        'revert skipped', ctx);
      configNode = fresh;
    }
  }
  // 0b. Scheduled manager messages (spec 2026-10-28 §3): owner messages are
  //     not engine jobs, so they go out BEFORE the stand-down below — a
  //     paused engine still delivers "Match day postponed". messages.ts owns
  //     the ScheduledPushes shape (SentAt claim, Sent / Error). A sweep
  //     without a pusher claims nothing.
  if (deps?.pusher) {
    await sendDueScheduledMessages(
      db, deps.pusher, { sport, season, nowUtc, log });
  }
  if (lockOverrideOf(configNode, nowMs) !== 'auto') {
    log.info('fantasy sweep: lockOverride frozen — standing down', ctx);
    return;
  }
  // A TestFill season (orchestration_db.ts TEST_FILL_NODE) stands down even
  // when auto: its History/Leaderboards/Badges are a replayed fake season.
  if (await isTestFillSeason(db, root)) {
    log.info(TEST_FILL_STAND_DOWN, { ...ctx, job: 'sweep' });
    return;
  }
  // A finished, settled season stands down by itself (D7, scale fixes
  // 2026-11-06): the league is flagged Finished, its badges are settled (the
  // SeasonBadgesSettledAt marker), every LockedWeeks entry is Scored with no
  // Finalizing or Rewinding stamp, GwState is 'finalized' and no match day
  // (bar a skipped one) is dated after the last locked week —
  // isSeasonOverAndSettled. Nothing here changes on its own, so the full
  // sweep below (Date, Squads, History, Players...) would only re-read it
  // every 15 minutes. Two steps still run, the very functions the normal
  // path calls: owner-scheduled news drafts publish (2b) and a lost live
  // hand-over heals (2d); step 0b (scheduled messages) already ran above.
  // The guard is what keeps a late change safe (final review I1): a game day
  // added after the season settled fails the match-day check, so the full
  // sweep opens and locks it like any week; a league flagged Finished before
  // its last finalize fails the GwState check until step 3 flips it.
  if (await isSeasonOverAndSettled(db, sport, season, configNode, log, ctx)) {
    log.info(SEASON_OVER_STAND_DOWN, ctx);
    await publishDueNewsDrafts(db, { sport, season, nowUtc, log });
    await healLostLiveSettle(db,
      { sport, season, nowUtc, log, clock: deps?.clock });
    return;
  }
  const cfg = configFromMap(configNode);

  // 0c. A called-off game day (schedule_rewind.ts — season setup + schedule
  //     plan 2026-11-05): the latest frozen week whose day was cancelled,
  //     skipped or moved before any game started is rewound as if it never
  //     happened and reopens; the rest of the sweep then runs on the fresh
  //     week list below. A season with no game day at all stands down
  //     (warned); a read that throws gives the season up for this run.
  const rewind = await rewindCancelledWeek(db, {
    sport, season, cfg, configNode, nowUtc, log, pusher: deps?.pusher,
  });
  if (rewind === 'standDown') return;

  const { gws } = await loadSeasonGameweeks(db, sport, season, cfg, configNode);
  const current = currentGameweek(gws, nowUtc);

  // 0d. The heal (rulings T3c/T3d, schedule_rewind.ts healOpenWeek): while
  //     the current week is open and not frozen no lock of it ever stood, so
  //     a lock write a stale sweep landed after a rewind (snapshots, a live
  //     node, a baseline FOR the next week) is undone before it can be
  //     adopted by the real lock or block a Save — only when week n - 1 is
  //     frozen (or n is 1) and History/<n> is absent (ruling T4d: a season
  //     without the ledger can renumber a scored week onto the open one).
  //     Logged; never blocks the steps below.
  if (current && !current.frozen &&
    gameweekStatusAt(current, nowUtc) !== 'locked') {
    try {
      await healOpenWeek(db, root, current, gws, log, ctx);
    } catch (err) {
      log.warn('fantasy heal: failed — retried by the next sweep',
        { ...ctx, gw: current.number, error: String(err) });
    }
  }

  // 1. Lock snapshots for the current gameweek (positions, prices, then
  //    picks), before any finalize can need them. Existence-guarded rather
  //    than transition-edge-triggered, so a sweep that was down at the lock
  //    instant still snapshots exactly once. Prices are claimed before the
  //    picks step because that one returns early for a week with no squads.
  //    The week is FROZEN first (LockedWeeks/<n> — claimLockedWeek, the
  //    lock's first write): a ledger already holding another date for this
  //    number, or marked Rewinding, skips the whole step (warned), and every
  //    lock write re-checks the ledger around it ([M2] stillFrozen,
  //    guardedSnapshotClaim) — the first refusal stops the step, and this
  //    sweep then writes no GwState (step 3, ruling T3d): its week list is
  //    older than the ledger, and a stale 'locked' must never land over a
  //    rewind.
  let lockStopped = false;
  if (current && gameweekStatusAt(current, nowUtc) === 'locked') {
    lockStopped = !(await claimLockedWeek(db, root, current, log, ctx) &&
      (await snapshotLockedPositions(db, root, current, log, ctx)).frozen &&
      await snapshotPriceHistory(db, root, current, log, ctx) &&
      await snapshotPublishedPicks(db, root, cfg, current, nowMs, log, ctx));
  }

  // 2. Finalize backstop: any lock-passed gameweek whose match day is
  //    complete but lacks History (first-run guard applies).
  for (const gw of gws) {
    if (gw.lockUtc.getTime() > nowUtc.getTime()) break;
    if (await db.exists(`${root}/History/${gw.number}`)) continue;
    if (!(await mayFinalizeFirstRun(db, root, gws, gw, nowUtc))) continue;
    const games = gamesOfDate(await db.read(`${sport}/${season}/Date/${gw.date}`));
    if (!allGamesFinal(games)) continue;
    log.info('fantasy sweep: backstop finalize', { ...ctx, gw: gw.number });
    await finalizeGameweek(db, {
      sport, season, cfg, configNode, gw, nowUtc, log, deps,
    });
  }

  // 2a. Season-end badges (spec 2026-10-30 §4): the league may flag the
  //     season Finished AFTER its last finalize, so the sweep checks too —
  //     but only settles a season that is not marked settled and holds no
  //     auto season award yet (the SeasonBadgesSettledAt marker answers
  //     first, without reading Badges or History; every later re-settle comes
  //     from a finalize rerun; badges.ts SEASON END + SETTLED MARKER).
  //     Before the season-over return below, which is exactly when it fires.
  //     A failure is logged (the next sweep retries — still unsettled) and
  //     never blocks the steps below.
  try {
    await settleSeasonBadges(db, {
      sport, season, cfg, nowUtc, log, onlyIfUnsettled: true,
    });
  } catch (err) {
    log.warn('fantasy badges: season-end check failed',
      { ...ctx, error: String(err) });
  }

  // 2b. News draft auto-publish (spec 2026-10-28 §4.4) — publishDueNewsDrafts.
  await publishDueNewsDrafts(db, { sport, season, nowUtc, log });

  // 2c. Live backstop (live design 2026-11-03 §4): a lost trigger must not
  //     leave the live week behind. While the STORED GwState says the
  //     current week is locked (a previous sweep saw the lock; 'finalized'
  //     once History exists), recompute it when SOME game of its date has
  //     started (status 1 or 2) and not all of them are Final, or when every
  //     game is Final but Live never reached this week's settled tombstone —
  //     refreshLiveWeek itself answers 'settled' once PlayerWeeks/<gw>
  //     exists, so the backstop finalize above wins (a lost settle is step
  //     2d's). After the backstop (step 2), before step 3. A failure is
  //     logged and never blocks the steps below.
  if (current) {
    try {
      const stored = await db.read(`${root}/GwState`);
      if (isPlainMap(stored) && stored['status'] === 'locked' &&
        toIntLoose(stored['current']) === current.number) {
        const games = gamesOfDate(
          await db.read(`${sport}/${season}/Date/${current.date}`));
        const allFinal = allGamesFinal(games);
        const started = games.some((g) => {
          const s = toIntLoose(g['status']);
          return s === 1 || s === 2;
        });
        let due = started && !allFinal;
        if (!due && allFinal) {
          const meta = liveMetaOf(await db.read(`${root}/Live/Meta`));
          due = !(meta !== null && meta.gw === current.number && meta.settled);
        }
        if (due) {
          const result = await refreshLiveWeek(db, {
            sport, season, dateKey: current.date, eventAtMs: nowMs, nowUtc,
            log, clock: deps?.clock,
          });
          log.info('fantasy sweep: live backstop',
            { ...ctx, gw: current.number, result });
        }
      }
    } catch (err) {
      log.warn('fantasy sweep: live backstop failed — retried by the next sweep',
        { ...ctx, error: String(err) });
    }
  }

  // 2d. Lost settle (live design §4) — healLostLiveSettle, on EVERY sweep.
  await healLostLiveSettle(db,
    { sport, season, nowUtc, log, clock: deps?.clock });

  // 3. GwState upsert (schedule_rewind.ts upsertGwState), after the backstop
  //    so a finalize lands as 'finalized' in the same sweep; season over =
  //    left as-is. Skipped when the lock step stopped on a week no longer
  //    frozen (step 1). The open-window steps below run only while open.
  if (lockStopped) {
    log.info('fantasy sweep: lock step stopped — GwState left to the next sweep',
      { ...ctx, gw: current?.number ?? null });
    return;
  }
  await upsertGwState(db, root, current, nowUtc, log, ctx);
  if (!current) return;
  const open = gameweekStatusAt(current, nowUtc) !== 'locked';

  // 3b. Position changes deferred while the window was locked (spec §3
  //     holder protection) apply the moment it reopens: relabel holders,
  //     alert + push the ones left with an illegal formation (free swap
  //     this gameweek). position_changes.ts owns the nodes.
  if (open) {
    const applied = await applyPendingPositionChanges(db, {
      sport, season, cfg,
      target: { gw: current.number, lockUtcMs: current.lockUtc.getTime() },
      nowUtc, log, pusher: deps?.pusher,
    });
    if (applied > 0) {
      log.info('fantasy sweep: deferred position changes applied',
        { ...ctx, gw: current.number, applied });
    }
  }

  // 3c. Over-budget preview (FPL selling, spec §4): while the week is open,
  //     warn — banner + one push per gameweek — every manager whose saved
  //     squad the coming lock would judge overBudget (prices moved after
  //     the save). After 3b, so a position alert it just wrote keeps the
  //     slot. A 'locked' (or 'open') lockOverride and a TestFill season
  //     already stood the whole sweep down above. A failure here is logged
  //     and never blocks the reminder below.
  if (open) {
    try {
      await previewOverBudget(db, root, cfg, {
        sport, season, gw: current.number,
        lockUtcMs: current.lockUtc.getTime(), nowMs, pusher: deps?.pusher,
      }, log, ctx);
    } catch (err) {
      log.warn('fantasy preview: over-budget check failed — retried by the ' +
        'next sweep', { ...ctx, gw: current.number, error: String(err) });
    }
  }

  // 4. Deadline reminder (Phase F): fires once per gameweek when a sweep
  //    first crosses the reminder instant while the week is still open.
  //    Audience = signed-up managers with UNCHANGED squads (spec §12; the
  //    measurable rule is pushes.ts reminderAudience). The ReminderSent
  //    claim lands BEFORE the send so concurrent sweeps can never
  //    double-push; a sweep without a pusher claims nothing.
  const pusher = deps?.pusher;
  if (pusher && open) {
    const rCfg = reminderConfigFrom(configNode['Reminder']);
    if (rCfg.enabled &&
      nowUtc.getTime() >= reminderInstantMs(current.lockUtc.getTime(), rCfg) &&
      (await db.read(`${root}/ReminderSent/${current.number}`)) == null) {
      const won = await db.writeIfAbsent(
        `${root}/ReminderSent/${current.number}`, { At: nowUtc.getTime() });
      if (won) {
        const audience = reminderAudience({
          managersRaw: await db.read(`${root}/Managers`),
          squadsRaw: await db.read(`${root}/Squads`),
          transferStateRaw: await db.read(`${root}/TransferState`),
          gw: current.number,
        });
        const body = fillReminderTemplate(
          rCfg.template, formatDeadlineInstant(current.lockUtc.getTime()));
        const data = fantasyPushData(sport, season, current.number);
        const sent = await pusher.sendToUsers(audience.map((uid) => ({
          uid, title: REMINDER_TITLE, body, data,
        })));
        log.info('fantasy reminder pushed',
          { ...ctx, gw: current.number, audience: audience.length, sent });
      }
    }
  }
}

/** The 15-minute scheduled sweep over every fantasy-enabled season. One
 *  season's failure never starves the others. Every run first seeds the
 *  global badge catalog (Fantasy/BadgeCatalog, set-if-absent per starter
 *  id — owner edits are never overwritten) from the catalog node itself, so
 *  the catalog exists for the Manager and the fan app even while every
 *  season is paused. The seasons come from listFantasySeasons — keys-only
 *  reads down to each season's Config — never from a read of the whole
 *  Fantasy node (every season's Players, Squads, History...); the catalog
 *  sibling is never listed as a sport. */
export async function runLifecycleSweep(
  db: FantasyDb, nowUtc: Date, log: FantasyLogger = silent,
  deps?: FantasyJobDeps,
): Promise<void> {
  const catalogNode = await db.read(BADGE_CATALOG_PATH);
  try {
    await seedBadgeCatalog(db, catalogNode, log);
  } catch (err) {
    log.warn('fantasy badges: catalog seeding failed', { error: String(err) });
  }
  const seasons = await listFantasySeasons(db, log);
  for (const ref of seasons) {
    try {
      await sweepSeason(db, ref, nowUtc, log, deps);
    } catch (err) {
      log.warn('fantasy sweep: season failed', {
        sport: ref.sport, season: ref.season, error: String(err),
      });
    }
  }
}

// ── Phase F: send-now callable core ────────────────────────────────────────

export interface ReminderNowArgs {
  sport: string;
  season: string;
  /** 'unchanged' (default) = the scheduled reminder's audience;
   *  'all' = every signed-up manager. */
  audience?: 'all' | 'unchanged';
  nowUtc: Date;
  log?: FantasyLogger;
}

/** The sendFantasyReminderNow callable's core: an admin's manual push to
 *  the reminder audience. A deliberate action, so it ignores
 *  Reminder.Enabled, the frozen-machine lockOverride and the ReminderSent
 *  guard, and it marks nothing — the scheduled reminder still fires on its
 *  own clock. Throws when the season is not fantasy-enabled or has no
 *  current gameweek (the callable maps that to failed-precondition). */
export async function sendReminderNow(
  db: FantasyDb, pusher: FantasyPusher, args: ReminderNowArgs,
): Promise<{ gw: number; audience: number; sent: number }> {
  const { sport, season } = args;
  const log = args.log ?? silent;
  const root = fantasyRoot(sport, season);

  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) {
    throw new Error(`No fantasy Config for ${sport}/${season}`);
  }
  const cfg = configFromMap(configNode);
  const { gws } = await loadSeasonGameweeks(db, sport, season, cfg, configNode);
  const current = currentGameweek(gws, args.nowUtc);
  if (!current) {
    throw new Error(`No current gameweek for ${sport}/${season}`);
  }

  const uids = reminderAudience({
    managersRaw: await db.read(`${root}/Managers`),
    squadsRaw: await db.read(`${root}/Squads`),
    // null state disables the unchanged filter = everyone (see pushes.ts).
    transferStateRaw: args.audience === 'all'
      ? null
      : await db.read(`${root}/TransferState`),
    gw: current.number,
  });
  const rCfg = reminderConfigFrom(configNode['Reminder']);
  const body = fillReminderTemplate(
    rCfg.template, formatDeadlineInstant(current.lockUtc.getTime()));
  const data = fantasyPushData(sport, season, current.number);
  const sent = await pusher.sendToUsers(uids.map((uid) => ({
    uid, title: REMINDER_TITLE, body, data,
  })));
  log.info('fantasy reminder sent now', {
    sport, season, gw: current.number,
    audience: uids.length, sent, mode: args.audience ?? 'unchanged',
  });
  return { gw: current.number, audience: uids.length, sent };
}

// ── Phase D: the morning-after repricing ───────────────────────────────────
// (named for the Monday it started as: the league plays Sundays today. The
// exported function names stay because renaming a deployed function deletes
// and recreates it — see fantasy_lifecycle.ts.)

/** How old a `Repriced/<gw> {Pending:true}` claim may get before the
 *  reprice job warns that its run died mid-way (a healthy run finalizes the
 *  row within seconds). */
const STALE_REPRICE_CLAIM_MS = 60 * 60 * 1000;

/** Teams reopen for the next week this long after a week's deadline (the
 *  "current" window of currentGameweek, gameweeks.ts). Repricing once they
 *  have would move prices under managers who are already planning. */
const REPRICE_WINDOW_AFTER_LOCK_MS = 24 * 60 * 60 * 1000;

/** Whether the MMDDYYYY match date [dateKey] is strictly before today in
 *  league time (America/Los_Angeles — never the server's or UTC's calendar
 *  day: Sunday 19:00 PDT is already Monday in UTC and still game day). */
function isBeforeLeagueToday(dateKey: string, nowUtc: Date): boolean {
  const wall = leagueWallClock(nowUtc);
  const todayMs = Date.UTC(
    wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate());
  return parseDbDate(dateKey).getTime() < todayMs;
}

/** Hourly 10:00-15:00 league time (fantasy_lifecycle.ts — the claim below
 *  makes every attempt after a successful one a no-op): reprice the most
 *  recent FINALIZED gameweek not yet repriced — the morning after its game
 *  day, whatever the weekday. That week is the largest week number in the
 *  season's History (latestScoredWeek: the keys only, never the weeks'
 *  contents — History is the truth, the LockedWeeks `Scored` mark is
 *  warn-only), and the seasons come from listFantasySeasons — the job never
 *  downloads the whole Fantasy node or a season's History.
 *  Only when the week's date is before today (league time) AND teams have
 *  not reopened (now < lockUtc + 24 h, taken from the week's Gameweek in
 *  loadSeasonGameweeks):
 *   - the game day is still today (or later) -> nothing, tomorrow's run;
 *   - finalized at or after lockUtc + 24 h -> Repriced/<gw> =
 *     {Skipped:'late', At} (writeIfAbsent: a real claim is never replaced),
 *     a warning, no price moves — the owner adjusts by hand on the Manager
 *     Players page;
 *   - the History week is not in the schedule (an oddity) -> warn, nothing.
 *  Otherwise, per position, repriceDeltas over ALL eligible market
 *  players (a player with no PlayerWeeks entry scored 0 that week — absent
 *  and no-game players included at their real score), applyDelta onto
 *  Players/<name>/priceTenths, PriceChanges/<gw> rows for the client's
 *  risers & fallers strip, then the Repriced/<gw> done-flag. An admin
 *  PriceChanges/<gw>/Manual == true makes the job stand down for that week
 *  (flagged done with Manual:true so it never re-evaluates); an
 *  owner-voided week (Voided/<gw> == true) is skipped the same way
 *  (flagged Voided:true). */
export async function runMondayReprice(
  db: FantasyDb, nowUtc: Date, log: FantasyLogger = silent,
): Promise<void> {
  const seasons = await listFantasySeasons(db, log);
  for (const ref of seasons) {
    const { sport, season } = ref;
    const ctx = { sport, season };
    try {
      if (lockOverrideOf(ref.configNode, nowUtc.getTime()) !== 'auto') {
        log.info('fantasy reprice: lockOverride frozen — standing down', ctx);
        continue;
      }
      const root = fantasyRoot(sport, season);
      if (await isTestFillSeason(db, root)) {
        log.info(TEST_FILL_STAND_DOWN, { ...ctx, job: 'reprice' });
        continue;
      }
      const cfg = configFromMap(ref.configNode);

      // The latest finalized week: the largest History week number (keys
      // only — never a read of the whole History node).
      const gw = await latestScoredWeek(db, root, log);
      if (gw === null) continue; // nothing finalized yet

      const done = await db.read(`${root}/Repriced/${gw}`);
      if (done != null) {
        // Done — or claimed. A claim still Pending an hour after it was
        // taken is a run that died mid-way (audit M5): say so loudly on
        // every later run, but NEVER take it over — its prices may be
        // half-moved, and repricing again would move them twice.
        if (isPlainMap(done) && done['Pending'] === true &&
          nowUtc.getTime() - toIntLoose(done['At']) > STALE_REPRICE_CLAIM_MS) {
          log.warn('fantasy reprice: stale Pending claim — needs operator ' +
            'attention', { ...ctx, gw, At: done['At'] ?? null });
        }
        continue;
      }

      // WHEN: the morning after the week's game day, and before teams
      // reopen. The week list comes from loadSeasonGameweeks (the week is
      // frozen at its locked date + deadline); a read that throws aborts
      // this season here (caught below) — never "no weeks", never "late".
      const { gws } = await loadSeasonGameweeks(
        db, sport, season, cfg, ref.configNode);
      const week = gws.find((g) => g.number === gw);
      if (week === undefined) {
        log.warn(`fantasy reprice: no gameweek ${gw} in the schedule — ` +
          'skipped', { ...ctx, gw });
        continue;
      }
      const reopenMs = week.lockUtc.getTime() + REPRICE_WINDOW_AFTER_LOCK_MS;
      if (nowUtc.getTime() >= reopenMs) {
        // Finalized after teams reopened: leave the prices alone for good.
        // writeIfAbsent so a claim another run just took is never replaced.
        if (await db.writeIfAbsent(`${root}/Repriced/${gw}`,
          { Skipped: 'late', At: nowUtc.getTime() })) {
          log.warn('fantasy reprice: week finalized after teams reopened — ' +
            'prices not moved', {
            ...ctx, gw, date: week.date, reopenedAtUtc: reopenMs,
          });
        }
        continue;
      }
      if (!isBeforeLeagueToday(week.date, nowUtc)) {
        // The game day is still today: tomorrow's run reprices it.
        log.info('fantasy reprice: game day is today — waiting for the ' +
          'morning after', { ...ctx, gw, date: week.date });
        continue;
      }

      // Once-only CLAIM (transaction): a double-fired schedule or two
      // overlapping runs must never move prices twice. The row is written
      // {At, Pending:true} up front and finalized below; a crash in between
      // leaves the claim (prices untouched or partially moved) for the
      // operator to clear — warned on every later run once it is over an
      // hour old (the done-check above).
      if (!(await db.writeIfAbsent(`${root}/Repriced/${gw}`,
        { At: nowUtc.getTime(), Pending: true }))) {
        log.info('fantasy reprice: claimed by a concurrent run — standing down',
          { ...ctx, gw });
        continue;
      }
      if (isVoidFlag(await db.read(`${root}/Voided/${gw}`))) {
        // An owner-voided week moves no prices (spec §15); flagged done so
        // it never re-evaluates.
        await db.write(`${root}/Repriced/${gw}`,
          { At: nowUtc.getTime(), Voided: true });
        log.info('fantasy reprice: voided week — skipped', { ...ctx, gw });
        continue;
      }
      if (await db.read(`${root}/PriceChanges/${gw}/Manual`) === true) {
        await db.write(`${root}/Repriced/${gw}`,
          { At: nowUtc.getTime(), Manual: true });
        log.info('fantasy reprice: admin Manual flag — standing down',
          { ...ctx, gw });
        continue;
      }

      const playersNode = await db.read(`${root}/Players`);
      // Peers are grouped at the week's LOCKED positions — the positions
      // its PlayerWeeks were scored at (a change made after the lock moves
      // the player's peer group from the next repriced week on).
      const players = withLockedPositions(marketPlayersOf(playersNode),
        lockedPositionsOf(await db.read(`${root}/LockedPositions/${gw}`)));
      const prices = marketPricesOf(playersNode);

      const weekPointsRaw = await db.read(`${root}/PlayerWeeks/${gw}`);
      if (weekPointsRaw == null) {
        log.warn('fantasy reprice: PlayerWeeks missing — repricing from ' +
          'zeros', { ...ctx, gw });
      }
      const weekPoints: Record<string, number> = {};
      for (const [name, v] of childEntries(weekPointsRaw)) {
        weekPoints[name] = toIntLoose(v);
      }

      const changes: Record<string, { delta: number }> = {};
      for (const pos of FANTASY_POSITIONS) {
        const group: Record<string, number> = {};
        for (const [name, p] of Object.entries(players)) {
          if (p.eligible && p.position === pos) {
            group[name] = weekPoints[name] ?? 0;
          }
        }
        const deltas = repriceDeltas(group, cfg);
        for (const [name, delta] of Object.entries(deltas)) {
          if (delta === 0) continue;
          const oldPrice = prices[name] ?? 0;
          const newPrice = applyDelta(oldPrice, delta, cfg);
          const effective = newPrice - oldPrice;
          if (effective === 0) continue; // clamped at floor/ceiling
          await db.write(`${root}/Players/${name}/priceTenths`, newPrice);
          changes[name] = { delta: effective };
        }
      }
      if (Object.keys(changes).length > 0) {
        await db.write(`${root}/PriceChanges/${gw}`, changes);
      }
      await db.write(`${root}/Repriced/${gw}`, { At: nowUtc.getTime() });
      log.info('fantasy gameweek repriced', {
        ...ctx, gw, moves: Object.keys(changes).length,
      });
    } catch (err) {
      log.warn('fantasy reprice: season failed', { ...ctx, error: String(err) });
    }
  }
}

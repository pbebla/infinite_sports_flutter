// Infinite Insiders "Verified on the field" watcher (Task X2). Purely an
// integrity flag — spec §3: "when the referred player records their first
// stat in any game, the referral is auto-marked 'verified on the field' ...
// gates nothing, costs the owner zero effort." No notification is sent (the
// spec calls it a silent dashboard checkmark), and the write is idempotent
// (a referral only ever flips Verified false -> true once).
//
// PATH CHOSEN: league StatLog only (`/{sport}/{season}/Date/{dateKey}/
// {gameIndex}/StatLog/{idx}`, Manager `FirebasePaths.gameStatLog` /
// `LineupService.incrementPlayerStatForGame`), NOT the tournament
// Team{N}Activity path. Both write shapes were checked in the Manager repo
// (InfiniteSportsManagerFlutter, read-only) before choosing:
//
//   - League: each StatLog entry is `{t: team, p: player, s: stat}` where
//     `player` is the roster key under `<sport>/<season>/Line Ups/<team>/
//     <player>` — the SAME node that optionally carries a `UID` field
//     (futsal_player.dart/basketball_player.dart/flag_football_player.dart
//     all have `uid: String?`). That UID is populated by a purpose-built,
//     first-class linking flow: `signup_roster.dart` (`buildSignupPickList`,
//     used by the futsal/basketball/flag-football manager "Create Lineup
//     from Sign-Ups" pages) plus `LineupService.linkLeaguePlayer` for
//     retroactive linking. `season_builder.dart`'s own rename/delete
//     cascades already trust `player['UID']` as the source of truth for
//     "is this roster row a linked account" with no fallback — i.e. this is
//     an established, already-relied-upon resolution path in the Manager
//     codebase, not something invented for this watcher.
//   - Tournament: `manage_rosters_page.dart` only offers a free-text "User
//     UID (optional)" field the admin types by hand — no signup-based
//     linking flow at all. That is strictly LESS reliable (typo-prone, no
//     structured source), so despite tournaments being the other stat-write
//     surface named in the plan, they were rejected as the verify source.
//
// A name->uid lookup is still a best-effort miss for any UNLINKED league
// player (no build-from-signups / no manual link) — in that case this
// watcher simply never marks Verified for that referral, which matches the
// spec's own framing of Verified as a bonus/nice-to-have signal ("gates
// nothing"), not a required or promised outcome. Tournament-verified is
// documented here as explicit future work if the owner later wants it (it
// would need the Manager tournament roster UID field turned into a
// structured/linked flow first, mirroring signup_roster.dart, to be
// trustworthy enough not to mis-fire).
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §3
// (Verified flag), §10 (automation — "Stat watcher: referred player's first
// recorded stat -> set Verified"). Plan:
// docs/superpowers/plans/2026-07-27-infinite-insiders.md Task X2.

import * as logger from 'firebase-functions/logger';
import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';

/** Same-instance root (index.ts/league_watch.ts/insiders_watch.ts dbRoot
 *  parity — matters in the emulator). */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

/** One `{t, p, s}` StatLog entry (LineupService.incrementPlayerStatForGame
 *  journal shape). Malformed/legacy entries (missing team or player) parse
 *  to null team/player so the caller can bail cleanly. */
function parseStatLogEntry(raw: unknown): { team: string; player: string } | null {
  if (!raw || typeof raw !== 'object') return null;
  const m = raw as Record<string, unknown>;
  const team = typeof m['t'] === 'string' ? m['t'] : '';
  const player = typeof m['p'] === 'string' ? m['p'] : '';
  if (!team || !player) return null;
  return { team, player };
}

/** Resolves a league roster row to a linked account uid, or null when the
 *  row has never been linked (no signup-built lineup entry / no manual
 *  link) — the expected, unremarkable case for a lot of legacy rosters. */
async function resolveLineupUid(
  root: Reference, sport: string, season: string, team: string, player: string,
): Promise<string | null> {
  const snap = await root.child(`${sport}/${season}/Line Ups/${team}/${player}/UID`).get();
  const v = snap.val();
  return typeof v === 'string' && v.length > 0 ? v : null;
}

/** Marks a referral Verified:true iff it's currently `counted` and not
 *  already Verified — idempotent (repeat stat entries for an already
 *  verified referral are a cheap early-exit) and silent (no FCM — spec §3
 *  calls this a dashboard-only integrity signal, not a notification). */
async function verifyReferralForUid(root: Reference, uid: string): Promise<void> {
  const pointerSnap = await root.child(`ReferredUsers/${uid}`).get();
  const referralId = pointerSnap.exists() ? String(pointerSnap.val()) : null;
  if (!referralId) return; // this player was never a referred user — nothing to verify

  const referralRef = root.child(`Referrals/${referralId}`);
  const referralSnap = await referralRef.get();
  const referral = referralSnap.val() as Record<string, unknown> | null;
  if (!referral) return; // dangling pointer — nothing to update

  if (referral['State'] !== 'counted' || referral['Verified'] === true) return;

  await referralRef.update({ Verified: true });
  logger.info('insider referral verified on the field', { uid, referralId });
}

async function handleStatLogWrite(
  sport: string, event: DatabaseEvent<Change<DataSnapshot>>,
): Promise<void> {
  if (!event.data.after.exists()) return; // entry removed (decrement/undo) — nothing to verify

  const entry = parseStatLogEntry(event.data.after.val());
  if (!entry) return;

  const season = String(event.params['season']);
  const root = dbRoot(event);

  const uid = await resolveLineupUid(root, sport, season, entry.team, entry.player);
  if (!uid) return; // unlinked roster row — no reliable identity to verify against

  await verifyReferralForUid(root, uid);
}

/** All Verified-watcher triggers for ONE sport (league_watch.ts
 *  makeLeagueTriggers convention: an explicit sport baked into the path via
 *  a factory call per sport, rather than a `{sport}` route wildcard). */
export function makeInsiderVerifyTrigger(sport: string) {
  return {
    onStatLogEntry: onValueWritten(
      `/${sport}/{season}/Date/{dateKey}/{gameIndex}/StatLog/{idx}`,
      (event) => handleStatLogWrite(sport, event),
    ),
  };
}

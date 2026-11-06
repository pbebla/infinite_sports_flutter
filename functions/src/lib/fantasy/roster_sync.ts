// Mid-season joiners enter the fantasy market by themselves (season setup +
// schedule plan 2026-11-05, Task 7). Pure TS behind the FantasyDb seam; the
// thin trigger lives in src/fantasy_roster.ts.
//
// The owner's rule: a player added to a team mid-season joins the market
// within minutes at the AVERAGE price of his position (even if he played an
// earlier season), with his last fantasy position if he has one, else his
// sign-up position, else ATT; nobody else's price ever changes. A player
// removed from a roster stays in the market (his history still scores).
//
// COST RULE [M4]: live scoring writes a stat increment under
// `<Sport>/<Season>/Line Ups/<team>/<player>/<Stat>` on every goal, and the
// trigger sees each one. rosterShapeChanged is a pure payload check — only a
// player key added/removed or a UID changed passes it — and maybeSyncRoster
// returns before ANY database read when it fails. Everything after the gate
// reads (Config, TestFill, Players, earlier seasons) and is paid only on a
// real roster change.
//
// This job does NOT stand down for lockOverride (a paused season still gets
// its joiners — they are only market rows); it does for a TestFill season and
// for a season with no Config (fantasy not started — season Start writes the
// whole market from the roster).

import { configFromMap } from './fantasy_config';
import {
  CarryOver, FantasyPosition, loadCarryOver, mapRegistrationPosition,
  marketEntriesOf, positionAveragePrice, readProfilePhoto, readSignupPosition,
  rosterOf, uidOf,
} from './market_entry';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, FantasyDb, fantasyRoot, isPlainMap, isTestFillSeason,
  TEST_FILL_STAND_DOWN, updateIfPresent,
} from './orchestration_db';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

// ── The gate ────────────────────────────────────────────────────────────────

/** A team node reduced to what the market cares about: {player key -> UID},
 *  an unlinked player ('', '0', missing) as ''. null = no team node. */
function shapeOf(team: unknown): Map<string, string> | null {
  if (team === null || team === undefined) return null;
  const out = new Map<string, string>();
  for (const [name, info] of childEntries(team)) {
    out.set(name, isPlainMap(info) ? (uidOf(info['UID']) ?? '') : '');
  }
  return out;
}

/** Whether a write to `<sport>/<season>/Line Ups/<team>` changed the roster's
 *  SHAPE: the set of player keys under the team, or any player's UID (trimmed;
 *  blank, '0' and missing all mean unlinked). A team node created or deleted
 *  counts as changed. Stat increments, jersey numbers and every other field
 *  are not a shape change. Pure — it reads the event payload only. */
export function rosterShapeChanged(before: unknown, after: unknown): boolean {
  const a = shapeOf(before);
  const b = shapeOf(after);
  if (a === null || b === null) return a !== b;
  if (a.size !== b.size) return true;
  for (const [name, uid] of a) {
    if (!b.has(name) || b.get(name) !== uid) return true;
  }
  return false;
}

// ── The sync ────────────────────────────────────────────────────────────────

export interface RosterSyncResult {
  /** Players written into the market by this run. */
  added: string[];
  /** Existing market players whose teamName was changed to the team. */
  teamUpdated: string[];
}

/** Brings one team's roster into `Fantasy/<sport>/<season>/Players`:
 *
 *  - a roster player already in the market — under his name, or under another
 *    name with the same `uid` field — only gets his `teamName` set when it
 *    differs (updateIfPresent: never price, position or eligibility, never
 *    recreates a row the owner deleted). The same uid under a NEW name is not
 *    added twice and is logged for the owner;
 *  - a missing player is written with writeIfAbsent (two teams' triggers racing
 *    for one name make one entry): position = his last fantasy position, else
 *    his sign-up position, else ATT; price = the CURRENT average of the
 *    eligible players of that position (positionAveragePrice, over the market
 *    as read — joiners of one run never feed each other), eligible, teamName,
 *    uid and photo when he has them.
 *
 *  All reads happen before the first write: a failed read throws and nothing
 *  is half-added (an error is not "no sign-up position"). A null team node,
 *  a missing Config or a TestFill season does nothing. */
export async function syncRosterIntoMarket(
  db: FantasyDb,
  args: {
    sport: string; season: string; team: string; teamNode: unknown;
    log?: FantasyLogger;
  },
): Promise<RosterSyncResult> {
  const { sport, season, team } = args;
  const log = args.log ?? silent;
  const result: RosterSyncResult = { added: [], teamUpdated: [] };
  const ctx = { sport, season, team };

  const roster = rosterOf({ [team]: args.teamNode });
  if (roster.length === 0) return result; // team deleted / empty: nothing to read

  const root = fantasyRoot(sport, season);
  const configNode = await db.read(`${root}/Config`);
  if (!isPlainMap(configNode)) return result; // fantasy not started: stay silent
  if (await isTestFillSeason(db, root)) {
    log.info(TEST_FILL_STAND_DOWN, { ...ctx, job: 'roster' });
    return result;
  }
  const cfg = configFromMap(configNode);

  // The market as it is now, indexed by name and by the uid it was written with.
  const playersNode = await db.read(`${root}/Players`);
  const marketRaw = new Map<string, unknown>(childEntries(playersNode));
  const nameOfUid = new Map<string, string>();
  for (const [name, raw] of marketRaw) {
    const uid = isPlainMap(raw) ? uidOf(raw['uid']) : null;
    if (uid !== null && !nameOfUid.has(uid)) nameOfUid.set(uid, name);
  }

  // Who is already in, who is missing.
  const retag = new Set<string>(); // market names whose teamName must be [team]
  const missing: Array<{ name: string; uid: string | null }> = [];
  const claimedUids = new Set<string>(); // uids of joiners already queued this run
  for (const p of roster) {
    let existing: string | undefined;
    if (marketRaw.has(p.name)) {
      existing = p.name;
    } else if (p.uid !== null && nameOfUid.has(p.uid)) {
      existing = nameOfUid.get(p.uid);
      log.warn('fantasy roster sync: uid already in the market under another name — not added', {
        ...ctx, name: p.name, existing, uid: p.uid,
      });
    }
    if (existing !== undefined) {
      const raw = marketRaw.get(existing);
      if (isPlainMap(raw) && raw['teamName'] !== team) retag.add(existing);
      continue;
    }
    if (p.uid !== null && claimedUids.has(p.uid)) {
      log.warn('fantasy roster sync: two roster names share one uid — only the first joins', {
        ...ctx, name: p.name, uid: p.uid,
      });
      continue;
    }
    if (p.uid !== null) claimedUids.add(p.uid);
    missing.push({ name: p.name, uid: p.uid });
  }

  // Everything the joiners need, read before anything is written.
  const joiners: Array<{ name: string; entry: Record<string, unknown>; from: string }> = [];
  if (missing.length > 0) {
    const carry = await loadCarryOver(db, sport, season);
    const entries = marketEntriesOf(playersNode);
    const looked = await Promise.all(missing.map(async (m) => {
      const carried: CarryOver | null = carry(m.name, m.uid);
      const [photoUrl, signup] = await Promise.all([
        m.uid === null ? null : readProfilePhoto(db, m.uid),
        carried !== null || m.uid === null ? '' : readSignupPosition(db, sport, m.uid),
      ]);
      return { m, carried, photoUrl, signup };
    }));
    for (const { m, carried, photoUrl, signup } of looked) {
      const position: FantasyPosition = carried !== null ? carried.position
        : m.uid !== null ? mapRegistrationPosition(signup) : 'ATT';
      const from = carried !== null ? 'season' : signup.trim().length > 0 ? 'signup' : 'default';
      joiners.push({
        name: m.name,
        from,
        entry: {
          position,
          priceTenths: positionAveragePrice(entries, position, cfg),
          eligible: true,
          teamName: team,
          ...(m.uid !== null ? { uid: m.uid } : {}),
          ...(photoUrl !== null ? { photoUrl } : {}),
        },
      });
    }
  }

  // Writes.
  await Promise.all(joiners.map(async (j) => {
    if (await db.writeIfAbsent(`${root}/Players/${j.name}`, j.entry)) {
      result.added.push(j.name);
      log.info('fantasy roster sync: joined the market', {
        ...ctx, name: j.name, position: j.entry['position'],
        priceTenths: j.entry['priceTenths'], positionFrom: j.from,
        uid: j.entry['uid'] ?? null,
      });
    }
  }));
  // result.added follows the roster order, whatever order the claims landed in.
  const order = new Map(joiners.map((j, i) => [j.name, i]));
  result.added.sort((a, b) => (order.get(a) ?? 0) - (order.get(b) ?? 0));

  for (const name of retag) {
    const landed = await updateIfPresent(db, `${root}/Players/${name}`, (cur) =>
      cur['teamName'] === team ? undefined : { ...cur, teamName: team });
    if (landed !== null) result.teamUpdated.push(name);
  }
  if (result.teamUpdated.length > 0) {
    log.info('fantasy roster sync: team name updated', {
      ...ctx, names: result.teamUpdated,
    });
  }
  return result;
}

/** The trigger's whole decision: the payload gate FIRST (zero reads unless the
 *  roster's shape changed), then the sync of the team's current node. Resolves
 *  to null when the gate said no. */
export async function maybeSyncRoster(
  db: FantasyDb,
  args: {
    sport: string; season: string; team: string; before: unknown; after: unknown;
    log?: FantasyLogger;
  },
): Promise<RosterSyncResult | null> {
  if (!rosterShapeChanged(args.before, args.after)) return null;
  return syncRosterIntoMarket(db, {
    sport: args.sport, season: args.season, team: args.team,
    teamNode: args.after, log: args.log,
  });
}

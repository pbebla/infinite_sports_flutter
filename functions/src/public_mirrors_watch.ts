// DB security lockdown Phase A (Task A2): triggers that maintain the public
// mirrors so the fan app keeps reading public subsets of otherwise-private
// nodes once rules flip to default-deny. Orchestration only — every
// projection decision is pure in src/lib/public_mirrors.ts.
//
//   /Users/{uid}                                -> /PublicProfiles/{uid}
//   /Registrations/{regId}/Config               -> /RegistrationsPublic/{regId}
//   /Registrations/{regId}/Submissions/{uid}    ->
//       /Registrations/{regId}/Teams/{teamId}/Members/{uid}
//
// A null projection deletes the mirror entry; a submission whose TeamId
// changed (or that was deleted) also removes its OLD team's member entry.
//
// Ordering: Cloud Functions do not run triggers in write order, so an older
// run can finish after a newer one. Every trigger therefore RE-READS the
// source node (once('value')) and projects from that fresh value - never from
// the event's own (possibly stale) snapshot - so whichever run finishes last
// writes the current state. Logs carry a 6-character uid prefix only.
//
// Spec: docs/superpowers/specs/2026-10-27-db-security-lockdown-design.md §4
// (the mirror pattern). Plan:
// docs/superpowers/plans/2026-10-27-db-lockdown-implementation.md Task A2.

import * as logger from 'firebase-functions/logger';
import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';
import {
  publicProfileProjection, registrationConfigProjection, teamMemberEntry,
} from './lib/public_mirrors';

/** Same-instance root (matters in the emulator) — index.ts/insiders_watch.ts
 *  dbRoot parity. */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

/** Logs never carry a whole uid (merge_notice_watch.ts parity). */
const uidPrefix = (uid: string): string => uid.slice(0, 6);

/** The current value at [path] (fresh read, not the event payload). */
async function freshValue(root: Reference, path: string): Promise<unknown> {
  return (await root.child(path).once('value')).val();
}

/** PublicProfiles/{uid} from the CURRENT Users/{uid}: a deleted / malformed /
 *  nothing-public-left profile removes the mirror. */
export async function mirrorPublicProfile(root: Reference, uid: string): Promise<void> {
  const mirrorRef = root.child(`PublicProfiles/${uid}`);
  const projection = publicProfileProjection(await freshValue(root, `Users/${uid}`));
  if (projection === null) {
    await mirrorRef.remove();
    logger.info('public profile mirror removed', { uid: uidPrefix(uid) });
    return;
  }
  await mirrorRef.set(projection);
}

/** RegistrationsPublic/{regId} from the CURRENT Registrations/{regId}/Config:
 *  a deleted / malformed Config removes the mirror. */
export async function mirrorRegistrationConfig(root: Reference, regId: string): Promise<void> {
  const mirrorRef = root.child(`RegistrationsPublic/${regId}`);
  const projection = registrationConfigProjection(
    await freshValue(root, `Registrations/${regId}/Config`),
  );
  if (projection === null) {
    await mirrorRef.remove();
    logger.info('registration config mirror removed', { regId });
    return;
  }
  await mirrorRef.set(projection);
}

/** Team member entry from the CURRENT submission. [beforeVal] (the event's
 *  before-state) only says which OLD team entry this write may have left
 *  behind: it is removed when the current submission is gone or on another
 *  team. The entry written is always the current one. */
export async function mirrorSubmission(
  root: Reference, regId: string, uid: string, beforeVal: unknown,
): Promise<void> {
  const before = teamMemberEntry(beforeVal);
  const current = teamMemberEntry(
    await freshValue(root, `Registrations/${regId}/Submissions/${uid}`),
  );
  if (!before && !current) return; // individual path / junk — no mirror work
  if (before && (!current || current.teamId !== before.teamId)) {
    await root
      .child(`Registrations/${regId}/Teams/${before.teamId}/Members/${uid}`)
      .remove();
    logger.info('team member mirror removed', {
      regId, uid: uidPrefix(uid), teamId: before.teamId,
    });
  }
  if (current) {
    await root
      .child(`Registrations/${regId}/Teams/${current.teamId}/Members/${uid}`)
      .set(current.value);
  }
}

/** Mirrors the public subset of a user profile to PublicProfiles/{uid} on
 *  every Users/{uid} write (projected from a fresh read). Logs carry a uid
 *  prefix only — never profile contents. */
export const onUserWritten = onValueWritten(
  '/Users/{uid}',
  async (event) => {
    await mirrorPublicProfile(dbRoot(event), String(event.params['uid']));
  },
);

/** Mirrors Registrations/{regId}/Config verbatim to
 *  RegistrationsPublic/{regId} (Config is public content: fees, dates,
 *  paths), from a fresh read. */
export const onRegistrationConfigWritten = onValueWritten(
  '/Registrations/{regId}/Config',
  async (event) => {
    await mirrorRegistrationConfig(dbRoot(event), String(event.params['regId']));
  },
);

/** Maintains Registrations/{regId}/Teams/{teamId}/Members/{uid} from each
 *  submission write so captains see their roster without reading the private
 *  Submissions bucket. Individual-path submissions (no TeamId) contribute
 *  nothing and clean up nothing they never wrote. */
export const onSubmissionWritten = onValueWritten(
  '/Registrations/{regId}/Submissions/{uid}',
  async (event) => {
    await mirrorSubmission(
      dbRoot(event), String(event.params['regId']), String(event.params['uid']),
      event.data.before.val(),
    );
  },
);

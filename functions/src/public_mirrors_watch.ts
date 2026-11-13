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

/** Mirrors the public subset of a user profile to PublicProfiles/{uid} on
 *  every Users/{uid} write. A deleted/malformed/nothing-public-left profile
 *  removes the mirror. Logs carry the uid only — never profile contents. */
export const onUserWritten = onValueWritten(
  '/Users/{uid}',
  async (event) => {
    const uid = String(event.params['uid']);
    const root = dbRoot(event);
    const mirrorRef = root.child(`PublicProfiles/${uid}`);
    const projection = publicProfileProjection(event.data.after.val());
    if (projection === null) {
      await mirrorRef.remove();
      logger.info('public profile mirror removed', { uid });
      return;
    }
    await mirrorRef.set(projection);
  },
);

/** Mirrors Registrations/{regId}/Config verbatim to
 *  RegistrationsPublic/{regId} (Config is public content: fees, dates,
 *  paths). A deleted/malformed Config removes the mirror. */
export const onRegistrationConfigWritten = onValueWritten(
  '/Registrations/{regId}/Config',
  async (event) => {
    const regId = String(event.params['regId']);
    const root = dbRoot(event);
    const mirrorRef = root.child(`RegistrationsPublic/${regId}`);
    const projection = registrationConfigProjection(event.data.after.val());
    if (projection === null) {
      await mirrorRef.remove();
      logger.info('registration config mirror removed', { regId });
      return;
    }
    await mirrorRef.set(projection);
  },
);

/** Maintains Registrations/{regId}/Teams/{teamId}/Members/{uid} from each
 *  submission write so captains see their roster without reading the private
 *  Submissions bucket. Writes the {DisplayName, Paid} entry for the
 *  submission's current team; removes the OLD team's entry when the TeamId
 *  changed or the submission was deleted. Individual-path submissions (no
 *  TeamId) contribute nothing and clean up nothing they never wrote. */
export const onSubmissionWritten = onValueWritten(
  '/Registrations/{regId}/Submissions/{uid}',
  async (event) => {
    const regId = String(event.params['regId']);
    const uid = String(event.params['uid']);
    const before = teamMemberEntry(event.data.before.val());
    const after = teamMemberEntry(event.data.after.val());
    if (!before && !after) return; // individual path / junk — no mirror work

    const root = dbRoot(event);
    if (before && (!after || after.teamId !== before.teamId)) {
      await root
        .child(`Registrations/${regId}/Teams/${before.teamId}/Members/${uid}`)
        .remove();
      logger.info('team member mirror removed', {
        regId, uid, teamId: before.teamId,
      });
    }
    if (after) {
      await root
        .child(`Registrations/${regId}/Teams/${after.teamId}/Members/${uid}`)
        .set(after.value);
    }
  },
);

// The public-mirror triggers re-read the source node before projecting, so a
// run that finishes last can never overwrite a newer mirror with its own
// (older) event payload: Cloud Functions do not order trigger runs.

import { describe, expect, it, vi } from 'vitest';

const logged = vi.hoisted(() => [] as string[]);
vi.mock('firebase-functions/logger', () => {
  const line = (kind: string) => (m: string, c?: unknown) => {
    logged.push(`${kind} ${m} ${JSON.stringify(c ?? {})}`);
  };
  return { info: line('info'), warn: line('warn'), error: line('error'), debug: line('debug') };
});

import {
  mirrorPublicProfile, mirrorRegistrationConfig, mirrorSubmission,
  onRegistrationConfigWritten, onSubmissionWritten, onUserWritten,
} from './public_mirrors_watch';

type Tree = Record<string, any>;
const UID = 'uid_alice_12345';

/** Admin-Reference fake over [tree]: child(), once('value'), set(), remove(). */
function fakeRef(tree: Tree, path: string): any {
  const parts = path.split('/').filter((p) => p.length > 0);
  const read = (): unknown => {
    let node: any = tree;
    for (const p of parts) {
      if (node === null || node === undefined || typeof node !== 'object') return null;
      node = node[p];
    }
    return node === undefined ? null : JSON.parse(JSON.stringify(node));
  };
  const write = (value: unknown): void => {
    let node: any = tree;
    for (const p of parts.slice(0, -1)) {
      if (node[p] === null || node[p] === undefined || typeof node[p] !== 'object') node[p] = {};
      node = node[p];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) delete node[last]; else node[last] = value;
  };
  const ref: any = {
    child: (sub: string) => fakeRef(tree, `${path}/${sub}`),
    once: async (kind: string) => {
      if (kind !== 'value') throw new Error(`unexpected once(${kind})`);
      return { val: () => read() };
    },
    get: async () => { throw new Error('get() is not used by the mirror triggers'); },
    set: async (v: unknown) => write(v),
    remove: async () => write(null),
  };
  ref.root = path === '' ? ref : fakeRef(tree, '');
  return ref;
}

/** A v2 database event whose payload is [before] -> [after] (stale or not). */
function event(tree: Tree, params: Record<string, string>, before: unknown, after: unknown): any {
  const root = fakeRef(tree, '');
  return {
    params,
    data: {
      before: { val: () => before, ref: { root } },
      after: { val: () => after, ref: { root } },
    },
  };
}

describe('onUserWritten (public profile mirror)', () => {
  it('projects from the fresh Users/<uid> value, not the older event payload', async () => {
    const tree: Tree = { Users: { [UID]: { 'First Name': 'Newer', Email: 'a***@example.com' } } };
    await (onUserWritten as any).run(event(tree, { uid: UID }, null, { 'First Name': 'Older' }));
    expect(tree.PublicProfiles[UID]).toEqual({ 'First Name': 'Newer' });
  });

  it('a fresh null removes the mirror even when the stale payload still had a profile', async () => {
    const tree: Tree = { PublicProfiles: { [UID]: { 'First Name': 'Gone' } } };
    await (onUserWritten as any).run(event(tree, { uid: UID }, null, { 'First Name': 'Older' }));
    expect(tree.PublicProfiles?.[UID]).toBeUndefined();
  });

  it('mirrorPublicProfile logs a short uid prefix only', async () => {
    logged.length = 0;
    await mirrorPublicProfile(fakeRef({}, ''), UID);
    expect(logged.join('\n')).not.toContain(UID);
    expect(logged.join('\n')).toContain(UID.slice(0, 6));
  });
});

describe('onRegistrationConfigWritten (public config mirror)', () => {
  it('projects from the fresh Config, not the older event payload', async () => {
    const tree: Tree = { Registrations: { r1: { Config: { Fee: 60 } } } };
    await (onRegistrationConfigWritten as any).run(event(tree, { regId: 'r1' }, null, { Fee: 50 }));
    expect(tree.RegistrationsPublic.r1).toEqual({ Fee: 60 });
  });

  it('a fresh null removes the mirror', async () => {
    const tree: Tree = { RegistrationsPublic: { r1: { Fee: 50 } } };
    await mirrorRegistrationConfig(fakeRef(tree, ''), 'r1');
    expect(tree.RegistrationsPublic?.r1).toBeUndefined();
  });
});

describe('onSubmissionWritten (team member mirror)', () => {
  const sub = (teamId: string, name = 'Alice A.') => ({ TeamId: teamId, DisplayName: name, Paid: false });

  it('a stale run (t1 -> t2) that finishes after the newer one (t2 -> t3) leaves only t3', async () => {
    const tree: Tree = {
      Registrations: { r1: {
        Submissions: { [UID]: sub('t3') },
        Teams: { t3: { Members: { [UID]: { DisplayName: 'Alice A.', Paid: false } } } },
      } },
    };
    await (onSubmissionWritten as any).run(
      event(tree, { regId: 'r1', uid: UID }, sub('t1'), sub('t2')),
    );
    const teams = tree.Registrations.r1.Teams;
    expect(teams.t2?.Members?.[UID]).toBeUndefined();
    expect(teams.t1?.Members?.[UID]).toBeUndefined();
    expect(teams.t3.Members[UID]).toBeDefined();
  });

  it('a team change removes the old entry and writes the new one', async () => {
    const tree: Tree = {
      Registrations: { r1: {
        Submissions: { [UID]: sub('t2') },
        Teams: { t1: { Members: { [UID]: { DisplayName: 'Alice A.', Paid: false } } } },
      } },
    };
    await mirrorSubmission(fakeRef(tree, ''), 'r1', UID, sub('t1'));
    const teams = tree.Registrations.r1.Teams;
    expect(teams.t1?.Members?.[UID]).toBeUndefined();
    expect(teams.t2.Members[UID]).toBeDefined();
  });

  it('a deleted submission removes its old entry; logs carry no full uid', async () => {
    logged.length = 0;
    const tree: Tree = {
      Registrations: { r1: { Teams: { t1: { Members: { [UID]: { DisplayName: 'A', Paid: true } } } } } },
    };
    await mirrorSubmission(fakeRef(tree, ''), 'r1', UID, sub('t1'));
    expect(tree.Registrations.r1.Teams.t1?.Members?.[UID]).toBeUndefined();
    expect(logged.join('\n')).not.toContain(UID);
  });
});

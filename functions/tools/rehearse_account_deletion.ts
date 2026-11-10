// Account deletion rehearsal against the Realtime Database EMULATOR (plan
// 2026-11-09-account-deletion, Task 2, step 5).
//
// Runs the REAL readAccountDeletionSnapshot -> planAccountDeletion ->
// applyAccountDeletion through the production rtdbFantasyDb adapter (so the
// real keys-only `?shallow=true` read is exercised too) with a fake
// ObjectStore, over a compact seed, then asserts the tree: deleted nodes
// absent, ledgers/Managers anonymised, the registration scrub, the stamp,
// bystanders untouched, and that a rerun plans only the stamp. Fix wave:
// an old account combined into alice (C1) is deleted with her and stamped
// 'merged'; her sign-up comment and unpaid sign-up go (I3, M11) while a
// foreign comment and the paid record stay; an unpaid registration loses
// its name.
//
// The Functions emulator has no Auth emulator here, so the callables
// themselves are covered by src/account_deletion.test.ts instead.
//
// RUN (from functions/):
//   npm run rehearse:deletion
// which is: tsc -p tools/tsconfig.json, then
//   npx firebase-tools emulators:exec --only database --project demo-deletion
//     "node tools/rehearsal_out/build/tools/rehearse_account_deletion.js"
// SAFETY: refuses to run unless FIREBASE_DATABASE_EMULATOR_HOST is set.

import * as assert from 'assert';
import * as admin from 'firebase-admin';
import { rtdbFantasyDb } from '../src/fantasy_adapter';
import {
  applyAccountDeletion, DeletionPlan, ObjectStore, planAccountDeletion,
  readAccountDeletionSnapshot, settlePendingAuth,
} from '../src/lib/account_deletion';

const A = 'uid_alice';
const B = 'uid_bob';
const C = 'uid_cara';
const O = 'uid_alice_old';
const NOW = Date.UTC(2026, 10, 9, 18);
const STAMP = { nowMs: NOW, provider: 'password' };
const F = 'Fantasy/Futsal/15';

function seed(): Record<string, unknown> {
  const squad = { captainId: 'x', picks: { 0: { playerId: 'x', position: 'ATT' } } };
  return {
    Users: {
      [A]: {
        'First Name': 'Alice', Email: 'a***@example.com', Token: 'tok', TournamentsPlayed: { t_spring: true },
        MergedFrom: { [O]: true },
      },
      [B]: { 'First Name': 'Bob' },
      [O]: { 'First Name': 'Alice', Token: 'tok_old', MergedInto: A, MergedAt: 7, MergedHint: 'a***@example.com' },
    },
    PublicProfiles: { [A]: { 'First Name': 'Alice' }, [B]: { 'First Name': 'Bob' }, [O]: { 'First Name': 'Alice' } },
    Fantasy: { Futsal: { '15': {
      Config: { budgetTenths: 1000 },
      Managers: { [A]: { TeamName: 'Alice FC', DisplayName: 'Alice Able', NamedAt: 5 }, [B]: { TeamName: 'Bob FC' } },
      Squads: { [A]: squad, [B]: squad },
      Badges: { [A]: { first_win: { At: 1 } }, [B]: { first_win: { At: 1 } } },
      History: { 1: { [A]: { TotalTenths: 40, TeamName: 'Alice FC' }, [B]: { TotalTenths: 90 } } },
      Leaderboards: { Overall: {
        [B]: { points: 90, rank: 1 }, [C]: { points: 70, rank: 2 },
        [A]: { points: 40, rank: 3, Name: 'Alice Able', PhotoUrl: 'https://img.example/a.jpg' },
      } },
      Access: { [A]: { Status: 'active', AmountCents: 1000, StripePaymentIntent: 'pi_1', Reason: 'note about alice' } },
      MiniLeagues: {
        ml_owned: { Name: 'Owned', Owner: A, Members: { [A]: true, [C]: true } },
        ml_solo: { Name: 'Solo', Owner: A, Members: { [A]: true } },
        ml_other: { Name: 'Other', Owner: B, Members: { [B]: true } },
      },
      Players: { 'Alice A': { position: 'ATT', uid: A, photoUrl: 'https://img.example/a.jpg' }, 'Bob B': { position: 'DEF', uid: B } },
    } } },
    Futsal: { '15': { 'Line Ups': { 'Team A': {
      'Alice A': { UID: A, Goals: 3, PhotoUrl: 'https://img.example/a.jpg' }, 'Bob B': { UID: B, Goals: 1 },
    } } } },
    Registrations: {
      'Futsal-16': { Submissions: {
        [A]: { Paid: true, PaidVia: 'card', PaidAmount: 80, DisplayName: 'Alice Able', SubmittedAt: 1234, AdjustReason: 'friend of owner', Phone: '555-0100', Answers: { Shirt: 'M' } },
        [B]: { Paid: false, Phone: '555-0101' },
      } },
      'Futsal-17': { Submissions: { [A]: { Paid: false, AmountCents: 8000, DisplayName: 'Alice Able', Phone: '555-0100' } } },
    },
    'Sign Ups': { Futsal: {
      '16': { Paid: { [A]: 'Alice Able' }, Comments: { 'Alice Able': `${A}:bring a ball`, Bob: `${B}:see you` } },
      '17': { NotPaid: { [A]: 'Alice Able', [B]: 'Bob' }, Comments: { 'Alice Old': `${O}:old comment` } },
    } },
    Support: { UserTickets: { [A]: { 7: true } }, Tickets: { 7: { Uid: A, Message: 'hi' }, 8: { Uid: B, Message: 'yo' } } },
    MergeNotices: { [A]: { Seen: false }, [O]: { Status: 'sent' } },
    Tournaments: { t_spring: { Rosters: { 'Team T': { 'Alice A': { uid: A, photoUrl: 'https://img.example/a.jpg' } } } } },
  };
}

class FakeObjectStore implements ObjectStore {
  deleted: string[] = [];
  async deleteObject(path: string): Promise<void> { this.deleted.push(path); }
}

async function main(): Promise<void> {
  if (!process.env.FIREBASE_DATABASE_EMULATOR_HOST) {
    throw new Error('refusing to run without FIREBASE_DATABASE_EMULATOR_HOST (use npm run rehearse:deletion)');
  }
  admin.initializeApp({
    projectId: 'demo-deletion', databaseURL: 'https://demo-deletion-default-rtdb.firebaseio.com',
  });
  const root = admin.database().ref();
  await root.set(seed());
  const db = rtdbFantasyDb(root);
  const get = async (p: string): Promise<any> => (await root.child(p).get()).val();

  const bystanders = JSON.stringify([
    await get(`Users/${B}`), await get(`${F}/Squads/${B}`), await get(`${F}/Leaderboards/Overall/${B}`),
    await get('Support/Tickets/8'), await get(`Registrations/Futsal-16/Submissions/${B}`),
    await get(`${F}/MiniLeagues/ml_other`), await get(`${F}/Players/Bob B`),
    await get('Sign Ups/Futsal/16/Comments/Bob'), await get(`Sign Ups/Futsal/17/NotPaid/${B}`),
  ]);

  const snapshot = await readAccountDeletionSnapshot(db, A);
  const plan = planAccountDeletion(snapshot, A, STAMP) as DeletionPlan;
  assert.strictEqual(plan.refused, undefined);
  assert.deepStrictEqual(plan.authUidsToDelete, [A, O]);
  const store = new FakeObjectStore();
  const summary = await applyAccountDeletion(db, store, plan);
  assert.deepStrictEqual(summary.errors, []);
  assert.strictEqual(summary.stamped, true);

  for (const gone of [
    `Users/${A}`, `PublicProfiles/${A}`, `${F}/Squads/${A}`, `${F}/Badges/${A}`,
    'Support/Tickets/7', `Support/UserTickets/${A}`, `MergeNotices/${A}`,
    `${F}/MiniLeagues/ml_solo`, `${F}/MiniLeagues/ml_owned/Members/${A}`,
    `${F}/Players/Alice A/uid`, `${F}/Players/Alice A/photoUrl`,
    'Futsal/15/Line Ups/Team A/Alice A/UID', 'Futsal/15/Line Ups/Team A/Alice A/PhotoUrl',
    'Tournaments/t_spring/Rosters/Team T/Alice A/uid',
    `Users/${O}`, `PublicProfiles/${O}`, `MergeNotices/${O}`, 'Sign Ups/Futsal/17/Comments',
    'Sign Ups/Futsal/16/Comments/Alice Able', `Sign Ups/Futsal/17/NotPaid/${A}`,
  ]) assert.strictEqual(await get(gone), null, `${gone} should be gone`);

  assert.deepStrictEqual(await get(`${F}/Managers/${A}`), { TeamName: 'Deleted manager', Deleted: true, NamedAt: 5 });
  assert.deepStrictEqual(await get(`${F}/Leaderboards/Overall/${A}`), { points: 40, rank: 3, Name: 'Deleted manager' });
  assert.deepStrictEqual(await get(`${F}/History/1/${A}`), { TotalTenths: 40, TeamName: 'Deleted manager' });
  assert.strictEqual(await get(`${F}/Leaderboards/Overall/${C}/points`), 70);
  assert.strictEqual(await get(`${F}/MiniLeagues/ml_owned/Owner`), C);
  assert.strictEqual(summary.handoffs, 1);
  assert.deepStrictEqual(await get(`${F}/Access/${A}`), {
    Status: 'active', AmountCents: 1000, StripePaymentIntent: 'pi_1', Deleted: true,
  });
  assert.deepStrictEqual(await get(`Registrations/Futsal-16/Submissions/${A}`), {
    Paid: true, PaidVia: 'card', PaidAmount: 80, DisplayName: 'Alice Able', SubmittedAt: 1234, Deleted: true,
  });
  assert.deepStrictEqual(await get(`Registrations/Futsal-17/Submissions/${A}`), {
    Paid: false, AmountCents: 8000, DisplayName: 'Deleted player', Deleted: true,
  });
  assert.strictEqual(await get(`Sign Ups/Futsal/16/Paid/${A}`), 'Alice Able');
  assert.deepStrictEqual(await get(`DeletedAccounts/${O}`), { At: NOW, Provider: 'merged', MergedInto: A });
  assert.deepStrictEqual(await get(`DeletedAccounts/${A}`), { At: NOW, Provider: 'password', PendingAuth: [O] });
  assert.ok(store.deleted.includes(`Users/${O}/profileimage.jpg`));
  assert.strictEqual(await get(`Futsal/15/Line Ups/Team A/Alice A/Goals`), 3);
  assert.ok(store.deleted.includes(`Users/${A}/profileimage.jpg`));
  assert.ok(store.deleted.includes('support/7/img_0.jpg'));
  assert.strictEqual(JSON.stringify([
    await get(`Users/${B}`), await get(`${F}/Squads/${B}`), await get(`${F}/Leaderboards/Overall/${B}`),
    await get('Support/Tickets/8'), await get(`Registrations/Futsal-16/Submissions/${B}`),
    await get(`${F}/MiniLeagues/ml_other`), await get(`${F}/Players/Bob B`),
    await get('Sign Ups/Futsal/16/Comments/Bob'), await get(`Sign Ups/Futsal/17/NotPaid/${B}`),
  ]), bystanders, 'bystanders must be untouched');

  // A rerun plans only the stamp.
  const again = planAccountDeletion(await readAccountDeletionSnapshot(db, A), A, STAMP) as DeletionPlan;
  assert.deepStrictEqual(again.steps.map((s) => s.path), [`DeletedAccounts/${A}`]);
  // ...and still lists the old Auth user until the callable settles it.
  assert.deepStrictEqual(again.authUidsToDelete, [A, O]);
  await settlePendingAuth(db, A, []);
  assert.deepStrictEqual(await get(`DeletedAccounts/${A}`), { At: NOW, Provider: 'password' });

  console.log(`rehearse:deletion OK - deleted=${summary.deleted} anonymised=${summary.anonymised} ` +
    `handoffs=${summary.handoffs} storageDeleted=${summary.storageDeleted} oldAccounts=${snapshot.merged.length} errors=0; ` +
    'tree, scrub, stamp, merged old account, sign-ups, bystanders and rerun asserted');
}

main().then(() => process.exit(0), (err) => { console.error('rehearse:deletion FAILED', err); process.exit(1); });

// Account deletion rehearsal against the Realtime Database EMULATOR (plan
// 2026-11-09-account-deletion, Task 2, step 5).
//
// Runs the REAL readAccountDeletionSnapshot -> planAccountDeletion ->
// applyAccountDeletion through the production rtdbFantasyDb adapter (so the
// real keys-only `?shallow=true` read is exercised too) with a fake
// ObjectStore, over a compact seed, then asserts the tree: deleted nodes
// absent, ledgers/Managers anonymised, the registration scrub, the stamp,
// bystanders untouched, and that a rerun plans only the stamp.
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
  readAccountDeletionSnapshot,
} from '../src/lib/account_deletion';

const A = 'uid_alice';
const B = 'uid_bob';
const C = 'uid_cara';
const NOW = Date.UTC(2026, 10, 9, 18);
const STAMP = { nowMs: NOW, provider: 'password' };
const F = 'Fantasy/Futsal/15';

function seed(): Record<string, unknown> {
  const squad = { captainId: 'x', picks: { 0: { playerId: 'x', position: 'ATT' } } };
  return {
    Users: {
      [A]: { 'First Name': 'Alice', Email: 'a***@example.com', Token: 'tok', TournamentsPlayed: { t_spring: true } },
      [B]: { 'First Name': 'Bob' },
    },
    PublicProfiles: { [A]: { 'First Name': 'Alice' }, [B]: { 'First Name': 'Bob' } },
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
    Registrations: { 'Futsal-16': { Submissions: {
      [A]: { Paid: true, PaidVia: 'card', PaidAmount: 80, DisplayName: 'Alice Able', SubmittedAt: 1234, AdjustReason: 'friend of owner', Phone: '555-0100', Answers: { Shirt: 'M' } },
      [B]: { Paid: false, Phone: '555-0101' },
    } } },
    'Sign Ups': { Futsal: { '16': { Paid: { [A]: 'Alice Able' } } } },
    Support: { UserTickets: { [A]: { 7: true } }, Tickets: { 7: { Uid: A, Message: 'hi' }, 8: { Uid: B, Message: 'yo' } } },
    MergeNotices: { [A]: { Seen: false } },
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
  ]);

  const snapshot = await readAccountDeletionSnapshot(db, A);
  const plan = planAccountDeletion(snapshot, A, STAMP) as DeletionPlan;
  assert.strictEqual(plan.refused, undefined);
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
  assert.strictEqual(await get(`Sign Ups/Futsal/16/Paid/${A}`), 'Alice Able');
  assert.deepStrictEqual(await get(`DeletedAccounts/${A}`), { At: NOW, Provider: 'password' });
  assert.strictEqual(await get(`Futsal/15/Line Ups/Team A/Alice A/Goals`), 3);
  assert.ok(store.deleted.includes(`Users/${A}/profileimage.jpg`));
  assert.ok(store.deleted.includes('support/7/img_0.jpg'));
  assert.strictEqual(JSON.stringify([
    await get(`Users/${B}`), await get(`${F}/Squads/${B}`), await get(`${F}/Leaderboards/Overall/${B}`),
    await get('Support/Tickets/8'), await get(`Registrations/Futsal-16/Submissions/${B}`),
    await get(`${F}/MiniLeagues/ml_other`), await get(`${F}/Players/Bob B`),
  ]), bystanders, 'bystanders must be untouched');

  // A rerun plans only the stamp.
  const again = planAccountDeletion(await readAccountDeletionSnapshot(db, A), A, STAMP) as DeletionPlan;
  assert.deepStrictEqual(again.steps.map((s) => s.path), [`DeletedAccounts/${A}`]);

  console.log(`rehearse:deletion OK - deleted=${summary.deleted} anonymised=${summary.anonymised} ` +
    `handoffs=${summary.handoffs} storageDeleted=${summary.storageDeleted} errors=0; ` +
    'tree, scrub, stamp, bystanders and rerun asserted');
}

main().then(() => process.exit(0), (err) => { console.error('rehearse:deletion FAILED', err); process.exit(1); });

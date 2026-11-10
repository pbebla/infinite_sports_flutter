// Account deletion planner + applier (plan 2026-11-09-account-deletion,
// Task 1; design D1, D2, D5; Review Focus 3-5). Every test drives the real
// read -> plan -> apply chain over the in-memory FakeDb and asserts the tree
// that is left behind, not the calls that were made.

import { describe, expect, it } from 'vitest';
import {
  AccountDeletionPlanning, anonymiseLedgerRow, applyAccountDeletion,
  DELETED_MANAGER, DeletionPlan, ObjectStore, planAccountDeletion,
  readAccountDeletionSnapshot,
} from './account_deletion';
import { FakeDb } from './fantasy/test_support';

const ALICE = 'uid_alice';
const NOW = Date.UTC(2026, 10, 9, 18);
const STAMP = { nowMs: NOW, provider: 'password' };

/** Records every deleteObject call; [failing] paths throw. */
class FakeObjectStore implements ObjectStore {
  deleted: string[] = [];
  failing = new Set<string>();
  async deleteObject(path: string): Promise<void> {
    if (this.failing.has(path)) throw new Error(`storage down for ${path}`);
    this.deleted.push(path);
  }
}

/** A db that "dies" after [okWrites] writes: every later write throws. */
class DyingDb extends FakeDb {
  constructor(seed: Record<string, any>, private okWrites: number) { super(seed); }
  override async write(path: string, value: unknown): Promise<void> {
    if (this.okWrites <= 0) throw new Error(`process died before ${path}`);
    this.okWrites--;
    await super.write(path, value);
  }
}

/** One fixture user (alice) present everywhere D1 names, next to bob, cara
 *  and dan whose data must never change. */
function world(): Record<string, any> {
  const squad = (cap: string) => ({ picks: [{ playerId: cap, position: 'ATT' }], captainId: cap, viceId: cap });
  return {
    Users: {
      [ALICE]: {
        'First Name': 'Alice', 'Last Name': 'Able', Email: 'a***@example.com',
        'Phone Number': '555-0100', DOB: '01012000', Token: 'tok_alice',
        ProfileUrl: 'https://img.example/alice.jpg',
        Played: { Futsal: { 'Season 15': 'Team A' } },
        TournamentsPlayed: { t_spring: true },
      },
      uid_bob: { 'First Name': 'Bob', Email: 'b***@example.com' },
    },
    PublicProfiles: {
      [ALICE]: { 'First Name': 'Alice', 'Last Name': 'Able' },
      uid_bob: { 'First Name': 'Bob' },
    },
    Fantasy: {
      BadgeCatalog: { first_win: { Name: 'First win' } },
      Futsal: {
        '15': {
          Config: { budgetTenths: 1000 },
          Managers: { [ALICE]: { TeamName: 'Alice FC' }, uid_bob: { TeamName: 'Bob FC' } },
          Squads: { [ALICE]: squad('Alice A'), uid_bob: squad('Bob B') },
          TransferState: { [ALICE]: { SavedGw: 2 }, uid_bob: { SavedGw: 2 } },
          Baselines: { [ALICE]: { ForGw: 2, RealizedTenths: 0 } },
          SquadAlerts: { [ALICE]: { Gw: 2, Kind: 'preview' } },
          AccessClaims: { [ALICE]: { k1: { Method: 'venmo', AmountDollars: 10, Note: 'from alice' } } },
          Watchlists: { [ALICE]: { 'Bob B': true } },
          Badges: { [ALICE]: { first_win: { At: 1 } }, uid_bob: { first_win: { At: 1 } } },
          BadgePushClaims: { [ALICE]: { first_win: { At: 1, Sent: true } } },
          Access: {
            [ALICE]: {
              Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 111, By: 'stripe',
              StripePaymentIntent: 'pi_test_1', Reason: 'note naming alice',
              Notified: { activated: true },
            },
            uid_bob: { Status: 'active', Via: 'granted', AmountCents: 0, PaidAt: 1, By: 'uid_admin' },
          },
          History: {
            '1': { [ALICE]: { ...squad('Alice A'), TotalTenths: 40 }, uid_bob: { ...squad('Bob B'), TotalTenths: 90 } },
          },
          PublishedPicks: { '1': { [ALICE]: squad('Alice A'), uid_bob: squad('Bob B') } },
          Leaderboards: {
            Overall: {
              uid_bob: { points: 90, rank: 1 },
              uid_cara: { points: 70, rank: 2 },
              [ALICE]: { points: 40, rank: 3, movement: -1 },
              uid_dan: { points: 10, rank: 4 },
            },
            Gameweek: { '1': { [ALICE]: { points: 4, rank: 3 }, uid_bob: { points: 9, rank: 1 } } },
            RankHistory: { [ALICE]: { '1': 3 }, uid_bob: { '1': 1 } },
          },
          Live: {
            Meta: { Gw: 2, State: 'live' },
            Squads: { [ALICE]: { NetTenths: 20 }, uid_bob: { NetTenths: 30 } },
            Board: { [ALICE]: { O: 42, R: 3 }, uid_bob: { O: 93, R: 1 } },
          },
          PreviewPushed: { '2': { [ALICE]: { At: 5 }, uid_bob: { At: 5 } } },
          TransferCosts: { '1': { [ALICE]: 4 } },
          LiveBase: { '2': { Gw: 2, Managers: { [ALICE]: { O: 40 } } } },
          MiniLeagues: {
            ml_owned: { Name: 'Owned', Code: 'OWN123', Owner: ALICE, CreatedAt: 1, Members: { [ALICE]: true, uid_cara: true, uid_bob: true } },
            ml_joined: { Name: 'Joined', Code: 'JOI123', Owner: 'uid_bob', CreatedAt: 2, Members: { uid_bob: true, [ALICE]: true } },
            ml_solo: { Name: 'Solo', Code: 'SOL123', Owner: ALICE, CreatedAt: 3, Members: { [ALICE]: true } },
            ml_other: { Name: 'Other', Code: 'OTH123', Owner: 'uid_bob', CreatedAt: 4, Members: { uid_bob: true } },
          },
          Players: {
            'Alice A': { position: 'ATT', priceTenths: 60, eligible: true, teamName: 'Team A', uid: ALICE, photoUrl: 'https://img.example/alice.jpg' },
            'Bob B': { position: 'DEF', priceTenths: 50, eligible: true, teamName: 'Team B', uid: 'uid_bob' },
          },
        },
        '16': {
          Config: { budgetTenths: 1000 },
          Managers: { [ALICE]: { TeamName: 'Alice FC' } },
          Squads: { [ALICE]: squad('Alice A') },
          Leaderboards: {
            // A legacy row carrying names + a photo: ruling 3's anonymiser.
            Overall: {
              [ALICE]: { points: 12, rank: 1, Name: 'Alice Able', TeamName: 'Alice FC', PhotoUrl: 'https://img.example/alice.jpg', Uid: ALICE },
              uid_bob: { points: 8, rank: 2, Name: 'Bob' },
            },
          },
        },
      },
    },
    Futsal: {
      '15': {
        'Line Ups': {
          'Team A': { 'Alice A': { UID: ALICE, Goals: 3, number: '7' }, 'Bob B': { UID: 'uid_bob', Goals: 1 } },
        },
      },
      'Futsal Season': 15,
    },
    'AFC San Jose': { Seasons: { '2': { Roster: { 'Alice A': { UID: ALICE, Goals: 1 }, 'Dan D': { UID: 'uid_dan' } } } } },
    Tournaments: {
      t_spring: { Rosters: { team1: { 'Alice A': { uid: ALICE, Goals: 2 }, 'Cara C': { uid: 'uid_cara' } } } },
    },
    Registrations: {
      'Futsal-16': {
        Submissions: {
          [ALICE]: {
            Paid: true, PaidVia: 'card', PaidAmount: 80, PaidAt: 222, StripePaymentIntent: 'pi_test_2',
            AmountCents: 8000, Method: 'card', Waived: false,
            DisplayName: 'Alice Able', Status: 'approved', TeamId: 'team_1', TeamName: 'Team A',
            Answers: { 'Emergency contact': 'Mom 555-0101', Shirt: 'M' },
            Email: 'a***@example.com', Phone: '555-0100', AdjustReason: 'friend of owner',
            SubmittedAt: 333,
          },
          uid_bob: { Paid: false, DisplayName: 'Bob', Phone: '555-0199' },
        },
      },
    },
    'Sign Ups': { Futsal: { '16': { Paid: { [ALICE]: 'Alice Able', uid_bob: 'Bob' } } } },
    Support: {
      Counter: 9,
      Tickets: {
        '7': { Num: 7, Uid: ALICE, Name: 'Alice', Email: 'a***@example.com', Message: 'help', Screenshots: ['u0'] },
        '8': { Num: 8, Uid: 'uid_bob', Name: 'Bob', Email: 'b***@example.com', Message: 'hi' },
        '9': { Num: 9, Uid: ALICE, Name: 'Alice', Email: 'a***@example.com', Message: 'again' },
      },
      // Index 8 is bob's ticket: the index is user-written, never trusted.
      UserTickets: { [ALICE]: { '7': true, '8': true, '9': true }, uid_bob: { '8': true } },
    },
    EventsV2: {
      ev1: { Title: 'Pickup', Attendees: { [ALICE]: true, uid_bob: true }, Reminders: { [ALICE]: true } },
      ev2: { Title: 'Clinic', Attendees: { uid_bob: true } },
    },
    Events: [{ Title: 'Old event', Attendees: { [ALICE]: true, uid_bob: true } }],
    MergeNotices: { [ALICE]: { Status: 'sent' } },
    Insiders: { [ALICE]: { Code: 'ALICE5', Status: 'approved', CurrentStanding: 3 } },
    InsiderCodes: { ALICE5: ALICE, BOB5: 'uid_bob' },
    ReferredUsers: { [ALICE]: 'ref1' },
    Referrals: {
      ref1: { InsiderUid: 'uid_bob', ReferredUid: ALICE, ReferredName: 'Alice Able', State: 'counted', CountedAt: 9 },
    },
  };
}

async function planFor(db: FakeDb, uid = ALICE): Promise<AccountDeletionPlanning> {
  return planAccountDeletion(await readAccountDeletionSnapshot(db, uid), uid, STAMP);
}

async function planOk(db: FakeDb, uid = ALICE): Promise<DeletionPlan> {
  const p = await planFor(db, uid);
  if (p.refused) throw new Error(`refused: ${p.refused}`);
  return p;
}

async function deleteAll(db: FakeDb, storage = new FakeObjectStore()) {
  const plan = await planOk(db);
  const summary = await applyAccountDeletion(db, storage, plan);
  return { plan, summary, storage };
}

const at = (db: FakeDb, path: string): unknown => {
  let node: any = db.data;
  for (const p of path.split('/')) {
    if (node === null || node === undefined) return null;
    node = node[p];
  }
  return node === undefined ? null : node;
};

describe('account deletion — every D1 row', () => {
  it('deletes the Users node, the public profile and the profile photo', async () => {
    const db = new FakeDb(world());
    const { storage } = await deleteAll(db);
    expect(at(db, `Users/${ALICE}`)).toBeNull();
    expect(at(db, `PublicProfiles/${ALICE}`)).toBeNull();
    expect(storage.deleted).toContain(`Users/${ALICE}/profileimage.jpg`);
    expect(at(db, 'Users/uid_bob')).toEqual({ 'First Name': 'Bob', Email: 'b***@example.com' });
    expect(at(db, 'PublicProfiles/uid_bob')).toEqual({ 'First Name': 'Bob' });
  });

  it('deletes every per-uid fantasy node in both seasons', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    for (const node of [
      'Managers', 'Squads', 'TransferState', 'Baselines', 'SquadAlerts', 'AccessClaims',
      'Watchlists', 'Badges', 'BadgePushClaims', 'Live/Squads', 'PreviewPushed/2',
    ]) {
      expect(at(db, `Fantasy/Futsal/15/${node}/${ALICE}`), node).toBeNull();
    }
    expect(at(db, `Fantasy/Futsal/16/Managers/${ALICE}`)).toBeNull();
    expect(at(db, `Fantasy/Futsal/16/Squads/${ALICE}`)).toBeNull();
    // Nobody else's rows move.
    expect(at(db, 'Fantasy/Futsal/15/Managers/uid_bob')).toEqual({ TeamName: 'Bob FC' });
    expect(at(db, 'Fantasy/Futsal/15/Badges/uid_bob')).toEqual({ first_win: { At: 1 } });
    expect(at(db, 'Fantasy/Futsal/15/PreviewPushed/2/uid_bob')).toEqual({ At: 5 });
    expect(at(db, 'Fantasy/BadgeCatalog')).toEqual({ first_win: { Name: 'First win' } });
  });

  it('keeps the payment part of Access/<uid> and drops its private parts', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, `Fantasy/Futsal/15/Access/${ALICE}`)).toEqual({
      Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 111, By: 'stripe',
      StripePaymentIntent: 'pi_test_1', Deleted: true,
    });
    expect(at(db, 'Fantasy/Futsal/15/Access/uid_bob'))
      .toEqual({ Status: 'active', Via: 'granted', AmountCents: 0, PaidAt: 1, By: 'uid_admin' });
  });

  it('keeps the ledger rows (History, PublishedPicks, Leaderboards, Live board) and the internal ledgers', async () => {
    const before = world();
    const db = new FakeDb(world());
    await deleteAll(db);
    const s15 = 'Fantasy/Futsal/15';
    expect(at(db, `${s15}/History/1/${ALICE}`)).toEqual(before.Fantasy.Futsal['15'].History['1'][ALICE]);
    expect(at(db, `${s15}/PublishedPicks/1/${ALICE}`)).toEqual(before.Fantasy.Futsal['15'].PublishedPicks['1'][ALICE]);
    expect(at(db, `${s15}/Leaderboards/Gameweek/1/${ALICE}`)).toEqual({ points: 4, rank: 3 });
    expect(at(db, `${s15}/Leaderboards/RankHistory/${ALICE}`)).toEqual({ '1': 3 });
    expect(at(db, `${s15}/Live/Board/${ALICE}`)).toEqual({ O: 42, R: 3 });
    expect(at(db, `${s15}/TransferCosts/1/${ALICE}`)).toBe(4);
    expect(at(db, `${s15}/LiveBase/2/Managers/${ALICE}`)).toEqual({ O: 40 });
  });

  it('Review Focus 4: a manager ranked 3rd deletes — 1, 2, (no name, same points), 4', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    const overall = at(db, 'Fantasy/Futsal/15/Leaderboards/Overall') as Record<string, any>;
    const ranked = Object.entries(overall).sort(([, a], [, b]) => a.rank - b.rank)
      .map(([uid, row]) => [uid, row.rank, row.points]);
    expect(ranked).toEqual([
      ['uid_bob', 1, 90], ['uid_cara', 2, 70], [ALICE, 3, 40], ['uid_dan', 4, 10],
    ]);
    expect(overall[ALICE]).toEqual({ points: 40, rank: 3, movement: -1 });
    // A row that did carry names: every name -> Deleted manager, photo gone,
    // every number kept.
    expect(at(db, `Fantasy/Futsal/16/Leaderboards/Overall/${ALICE}`)).toEqual({
      points: 12, rank: 1, Name: DELETED_MANAGER, TeamName: DELETED_MANAGER, Uid: ALICE,
    });
    expect(at(db, 'Fantasy/Futsal/16/Leaderboards/Overall/uid_bob')).toEqual({ points: 8, rank: 2, Name: 'Bob' });
  });

  it('removes the person from mini-leagues: hand-off, solo delete, plain leave', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    const ml = 'Fantasy/Futsal/15/MiniLeagues';
    // Owned with others left: the first remaining member (uid order) owns it.
    expect(at(db, `${ml}/ml_owned`)).toEqual({
      Name: 'Owned', Code: 'OWN123', Owner: 'uid_bob', CreatedAt: 1,
      Members: { uid_cara: true, uid_bob: true },
    });
    expect(at(db, `${ml}/ml_joined/Members`)).toEqual({ uid_bob: true });
    expect(at(db, `${ml}/ml_joined/Owner`)).toBe('uid_bob');
    expect(at(db, `${ml}/ml_solo`)).toBeNull();
    expect(at(db, `${ml}/ml_other`)).toEqual(world().Fantasy.Futsal['15'].MiniLeagues.ml_other);
  });

  it('removes only the uid leaf (and the copied photo) from the market row', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, "Fantasy/Futsal/15/Players/Alice A")).toEqual({
      position: 'ATT', priceTenths: 60, eligible: true, teamName: 'Team A',
    });
    expect(at(db, 'Fantasy/Futsal/15/Players/Bob B/uid')).toBe('uid_bob');
  });

  it('removes only the UID leaf from league, AFC and tournament roster rows', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, 'Futsal/15/Line Ups/Team A/Alice A')).toEqual({ Goals: 3, number: '7' });
    expect(at(db, 'Futsal/15/Line Ups/Team A/Bob B')).toEqual({ UID: 'uid_bob', Goals: 1 });
    expect(at(db, 'AFC San Jose/Seasons/2/Roster/Alice A')).toEqual({ Goals: 1 });
    expect(at(db, 'AFC San Jose/Seasons/2/Roster/Dan D')).toEqual({ UID: 'uid_dan' });
    expect(at(db, 'Tournaments/t_spring/Rosters/team1/Alice A')).toEqual({ Goals: 2 });
    expect(at(db, 'Tournaments/t_spring/Rosters/team1/Cara C')).toEqual({ uid: 'uid_cara' });
  });

  it('keeps the sign-up record', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, `Sign Ups/Futsal/16/Paid/${ALICE}`)).toBe('Alice Able');
  });

  it('keeps the registration payment fields + display name, deletes every other answer', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, `Registrations/Futsal-16/Submissions/${ALICE}`)).toEqual({
      Paid: true, PaidVia: 'card', PaidAmount: 80, PaidAt: 222, StripePaymentIntent: 'pi_test_2',
      AmountCents: 8000, Method: 'card', Waived: false,
      DisplayName: 'Alice Able', Status: 'approved', TeamId: 'team_1', TeamName: 'Team A',
      Deleted: true,
    });
    expect(at(db, 'Registrations/Futsal-16/Submissions/uid_bob'))
      .toEqual({ Paid: false, DisplayName: 'Bob', Phone: '555-0199' });
  });

  it("deletes the person's support tickets, their index and screenshots — never another person's ticket", async () => {
    const db = new FakeDb(world());
    const { storage } = await deleteAll(db);
    expect(at(db, 'Support/Tickets/7')).toBeNull();
    expect(at(db, 'Support/Tickets/9')).toBeNull();
    expect(at(db, 'Support/Tickets/8')).toEqual(world().Support.Tickets['8']);
    expect(at(db, `Support/UserTickets/${ALICE}`)).toBeNull();
    expect(at(db, 'Support/UserTickets/uid_bob')).toEqual({ '8': true });
    for (const n of ['7', '9']) {
      for (let i = 0; i < 5; i++) expect(storage.deleted).toContain(`support/${n}/img_${i}.jpg`);
    }
    expect(storage.deleted.some((p) => p.startsWith('support/8/'))).toBe(false);
  });

  it('deletes MergeNotices, the Insider record + its code, and the name on the referral row', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, `MergeNotices/${ALICE}`)).toBeNull();
    expect(at(db, `Insiders/${ALICE}`)).toBeNull();
    expect(at(db, 'InsiderCodes')).toEqual({ BOB5: 'uid_bob' });
    // The referral still counts for bob (his tier never moves); no name on it.
    expect(at(db, 'Referrals/ref1')).toEqual({
      InsiderUid: 'uid_bob', ReferredUid: ALICE, State: 'counted', CountedAt: 9,
    });
    expect(at(db, `ReferredUsers/${ALICE}`)).toBe('ref1');
  });

  it('deletes event RSVPs (and reminders) in EventsV2 and legacy Events', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, 'EventsV2/ev1/Attendees')).toEqual({ uid_bob: true });
    expect(at(db, `EventsV2/ev1/Reminders/${ALICE}`)).toBeNull();
    expect(at(db, 'Events/0/Attendees')).toEqual({ uid_bob: true });
    expect(at(db, 'EventsV2/ev2')).toEqual({ Title: 'Clinic', Attendees: { uid_bob: true } });
  });

  it('writes DeletedAccounts/<uid> = {At, Provider} as the very last step', async () => {
    const db = new FakeDb(world());
    const { plan, summary } = await deleteAll(db);
    expect(at(db, `DeletedAccounts/${ALICE}`)).toEqual({ At: NOW, Provider: 'password' });
    expect(plan.steps[plan.steps.length - 1])
      .toEqual({ path: `DeletedAccounts/${ALICE}`, action: 'write', after: { At: NOW, Provider: 'password' } });
    expect(db.writes[db.writes.length - 1]).toBe(`DeletedAccounts/${ALICE}`);
    expect(summary.errors).toEqual([]);
    const writes = plan.steps.filter((s) => s.action === 'write').length;
    expect(summary).toEqual({
      deleted: plan.steps.length - writes,
      anonymised: writes - 1,
      storageDeleted: plan.storagePaths.length,
      errors: [],
    });
    // The Users node goes after everything that was found through it.
    const users = plan.steps.findIndex((s) => s.path === `Users/${ALICE}`);
    const tournament = plan.steps.findIndex((s) => s.path.startsWith('Tournaments/'));
    expect(tournament).toBeGreaterThanOrEqual(0);
    expect(users).toBeGreaterThan(tournament);
    expect(users).toBe(plan.steps.length - 2);
  });

  it('an unknown uid plans only the DeletedAccounts write', async () => {
    const db = new FakeDb(world());
    const plan = await planOk(db, 'uid_nobody');
    expect(plan.steps).toEqual([
      { path: 'DeletedAccounts/uid_nobody', action: 'write', after: { At: NOW, Provider: 'password' } },
    ]);
    expect(plan.storagePaths).toEqual(['Users/uid_nobody/profileimage.jpg']);
  });
});

describe('account deletion — bounded snapshot reads', () => {
  it('never reads a whole season tree, the Fantasy node or all support tickets', async () => {
    const db = new FakeDb(world());
    await readAccountDeletionSnapshot(db, ALICE);
    const forbidden = [
      'read:Fantasy', 'read:Fantasy/Futsal', 'read:Fantasy/Futsal/15', 'read:Fantasy/Futsal/16',
      'read:Support/Tickets', 'read:Support', 'read:Fantasy/Futsal/15/History',
      'read:Fantasy/Futsal/15/PublishedPicks', 'read:Fantasy/Futsal/15/Leaderboards',
      'read:Fantasy/Futsal/15/Squads', 'read:EventsV2', 'read:Events', 'read:Registrations',
      'read:Referrals', 'read:Insiders', 'read:Users', 'read:Tournaments',
    ];
    for (const f of forbidden) expect(db.reads, f).not.toContain(f);
    expect(db.reads).toContain('keys:Fantasy');
    expect(db.reads).toContain(`read:Fantasy/Futsal/15/History/1/${ALICE}`);
    expect(db.reads).toContain(`read:Support/UserTickets/${ALICE}`);
    expect(db.reads).toContain('read:Support/Tickets/7/Uid');
  });
});

describe('account deletion — Review Focus 5: an old merged account', () => {
  it('is refused with the masked kept-account hint and nothing is written', async () => {
    const seed = world();
    seed.Users[ALICE].MergedInto = 'uid_keep';
    seed.Users[ALICE].MergedHint = 'a•••@example.com';
    const db = new FakeDb(seed);
    const before = db.snapshot();
    const plan = await planFor(db);
    expect(plan).toEqual({ refused: 'already-merged', keepHint: 'a•••@example.com' });
    expect(db.writes).toEqual([]);
    expect(db.snapshot()).toBe(before);
  });

  it('a missing hint reads as an empty keepHint', async () => {
    const seed = world();
    seed.Users[ALICE].MergedInto = 'uid_keep';
    expect(await planFor(new FakeDb(seed))).toEqual({ refused: 'already-merged', keepHint: '' });
  });
});

describe('account deletion — Review Focus 3: the function dies halfway', () => {
  it('a second run plans only the remaining steps and still ends with DeletedAccounts — at every cut point', async () => {
    const full = await planOk(new FakeDb(world()));
    const clean = new FakeDb(world());
    await deleteAll(clean);
    for (let done = 0; done < full.steps.length; done++) {
      const dying = new DyingDb(world(), done);
      const first = await applyAccountDeletion(dying, new FakeObjectStore(), full);
      expect(first.errors, `cut ${done}`).toHaveLength(1);
      expect(at(dying, `DeletedAccounts/${ALICE}`)).toBeNull();

      const resumed = new FakeDb(dying.data);
      const rest = await planOk(resumed);
      expect(rest.steps, `cut ${done}`).toEqual(full.steps.slice(done));
      const second = await applyAccountDeletion(resumed, new FakeObjectStore(), rest);
      expect(second.errors).toEqual([]);
      expect(resumed.data, `cut ${done}`).toEqual(clean.data);
    }
  });

  it('a finished deletion re-plans only the DeletedAccounts write (no double anonymising)', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    const again = await planOk(db);
    expect(again.steps.map((s) => s.path)).toEqual([`DeletedAccounts/${ALICE}`]);
  });

  it('a row already reading Deleted manager is not planned again', () => {
    expect(anonymiseLedgerRow({ points: 3, rank: 2, Name: DELETED_MANAGER })).toBeNull();
    expect(anonymiseLedgerRow({ points: 3, rank: 2 })).toBeNull();
    expect(anonymiseLedgerRow({ points: 3, Name: 'Alice', ProfileUrl: 'x', ok: true }))
      .toEqual({ points: 3, Name: DELETED_MANAGER, ok: true });
    expect(anonymiseLedgerRow([null, 3])).toBeNull();
  });
});

describe('account deletion — the applier', () => {
  it('a failed Storage delete stops before any database step, reported without the uid', async () => {
    const db = new FakeDb(world());
    const before = db.snapshot();
    const storage = new FakeObjectStore();
    storage.failing.add('support/7/img_0.jpg');
    const plan = await planOk(db);
    const summary = await applyAccountDeletion(db, storage, plan);
    expect(summary.errors.length).toBeGreaterThan(0);
    for (const e of summary.errors) expect(e).not.toContain(ALICE);
    expect(summary.storageDeleted).toBe(plan.storagePaths.length - 1);
    expect(summary.deleted).toBe(0);
    expect(summary.anonymised).toBe(0);
    // Nothing in the database moved, so the ticket (and its screenshots)
    // can still be found by the retry.
    expect(db.writes).toEqual([]);
    expect(db.snapshot()).toBe(before);

    const retry = await planOk(db);
    expect(retry).toEqual(plan);
    const ok = await applyAccountDeletion(db, new FakeObjectStore(), retry);
    expect(ok.errors).toEqual([]);
    expect(at(db, `DeletedAccounts/${ALICE}`)).toEqual({ At: NOW, Provider: 'password' });
  });

  it('a failed database step stops the run and holds back the DeletedAccounts stamp', async () => {
    const plan = await planOk(new FakeDb(world()));
    const db = new DyingDb(world(), 3);
    const summary = await applyAccountDeletion(db, new FakeObjectStore(), plan);
    expect(summary.errors).toHaveLength(1);
    expect(summary.errors[0]).not.toContain(ALICE);
    expect(summary.deleted + summary.anonymised).toBe(3);
    expect(at(db, `DeletedAccounts/${ALICE}`)).toBeNull();
  });

  it('deletes Storage objects before any database step', async () => {
    const db = new FakeDb(world());
    const order: string[] = [];
    const storage: ObjectStore = { deleteObject: async (p) => { order.push(`storage:${p}`); } };
    const origWrite = db.write.bind(db);
    db.write = async (p, v) => { order.push(`db:${p}`); await origWrite(p, v); };
    const plan = await planOk(db);
    await applyAccountDeletion(db, storage, plan);
    const lastStorage = order.map((o) => o.startsWith('storage:')).lastIndexOf(true);
    const firstDb = order.findIndex((o) => o.startsWith('db:'));
    expect(lastStorage).toBeLessThan(firstDb);
  });
});

// Account deletion planner + applier (plan 2026-11-09-account-deletion,
// Task 1; design D1, D2, D5; Review Focus 3-5). Every test drives the real
// read -> plan -> apply chain over the in-memory FakeDb and asserts the tree
// that is left behind, not the calls that were made.

import { describe, expect, it } from 'vitest';
import {
  AccountDeletionPlanning, anonymiseLedgerRow, anonymiseManager, applyAccountDeletion,
  DELETED_MANAGER, DeletionPlan, ObjectStore, planAccountDeletion,
  readAccountDeletionSnapshot, settlePendingAuth,
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
          Managers: {
            [ALICE]: { TeamName: 'Alice FC', NameFlagged: false, NamedAt: 5, PhotoUrl: 'https://img.example/alice.jpg', DisplayName: 'Alice Able' },
            uid_bob: { TeamName: 'Bob FC' },
          },
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
          'Team A': {
            'Alice A': { UID: ALICE, Goals: 3, number: '7', PhotoUrl: 'https://img.example/alice.jpg' },
            'Bob B': { UID: 'uid_bob', Goals: 1, PhotoUrl: 'https://img.example/bob.jpg' },
          },
        },
      },
      'Futsal Season': 15,
    },
    'AFC San Jose': { Seasons: { '2': { Roster: { 'Alice A': { UID: ALICE, Goals: 1 }, 'Dan D': { UID: 'uid_dan' } } } } },
    Tournaments: {
      t_spring: { Rosters: { team1: { 'Alice A': { uid: ALICE, Goals: 2, photoUrl: 'https://img.example/alice.jpg' }, 'Cara C': { uid: 'uid_cara' } } } },
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
      // M11: an UNPAID submission - nothing was paid, so no name is kept.
      'Futsal-17': {
        Submissions: {
          [ALICE]: {
            Paid: false, AmountCents: 8000, EligibleFee: 80, DisplayName: 'Alice Able',
            Status: 'pending', Phone: '555-0100', Answers: { Shirt: 'M' },
          },
        },
      },
    },
    'Sign Ups': {
      Futsal: {
        '16': {
          Paid: { [ALICE]: 'Alice Able', uid_bob: 'Bob' },
          // I3: `<displayName>: "<uid>:<text>"`; another uid that merely
          // STARTS with alice's uid must stay.
          Comments: {
            'Alice Able': `${ALICE}:bring a ball`,
            Bob: 'uid_bob:see you there',
            'Alice Two': `${ALICE}2:not hers`,
          },
        },
        '17': { NotPaid: { [ALICE]: 'Alice Able', uid_bob: 'Bob' } },
      },
      'Spring Cup': { t_spring: { NotPaid: { [ALICE]: 'Alice Able' }, Comments: { 'Alice Able': `${ALICE}:hi` } } },
      Rules: 'Be kind.',
    },
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
      'Squads', 'TransferState', 'Baselines', 'SquadAlerts', 'AccessClaims',
      'Watchlists', 'Badges', 'BadgePushClaims', 'Live/Squads', 'PreviewPushed/2',
    ]) {
      expect(at(db, `Fantasy/Futsal/15/${node}/${ALICE}`), node).toBeNull();
    }
    expect(at(db, `Fantasy/Futsal/16/Managers/${ALICE}`)).toEqual({ TeamName: DELETED_MANAGER, Deleted: true });
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
    // The row's name comes from Managers/<uid> (realName ?? teamName): kept
    // and anonymised, never deleted, so the row reads "Deleted manager".
    expect(at(db, `Fantasy/Futsal/15/Managers/${ALICE}`)).toEqual({
      TeamName: DELETED_MANAGER, NamedAt: 5, Deleted: true,
    });
    expect(at(db, `PublicProfiles/${ALICE}`)).toBeNull();
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

  it('removes only the UID leaf (and its photo url) from league, AFC and tournament roster rows', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, 'Futsal/15/Line Ups/Team A/Alice A')).toEqual({ Goals: 3, number: '7' });
    expect(at(db, 'Futsal/15/Line Ups/Team A/Bob B'))
      .toEqual({ UID: 'uid_bob', Goals: 1, PhotoUrl: 'https://img.example/bob.jpg' });
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
      SubmittedAt: 333, Deleted: true,
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
    const handoffs = plan.steps.filter((s) => s.handoff === true).length;
    expect(handoffs).toBe(1); // ml_owned -> a new Owner
    expect(summary).toEqual({
      deleted: plan.steps.length - writes,
      anonymised: writes - 1 - handoffs,
      handoffs,
      stamped: true,
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
      'read:Sign Ups', 'read:Sign Ups/Futsal', 'read:Sign Ups/Futsal/16', 'read:Sign Ups/Futsal/17/NotPaid',
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

  it('a Managers node already marked Deleted is not planned again', () => {
    expect(anonymiseManager({ TeamName: DELETED_MANAGER, Deleted: true, NamedAt: 5 })).toBeNull();
    expect(anonymiseManager(null)).toBeNull();
    // A flagged manager reads "Deleted manager" too: the flag would hide it.
    expect(anonymiseManager({ TeamName: 'X', Name: 'Y', ProfileUrl: 'z', NameFlagged: true, NamedAt: 2 }))
      .toEqual({ TeamName: DELETED_MANAGER, NamedAt: 2, Deleted: true });
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
  it('a failed Storage delete is recorded without the uid and carried in the stamp as PendingStorage', async () => {
    const db = new FakeDb(world());
    const storage = new FakeObjectStore();
    storage.failing.add('support/7/img_2.jpg');
    const plan = await planOk(db);
    const summary = await applyAccountDeletion(db, storage, plan);
    expect(summary.errors).toHaveLength(1);
    expect(summary.errors[0]).toContain('support/7/img_2.jpg');
    expect(summary.errors[0]).not.toContain(ALICE);
    expect(summary.storageDeleted).toBe(plan.storagePaths.length - 1);
    const writes = plan.steps.filter((s) => s.action === 'write').length;
    expect(summary.deleted).toBe(plan.steps.length - writes);
    expect(summary.anonymised + summary.handoffs).toBe(writes - 1);
    expect(summary.stamped).toBe(true);
    // Every database step landed: the ticket is gone, the stamp is written
    // and remembers the object it could not delete.
    expect(at(db, 'Support/Tickets/7')).toBeNull();
    expect(at(db, `Users/${ALICE}`)).toBeNull();
    expect(at(db, `DeletedAccounts/${ALICE}`)).toEqual({
      At: NOW, Provider: 'password', PendingStorage: ['support/7/img_2.jpg'],
    });

    // The retry plans that object again (next to the always-planned
    // profile photo) and its stamp clears the field.
    const retry = await planOk(db);
    expect(retry.steps.map((s) => s.path)).toEqual([`DeletedAccounts/${ALICE}`]);
    expect(retry.storagePaths).toEqual([`Users/${ALICE}/profileimage.jpg`, 'support/7/img_2.jpg']);
    const again = new FakeObjectStore();
    const ok = await applyAccountDeletion(db, again, retry);
    expect(ok).toEqual({
      deleted: 0, anonymised: 0, handoffs: 0, stamped: true, storageDeleted: 2, errors: [],
    });
    expect(again.deleted).toContain('support/7/img_2.jpg');
    expect(at(db, `DeletedAccounts/${ALICE}`)).toEqual({ At: NOW, Provider: 'password' });
    expect((await planOk(db)).storagePaths).toEqual([`Users/${ALICE}/profileimage.jpg`]);
  });

  it('a PendingStorage entry that is not a known object path is never planned', async () => {
    const seed = world();
    seed.DeletedAccounts = { [ALICE]: { At: 1, Provider: 'password', PendingStorage: ['support/8/../x', 'Users/uid_bob/other.jpg', 7] } };
    const plan = await planOk(new FakeDb(seed));
    expect(plan.storagePaths.filter((p) => !p.startsWith('support/7/') && !p.startsWith('support/9/')))
      .toEqual([`Users/${ALICE}/profileimage.jpg`]);
  });

  it('a failed database step stops the run: no Storage, no stamp', async () => {
    const plan = await planOk(new FakeDb(world()));
    const db = new DyingDb(world(), 3);
    const storage = new FakeObjectStore();
    const summary = await applyAccountDeletion(db, storage, plan);
    expect(summary.errors).toHaveLength(1);
    expect(summary.errors[0]).not.toContain(ALICE);
    expect(summary.deleted + summary.anonymised + summary.handoffs).toBe(3);
    expect(summary.stamped).toBe(false);
    expect(storage.deleted).toEqual([]);
    expect(at(db, `DeletedAccounts/${ALICE}`)).toBeNull();
  });

  it('runs the database steps, then Storage, then the stamp', async () => {
    const db = new FakeDb(world());
    const order: string[] = [];
    const storage: ObjectStore = { deleteObject: async (p) => { order.push(`storage:${p}`); } };
    const origWrite = db.write.bind(db);
    db.write = async (p, v) => { order.push(`db:${p}`); await origWrite(p, v); };
    const plan = await planOk(db);
    await applyAccountDeletion(db, storage, plan);
    const kinds = order.map((o) => o.split(':')[0]);
    const firstStorage = kinds.indexOf('storage');
    const lastStorage = kinds.lastIndexOf('storage');
    expect(kinds.slice(0, firstStorage).every((k) => k === 'db')).toBe(true);
    expect(firstStorage).toBe(plan.steps.length - 1);
    expect(lastStorage - firstStorage + 1).toBe(plan.storagePaths.length);
    expect(order[order.length - 1]).toBe(`db:DeletedAccounts/${ALICE}`);
  });
});

describe('account deletion — stamp By/Reason and the payment allow-list', () => {
  it('a retry keeps the first At, Provider and an existing By/Reason, and adds them when missing', async () => {
    const seed = world();
    seed.DeletedAccounts = { [ALICE]: { At: 5, Provider: 'password', By: 'uid_admin', Reason: 'emailed request' } };
    const db = new FakeDb(seed);
    const snap = await readAccountDeletionSnapshot(db, ALICE);
    const plan = planAccountDeletion(snap, ALICE, { nowMs: NOW, provider: 'google.com', by: 'uid_other', reason: 'later' }) as DeletionPlan;
    const stamp = plan.steps[plan.steps.length - 1].after;
    expect(stamp).toEqual({ At: 5, Provider: 'password', By: 'uid_admin', Reason: 'emailed request' });

    const fresh = planAccountDeletion(await readAccountDeletionSnapshot(new FakeDb(world()), ALICE), ALICE,
      { nowMs: NOW, provider: 'password', by: 'uid_admin', reason: 'why' }) as DeletionPlan;
    expect(fresh.steps[fresh.steps.length - 1].after)
      .toEqual({ At: NOW, Provider: 'password', By: 'uid_admin', Reason: 'why' });
  });

  it('a registration scrub keeps only the allow-list: an unknown Paid*/Refund* key is dropped', async () => {
    const seed = world();
    seed.Registrations['Futsal-16'].Submissions[ALICE] = {
      Paid: true, PaidVia: 'card', PaidAmount: 80, RefundedAt: 9, RefundAmountCents: 100,
      PaidNote: 'call 555-0100', RefundMemo: 'text me', Phone: '555-0100',
      SubmittedAt: 1234, AdjustReason: 'friend of owner',
    };
    const db = new FakeDb(seed);
    await deleteAll(db);
    expect(at(db, `Registrations/Futsal-16/Submissions/${ALICE}`)).toEqual({
      Paid: true, PaidVia: 'card', PaidAmount: 80, RefundedAt: 9, RefundAmountCents: 100, SubmittedAt: 1234, Deleted: true,
    });
  });
});

describe('I3 + M11: sign-up comments, unpaid sign-ups and unpaid registrations', () => {
  it("deletes the person's sign-up comments in every listed season and leaves everyone else's", async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, 'Sign Ups/Futsal/16/Comments')).toEqual({
      Bob: 'uid_bob:see you there', 'Alice Two': `${ALICE}2:not hers`,
    });
    expect(at(db, 'Sign Ups/Spring Cup/t_spring/Comments/Alice Able')).toBeNull();
    expect(at(db, 'Sign Ups/Rules')).toBe('Be kind.');
  });

  it('deletes an unpaid sign-up (NotPaid) and keeps a paid one', async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, `Sign Ups/Futsal/17/NotPaid/${ALICE}`)).toBeNull();
    expect(at(db, 'Sign Ups/Futsal/17/NotPaid/uid_bob')).toBe('Bob');
    expect(at(db, `Sign Ups/Spring Cup/t_spring/NotPaid/${ALICE}`)).toBeNull();
    expect(at(db, `Sign Ups/Futsal/16/Paid/${ALICE}`)).toBe('Alice Able');
  });

  it("an unpaid registration keeps its payment keys but not the person's name; a paid one is unchanged", async () => {
    const db = new FakeDb(world());
    await deleteAll(db);
    expect(at(db, `Registrations/Futsal-17/Submissions/${ALICE}`)).toEqual({
      Paid: false, AmountCents: 8000, EligibleFee: 80, DisplayName: 'Deleted player',
      Status: 'pending', Deleted: true,
    });
    expect(at(db, `Registrations/Futsal-16/Submissions/${ALICE}/DisplayName`)).toBe('Alice Able');
  });
});

// ── C1: an old merged account is deleted with the account it was combined into
const OLD = 'uid_alice_old';

/** alice (kept) combined from OLD; a forged link to bob must never reach bob. */
function mergedWorld(): Record<string, any> {
  const w = world();
  w.Users[ALICE].MergedFrom = { [OLD]: true, uid_bob: true };
  w.Users[OLD] = {
    'First Name': 'Alice', Email: 'a***@example.com', Token: 'tok_old',
    MergedInto: ALICE, MergedAt: 7, MergedHint: 'a•••@example.com',
  };
  w.PublicProfiles[OLD] = { 'First Name': 'Alice' };
  w.MergeNotices[OLD] = { KeepHint: 'a•••@example.com', Status: 'sent' };
  w.Support.Tickets['10'] = { Num: 10, Uid: OLD, Name: 'Alice', Message: 'old account' };
  w.Support.UserTickets[OLD] = { '10': true };
  w.EventsV2.ev2.Attendees[OLD] = true;
  // A roster leftover still pointing at the old account.
  w.Futsal['15']['Line Ups']['Team A']['Alice Old'] = { UID: OLD, Goals: 0 };
  w['Sign Ups'].Futsal['16'].Comments['Alice Old'] = `${OLD}:from the old account`;
  return w;
}

describe('C1: deleting the kept account also deletes the old accounts it was combined from', () => {
  it("plans the old account's own deletion, stamps it as merged and lists both Auth users", async () => {
    const db = new FakeDb(mergedWorld());
    const plan = await planOk(db);
    expect(plan.authUidsToDelete).toEqual([ALICE, OLD]);
    const storage = new FakeObjectStore();
    const summary = await applyAccountDeletion(db, storage, plan);
    expect(summary.errors).toEqual([]);
    expect(summary.stamped).toBe(true);
    for (const p of [`Users/${OLD}`, `PublicProfiles/${OLD}`, `MergeNotices/${OLD}`,
      'Support/Tickets/10', `Support/UserTickets/${OLD}`, `EventsV2/ev2/Attendees/${OLD}`,
      'Sign Ups/Futsal/16/Comments/Alice Old', 'Futsal/15/Line Ups/Team A/Alice Old/UID']) {
      expect(at(db, p), p).toBeNull();
    }
    expect(storage.deleted).toContain(`Users/${OLD}/profileimage.jpg`);
    expect(storage.deleted).toContain('support/10/img_0.jpg');
    expect(at(db, `DeletedAccounts/${OLD}`)).toEqual({ At: NOW, Provider: 'merged', MergedInto: ALICE });
    // The kept account's stamp remembers the old Auth user until it is gone.
    expect(at(db, `DeletedAccounts/${ALICE}`)).toEqual({ At: NOW, Provider: 'password', PendingAuth: [OLD] });
    // The forged link never reaches bob.
    expect(at(db, 'Users/uid_bob')).toEqual({ 'First Name': 'Bob', Email: 'b***@example.com' });
    expect(at(db, 'PublicProfiles/uid_bob')).toEqual({ 'First Name': 'Bob' });
    expect(at(db, 'DeletedAccounts/uid_bob')).toBeNull();
    expect(plan.authUidsToDelete).not.toContain('uid_bob');
  });

  it('a link to an account that is not merged into this one costs two reads and nothing else', async () => {
    const db = new FakeDb(mergedWorld());
    await readAccountDeletionSnapshot(db, ALICE);
    const bobReads = db.reads.filter((r) => r.includes('uid_bob'));
    expect(bobReads).toEqual(['read:Users/uid_bob', 'read:DeletedAccounts/uid_bob']);
  });

  it('the old account is not refused as already-merged when reached this way', async () => {
    const plan = await planFor(new FakeDb(mergedWorld()));
    expect(plan.refused).toBeUndefined();
  });

  it('the old account steps (and its stamp) come before the kept Users node is deleted', async () => {
    const plan = await planOk(new FakeDb(mergedWorld()));
    const idx = (p: string) => plan.steps.findIndex((s) => s.path === p);
    expect(idx(`DeletedAccounts/${OLD}`)).toBeLessThan(idx(`Users/${OLD}`));
    expect(idx(`Users/${OLD}`)).toBeLessThan(idx(`Users/${ALICE}`));
    expect(plan.steps[plan.steps.length - 1].path).toBe(`DeletedAccounts/${ALICE}`);
  });

  it('dies at every cut point: the rerun plans exactly the remainder, still lists the old Auth user, and converges', async () => {
    const full = await planOk(new FakeDb(mergedWorld()));
    const clean = new FakeDb(mergedWorld());
    await applyAccountDeletion(clean, new FakeObjectStore(), await planOk(clean));
    for (let done = 0; done < full.steps.length; done++) {
      const dying = new DyingDb(mergedWorld(), done);
      await applyAccountDeletion(dying, new FakeObjectStore(), full);
      const resumed = new FakeDb(dying.data);
      const rest = await planOk(resumed);
      expect(rest.steps, `cut ${done}`).toEqual(full.steps.slice(done));
      expect(rest.authUidsToDelete, `cut ${done}`).toEqual([ALICE, OLD]);
      await applyAccountDeletion(resumed, new FakeObjectStore(), rest);
      expect(resumed.data, `cut ${done}`).toEqual(clean.data);
    }
  });

  it('a finished run still lists the old Auth user until PendingAuth is settled', async () => {
    const db = new FakeDb(mergedWorld());
    await applyAccountDeletion(db, new FakeObjectStore(), await planOk(db));
    const again = await planOk(db);
    expect(again.authUidsToDelete).toEqual([ALICE, OLD]);
    await settlePendingAuth(db, ALICE, []);
    expect(at(db, `DeletedAccounts/${ALICE}`)).toEqual({ At: NOW, Provider: 'password' });
    expect((await planOk(db)).authUidsToDelete).toEqual([ALICE]);
    await settlePendingAuth(db, ALICE, [OLD]);
    expect(at(db, `DeletedAccounts/${ALICE}/PendingAuth`)).toEqual([OLD]);
    expect((await planOk(db)).authUidsToDelete).toEqual([ALICE, OLD]);
  });

  it('a PendingAuth entry that is not a uid is never listed', async () => {
    const seed = world();
    seed.DeletedAccounts = { [ALICE]: { At: 1, Provider: 'password', PendingAuth: ['../x', 7, ALICE, 'uid_ok_1'] } };
    expect((await planOk(new FakeDb(seed))).authUidsToDelete).toEqual([ALICE, 'uid_ok_1']);
  });

  it('allowMerged (the admin path) deletes an old merged account on its own', async () => {
    const db = new FakeDb(mergedWorld());
    const snap = await readAccountDeletionSnapshot(db, OLD, undefined, { allowMerged: true });
    const plan = planAccountDeletion(snap, OLD, STAMP, { allowMerged: true });
    if (plan.refused) throw new Error('refused');
    expect(plan.authUidsToDelete).toEqual([OLD]);
    await applyAccountDeletion(db, new FakeObjectStore(), plan);
    expect(at(db, `Users/${OLD}`)).toBeNull();
    expect(at(db, `Users/${ALICE}`)).not.toBeNull();
    // Without the option the user path still refuses it.
    expect(await planFor(new FakeDb(mergedWorld()), OLD)).toMatchObject({ refused: 'already-merged' });
  });
});

describe('C1: old-account edge cases', () => {
  it("an old account's Storage failure is masked and carried in the kept account's PendingStorage", async () => {
    const db = new FakeDb(mergedWorld());
    const storage = new FakeObjectStore();
    storage.failing.add(`Users/${OLD}/profileimage.jpg`);
    const summary = await applyAccountDeletion(db, storage, await planOk(db));
    expect(summary.stamped).toBe(true);
    expect(summary.errors).toHaveLength(1);
    expect(summary.errors[0]).not.toContain(OLD);
    expect(summary.errors[0]).not.toContain(ALICE);
    expect(at(db, `DeletedAccounts/${ALICE}/PendingStorage`)).toEqual([`Users/${OLD}/profileimage.jpg`]);
    expect((await planOk(db)).storagePaths).toContain(`Users/${OLD}/profileimage.jpg`);
  });

  it('a league the old account owns never passes to the kept account that is leaving too', async () => {
    const seed = mergedWorld();
    seed.Fantasy.Futsal['15'].MiniLeagues.ml_old = {
      Name: 'Old', Code: 'OLD123', Owner: OLD, CreatedAt: 9, Members: { [ALICE]: true, [OLD]: true, uid_cara: true },
    };
    seed.Fantasy.Futsal['15'].MiniLeagues.ml_pair = {
      Name: 'Pair', Code: 'PAI123', Owner: OLD, CreatedAt: 9, Members: { [ALICE]: true, [OLD]: true },
    };
    const db = new FakeDb(seed);
    await applyAccountDeletion(db, new FakeObjectStore(), await planOk(db));
    const ml = 'Fantasy/Futsal/15/MiniLeagues';
    expect(at(db, `${ml}/ml_old/Owner`)).toBe('uid_cara');
    expect(at(db, `${ml}/ml_old/Members`)).toEqual({ uid_cara: true });
    expect(at(db, `${ml}/ml_pair`)).toBeNull();
  });
});

// RULES CONTRACT (audit C1, 2026-10-31): every path the Manager or the fan
// app WRITES under Fantasy/ must be granted `.write` by the RTDB rules — on
// the node itself or on some ancestor (RTDB write grants cascade down; a
// deeper `.write` never grants a write made higher up). The Manager's VOID
// toggle (Voided/<gw>) and Manual-price flag (PriceChanges/<gw>/Manual)
// shipped with NO grant anywhere on their chain, so the owner's taps were
// permission_denied in production and nothing caught it. This test would
// have.
//
// The expected list is hard-coded on purpose, one entry per client write,
// with where it comes from:
//   - Manager (InfiniteSportsManagerFlutter): lib/core/constants/
//     fantasy_paths.dart helpers written by lib/services/firebase/
//     fantasy_admin_service.dart (`.set(` / `.update(` / `.remove(` /
//     `runTransaction(` — the race-safe ones go through lib/services/
//     fantasy_guarded_writes.dart's store seam, which adds no paths of its
//     own).
//   - Fan app: lib/fantasy/data/fantasy_service.dart.
// A NEW client write path must be added here, with its kind; a rules edit
// that drops a grant fails with the path's name.
//
// Kinds:
//   admin        — some `.write` on the chain is the admin gate
//                  (root.child('Admins').child(auth.uid)).
//   own          — some `.write` on the chain compares auth.uid with the
//                  wildcard bound to the path's UID segment (the writer's own
//                  uid).
//   ownerCreate  — some `.write` on the chain requires the NEW row's Owner to
//                  be auth.uid (mini-league create under a fresh push id).
//
// Both rules files are checked: database.rules.stage1.json is what firebase.json
// deploys today (live), database.rules.json the target posture — a grant must
// exist in both.

import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it } from 'vitest';
import { configFromMap, squadSize } from './lib/fantasy/fantasy_config';

type Json = Record<string, any>;
type Kind = 'admin' | 'own' | 'ownerCreate';

interface ContractEntry {
  /** Root-relative RTDB path, as the client writes it. `UID` = the signed-in
   *  writer's own uid; every other segment is a representative value. */
  path: string;
  kind: Kind;
  /** Who writes it, and how. */
  note: string;
}

const S = 'Fantasy/Futsal/16'; // any <sport>/<season>

const CONTRACT: ContractEntry[] = [
  // ── Manager (admin) — fantasy_admin_service.dart ──────────────────────────
  { path: `${S}/Config`, kind: 'admin',
    note: 'setLockOverride: Config update {lockOverride, lockOverrideUntil}' },
  { path: `${S}/Config/lockHour`, kind: 'admin',
    note: 'setLockHour: set' },
  { path: `${S}/Config/Reminder`, kind: 'admin',
    note: 'saveReminderConfig: set' },
  { path: `${S}/Config/NewsAutopilot`, kind: 'admin',
    note: 'saveNewsAutopilot: set' },
  { path: `${S}/Config/NewsAutopilot/Enabled`, kind: 'admin',
    note: 'turnNewsAutopilotOff: root multi-path update (also Weekday/Hour)' },
  { path: `${S}/Config/DreamTeamPost`, kind: 'admin',
    note: 'saveDreamTeamPostConfig (legacy): set' },
  { path: `${S}/Players/Some Player/priceTenths`, kind: 'admin',
    note: 'setPlayerPrice: set' },
  { path: `${S}/Players/Some Player/eligible`, kind: 'admin',
    note: 'setPlayerEligible: set' },
  { path: `${S}/Players/Some Player`, kind: 'admin',
    note: 'setPlayerPosition: update {position, priceTenths?}' },
  { path: `${S}/Managers/someUid/NameFlagged`, kind: 'admin',
    note: 'setNameFlagged: set' },
  { path: `${S}/Voided/5`, kind: 'admin',
    note: 'setVoided: set(true) / remove() — spec §15 owner void (C1)' },
  { path: `${S}/PriceChanges/5/Manual`, kind: 'admin',
    note: 'setManualReprice: set(true) / remove() — Monday-job stand-down (C1)' },
  { path: `${S}/ScheduledPushes/-pushId`, kind: 'admin',
    note: 'scheduleManagerMessage: push().set; cancelScheduledMessage: runTransaction' },
  { path: `${S}/News/Drafts/-pushId`, kind: 'admin',
    note: 'saveDraft: push().set / runTransaction edit; discardDraft + publishDraft: root update (null)' },
  { path: `${S}/News/Drafts/-pushId/AutoPublishAt`, kind: 'admin',
    note: 'turnNewsAutopilotOff: root multi-path update (null)' },
  { path: `${S}/News/Published/-pushId`, kind: 'admin',
    note: 'composePost: push().set; publishDraft/updatePublishedPost/discardDraft: runTransaction; deletePublishedPost: remove' },
  { path: `${S}/News/Published/-pushId/At`, kind: 'admin',
    note: 'publishDraft: root update re-stamping the server At' },
  { path: 'Fantasy/BadgeCatalog/someBadge', kind: 'admin',
    note: 'createBadge: create-only runTransaction; updateBadge: update' },
  { path: 'Fantasy/BadgeCatalog/someBadge/ImageUrl', kind: 'admin',
    note: 'createBadge: set after the picture upload' },
  { path: 'Fantasy/BadgeCatalog/someBadge/Active', kind: 'admin',
    note: 'setBadgeActive: set' },
  { path: `${S}/Badges/someUid/-pushId`, kind: 'admin',
    note: 'giveBadge: push().set; removeBadgeAward: remove' },
  // Season setup + schedule (plan 2026-11-05): the owner's per-date
  // deadline override and skipped game day, under the admin Config grant.
  { path: `${S}/Config/Deadlines/10042026`, kind: 'admin',
    note: 'setDeadlineOverride: set(epoch ms) / remove()' },
  { path: `${S}/Config/SkippedDates/10042026`, kind: 'admin',
    note: 'setDateSkipped: set(true) / remove()' },

  // ── Fan app (signed-in user) — fantasy_service.dart ───────────────────────
  { path: `${S}/Squads/UID`, kind: 'own',
    note: 'saveMySquad: set the whole squad' },
  { path: `${S}/Managers/UID`, kind: 'own',
    note: 'saveTeamName: set {TeamName, NameFlagged:false}' },
  { path: `${S}/Watchlists/UID/Some Player`, kind: 'own',
    note: 'setWatchlisted: set(true) / remove()' },
  { path: `${S}/MiniLeagues/-pushId`, kind: 'ownerCreate',
    note: 'createMiniLeague: push().set {Name, Code, Owner:uid, CreatedAt, Members}' },
  { path: `${S}/MiniLeagues/-leagueId/Members/UID`, kind: 'own',
    note: 'joinMiniLeague: set(true)' },

  // ── Paid access (spec 2026-11-01) ─────────────────────────────────────────
  { path: `${S}/AccessClaims/UID/-pushId`, kind: 'own',
    note: 'fan submitAccessClaim: push().set {Method, AmountDollars, Note, At} (create-only)' },
  { path: `${S}/Config/Access`, kind: 'admin',
    note: 'Manager saveConfig: multi-path update (+ grandfathered Access rows)' },
  { path: `${S}/Access/someUid`, kind: 'admin',
    note: 'Manager grant / approve / reject / revoke: transaction + multi-path update' },
  { path: `${S}/AccessClaims/someUid/-pushId/Resolved`, kind: 'admin',
    note: 'Manager approve / reject: claim Resolved patch' },
  { path: 'Fantasy/Templates/Access/claimAdmin', kind: 'admin',
    note: 'Manager saveTemplate: set; resetTemplate: remove' },
  { path: 'Fantasy/Templates/Access/AdminEmail', kind: 'admin',
    note: 'Manager saveAdminEmail: set' },
];

/** The paid-access gate (spec §5) appended to the Squads/$uid and
 *  Managers/$uid .write expressions: a client save needs the season NOT in
 *  pass mode, or an active Access record for that uid. Admin SDK writes
 *  (functions) bypass rules. */
const ACCESS_GATE =
  "(root.child('Fantasy/' + $sport + '/' + $season + '/Config/Access/Mode').val() !== 'pass' || " +
  "root.child('Fantasy/' + $sport + '/' + $season + '/Access/' + $uid + '/Status').val() === 'active')";

// ── Rules walking ───────────────────────────────────────────────────────────

function repoRoot(): string {
  let dir = process.cwd();
  for (; ;) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) {
      throw new Error(`Could not find the Flutter repo root above ${process.cwd()}`);
    }
    dir = parent;
  }
}

function loadRules(file: string): Json {
  return JSON.parse(fs.readFileSync(path.join(repoRoot(), file), 'utf8'));
}

interface ChainLink {
  /** The rules node's location, wildcards as written (e.g. Squads/$uid). */
  at: string;
  write: unknown;
}

/** Every `.write` on [p]'s chain, root first, plus the wildcard bindings
 *  ($name -> path segment). A literal child wins over a $wildcard sibling,
 *  as in RTDB; segments past the deepest rules node add nothing. */
function writeChain(rules: Json, p: string): {
  links: ChainLink[]; bindings: Record<string, string>;
} {
  const links: ChainLink[] = [];
  const bindings: Record<string, string> = {};
  let node: Json | undefined = rules['rules'];
  const at: string[] = [];
  if (node && '.write' in node) links.push({ at: '/', write: node['.write'] });
  for (const seg of p.split('/')) {
    if (!node) break;
    let next: Json | undefined;
    if (Object.prototype.hasOwnProperty.call(node, seg) && !seg.startsWith('$') &&
      !seg.startsWith('.')) {
      next = node[seg];
      at.push(seg);
    } else {
      const wild = Object.keys(node).find((k) => k.startsWith('$'));
      if (wild !== undefined) {
        next = node[wild];
        bindings[wild] = seg;
        at.push(wild);
      }
    }
    if (next === undefined) break;
    node = next;
    if ('.write' in node) links.push({ at: at.join('/'), write: node['.write'] });
  }
  return { links, bindings };
}

const ADMIN_GATE = "root.child('Admins').child(auth.uid)";

function grants(kind: Kind, link: ChainLink, bindings: Record<string, string>): boolean {
  const w = link.write;
  if (typeof w !== 'string') return false; // `false` (or junk) grants nothing
  switch (kind) {
    case 'admin':
      return w.includes(ADMIN_GATE);
    case 'own': {
      const re = /auth\.uid\s*={2,3}\s*(\$\w+)|(\$\w+)\s*={2,3}\s*auth\.uid/g;
      for (const m of w.matchAll(re)) {
        if (bindings[m[1] ?? m[2]] === 'UID') return true;
      }
      return false;
    }
    case 'ownerCreate':
      return /newData\.child\('Owner'\)\.val\(\)\s*={2,3}\s*auth\.uid/.test(w);
  }
}

const RULES_FILES = ['database.rules.stage1.json', 'database.rules.json'];

for (const file of RULES_FILES) {
  describe(`rules contract: ${file}`, () => {
    const rules = loadRules(file);

    it.each(CONTRACT.map((e) => [e.path, e] as const))(
      'grants the client write %s', (p, entry) => {
        const { links, bindings } = writeChain(rules, p);
        const ok = links.some((l) => grants(entry.kind, l, bindings));
        expect(ok, `${file}: NO ${entry.kind} .write grant for client write path ` +
          `"${p}" (${entry.note}); chain .write rules seen: ` +
          `${JSON.stringify(links)}`).toBe(true);
      });

    // The C1 shape: the owner may set/remove the VOID flag and the Manual
    // flag, and nothing else under PriceChanges (the server's
    // {name: {delta}} rows are functions-only). A grant at PriceChanges/<gw>
    // or above would let an admin client rewrite the published moves.
    it('PriceChanges: admin writes ONLY <gw>/Manual (validated true), never the delta rows', () => {
      for (const p of [`${S}/PriceChanges`, `${S}/PriceChanges/5`, `${S}/PriceChanges/5/Some Player`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
      const manual = rules['rules']['Fantasy']['$sport']['$season']['PriceChanges']['$gw']['Manual'];
      expect(manual['.validate']).toBe('newData.val() === true');
    });

    // SQUAD HARDENING (audit I2/I3, owner-approved 2026-11-01): a client
    // save of Squads/<uid> must be squad-SHAPED (picks + captainId + viceId,
    // each pick playerId <= 60 / priceTenths number / bench bool, at most
    // squadSize picks) and must land BEFORE the lock by Firebase's SERVER
    // clock (`now`) — so a skewed phone clock or a REST write can't edit a
    // locked week.
    //
    // UNCOUNTED SAVES (FPL selling plan Task 5, owner 2026-11-03 "do
    // both"; fix round 1): the save trigger (recordSquadSave) counts
    // transfers only while GwState says 'open' and before lockAtUtc (or
    // under the effective 'open' override while GwState says 'open'); it
    // stands down under a 'locked' override. So a save is accepted only:
    //   - with no GwState yet (the season hasn't started);
    //   - while GwState says 'open' AND the server clock is before
    //     lockAtUtc (the counted window);
    //   - once 24 h have passed since the stored lockAtUtc while GwState
    //     still says 'locked'/'finalized' — the fan app reopens the next
    //     week exactly at lock + 24 h (gameweeks.dart currentGameweek), a
    //     sweep may flip GwState up to 15 min later, and a save refused in
    //     that gap would drop the fan's edits;
    //   - under the owner's effective 'open' lockOverride.
    // 'locked'/'finalized' before lock + 24 h used to accept saves the
    // trigger never counted (the app shows that window as locked; only a
    // REST write could use it) — now refused. Saves the trigger misses
    // (the +24 h gap, a 'locked' override before the lock, an 'open'
    // override after GwState left 'open', a failed trigger) are caught by
    // the next lock's recount, which is charged AND persisted into
    // TransferState.UsedThisGw (transfer_state.ts lockAccounting usedByUid,
    // orchestration.ts freezeLockTransferState).
    //
    // A delete (null) skips .validate, so a deadline sits on .write for
    // deletes only (`newData.exists() || <window>`): nobody wipes a squad
    // between the lock and the sweep's snapshot (the client never deletes a
    // squad; the server's own deletes bypass rules). That delete gate keeps
    // the ORIGINAL deadline group verbatim (review ruling, Task 5 — "the
    // delete gate stays"). Admin SDK writes (functions) bypass rules
    // entirely, so the Free Hit restore / chip switch-off still land.
    //
    // realizedTenths (FPL selling, spec §4) is the server's own number on
    // a LOCKED snapshot; a client may never write it on Squads/<uid> (a
    // malformed squad is snapshotted verbatim, so a planted value would
    // survive into the record). The fan app never sends it.
    //
    // KEEP IN SYNC WITH CONFIG: the pick-key regex hard-codes the squad
    // size (keys 0..squadSize-1 — RTDB lists are index-keyed, and rules have
    // no child count). It is pinned here against the futsal default
    // squadSize(Config); a Config formation change that grows the squad
    // must widen `$i.matches(/^[0-N]$/)` in BOTH rules files (single digit:
    // up to 10 picks).
    it('Squads/$uid: .validate pins the squad shape and the server-clock deadline', () => {
      const uidNode = rules['rules']['Fantasy']['$sport']['$season']['Squads']['$uid'];
      // The owner-only read grant is unchanged; the write grant is the
      // owner's, plus the deadline for deletes (a null write skips
      // .validate).
      expect(uidNode['.read']).toBe('auth != null && auth.uid == $uid');
      const w = String(uidNode['.write'] ?? '');
      expect(w.startsWith('auth != null && auth.uid == $uid && (newData.exists() || ')).toBe(true);

      const gw = "root.child('Fantasy/' + $sport + '/' + $season + '/GwState";
      const cfgP = "root.child('Fantasy/' + $sport + '/' + $season + '/Config";
      const openOverride =
        `(${cfgP}/lockOverride').val() === 'open' && ` +
        `(!${cfgP}/lockOverrideUntil').isNumber() || now < ${cfgP}/lockOverrideUntil').val()))`;
      // The squad shape (unchanged since the hardening round).
      const shape =
        "newData.hasChildren(['picks', 'captainId', 'viceId']) && " +
        "newData.child('captainId').isString() && newData.child('captainId').val().length <= 60 && " +
        "newData.child('viceId').isString() && newData.child('viceId').val().length <= 60";
      // The save window: no GwState, OR (open AND before the lock), OR (not
      // open AND 24 h past the stored lock — the app's own reopen), OR the
      // effective 'open' override — and nothing else.
      const saveWindow =
        `(!${gw}').exists() || ` +
        `(${gw}/status').val() === 'open' && now < ${gw}/lockAtUtc').val()) || ` +
        `(${gw}/status').val() !== 'open' && now >= ${gw}/lockAtUtc').val() + 86400000) || ` +
        `${openOverride})`;
      expect(uidNode['.validate'], `${file}: Squads/$uid .validate`)
        .toBe(`${shape} && ${saveWindow}`);
      // The delete gate keeps its ORIGINAL deadline group verbatim (review
      // ruling), then the paid-access gate (spec 2026-11-01 §5).
      const deleteWindow =
        `(!${gw}').exists() || ${gw}/status').val() !== 'open' || ` +
        `now < ${gw}/lockAtUtc').val() || ${openOverride})`;
      expect(w).toBe(
        `auth != null && auth.uid == $uid && (newData.exists() || ${deleteWindow}) && ${ACCESS_GATE}`);
      // A client never writes the server's realizedTenths.
      expect(uidNode['realizedTenths'], `${file}: Squads/$uid lets a client write realizedTenths`)
        .toEqual({ '.validate': false });

      const pick = String(uidNode['picks']?.['$i']?.['.validate'] ?? '');
      const n = squadSize(configFromMap({}));
      expect(n).toBeLessThanOrEqual(10); // the single-digit key regex
      expect(pick).toContain(`$i.matches(/^[0-${n - 1}]$/)`);
      expect(pick).toContain("newData.child('playerId').isString()");
      expect(pick).toContain("newData.child('playerId').val().length <= 60");
      expect(pick).toContain("newData.child('priceTenths').isNumber()");
      expect(pick).toContain("newData.child('bench').isBoolean()");
    });

    // TRANSFERS IN-APP (plan 2026-11-03 Task 2): the squad's chip is one of
    // the four chip names and nothing else (it used to be any string, so a
    // REST write could plant 'superSub' and the Wildcard / Free Hit /
    // Triple Captain / Bench Boost handling downstream would misread it).
    // `.validate` only runs on NON-null new data, so removing the field (the
    // chip switch-off / a save with no chip) stays allowed. TransferState
    // stays server-written: no client `.write` anywhere on its chain, so a
    // fan can't forge the transfer budget the app shows.
    it('Squads/$uid/chip: .validate pins the four chip names; TransferState has no client write', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(season['Squads']['$uid']['chip'], `${file}: Squads/$uid/chip`).toEqual({
        '.validate':
          "newData.isString() && newData.val().matches(/^(tripleCaptain|benchBoost|wildcard|freeHit)$/)",
      });
      const ts = season['TransferState'];
      expect(ts, `${file}: no TransferState rules`).toBeDefined();
      expect(ts['.write']).toBeUndefined();
      expect(ts['$uid']['.write']).toBeUndefined();
      for (const p of [`${S}/TransferState`, `${S}/TransferState/UID`,
        `${S}/TransferState/UID/UsedThisGw`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
    });

    // PAID ACCESS (spec 2026-11-01 §4–§6, plan A5): the Squads/Managers gate
    // on both nodes; Access = admin-written, own-or-admin read; AccessClaims =
    // fan create-only with a validated shape, admin resolve; Templates/Access
    // = admin only. The fan app and the Manager are built against these.
    it('paid access: Squads/$uid and Managers/$uid .write end with the Mode/Status gate', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(String(season['Squads']['$uid']['.write']).endsWith(` && ${ACCESS_GATE}`)).toBe(true);
      expect(season['Managers']['$uid']['.write'])
        .toBe(`auth != null && auth.uid == $uid && ${ACCESS_GATE}`);
      // The gate never leaks into .validate (validate binds admins too; an
      // admin client write to Managers/<uid>/NameFlagged must still land).
      expect(String(season['Managers']['$uid']['.validate'])).not.toContain('Config/Access');
      expect(String(season['Squads']['$uid']['.validate'])).not.toContain('Config/Access');
    });

    it('paid access: Access is admin-written, whole-node admin read, own-or-admin per uid', () => {
      const access = rules['rules']['Fantasy']['$sport']['$season']['Access'];
      expect(String(access['.read'])).toContain(ADMIN_GATE);
      expect(String(access['.write'])).toContain(ADMIN_GATE);
      expect(access['$uid']['.read'])
        .toBe("auth != null && (auth.uid == $uid || root.child('Admins').child(auth.uid).exists())");
      expect(access['$uid']['.write']).toBeUndefined(); // the fan never writes their own record
    });

    it('paid access: AccessClaims — fan create-only own claim, validated; admin resolves', () => {
      const claims = rules['rules']['Fantasy']['$sport']['$season']['AccessClaims'];
      expect(String(claims['.read'])).toContain(ADMIN_GATE);
      expect(String(claims['.write'])).toContain(ADMIN_GATE);
      expect(claims['$uid']['.read'])
        .toBe("auth != null && (auth.uid == $uid || root.child('Admins').child(auth.uid).exists())");
      expect(claims['$uid']['$key']['.write'])
        .toBe('auth != null && auth.uid == $uid && !data.exists() && newData.exists()');
      const v = String(claims['$uid']['$key']['.validate']);
      expect(v).toContain("newData.hasChildren(['Method', 'AmountDollars', 'At'])");
      expect(v).toContain("newData.child('Method').val().matches(/^(venmo|zelle)$/)");
      // Cash is recorded by an admin (Access/<uid> Via 'cash'); a fan can't claim it.
      expect(v).not.toContain('cash');
      expect(v).toContain("newData.child('AmountDollars').isNumber()");
      expect(v).toContain("newData.child('AmountDollars').val() >= 0");
      expect(v).toContain("newData.child('At').isNumber()");
      expect(v).toContain("(!newData.hasChild('Note') || (newData.child('Note').isString() && newData.child('Note').val().length <= 120))");
      // Only an admin may write the resolution / notification fields.
      expect(v).toContain(`(${ADMIN_GATE}.exists() || (!newData.hasChild('Resolved')`);
    });

    it('paid access: Fantasy/Templates/Access is admin read + write (a literal child, not a $sport)', () => {
      const templates = rules['rules']['Fantasy']['Templates']['Access'];
      expect(String(templates['.read'])).toContain(ADMIN_GATE);
      expect(String(templates['.write'])).toContain(ADMIN_GATE);
    });

    // FPL SELLING (spec §4, plan Task 3): Baselines/<uid> = { ForGw,
    // RealizedTenths, Prices } is the server's own money record (written
    // by functions at each lock + finalize). A fan reads his own (the squad
    // builder's budget), an admin reads the node, NOBODY writes — exactly
    // TransferState's shape. A client write here would forge the budget
    // the app shows.
    it('Baselines: admin reads the node, a fan reads only his own, no client write', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      const b = season['Baselines'];
      expect(b, `${file}: no Baselines rules`).toBeDefined();
      expect(b['.read']).toBe("auth != null && root.child('Admins').child(auth.uid).exists()");
      expect(b['$uid']['.read']).toBe('auth != null && auth.uid == $uid');
      expect(b['.write']).toBeUndefined();
      expect(b['$uid']['.write']).toBeUndefined();
      expect(b).toEqual(season['TransferState']);
    });

    // LIVE (live design 2026-11-03 §5, plan Task 3): Live/** is the server's
    // provisional gameweek (Meta/Board/Players/Squads/TeamOfWeek, or the
    // settled tombstone) — any signed-in user reads it, NOBODY writes it
    // (functions only, Admin SDK). LiveBase/<gw> is its functions-only
    // settled base: admin read (TransferState's node read), no client
    // write anywhere on either chain.
    it('Live: signed-in read, no client write; LiveBase: admin read only, no client write', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(season['Live'], `${file}: Live`).toEqual({ '.read': 'auth != null' });
      expect(season['LiveBase'], `${file}: LiveBase`).toEqual({
        '.read': "auth != null && root.child('Admins').child(auth.uid).exists()",
      });
      expect(season['LiveBase']['.read']).toBe(season['TransferState']['.read']);
      for (const p of [`${S}/Live`, `${S}/Live/Meta`, `${S}/Live/Board/UID`,
        `${S}/Live/Squads/UID`, `${S}/LiveBase`, `${S}/LiveBase/3`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
    });

    // SEASON SETUP + SCHEDULE (plan 2026-11-05, Task 3): the Manager writes
    // the owner's Config/Deadlines/<date> and Config/SkippedDates/<date> —
    // every grant on their chain is the admin gate, so a fan can never move
    // a deadline or skip a game day. LockedWeeks/<n> = {Date, LockAtUtc,
    // Scored?} is the server's frozen-week ledger (functions only, Admin
    // SDK): any signed-in user reads it (the apps' week lists), NOBODY
    // writes it.
    it('Config/Deadlines + SkippedDates: admin write only; LockedWeeks: signed-in read, no client write', () => {
      for (const p of [`${S}/Config/Deadlines/10042026`, `${S}/Config/SkippedDates/10042026`]) {
        const { links, bindings } = writeChain(rules, p);
        const grantsSeen = links.filter((l) => typeof l.write === 'string' && l.write !== 'false');
        expect(grantsSeen.length, `${file}: no .write on ${p}`).toBeGreaterThan(0);
        for (const l of grantsSeen) {
          expect(String(l.write), `${file}: non-admin .write at ${l.at} for ${p}`)
            .toContain(ADMIN_GATE);
        }
        expect(links.some((l) => grants('own', l, bindings) ||
          grants('ownerCreate', l, bindings)), `${file}: fan grant on ${p}`).toBe(false);
      }
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(season['LockedWeeks'], `${file}: LockedWeeks`).toEqual({ '.read': 'auth != null' });
      for (const p of [`${S}/LockedWeeks`, `${S}/LockedWeeks/3`, `${S}/LockedWeeks/3/Scored`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
    });

    it('Voided: public read, admin write, each <gw> validated true', () => {
      const voided = rules['rules']['Fantasy']['$sport']['$season']['Voided'];
      expect(voided['.read']).toBe(true);
      expect(String(voided['.write'])).toContain(ADMIN_GATE);
      expect(voided['$gw']['.validate']).toBe('newData.val() === true');
    });
  });
}

describe('rules contract: the walker itself', () => {
  const rules = loadRules('database.rules.json');

  it('a functions-only path has no client grant (the check can fail)', () => {
    for (const p of [`${S}/History/3/someUid`, `${S}/BadgePushClaims/u/a`,
      `${S}/TransferState/UID`, `${S}/Repriced/5`, `${S}/Baselines/UID`,
      `${S}/Baselines/UID/RealizedTenths`, `${S}/Baselines/UID/Prev`,
      `${S}/Live/Board/UID`, `${S}/LiveBase/3`, `${S}/LockedWeeks/3`]) {
      const { links, bindings } = writeChain(rules, p);
      for (const kind of ['admin', 'own', 'ownerCreate'] as const) {
        expect(links.some((l) => grants(kind, l, bindings)), `${p} ${kind}`).toBe(false);
      }
    }
  });

  it("paid access: a fan has no 'own' grant on their Access record or another uid's claims", () => {
    for (const p of [`${S}/Access/UID`, `${S}/AccessClaims/otherUid/-pushId`]) {
      const { links, bindings } = writeChain(rules, p);
      expect(links.some((l) => grants('own', l, bindings)), p).toBe(false);
    }
  });

  it("'own' binds to the writer's uid only — another uid's squad is not granted", () => {
    const { links, bindings } = writeChain(rules, `${S}/Squads/otherUid`);
    expect(links.some((l) => grants('own', l, bindings))).toBe(false);
  });
});

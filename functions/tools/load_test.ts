// Infinite Fantasy — repeatable LOAD TEST of the 15-minute lifecycle sweep.
//
// WHAT IT DOES
//   Replays Season 15 on a simulated clock through the REAL engine
//   (rehearse_s15.ts runReplay: runLifecycleSweep every 15 minutes,
//   maybeFinalizeGame, runMondayReprice, recordSquadSave) with N made-up
//   managers (load-0001.., "Load Team N"), and measures what every
//   runLifecycleSweep READS from the database: the JSON bytes of every value
//   a read hands back, per sweep and by path (week numbers and manager uids
//   collapsed), plus how many reads were of the whole `Fantasy` node (the
//   expensive one — must be 0).
//
// HOW IT MEASURES
//   runReplay takes an optional sweepDb hook; the sweep gets a counting
//   wrapper around the replay's db instead of the db itself. The wrapper
//   counts read (JSON bytes), exists (about 1 KB — production downloads at
//   most one child), childKeys (the JSON of the keys array). It offers
//   childKeys even though the in-memory db has none, answering from the
//   node WITHOUT counting the node: production's rtdbFantasyDb has the
//   keys-only `?shallow=true` read, so that is what is being measured (the
//   fallback when it fails is pinned by the engine's own tests). Writes,
//   writeIfAbsent and transactions pass through uncounted.
//
// The replay plays the league's Finished flag like production: false while
// the season is played, flipped on two hours after the last game goes final
// (rehearse_s15.ts finishedAtEnd). The snapshot's season is already over, and
// left that way every sweep would also read the whole History and Badges.
//
// SAFETY: in-memory only. The replay never writes anywhere and closes the
// network once its snapshot is loaded (see rehearse_s15.ts).
//
// RUN (from functions/):
//   npm run loadtest -- 250                the rehearsal's public GET snapshot
//                                          (rehearsal_out/snapshot.json), replay
//   npm run loadtest -- 1000 --offline     the cached fill snapshot, no network
// Prints one JSON report; the exit code is 1 when anything crashed, an
// invariant failed, or any sweep still read the whole Fantasy node.

import type { FantasyDb } from '../src/lib/fantasy/orchestration_db';
import { childEntries } from '../src/lib/fantasy/orchestration_db';
import { loadSnapshot, runReplay } from './rehearse_s15';

const MB = 1_048_576;

/** What an `exists` is counted as: production downloads at most one child. */
export const EXISTS_BYTES = 1024;

const USAGE = 'Usage: npm run loadtest -- <managers> [--offline]   (managers: a whole number >= 1)';

export interface SweepReads {
  /** The sweep's simulated time (ISO). */
  at: string;
  bytes: number;
  wholeFantasyReads: number;
}

export interface PathTotal { bytes: number; calls: number }

/** `Fantasy/Futsal/15/History/3/load-0042` -> `History/<n>/<uid>`: the season
 *  prefix dropped, week/season numbers and fake-manager uids collapsed so a
 *  path names a KIND of read, not one manager's. */
export function collapsePath(p: string): string {
  return p.replace(/^\/+|\/+$/g, '')
    .replace(/^Fantasy\/[^/]+\/\d+\//, '')
    .split('/')
    .map((seg) => (/^\d+$/.test(seg) ? '<n>' : /^(load|test)-\d+$/.test(seg) ? '<uid>' : seg))
    .join('/');
}

function isWholeFantasy(p: string): boolean {
  return p.replace(/^\/+|\/+$/g, '') === 'Fantasy';
}

const bytesOf = (v: unknown): number => (v == null ? 0 : Buffer.byteLength(JSON.stringify(v)));

/** [db] with every read counted into [rec] (this sweep) and [byPath] (the
 *  whole run). See the header for what each member counts. */
export function countingDb(
  db: FantasyDb, rec: SweepReads, byPath: Map<string, PathTotal>,
): FantasyDb {
  const add = (op: string, p: string, bytes: number) => {
    rec.bytes += bytes;
    const key = `${op}:${collapsePath(p)}`;
    const t = byPath.get(key) ?? { bytes: 0, calls: 0 };
    t.bytes += bytes;
    t.calls++;
    byPath.set(key, t);
  };
  return {
    async read(p) {
      const v = await db.read(p);
      add('read', p, bytesOf(v));
      if (isWholeFantasy(p)) rec.wholeFantasyReads++;
      return v;
    },
    async exists(p) {
      const found = await db.exists(p);
      add('exists', p, EXISTS_BYTES);
      return found;
    },
    async childKeys(p) {
      const keys = db.childKeys
        ? await db.childKeys(p)
        : childEntries(await db.read(p)).map(([k]) => k);
      add('childKeys', p, bytesOf(keys));
      return keys;
    },
    write: (p, v) => db.write(p, v),
    writeIfAbsent: (p, v) => db.writeIfAbsent(p, v),
    transaction: (p, update) => db.transaction(p, update),
  };
}

/** One record per sweep, in simulated order (sweeps run one after another,
 *  so a record is complete when the next sweep starts), plus the by-path
 *  totals for the whole run. */
export class ReadMeter {
  readonly sweeps: SweepReads[] = [];
  readonly byPath = new Map<string, PathTotal>();

  /** The runReplay `sweepDb` hook. */
  wrap = (db: FantasyDb, now: Date): FantasyDb => {
    const rec: SweepReads = { at: now.toISOString(), bytes: 0, wholeFantasyReads: 0 };
    this.sweeps.push(rec);
    return countingDb(db, rec, this.byPath);
  };
}

/** Nearest-rank percentile (p in 0..1) of [values]; 0 for none. */
export function percentile(values: readonly number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(p * sorted.length) - 1)];
}

export interface LoadTestReport {
  managers: number;
  crashes: number;
  invariantFailures: number;
  /** The replay's expected-ledger cross-check: reported, not a gate (the
   *  fill tool treats it the same way). */
  ledgerMismatches: number;
  sweeps: number;
  wholeFantasyReads: number;
  perSweepMB: { median: number; p95: number; max: number };
  topPaths: Array<{ path: string; MB: number; calls: number }>;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

export function summarize(
  managers: number,
  result: { crashes: number; invariantFailures: number; ledgerMismatches: number },
  meter: ReadMeter, topN = 12,
): { report: LoadTestReport; failed: boolean } {
  const perSweep = meter.sweeps.map((s) => s.bytes);
  const wholeFantasyReads = meter.sweeps.reduce((a, s) => a + s.wholeFantasyReads, 0);
  const report: LoadTestReport = {
    managers,
    crashes: result.crashes,
    invariantFailures: result.invariantFailures,
    ledgerMismatches: result.ledgerMismatches,
    sweeps: meter.sweeps.length,
    wholeFantasyReads,
    perSweepMB: {
      median: round2(percentile(perSweep, 0.5) / MB),
      p95: round2(percentile(perSweep, 0.95) / MB),
      max: round2(percentile(perSweep, 1) / MB),
    },
    topPaths: [...meter.byPath.entries()]
      .sort((a, b) => b[1].bytes - a[1].bytes)
      .slice(0, topN)
      .map(([path, t]) => ({ path, MB: round2(t.bytes / MB), calls: t.calls })),
  };
  const failed = result.crashes > 0 || result.invariantFailures > 0 || wholeFantasyReads > 0;
  return { report, failed };
}

const loadUid = (i: number) => `load-${String(i + 1).padStart(4, '0')}`;

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const offline = args.includes('--offline');
  const rest = args.filter((a) => a !== '--offline');
  if (rest.length !== 1 || !/^\d+$/.test(rest[0]) || Number(rest[0]) < 1) throw new Error(USAGE);
  const managers = Number(rest[0]);

  const meter = new ReadMeter();
  const result = await runReplay({
    offline,
    managerCount: managers,
    // --offline: the fill tool's cached snapshot. Otherwise runReplay takes
    // the rehearsal's own public GET snapshot (read-only, network guarded).
    snapshot: offline ? await loadSnapshot(true, { file: 'fill_snapshot.json' }) : undefined,
    names: Array.from({ length: managers }, (_, i) => `Load Team ${i + 1}`),
    uidOf: loadUid,
    sweepDb: meter.wrap,
    // The snapshot's season is already Finished; production's is not until
    // the end, and a Finished-but-unsettled season costs every sweep a full
    // History + Badges read that a live season never pays.
    finishedAtEnd: true,
  });

  const failures = Object.entries(result.invariantFailures).filter(([, f]) => f.length > 0);
  const { report, failed } = summarize(managers, {
    crashes: result.crashes.length,
    invariantFailures: failures.reduce((a, [, f]) => a + f.length, 0),
    ledgerMismatches: result.managerLedgerMismatches,
  }, meter);
  console.log(JSON.stringify(report, null, 1));

  for (const [k, f] of failures) for (const m of f.slice(0, 3)) console.error(`invariant ${k}: ${m}`);
  for (const c of result.crashes.slice(0, 3)) {
    console.error(`crash ${c.at} ${c.job}: ${c.error.split('\n')[0]}`);
  }
  if (report.wholeFantasyReads > 0) {
    console.error(`${report.wholeFantasyReads} sweep read(s) of the whole Fantasy node.`);
  }
  process.exitCode = failed ? 1 : 0;
}

// Run only when executed directly (npm run loadtest) — the test imports the
// meter without triggering it.
if (typeof require !== 'undefined' && require.main === module) {
  main().catch((err) => {
    console.error((err as Error)?.stack ?? String(err));
    process.exitCode = 1;
  });
}

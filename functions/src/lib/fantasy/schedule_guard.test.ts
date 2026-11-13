// Schedule guard (season setup + schedule changes, Task 2): ONE place decides
// the gameweek list and ONE place formats a deadline.
//
//  - Every server job gets its gameweeks from loadSeasonGameweeks
//    (orchestration_db.ts), which feeds deriveGameweeks the frozen weeks
//    (LockedWeeks), the owner's skips / deadline overrides and the real
//    kickoff times. A job that calls deriveGameweeks(dateKeysOf(...), cfg)
//    itself silently ignores all of that: its week list, its lock instants
//    and its deadline text drift from what the managers see.
//  - A deadline is formatted from the real lock INSTANT
//    (formatDeadlineInstant, pushes.ts). The old formatDeadline(date,
//    lockHour) rebuilt it from the config lock hour and so lied the moment a
//    deadline was overridden or pulled in before an early kickoff.
//  - cfg.lockHour is only the AUTOMATIC deadline's default; only the engine
//    (gameweeks.ts) and the config parser (fantasy_config.ts) may read it.
//    news.ts has its own publish slot and never reads it, so it is
//    whitelisted for the day it needs to. season_start.ts is whitelisted
//    because the Manager's Start preview SHOWS the setting a new season
//    copies (settings.lockHour); it never computes a deadline from it.
//
// This test greps the non-test sources under functions/src and names every
// offending file:line, so a future change that reintroduces one of these
// fails here with the place to fix.

import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

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

const SRC = path.join(repoRoot(), 'functions', 'src');

/** Every non-test .ts file under functions/src, as a '/'-separated path
 *  relative to it. */
function sourceFiles(dir: string = SRC): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...sourceFiles(full));
    } else if (entry.name.endsWith('.ts') && !entry.name.endsWith('.test.ts')) {
      out.push(path.relative(SRC, full).split(path.sep).join('/'));
    }
  }
  return out.sort();
}

/** A line that is only a comment (// ..., /* ..., * ...): prose may mention a
 *  banned call when it explains why it is banned. */
function isCommentLine(line: string): boolean {
  const t = line.trim();
  return t.startsWith('//') || t.startsWith('/*') || t.startsWith('*');
}

/** 'file:line  <code>' for every code line matching [pattern] in a file that
 *  is not whitelisted (a whitelisted entry is a basename). */
function offenders(pattern: RegExp, allowedBasenames: string[]): string[] {
  const hits: string[] = [];
  for (const file of sourceFiles()) {
    if (allowedBasenames.includes(path.posix.basename(file))) continue;
    const lines = fs.readFileSync(path.join(SRC, file), 'utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      if (!isCommentLine(line) && pattern.test(line)) {
        hits.push(`functions/src/${file}:${i + 1}  ${line.trim()}`);
      }
    });
  }
  return hits;
}

function failure(rule: string, hits: string[]): string {
  return `${rule}\n  ${hits.join('\n  ')}`;
}

describe('schedule guard', () => {
  it('the guard sees the source tree (a wrong root must not pass vacuously)', () => {
    const files = sourceFiles();
    expect(files).toContain('lib/fantasy/gameweeks.ts');
    expect(files).toContain('lib/fantasy/orchestration_db.ts');
    expect(files).toContain('lib/fantasy/orchestration.ts');
    expect(files.some((f) => f.endsWith('.test.ts'))).toBe(false);
  });

  it('deriveGameweeks( is called only by gameweeks.ts and orchestration_db.ts', () => {
    const hits = offenders(/\bderiveGameweeks\(/,
      ['gameweeks.ts', 'orchestration_db.ts']);
    expect(hits, failure(
      'Get the week list from loadSeasonGameweeks(db, sport, season, cfg, ' +
      'configNode) (orchestration_db.ts), never deriveGameweeks(dateKeysOf(' +
      '...), cfg) — it ignores the frozen weeks, skips, deadline overrides ' +
      'and kickoff times. Offending call sites:', hits)).toEqual([]);
  });

  it('formatDeadline( no longer exists', () => {
    const hits = offenders(/\bformatDeadline\(/, []);
    expect(hits, failure(
      'Format the deadline from the real lock instant: ' +
      'formatDeadlineInstant(gw.lockUtc.getTime()) (pushes.ts). ' +
      'Offending call sites:', hits)).toEqual([]);
  });

  it('cfg.lockHour is read only by gameweeks.ts, fantasy_config.ts, news.ts and season_start.ts', () => {
    const hits = offenders(/\.lockHour\b/,
      ['gameweeks.ts', 'fantasy_config.ts', 'news.ts', 'season_start.ts']);
    expect(hits, failure(
      'cfg.lockHour is only the automatic deadline default — read the ' +
      'gameweek\'s lockUtc instead (it also honours overrides and early ' +
      'kickoffs). Offending lines:', hits)).toEqual([]);
  });
});

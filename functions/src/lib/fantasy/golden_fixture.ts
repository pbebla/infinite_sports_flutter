// Test helper: loads test/fantasy/fixtures/golden_gameweek.json from the
// Flutter repo root (golden_replay.test.ts fixturePath parity). Used by the
// P4 orchestration tests so the finalize pipeline is exercised over the SAME
// pinned games/squads as the cross-engine golden replay.

import * as fs from 'fs';
import * as path from 'path';

export type Json = Record<string, any>;

export function loadGoldenFixture(): Json {
  let dir = process.cwd();
  for (; ;) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) {
      return JSON.parse(fs.readFileSync(path.join(
        dir, 'test', 'fantasy', 'fixtures', 'golden_gameweek.json'), 'utf8'));
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      throw new Error(
        'Could not find the Flutter repo root (pubspec.yaml) above ' +
        process.cwd());
    }
    dir = parent;
  }
}

/** Deep JSON clone — tests seed fake databases with fixture pieces and must
 *  never mutate the shared fixture object. */
export function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

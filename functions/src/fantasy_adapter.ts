// The real FantasyDb over an admin RTDB Reference (P4 Phases B–D). The whole
// job logic lives pure in src/lib/fantasy/orchestration.ts behind this seam
// so vitest never needs an emulator; this file is the only fantasy code that
// touches firebase-admin.

import * as logger from 'firebase-functions/logger';
import type { Reference } from 'firebase-admin/database';
import { FantasyDb } from './lib/fantasy/orchestration_db';
import { FantasyLogger } from './lib/fantasy/orchestration';

export function rtdbFantasyDb(root: Reference): FantasyDb {
  return {
    async read(path: string): Promise<unknown> {
      return (await root.child(path).get()).val();
    },
    async write(path: string, value: unknown): Promise<void> {
      if (value === null || value === undefined) {
        await root.child(path).remove();
      } else {
        await root.child(path).set(value);
      }
    },
    async writeIfAbsent(path: string, value: unknown): Promise<boolean> {
      // Raw transaction claim (index.ts claimKey parity) — only the writer
      // that finds null wins, so a snapshot can never be overwritten.
      const result = await root.child(path).transaction((cur) =>
        (cur === null ? value : undefined));
      return result.committed;
    },
  };
}

/** firebase-functions/logger behind the orchestration's injected seam. */
export const fantasyLogger: FantasyLogger = {
  info: (message, context) => logger.info(message, context ?? {}),
  warn: (message, context) => logger.warn(message, context ?? {}),
};

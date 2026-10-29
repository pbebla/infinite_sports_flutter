// The real FantasyDb + FantasyPusher over admin RTDB/FCM (P4 Phases B–F).
// The whole job logic lives pure in src/lib/fantasy/orchestration.ts behind
// these seams so vitest never needs an emulator; this file is the only
// fantasy code that touches firebase-admin.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import type { Reference } from 'firebase-admin/database';
import { chunk } from './lib/campaigns';
import { FantasyDb } from './lib/fantasy/orchestration_db';
import { FantasyLogger } from './lib/fantasy/orchestration';
import { FantasyPusher, FantasyUserPush } from './lib/fantasy/pushes';
import { anthropicApiKey } from './support_joke';

/** The shared ANTHROPIC_API_KEY (support_joke.ts defineSecret), read the
 *  way generateTicketJoke reads it: unbound/absent -> '' -> the news
 *  drafting skips itself (never a crash). The calling function must list
 *  the secret in its own options. */
export function readAnthropicKey(): string {
  try {
    return (anthropicApiKey.value() ?? '').trim();
  } catch {
    return '';
  }
}

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

const BRAND_COLOR = '#D00000'; // infiniteSportsPrimaryColor

/** Banner-pop delivery on the app's max-importance channel — shared by the
 *  per-user and topic sends (campaign_watch parity). */
const FCM_DISPLAY = {
  android: {
    priority: 'high' as const,
    notification: {
      channelId: 'infinite_sports_notifications',
      sound: 'default',
      color: BRAND_COLOR,
    },
  },
  apns: { payload: { aps: { sound: 'default' } } },
};

/** The real FantasyPusher over admin FCM (campaign_watch sendToUids
 *  conventions): resolves Users/<uid>/Token per message — uids without a
 *  stored token are skipped silently — sends personalized messages in
 *  batches of 500 on the app's max-importance channel, prunes tokens FCM
 *  reports dead, and dry-runs in the emulator. Topic sends (campaign_watch
 *  sendToTopic parity) count 1 when FCM accepts them; a failure is logged
 *  and counts 0. */
export function rtdbFantasyPusher(root: Reference): FantasyPusher {
  return {
    async sendToTopic(
      topic: string, title: string, body: string, data: Record<string, string>,
    ): Promise<number> {
      if (process.env.FUNCTIONS_EMULATOR === 'true') {
        logger.info('DRY-RUN fantasy topic push', { topic, title });
        return 1;
      }
      try {
        await admin.messaging().send({
          topic,
          notification: { title, ...(body ? { body } : {}) },
          data,
          ...FCM_DISPLAY,
        });
        return 1;
      } catch (err) {
        logger.warn('fantasy topic push failed', { topic, error: String(err) });
        return 0;
      }
    },
    async sendToUsers(messages: FantasyUserPush[]): Promise<number> {
      const withTokens: Array<{ msg: FantasyUserPush; token: string }> = [];
      await Promise.all(messages.map(async (msg) => {
        const snap = await root.child(`Users/${msg.uid}/Token`).get();
        const token = String(snap.val() ?? '').trim();
        if (token) withTokens.push({ msg, token });
      }));
      if (withTokens.length === 0) return 0;

      if (process.env.FUNCTIONS_EMULATOR === 'true') {
        logger.info('DRY-RUN fantasy push', {
          devices: withTokens.length, title: withTokens[0].msg.title,
        });
        return withTokens.length;
      }

      let sent = 0;
      for (const batch of chunk(withTokens, 500)) {
        const res = await admin.messaging().sendEach(batch.map(({ msg, token }) => ({
          token,
          notification: {
            title: msg.title, ...(msg.body ? { body: msg.body } : {}),
          },
          data: msg.data,
          ...FCM_DISPLAY,
        })));
        sent += res.successCount;
        // Prune tokens FCM says are gone so future sends stay clean.
        await Promise.all(res.responses.map(async (r, i) => {
          const code = r.error?.code ?? '';
          if (code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token') {
            await root.child(`Users/${batch[i].msg.uid}/Token`).remove()
              .catch(() => {});
          }
        }));
      }
      return sent;
    },
  };
}

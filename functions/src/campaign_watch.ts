import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { onValueCreated } from 'firebase-functions/v2/database';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import type { Reference } from 'firebase-admin/database';
import {
  audienceTopic, Campaign, chunk, isDue, parseCampaign,
} from './lib/campaigns';

const BRAND_COLOR = '#D00000';

/** Sends one campaign push to a topic. Mirrors sendAlert's channel/priority
 *  so campaigns banner-pop like match alerts; dry-runs in the emulator. */
async function sendToTopic(topic: string, c: Campaign): Promise<void> {
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    logger.info('DRY-RUN campaign topic send', { topic, title: c.title });
    return;
  }
  await admin.messaging().send({
    topic,
    notification: { title: c.title, ...(c.body ? { body: c.body } : {}) },
    data: c.data,
    android: {
      priority: 'high',
      notification: {
        channelId: 'infinite_sports_notifications',
        sound: 'default',
        color: BRAND_COLOR,
      },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  });
}

/** Sends to hand-picked users via their stored tokens. Returns how many
 *  devices accepted, and prunes tokens FCM reports as dead. */
async function sendToUids(
  root: Reference, uids: string[], c: Campaign,
): Promise<number> {
  const tokenByUid = new Map<string, string>();
  await Promise.all(uids.map(async (uid) => {
    const snap = await root.child(`Users/${uid}/Token`).get();
    const token = String(snap.val() ?? '').trim();
    if (token) tokenByUid.set(uid, token);
  }));
  if (tokenByUid.size === 0) return 0;

  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    logger.info('DRY-RUN campaign token send', {
      title: c.title, tokens: tokenByUid.size,
    });
    return tokenByUid.size;
  }

  const uidList = [...tokenByUid.keys()];
  let reached = 0;
  for (const uidBatch of chunk(uidList, 500)) {
    const tokens = uidBatch.map((uid) => tokenByUid.get(uid)!);
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: c.title, ...(c.body ? { body: c.body } : {}) },
      data: c.data,
      android: {
        priority: 'high',
        notification: {
          channelId: 'infinite_sports_notifications',
          sound: 'default',
          color: BRAND_COLOR,
        },
      },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    reached += res.successCount;
    // Prune tokens FCM says are gone so future sends stay clean.
    await Promise.all(res.responses.map(async (r, i) => {
      const code = r.error?.code ?? '';
      if (code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token') {
        await root.child(`Users/${uidBatch[i]}/Token`).remove().catch(() => {});
      }
    }));
  }
  return reached;
}

/** Claims and sends one campaign. The transaction flips pending->sending so
 *  the onCreate trigger and the scheduler can never double-send. */
async function processCampaign(
  root: Reference, id: string, c: Campaign,
): Promise<void> {
  const statusRef = root.child(`Campaigns/${id}/Status`);
  const claim = await statusRef.transaction((current) =>
    (current === 'pending' ? 'sending' : undefined));
  if (!claim.committed) return; // someone else claimed it

  try {
    let reached: number | null = null;
    const topic = audienceTopic(c.audience);
    if (topic) {
      await sendToTopic(topic, c);
      // Event audiences also cover people who RSVPed (Attend) but never
      // tapped Remind me: they aren't on the event topic, so reach them by
      // token. Reminder-subscribers are excluded to avoid double delivery.
      if (c.audience.type === 'event' && c.audience.eventId) {
        const base = root.child(`EventsV2/${c.audience.eventId}`);
        const [remSnap, attSnap] = await Promise.all([
          base.child('Reminders').get(),
          base.child('Attendees').get(),
        ]);
        const reminded = new Set(Object.keys(remSnap.val() ?? {}));
        const attendeesOnly = Object.keys(attSnap.val() ?? {})
          .filter((uid) => !reminded.has(uid));
        if (attendeesOnly.length > 0) {
          await sendToUids(root, attendeesOnly, c);
        }
      }
    } else {
      reached = await sendToUids(root, c.audience.uids ?? [], c);
    }
    await root.child(`Campaigns/${id}`).update({
      Status: 'sent',
      SentAt: admin.database.ServerValue.TIMESTAMP,
      ...(reached !== null ? { Reached: reached } : {}),
    });
    logger.info('campaign sent', { id, title: c.title, topic, reached });
  } catch (err) {
    logger.error('campaign failed', { id, error: String(err) });
    await root.child(`Campaigns/${id}`).update({
      Status: 'error',
      Error: String(err),
    }).catch(() => {});
  }
}

/** Immediate sends: fires when the manager creates a campaign. Scheduled
 *  campaigns (SendAt in the future) are left pending for the sweeper. */
export const onCampaignCreated = onValueCreated(
  { ref: '/Campaigns/{id}' },
  async (event) => {
    const campaign = parseCampaign(event.data.val());
    if (!campaign) {
      logger.warn('unparseable campaign', { id: event.params.id });
      return;
    }
    if (!isDue(campaign, Date.now())) return;
    await processCampaign(
      event.data.ref.root as Reference, event.params.id, campaign);
  },
);

/** Scheduled sends: sweeps pending campaigns whose time has come. */
export const processScheduledCampaigns = onSchedule(
  'every 5 minutes',
  async () => {
    const root = admin.database().ref();
    const snap = await root.child('Campaigns').get();
    const all = (snap.val() ?? {}) as Record<string, unknown>;
    const now = Date.now();
    for (const [id, raw] of Object.entries(all)) {
      const campaign = parseCampaign(raw);
      if (campaign && isDue(campaign, now)) {
        await processCampaign(root, id, campaign);
      }
    }
  },
);

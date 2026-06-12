import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import type { AlertDecision } from './decide';

export async function sendAlert(d: AlertDecision): Promise<void> {
  if (process.env.FUNCTIONS_EMULATOR === 'true') {
    // Emulator dress rehearsal: log instead of sending real pushes.
    logger.info('DRY-RUN sendAlert', {
      kind: d.kind, title: d.title, body: d.body, condition: d.condition, data: d.data,
    });
    return;
  }
  try {
    await admin.messaging().send({
      condition: d.condition,
      notification: { title: d.title, ...(d.body ? { body: d.body } : {}) },
      data: d.data,
      // High priority + the app's max-importance channel so alerts banner-pop
      // on Android instead of arriving silently in the tray.
      android: {
        priority: 'high',
        notification: {
          channelId: 'infinite_sports_notifications',
          sound: 'default',
        },
      },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    logger.info('sent', { kind: d.kind, title: d.title });
  } catch (err) {
    logger.error('sendAlert failed', { kind: d.kind, error: String(err) });
    throw err;
  }
}

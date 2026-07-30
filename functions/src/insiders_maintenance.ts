// Infinite Insiders daily tier-maintenance job (Task X2). Orchestration
// only — every decision is pure in src/lib/insiders.ts (maintenanceDecision).
// Runs once a day in America/Los_Angeles, following the existing scheduled-
// function pattern (campaign_watch.ts processScheduledCampaigns): inactivity
// reminders/warnings/drops and Infinite annual maintenance + calendar-year
// rollover.
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §2
// (tiers/inactivity/Infinite maintenance), §10 (automation — "Daily
// scheduled job ... inactivity reminders/warnings/drops; Infinite annual
// maintenance; year rollover"). Plan:
// docs/superpowers/plans/2026-07-27-infinite-insiders.md Task X2.

import * as logger from 'firebase-functions/logger';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import type { Reference } from 'firebase-admin/database';
import * as admin from 'firebase-admin';
import {
  MaintenanceDecision, maintenanceDecision, notificationFor,
} from './lib/insiders';
import { sendToInsider } from './insiders_watch';

/** True only on the one daily run that lands on Dec 31 or Jan 1 in
 *  America/Los_Angeles — the Infinite annual-maintenance window (spec §2)
 *  and the CurrentYearCount reset-for-everyone day. Computed here (not in
 *  lib/insiders.ts) so maintenanceDecision stays a plain-millis, Intl-free
 *  function that unit-tests with fixed fixtures and no timezone setup. */
export function isYearRolloverNow(nowMs: number): boolean {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Los_Angeles', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date(nowMs));
  const month = parts.find((p) => p.type === 'month')?.value;
  const day = parts.find((p) => p.type === 'day')?.value;
  return (month === '12' && day === '31') || (month === '01' && day === '01');
}

/** Applies one Insider's maintenance decision: writes the counter/stamp
 *  updates and sends the matching push, if any. Every write for one Insider
 *  goes through a single `.update()` so a mid-flight failure can't leave a
 *  half-applied state (e.g. Tier dropped but CurrentYearCount not reset). */
async function processInsider(
  root: Reference,
  uid: string,
  raw: Record<string, unknown>,
  nowMs: number,
  yearRollover: boolean,
): Promise<void> {
  if (raw['Status'] !== 'active') return;

  const standing = Number(raw['CurrentStanding'] ?? 0);
  const tier = Number(raw['Tier'] ?? 0);
  const lastReferralAtMs = Number(raw['LastReferralAt'] ?? 0);
  const currentYearCount = Number(raw['CurrentYearCount'] ?? 0);
  const lastReminderSentMs = raw['LastInactivityRemindedAt'] != null
    ? Number(raw['LastInactivityRemindedAt']) : null;
  const lastWarnSentMs = raw['LastInactivityWarnedAt'] != null
    ? Number(raw['LastInactivityWarnedAt']) : null;

  const decision: MaintenanceDecision = maintenanceDecision({
    standing,
    tier,
    lastReferralAtMs,
    currentYearCount,
    nowMs,
    lastReminderSentMs,
    lastWarnSentMs,
    isYearRollover: yearRollover,
    tzOffsetNote: 'America/Los_Angeles daily 06:00 run',
  });

  // Year rollover resets CurrentYearCount for EVERY active Insider (spec §2
  // "Year rollover also resets CurrentYearCount to 0 for ALL insiders") —
  // handled here by the trigger rather than as a maintenanceDecision output,
  // since it applies regardless of that Insider's own decision.action.
  const updates: Record<string, unknown> = yearRollover ? { CurrentYearCount: 0 } : {};

  switch (decision.action) {
    case 'none':
      if (Object.keys(updates).length > 0) await root.child(`Insiders/${uid}`).update(updates);
      return;

    case 'remind5mo':
      updates['LastInactivityRemindedAt'] = nowMs;
      await root.child(`Insiders/${uid}`).update(updates);
      await sendToInsider(root, uid, notificationFor({ type: 'maintenanceRemind' }));
      return;

    case 'warn2wk':
      updates['LastInactivityWarnedAt'] = nowMs;
      await root.child(`Insiders/${uid}`).update(updates);
      await sendToInsider(root, uid, notificationFor({ type: 'maintenanceWarn', tier }));
      return;

    case 'dropInactivity':
      updates['CurrentStanding'] = decision.newStanding;
      updates['Tier'] = decision.newTier;
      // Restart the inactivity clock at the moment of the drop (docstring on
      // maintenanceDecision explains why: otherwise a single stale
      // LastReferralAt would keep reading as ">=180 days ago" on every
      // future daily run and cascade into dropping tier after tier, instead
      // of the single "drop one tier" the spec describes).
      updates['LastReferralAt'] = nowMs;
      updates['LastInactivityRemindedAt'] = null;
      updates['LastInactivityWarnedAt'] = null;
      await root.child(`Insiders/${uid}`).update(updates);
      await sendToInsider(root, uid, notificationFor({
        type: 'maintenanceDropped', tier: decision.newTier as number,
      }));
      return;

    case 'dropInfiniteAnnual':
      updates['CurrentStanding'] = decision.newStanding;
      updates['Tier'] = decision.newTier;
      await root.child(`Insiders/${uid}`).update(updates);
      await sendToInsider(root, uid, notificationFor({
        type: 'infiniteMaintenanceDropped', currentYearCount,
      }));
      return;

    default:
      return;
  }
}

/** Daily Insiders tier-maintenance sweep (Task X2). Iterates every Insider
 *  regardless of tier — processInsider bails immediately for non-active
 *  status and maintenanceDecision itself is a no-op for tier 0/1 — so this
 *  stays correct as the Insiders list grows without needing a status-scoped
 *  RTDB query. */
export const insidersDailyMaintenance = onSchedule(
  { schedule: 'every day 06:00', timeZone: 'America/Los_Angeles' },
  async () => {
    const root = admin.database().ref();
    const nowMs = Date.now();
    const yearRollover = isYearRolloverNow(nowMs);

    const snap = await root.child('Insiders').get();
    const all = (snap.val() ?? {}) as Record<string, unknown>;

    for (const [uid, raw] of Object.entries(all)) {
      if (!raw || typeof raw !== 'object') continue;
      try {
        await processInsider(root, uid, raw as Record<string, unknown>, nowMs, yearRollover);
      } catch (err) {
        logger.error('insider maintenance failed', { uid, error: String(err) });
      }
    }

    logger.info('insider daily maintenance swept', {
      count: Object.keys(all).length, yearRollover,
    });
  },
);

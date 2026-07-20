import { sanitizeId } from './decide';

/** Owner-authored campaign written by the manager app to /Campaigns/<id>.
 *  Topic names MUST stay in parity with the fan app's
 *  lib/misc/notification_topics.dart (allUsersTopic/sportTopic/eventTopic). */

export interface CampaignAudience {
  type: 'all' | 'sport' | 'event' | 'users';
  sport?: string;
  eventId?: string;
  uids?: string[];
}

export interface Campaign {
  title: string;
  body: string;
  audience: CampaignAudience;
  data: Record<string, string>;
  sendAtMs: number;
  status: string;
}

/** Tolerant parse of a raw /Campaigns/<id> value. Returns null when the
 *  record can't be sent safely (missing title/audience). */
export function parseCampaign(raw: unknown): Campaign | null {
  if (raw === null || typeof raw !== 'object') return null;
  const c = raw as Record<string, unknown>;
  const title = String(c['Title'] ?? '').trim();
  if (!title) return null;

  const a = (c['Audience'] ?? {}) as Record<string, unknown>;
  const type = String(a['Type'] ?? '');
  if (!['all', 'sport', 'event', 'users'].includes(type)) return null;

  const audience: CampaignAudience = { type: type as CampaignAudience['type'] };
  if (type === 'sport') {
    audience.sport = String(a['Sport'] ?? '').trim();
    if (!audience.sport) return null;
  }
  if (type === 'event') {
    audience.eventId = String(a['EventId'] ?? '').trim();
    if (!audience.eventId) return null;
  }
  if (type === 'users') {
    const uidsRaw = a['Uids'];
    const uids: string[] = [];
    if (Array.isArray(uidsRaw)) {
      for (const u of uidsRaw) if (u) uids.push(String(u));
    } else if (uidsRaw && typeof uidsRaw === 'object') {
      for (const [uid, v] of Object.entries(uidsRaw as Record<string, unknown>)) {
        if (v) uids.push(uid);
      }
    }
    if (uids.length === 0) return null;
    audience.uids = uids;
  }

  const data: Record<string, string> = { type: 'campaign' };
  const dataRaw = c['Data'];
  if (dataRaw && typeof dataRaw === 'object') {
    for (const [k, v] of Object.entries(dataRaw as Record<string, unknown>)) {
      if (v !== null && v !== undefined) data[k] = String(v);
    }
  }

  return {
    title,
    body: String(c['Body'] ?? ''),
    audience,
    data,
    sendAtMs: Number(c['SendAt'] ?? 0) || 0,
    status: String(c['Status'] ?? 'pending'),
  };
}

/** The FCM topic for broadcast audiences; null for per-user (token) sends. */
export function audienceTopic(a: CampaignAudience): string | null {
  switch (a.type) {
    case 'all':
      return 'all_users';
    case 'sport':
      return `sport_${sanitizeId(a.sport ?? '')}`;
    case 'event':
      return `event_${sanitizeId(a.eventId ?? '')}`;
    case 'users':
      return null;
  }
}

/** Pending and its send time has arrived (SendAt 0 = immediately). */
export function isDue(c: Campaign, nowMs: number): boolean {
  return c.status === 'pending' && c.sendAtMs <= nowMs;
}

/** FCM multicast accepts at most 500 tokens per call. */
export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

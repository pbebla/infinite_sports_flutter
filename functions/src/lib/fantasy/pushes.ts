// Fantasy pushes (P4 Phase F) — the pure building blocks behind the
// deadline reminder, the send-now callable and the weekly recap. No
// firebase imports; the real FCM sender lives in src/fantasy_adapter.ts
// behind the FantasyPusher seam, and the scheduling/guard logic in
// orchestration.ts.
//
// Spec §12: deadline reminder (default Sunday noon, to managers with
// UNCHANGED squads; time/template/on-off owner-editable + a manual Send
// now), weekly recap "GW3: you scored 41, moved to #4, top score 52."
// Lock/price notices stay hub badges — never pushes.

import { parseDbDate } from './league_time';
import { childEntries, isPlainMap, toIntLoose } from './orchestration_db';

export interface FantasyUserPush {
  uid: string;
  title: string;
  body: string;
  data: Record<string, string>;
}

/** Injected FCM seam. The real adapter resolves each uid's stored token
 *  (Users/<uid>/Token), skips missing tokens silently, batches sends and
 *  prunes dead tokens; tests capture the messages. Returns the delivered
 *  count. */
export interface FantasyPusher {
  sendToUsers(messages: FantasyUserPush[]): Promise<number>;
}

/** Every fantasy push carries this payload — the future tap-routing hook. */
export function fantasyPushData(
  sport: string, season: string, gw: number,
): Record<string, string> {
  return { type: 'fantasy', sport, season, gw: String(gw) };
}

// ── Deadline reminder ───────────────────────────────────────────────────────

export const REMINDER_TITLE = 'Fantasy deadline';
export const DEFAULT_REMINDER_TEMPLATE =
  'Your fantasy squad is untouched this week — deadline {deadline}.';

export interface ReminderConfig {
  enabled: boolean;
  hoursBefore: number;
  template: string;
}

/** Fantasy/<sport>/<season>/Config/Reminder — the owner-editable (Manager
 *  P5) reminder shape, every field optional:
 *
 *    { Enabled:bool        (default true),
 *      HoursBefore:int     (default 3 — "send N hours before the deadline";
 *                           3 hours before the default Sunday 3 PM lock IS
 *                           spec §12's Sunday noon),
 *      Template:string }   (the push body; {deadline} becomes the absolute
 *                           league-local lock time, e.g. "Sun, Oct 19 ·
 *                           3:00 PM")
 *
 *  Hours-before-the-deadline was chosen over a weekday+time pair because it
 *  survives a schedule whose match days move around: one number, one
 *  owner-explainable sentence. */
export function reminderConfigFrom(raw: unknown): ReminderConfig {
  const m = isPlainMap(raw) ? raw : {};
  const hours = toIntLoose(m['HoursBefore']);
  const template = m['Template'];
  return {
    enabled: m['Enabled'] !== false,
    hoursBefore: hours > 0 ? hours : 3,
    template: typeof template === 'string' && template.trim().length > 0
      ? template
      : DEFAULT_REMINDER_TEMPLATE,
  };
}

/** The instant the scheduled reminder fires for a gameweek. */
export function reminderInstantMs(
  lockUtcMs: number, cfg: ReminderConfig,
): number {
  return lockUtcMs - cfg.hoursBefore * 3_600_000;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** The absolute league-local lock time, spec §5 style ("Sun, Oct 19 ·
 *  3:00 PM") — formatted straight from the match date + lock hour, so no
 *  timezone math can drift it. */
export function formatDeadline(dateKey: string, lockHour: number): string {
  const d = parseDbDate(dateKey);
  const h12 = lockHour % 12 === 0 ? 12 : lockHour % 12;
  const ampm = lockHour % 24 < 12 ? 'AM' : 'PM';
  return `${WEEKDAYS[d.getUTCDay()]}, ${MONTHS[d.getUTCMonth()]} ` +
    `${d.getUTCDate()} · ${h12}:00 ${ampm}`;
}

export function fillReminderTemplate(
  template: string, deadline: string,
): string {
  return template.split('{deadline}').join(deadline);
}

/** The measurable "unchanged squad" audience rule (spec §12): a signed-up
 *  manager — any Managers/<uid> or Squads/<uid> key — is reminded unless
 *  TransferState says they saved a squad THIS gameweek (SavedGw == gw;
 *  recordSquadSave stamps it on every MANAGER save while the week is open,
 *  transfers or not — never on the server's own Squads writes like the
 *  chip switch-off, Free Hit restore or a position re-label). Passing
 *  transferStateRaw null disables the filter — that is the send-now
 *  callable's 'all' audience. Sorted for deterministic sends. */
export function reminderAudience(args: {
  managersRaw: unknown;
  squadsRaw: unknown;
  transferStateRaw: unknown;
  gw: number;
}): string[] {
  const uids = new Set<string>();
  for (const [uid] of childEntries(args.managersRaw)) uids.add(uid);
  for (const [uid] of childEntries(args.squadsRaw)) uids.add(uid);
  const states = isPlainMap(args.transferStateRaw) ? args.transferStateRaw : {};
  return [...uids].filter((uid) => {
    const s = states[uid];
    return !isPlainMap(s) || toIntLoose(s['SavedGw']) !== args.gw;
  }).sort();
}

// ── Weekly recap ────────────────────────────────────────────────────────────

export const RECAP_TITLE = 'Fantasy recap';

/** Spec §12 verbatim: "GW3: you scored 41, moved to #4, top score 52." —
 *  points = the manager's gameweek points, rank = their OVERALL rank after
 *  the week settled, top score = the week's best gameweek score. */
export function recapBody(args: {
  gw: number; points: number; rank: number; topScore: number;
}): string {
  return `GW${args.gw}: you scored ${args.points}, moved to #${args.rank}, ` +
    `top score ${args.topScore}.`;
}

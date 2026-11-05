// Gameweek derivation + status. Faithful port of
// lib/fantasy/engine/gameweeks.dart: weeks freeze once locked (the
// LockedWeeks ledger), later weeks are one per un-skipped match date after
// the last frozen one, the lock is the per-date override else the config lock
// hour pulled earlier to N minutes before the day's first kickoff, a week
// opens at league midnight after the previous week's date, 24h "current"
// window after lock. The golden schedule fixture
// (test/fantasy/fixtures/golden_schedule.json) is replayed by both twins.

import { FantasyConfig } from './fantasy_config';
import { lockInstantUtc, parseDbDate } from './league_time';

export type GameweekStatus = 'upcoming' | 'open' | 'locked';

export interface Gameweek {
  number: number;
  date: string; // MMDDYYYY
  lockUtc: Date;
  opensUtc: Date | null; // null = open from launch (gw1)
  /** True for a week taken from the LockedWeeks ledger: its date and lock
   *  no longer follow the match calendar or the config. */
  frozen: boolean;
}

/** A gameweek the server has already locked (`LockedWeeks/<n>`). */
export interface LockedWeek {
  date: string; // MMDDYYYY
  lockUtc: Date;
  /** The week's points are final (absent = false). */
  scored?: boolean;
}

/** Default of the automatic deadline's lead time (minutes before kickoff). */
export const DEFAULT_MINUTES_BEFORE_KICKOFF = 60;

/** Everything deriveGameweeks needs beyond the match dates and the config.
 *  Every part is optional (Partial): the empty schedule is the legacy "one
 *  gameweek per match date, locking at cfg.lockHour". */
export interface GameweekSchedule {
  /** Frozen weeks by gameweek number; only the unbroken run 1..L counts. */
  lockedWeeks: Record<number, LockedWeek>;
  /** Match dates (MMDDYYYY) that are not a gameweek. */
  skippedDates: Set<string>;
  /** Per-date lock instants that beat the automatic deadline. */
  deadlineOverrides: Record<string, Date>;
  /** The earliest kickoff of each match date (MMDDYYYY). */
  firstKickoffUtc: Record<string, Date>;
  /** The automatic deadline is this many minutes before the first kickoff
   *  when that is earlier than the config's lock hour. */
  minutesBeforeKickoff: number;
}

/** The owner-editable part of a schedule (Config/SkippedDates,
 *  Config/Deadlines, Config/deadlineMinutesBeforeKickoff) — Dart
 *  ScheduleOverrides. */
export type ScheduleOverrides = Pick<
  GameweekSchedule,
  'skippedDates' | 'deadlineOverrides' | 'minutesBeforeKickoff'
>;

/** Dart Gameweek.statusAt. */
export function gameweekStatusAt(g: Gameweek, nowUtc: Date): GameweekStatus {
  if (g.opensUtc !== null && nowUtc.getTime() < g.opensUtc.getTime()) {
    return 'upcoming';
  }
  return nowUtc.getTime() < g.lockUtc.getTime() ? 'open' : 'locked';
}

/** [S2] The legacy derived kickoff 'HH:00' of a game that stores no `Time`:
 *  the season Start Time + the game's index, read as PM (h = start + index;
 *  if h < 12 then h += 12; if h > 23 then h = 23). No Start Time
 *  (startHour <= 0) means no derived kickoff (null). Dart legacyKickoffHHmm
 *  / the Manager's derivedStoredTime. */
export function legacyKickoffHHmm(
  startHour: number, index: number,
): string | null {
  if (startHour <= 0) return null;
  let h = startHour + index;
  if (h < 12) h += 12;
  if (h > 23) h = 23;
  return `${String(h).padStart(2, '0')}:00`;
}

/** League midnight after the match day [prevDate] (MMDDYYYY): when the next
 *  gameweek opens. Null for the first gameweek. */
function opensAfter(prevDate: string | null): Date | null {
  if (prevDate === null) return null;
  const next = new Date(parseDbDate(prevDate).getTime() + 24 * 60 * 60 * 1000);
  const mm = String(next.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(next.getUTCDate()).padStart(2, '0');
  return lockInstantUtc(`${mm}${dd}${next.getUTCFullYear()}`, 0);
}

/** The season's gameweeks, numbered from 1 (Dart deriveGameweeks).
 *
 *  1. Frozen weeks: schedule.lockedWeeks entries 1..L while every key 1..L is
 *     present (the first gap ends the run; later entries are ignored). They
 *     keep their stored date and lock instant.
 *  2. Later weeks: the distinct matchDates, sorted by calendar date, that are
 *     not skipped and fall strictly after the last frozen week's date. Their
 *     lock is the per-date override if any, else the config lock hour pulled
 *     earlier to minutesBeforeKickoff before the day's first kickoff when
 *     that comes sooner.
 *  3. Every week but the first opens at league midnight after the PREVIOUS
 *     week's date, frozen or not. */
export function deriveGameweeks(
  matchDates: string[], cfg: FantasyConfig,
  schedule: Partial<GameweekSchedule> = {},
): Gameweek[] {
  const lockedWeeks = schedule.lockedWeeks ?? {};
  const skippedDates = schedule.skippedDates ?? new Set<string>();
  const deadlineOverrides = schedule.deadlineOverrides ?? {};
  const firstKickoffUtc = schedule.firstKickoffUtc ?? {};
  const minutesBeforeKickoff =
    schedule.minutesBeforeKickoff ?? DEFAULT_MINUTES_BEFORE_KICKOFF;

  const out: Gameweek[] = [];
  let prevDate: string | null = null;

  for (;;) {
    const w: LockedWeek | undefined = lockedWeeks[out.length + 1];
    if (w === undefined) break;
    out.push({
      number: out.length + 1,
      date: w.date,
      lockUtc: w.lockUtc,
      opensUtc: opensAfter(prevDate),
      frozen: true,
    });
    prevDate = w.date;
  }

  const lastFrozenMs = prevDate === null ? null : parseDbDate(prevDate).getTime();
  const future = [...new Set(matchDates)]
    .filter((d) => !skippedDates.has(d) &&
      (lastFrozenMs === null || parseDbDate(d).getTime() > lastFrozenMs))
    .sort((a, b) => parseDbDate(a).getTime() - parseDbDate(b).getTime());

  for (const d of future) {
    let auto = lockInstantUtc(d, cfg.lockHour);
    const kickoff: Date | undefined = firstKickoffUtc[d];
    if (kickoff !== undefined) {
      const beforeKickoff = new Date(
        kickoff.getTime() - minutesBeforeKickoff * 60 * 1000);
      if (beforeKickoff.getTime() < auto.getTime()) auto = beforeKickoff;
    }
    out.push({
      number: out.length + 1,
      date: d,
      lockUtc: deadlineOverrides[d] ?? auto,
      opensUtc: opensAfter(prevDate),
      frozen: false,
    });
    prevDate = d;
  }
  return out;
}

/** The gameweek a manager is editing/watching at [nowUtc]: the first one
 *  whose lock is still ahead, else the last locked one while its match day
 *  is ongoing (lock day), else null (season over). */
export function currentGameweek(
  gws: Gameweek[], nowUtc: Date,
): Gameweek | null {
  for (const g of gws) {
    const dayEnd = g.lockUtc.getTime() + 24 * 60 * 60 * 1000;
    if (nowUtc.getTime() < dayEnd) return g;
  }
  return null;
}

// Gameweek derivation + status. Faithful port of
// lib/fantasy/engine/gameweeks.dart (one gameweek per match date, lock at
// cfg.lockHour league time, opens at league midnight after the previous
// match day, 24h "current" window after lock).

import { FantasyConfig } from './fantasy_config';
import { lockInstantUtc, parseDbDate } from './league_time';

export type GameweekStatus = 'upcoming' | 'open' | 'locked';

export interface Gameweek {
  number: number;
  date: string; // MMDDYYYY
  lockUtc: Date;
  opensUtc: Date | null; // null = open from launch (gw1)
}

/** Dart Gameweek.statusAt. */
export function gameweekStatusAt(g: Gameweek, nowUtc: Date): GameweekStatus {
  if (g.opensUtc !== null && nowUtc.getTime() < g.opensUtc.getTime()) {
    return 'upcoming';
  }
  return nowUtc.getTime() < g.lockUtc.getTime() ? 'open' : 'locked';
}

export function deriveGameweeks(
  matchDates: string[], cfg: FantasyConfig,
): Gameweek[] {
  const sorted = [...matchDates]
    .sort((a, b) => parseDbDate(a).getTime() - parseDbDate(b).getTime());
  const out: Gameweek[] = [];
  for (let i = 0; i < sorted.length; i++) {
    let opens: Date | null = null;
    if (i > 0) {
      const prev = new Date(
        parseDbDate(sorted[i - 1]).getTime() + 24 * 60 * 60 * 1000);
      const mm = String(prev.getUTCMonth() + 1).padStart(2, '0');
      const dd = String(prev.getUTCDate()).padStart(2, '0');
      opens = lockInstantUtc(`${mm}${dd}${prev.getUTCFullYear()}`, 0);
    }
    out.push({
      number: i + 1,
      date: sorted[i],
      lockUtc: lockInstantUtc(sorted[i], cfg.lockHour),
      opensUtc: opens,
    });
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

// League wall-clock -> UTC. The league runs on America/Los_Angeles; deadlines
// are league-local (spec §5), never the server's timezone.
//
// Faithful port of lib/fantasy/engine/league_time.dart — the golden replay
// (golden_replay.test.ts) proves both engines produce identical instants.

/** MMDDYYYY database date -> UTC midnight of that calendar date. */
export function parseDbDate(mmddyyyy: string): Date {
  return new Date(Date.UTC(
    Number(mmddyyyy.substring(4, 8)),
    Number(mmddyyyy.substring(0, 2)) - 1, // JS months are 0-based
    Number(mmddyyyy.substring(2, 4)),
  ));
}

/** Nth (1-based) given weekday of a month, as a UTC date.
 *  [weekday] uses the Dart convention: Monday=1 .. Sunday=7. */
function nthWeekday(year: number, month1: number, weekday: number, n: number): Date {
  const d = new Date(Date.UTC(year, month1 - 1, 1));
  // Dart DateTime.weekday is Mon=1..Sun=7; JS getUTCDay is Sun=0..Sat=6.
  const dartDay = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  const first = (weekday - dartDay + 7) % 7;
  return new Date(Date.UTC(year, month1 - 1, 1 + first + 7 * (n - 1)));
}

const SUNDAY = 7; // Dart DateTime.sunday

/** True if this local-calendar date (a UTC-midnight Date) is inside US
 *  daylight saving time (2nd Sunday of March through the day before the
 *  1st Sunday of November). */
export function isPacificDst(localDate: Date): boolean {
  const start = nthWeekday(localDate.getUTCFullYear(), 3, SUNDAY, 2);
  const end = nthWeekday(localDate.getUTCFullYear(), 11, SUNDAY, 1);
  const d = Date.UTC(
    localDate.getUTCFullYear(), localDate.getUTCMonth(), localDate.getUTCDate());
  return d >= start.getTime() && d < end.getTime();
}

/** UTC instant of [hour]:00 league time on a database date (MMDDYYYY). */
export function lockInstantUtc(mmddyyyy: string, hour: number): Date {
  const d = parseDbDate(mmddyyyy);
  const offset = isPacificDst(d) ? 7 : 8; // PDT -7, PST -8
  return new Date(Date.UTC(
    d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), hour + offset));
}

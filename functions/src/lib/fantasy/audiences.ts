// Fantasy push audiences (spec §3) — pure, shared by the news push on
// publish, the Message-managers callable and scheduled manager messages.
// The 'unchanged squads' audience stays pushes.ts reminderAudience.

import { childEntries, isPlainMap } from './orchestration_db';
import { squadFromMap } from './squad';

/** Every fantasy manager: keys of Managers ∪ Squads (a manager who saved a
 *  squad but has no Managers row still counts — reminderAudience's union),
 *  sorted for deterministic sends. */
export function allManagers(managersRaw: unknown, squadsRaw: unknown): string[] {
  const uids = new Set<string>();
  for (const [uid] of childEntries(managersRaw)) uids.add(uid);
  for (const [uid] of childEntries(squadsRaw)) uids.add(uid);
  return [...uids].sort();
}

/** Managers whose CURRENT squad (Squads/<uid>, any slot — starters or
 *  bench) holds any of [names], sorted. Squads are read with the stored
 *  squad parser (squadFromMap); a malformed squad is skipped. */
export function ownersOf(squadsRaw: unknown, names: string[]): string[] {
  const wanted = new Set(names);
  if (wanted.size === 0) return [];
  const out: string[] = [];
  for (const [uid, raw] of childEntries(squadsRaw)) {
    if (!isPlainMap(raw)) continue;
    let picks: string[];
    try {
      picks = squadFromMap(raw).picks.map((p) => p.playerId);
    } catch {
      continue;
    }
    if (picks.some((id) => wanted.has(id))) out.push(uid);
  }
  return out.sort();
}

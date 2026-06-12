import type { Reference } from 'firebase-admin/database';
import type { MatchContext, Names } from './decide';

const CACHE_TTL_MS = 5 * 60 * 1000; // names may be corrected mid-tournament
const cache = new Map<string, { value: string; expiresAt: number }>();

async function readName(root: Reference, path: string, fallback: string): Promise<string> {
  const hit = cache.get(path);
  if (hit && hit.expiresAt > Date.now()) return hit.value;
  try {
    const snap = await root.child(path).get();
    const v = snap.val();
    const name = typeof v === 'string' && v.trim() ? v : fallback;
    cache.set(path, { value: name, expiresAt: Date.now() + CACHE_TTL_MS });
    return name;
  } catch {
    return fallback;
  }
}

export async function loadNames(root: Reference, tid: string, match: MatchContext): Promise<Names> {
  const [tournament, team1, team2] = await Promise.all([
    readName(root, `Tournaments/${tid}/Name`, tid),
    match.team1Id ? readName(root, `Tournaments/${tid}/Teams/${match.team1Id}/Name`, match.team1Id) : Promise.resolve('TBD'),
    match.team2Id ? readName(root, `Tournaments/${tid}/Teams/${match.team2Id}/Name`, match.team2Id) : Promise.resolve('TBD'),
  ]);
  return { tournament, team1, team2 };
}

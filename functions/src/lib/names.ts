import * as admin from 'firebase-admin';
import type { MatchContext, Names } from './decide';

const cache = new Map<string, string>();

async function readName(path: string, fallback: string): Promise<string> {
  const hit = cache.get(path);
  if (hit !== undefined) return hit;
  try {
    const snap = await admin.database().ref(path).get();
    const v = snap.val();
    const name = typeof v === 'string' && v.trim() ? v : fallback;
    cache.set(path, name);
    return name;
  } catch {
    return fallback;
  }
}

export async function loadNames(tid: string, match: MatchContext): Promise<Names> {
  const [tournament, team1, team2] = await Promise.all([
    readName(`Tournaments/${tid}/Name`, tid),
    match.team1Id ? readName(`Tournaments/${tid}/Teams/${match.team1Id}/Name`, match.team1Id) : Promise.resolve('TBD'),
    match.team2Id ? readName(`Tournaments/${tid}/Teams/${match.team2Id}/Name`, match.team2Id) : Promise.resolve('TBD'),
  ]);
  return { tournament, team1, team2 };
}

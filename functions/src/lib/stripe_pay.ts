// Pure Stripe payment-amount + legacy-target + webhook-metadata helpers
// (Leagues epic L1, phase L1c). No Firebase/Stripe imports — unit-tested
// directly with vitest. This is the server-side (cents-based) twin of the
// Dart dollar-based amountOwed/legacySignUpTarget in
// lib/registration/registration_models.dart — the two MUST agree on every
// case; when one changes, check the other.

/** The subset of RegistrationConfig fields the payment math needs. */
export interface RegistrationConfigLike {
  targetType: 'league' | 'tournament';
  sport: string;
  season: string;
  tournamentId: string;
  tournamentName: string;
  fee: number; // dollars
  teamFee: number; // dollars
  paymentMode: 'perPlayer' | 'teamFee' | 'both';
}

/** The subset of RegSubmission fields the payment math needs. */
export interface SubmissionLike {
  path: 'individual' | 'captain' | 'joiner' | string;
  paid: boolean;
}

/** The subset of RegTeam fields the payment math needs. */
export interface TeamLike {
  codeWaivesPayment: boolean;
}

/** Dollars -> integer cents, rounded to the nearest cent (Stripe requires
 *  an integer amount). */
function toCents(dollars: number): number {
  return Math.round(dollars * 100);
}

/**
 * The amount (in cents) [submission] owes right now — 0 whenever nothing is
 * owed. Mirrors Dart's `paymentOwed` + `amountOwed` combined:
 *  - already paid -> 0
 *  - joiner -> the per-player fee, unless [team].codeWaivesPayment
 *  - captain -> the flat team fee, only under 'teamFee' or 'both'
 *  - individual (or any other/legacy path) -> the per-player fee, only
 *    under 'perPlayer' or 'both'
 * [team] is omitted for individual/captain paths; a joiner with no [team]
 * defensively owes the full per-player fee (fail closed, never accidentally
 * free).
 */
export function owedCents(
  config: RegistrationConfigLike,
  submission: SubmissionLike,
  team?: TeamLike,
): number {
  if (submission.paid) return 0;
  if (submission.path === 'joiner') {
    if (config.fee <= 0) return 0;
    if (team?.codeWaivesPayment) return 0;
    return toCents(config.fee);
  }
  if (submission.path === 'captain') {
    if (config.teamFee <= 0) return 0;
    if (config.paymentMode !== 'teamFee' && config.paymentMode !== 'both') return 0;
    return toCents(config.teamFee);
  }
  // individual (and any other/legacy path)
  if (config.fee <= 0) return 0;
  if (config.paymentMode !== 'perPlayer' && config.paymentMode !== 'both') return 0;
  return toCents(config.fee);
}

/** Where the legacy dual-write goes — mirrors Dart's legacySignUpTarget. */
export function legacyTarget(config: RegistrationConfigLike): { league: string; season: string } {
  if (config.targetType === 'tournament') {
    return {
      league: config.tournamentName.length > 0 ? config.tournamentName : config.tournamentId,
      season: config.tournamentId,
    };
  }
  return { league: config.sport, season: config.season };
}

/** The identifying fields the webhook needs to flip Paid on the right
 *  submission — carried as Stripe PaymentIntent metadata (Stripe stores
 *  metadata values as strings; keys/values here are already strings). */
export interface WebhookMeta {
  regId: string;
  uid: string;
  league: string;
  season: string;
}

/** Builds the metadata object passed to `stripe.paymentIntents.create`. */
export function webhookMetadata(meta: WebhookMeta): Record<string, string> {
  return { regId: meta.regId, uid: meta.uid, league: meta.league, season: meta.season };
}

/** Defensive parse of a Stripe event's `metadata` back into [WebhookMeta].
 *  Returns null when any required field is missing or not a string, so the
 *  webhook can log-and-200 instead of crashing on a malformed/foreign event. */
export function parseWebhookMetadata(raw: unknown): WebhookMeta | null {
  if (raw === null || raw === undefined || typeof raw !== 'object') return null;
  const m = raw as Record<string, unknown>;
  const regId = m['regId'];
  const uid = m['uid'];
  const league = m['league'];
  const season = m['season'];
  if (
    typeof regId !== 'string' || regId.length === 0 ||
    typeof uid !== 'string' || uid.length === 0 ||
    typeof league !== 'string' || league.length === 0 ||
    typeof season !== 'string'
  ) {
    return null;
  }
  return { regId, uid, league, season };
}

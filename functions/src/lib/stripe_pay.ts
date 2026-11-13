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

/** Integer cents -> dollars, for writing RegSubmission.PaidAmount (a Dart
 *  `num`, stored in dollars — the reverse of [toCents]). */
export function centsToDollars(cents: number): number {
  return cents / 100;
}

/**
 * True when [submission] is already marked Paid — the double-pay server
 * guard (createRegistrationPaymentIntent) checks this FIRST so a caller who
 * re-opens the payment sheet after already paying (card webhook, or the
 * owner manually marking Paid in the Manager) gets a distinct 'Already
 * paid.' error instead of the generic "nothing owed" message.
 */
export function isAlreadyPaid(submission: SubmissionLike): boolean {
  return submission.paid;
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
 *  metadata values as strings; keys/values here are already strings).
 *  Registration metadata carries NO `kind` — every PaymentIntent created
 *  before paid access, and every one after (webhookMetadata is unchanged) —
 *  and the parser treats an absent kind as a registration. */
export interface RegistrationMeta {
  kind?: 'registration';
  regId: string;
  uid: string;
  league: string;
  season: string;
}

/** A fantasy season-pass Checkout payment (paid access spec 2026-11-01 §7):
 *  `kind` routes payment_intent.succeeded / charge.refunded to the
 *  Fantasy/<sport>/<season>/Access/<uid> record instead of a submission. */
export interface FantasyAccessMeta {
  kind: 'fantasyAccess';
  sport: string;
  season: string;
  uid: string;
}

export type WebhookMeta = RegistrationMeta | FantasyAccessMeta;

/** Builds the metadata object passed to `stripe.paymentIntents.create`
 *  (registration — no kind, byte-identical to before paid access). */
export function webhookMetadata(meta: RegistrationMeta): Record<string, string> {
  return { regId: meta.regId, uid: meta.uid, league: meta.league, season: meta.season };
}

/** Builds the `payment_intent_data.metadata` of a fantasy Checkout Session. */
export function fantasyAccessMetadata(
  meta: { sport: string; season: string; uid: string },
): Record<string, string> {
  return { kind: 'fantasyAccess', sport: meta.sport, season: meta.season, uid: meta.uid };
}

function nonEmptyString(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0;
}

/** Defensive parse of a Stripe event's `metadata` back into [WebhookMeta].
 *  Returns null when any required field is missing or not a string, so the
 *  webhook can log-and-200 instead of crashing on a malformed/foreign event.
 *  No kind (or 'registration') -> the registration shape, exactly as before;
 *  'fantasyAccess' -> the fantasy shape (never falls back to the
 *  registration parse); any other kind -> null. */
export function parseWebhookMetadata(raw: unknown): WebhookMeta | null {
  if (raw === null || raw === undefined || typeof raw !== 'object') return null;
  const m = raw as Record<string, unknown>;
  const kind = m['kind'];
  if (kind === 'fantasyAccess') {
    const sport = m['sport'];
    const season = m['season'];
    const uid = m['uid'];
    if (!nonEmptyString(sport) || !nonEmptyString(season) || !nonEmptyString(uid)) {
      return null;
    }
    return { kind: 'fantasyAccess', sport, season, uid };
  }
  if (kind !== undefined && kind !== 'registration') return null;
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

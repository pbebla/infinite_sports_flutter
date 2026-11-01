// Infinite Fantasy paid access (season pass) — pure TS behind the FantasyDb /
// FantasyPusher seams, no firebase imports. The thin Cloud Function exports
// (callables + RTDB triggers) live in src/fantasy_access.ts; the Stripe
// webhook routing in src/stripeWebhook.ts.
//
// Spec: docs/superpowers/specs/2026-11-01-fantasy-paid-access-design.md
// Plan: docs/superpowers/plans/2026-11-01-fantasy-paid-access.md (Track A)
//
// NODES (all under Fantasy/<sport>/<season>/ unless noted):
//
//   Config/Access = { Mode:'free'|'pass', AmountDollars, Methods:{Venmo,
//     Zelle, Card}, RegisteredPlayersFree, Copy:{Headline, Body, Button},
//     ChangedAt, ChangedBy }                      (Manager-written, §3)
//   Access/<uid>  = { Status:'active'|'pending'|'revoked', Via:'card'|'venmo'
//     |'zelle'|'granted'|'player'|'grandfathered', AmountCents, PaidAt, By,
//     Reason?, StripePaymentIntent?, RefundedAt?, RevokedBy?, RevokeReason?,
//     Notified:{<key>:true} }                     (server/admin-written, §4)
//   AccessClaims/<uid>/<pushKey> = { Method:'venmo'|'zelle', AmountDollars,
//     Note, At, Resolved?:'approved'|'rejected'|'superseded', ResolvedAt?,
//     ResolvedBy?, Reason?, Notified?:true }      (fan-created, §6)
//   root Fantasy/Templates/Access/<key> = { PushTitle, PushBody,
//     EmailSubject, EmailBody } + Fantasy/Templates/Access/AdminEmail (§9)
//
// TWINS: the fan app (lib/fantasy/data/fantasy_access.dart) and the Manager
// (lib/fantasy/data/fantasy_access_admin.dart) carry Dart copies of the
// defaults below; when one changes, change all three.

import { legacyTarget, RegistrationConfigLike } from '../stripe_pay';
import { escapeHtml } from '../support';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, FantasyDb, fantasyRoot, isPlainMap,
} from './orchestration_db';
import { adminUidsOf, FantasyPusher } from './pushes';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

// ── Config/Access ───────────────────────────────────────────────────────────

export type AccessMode = 'free' | 'pass';

export interface AccessCopy {
  headline: string;
  body: string;
  button: string;
}

export interface AccessConfig {
  mode: AccessMode;
  /** Whole dollars or .50; the server charges exactly this (§3). */
  amountDollars: number;
  methods: { venmo: boolean; zelle: boolean; cash: boolean; card: boolean };
  registeredPlayersFree: boolean;
  copy: AccessCopy;
}

/** Spec §9 `Copy` row — the paywall text the fan app shows (verbatim). */
export const COPY_DEFAULTS: AccessCopy = {
  headline: 'Join Infinite Fantasy',
  body: 'A season pass for {season} is {amount}. Pay once, play the whole season.',
  button: 'Pay with card',
};

function nonBlank(v: unknown): string | null {
  return typeof v === 'string' && v.trim().length > 0 ? v : null;
}

function boolOr(v: unknown, dflt: boolean): boolean {
  return typeof v === 'boolean' ? v : dflt;
}

/** Config/Access with every default (§3): absent = free mode (today's
 *  behaviour); bad types fall back field by field. */
export function accessConfigFrom(raw: unknown): AccessConfig {
  const m = isPlainMap(raw) ? raw : {};
  const methods = isPlainMap(m['Methods']) ? m['Methods'] : {};
  const copy = isPlainMap(m['Copy']) ? m['Copy'] : {};
  const amount = typeof m['AmountDollars'] === 'number' &&
    Number.isFinite(m['AmountDollars']) && m['AmountDollars'] > 0
    ? m['AmountDollars'] : 0;
  return {
    mode: m['Mode'] === 'pass' ? 'pass' : 'free',
    amountDollars: amount,
    methods: {
      venmo: boolOr(methods['Venmo'], true),
      zelle: boolOr(methods['Zelle'], false),
      cash: boolOr(methods['Cash'], false),
      card: boolOr(methods['Card'], true),
    },
    registeredPlayersFree: m['RegisteredPlayersFree'] === true,
    copy: {
      headline: nonBlank(copy['Headline']) ?? COPY_DEFAULTS.headline,
      body: nonBlank(copy['Body']) ?? COPY_DEFAULTS.body,
      button: nonBlank(copy['Button']) ?? COPY_DEFAULTS.button,
    },
  };
}

export function isPassMode(cfg: AccessConfig): boolean {
  return cfg.mode === 'pass';
}

// ── Access/<uid> ────────────────────────────────────────────────────────────

export type AccessStatus = 'active' | 'pending' | 'revoked';
export type AccessVia =
  'card' | 'venmo' | 'zelle' | 'cash' | 'granted' | 'player' | 'grandfathered';

const VIAS: AccessVia[] = ['card', 'venmo', 'zelle', 'cash', 'granted', 'player', 'grandfathered'];

/** The vias that carry money — their activation email is the receipt. */
export const PAID_VIAS: ReadonlyArray<AccessVia> = ['card', 'venmo', 'zelle', 'cash'];

export interface AccessRecord {
  status: AccessStatus;
  via: AccessVia;
  amountCents: number;
  /** The activation instant (also the receipt date); null while pending. */
  paidAt: number | null;
  by: string;
  reason?: string;
  stripePaymentIntent?: string;
  refundedAt?: number | null;
  revokedBy?: string;
  revokeReason?: string;
  notified: Record<string, true>;
}

function numOrNull(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function strOpt(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 ? v : undefined;
}

/** Access/<uid> tolerant parse: null when absent, not a map, or the Status
 *  is not one of the three. An unknown Via reads as 'granted' (no money
 *  shown, no receipt — the safe side). */
export function accessRecordFrom(raw: unknown): AccessRecord | null {
  if (!isPlainMap(raw)) return null;
  const status = raw['Status'];
  if (status !== 'active' && status !== 'pending' && status !== 'revoked') return null;
  const via = VIAS.includes(raw['Via'] as AccessVia) ? raw['Via'] as AccessVia : 'granted';
  const notified: Record<string, true> = {};
  for (const [k, v] of childEntries(raw['Notified'])) {
    if (v === true) notified[k] = true;
  }
  const amount = numOrNull(raw['AmountCents']);
  const rec: AccessRecord = {
    status,
    via,
    amountCents: amount !== null && amount >= 0 ? Math.round(amount) : 0,
    paidAt: numOrNull(raw['PaidAt']),
    by: typeof raw['By'] === 'string' ? raw['By'] : '',
    notified,
  };
  const reason = strOpt(raw['Reason']);
  if (reason !== undefined) rec.reason = reason;
  const pi = strOpt(raw['StripePaymentIntent']);
  if (pi !== undefined) rec.stripePaymentIntent = pi;
  if (raw['RefundedAt'] !== undefined) rec.refundedAt = numOrNull(raw['RefundedAt']);
  const revokedBy = strOpt(raw['RevokedBy']);
  if (revokedBy !== undefined) rec.revokedBy = revokedBy;
  const revokeReason = strOpt(raw['RevokeReason']);
  if (revokeReason !== undefined) rec.revokeReason = revokeReason;
  return rec;
}

export function isActive(rec: AccessRecord | null): boolean {
  return rec !== null && rec.status === 'active';
}

/** The Access node for an activation (§4). [extra] carries the per-via
 *  fields: {StripePaymentIntent} for card, {Reason} for an admin grant. */
export function activationFor(
  via: AccessVia, amountCents: number, nowMs: number, by: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    Status: 'active', Via: via, AmountCents: amountCents, PaidAt: nowMs, By: by,
    ...extra,
  };
}

/** The Access node a Venmo/Zelle claim opens (§4 'pending'): no PaidAt
 *  (RTDB stores no nulls), the claim instant as ClaimedAt. */
export function pendingFor(claim: AccessClaim, nowMs: number): Record<string, unknown> {
  return {
    Status: 'pending', Via: claim.method, AmountCents: dollarsToCents(claim.amountDollars),
    By: 'system', ClaimedAt: nowMs,
  };
}

/** The fields a revoke adds to an active record (§4, §7). */
export function revokedPatch(
  nowMs: number, by: string, reason?: string,
): Record<string, unknown> {
  return {
    Status: 'revoked', RefundedAt: nowMs, RevokedBy: by,
    ...(reason ? { RevokeReason: reason } : {}),
  };
}

/** The once-only key for the status notification (§7): active_<PaidAt> /
 *  revoked_<RefundedAt>. A record missing its stamp (a hand-written admin
 *  node) notifies once ever under `_unknown`. */
export function notifyKeyFor(status: 'active' | 'revoked', rec: AccessRecord): string {
  const stamp = status === 'active' ? rec.paidAt : rec.refundedAt ?? null;
  return `${status}_${stamp === null || stamp === undefined ? 'unknown' : stamp}`;
}

// ── AccessClaims/<uid>/<key> ────────────────────────────────────────────────

export type ClaimMethod = 'venmo' | 'zelle' | 'cash';

export interface AccessClaim {
  method: ClaimMethod;
  amountDollars: number;
  note: string;
  at: number;
  resolved: 'approved' | 'rejected' | 'superseded' | null;
}

/** A fan's "I sent it" claim (§6); null unless Method is venmo/zelle (the
 *  rules validate that too — this is the server's belt and braces). */
export function claimFrom(raw: unknown): AccessClaim | null {
  if (!isPlainMap(raw)) return null;
  const method = raw['Method'];
  if (method !== 'venmo' && method !== 'zelle' && method !== 'cash') return null;
  const amount = numOrNull(raw['AmountDollars']);
  const resolved = raw['Resolved'];
  return {
    method,
    amountDollars: amount !== null && amount >= 0 ? amount : 0,
    note: typeof raw['Note'] === 'string' ? raw['Note'] : '',
    at: numOrNull(raw['At']) ?? 0,
    resolved: resolved === 'approved' || resolved === 'rejected' || resolved === 'superseded'
      ? resolved : null,
  };
}

// ── Templates (§9) ──────────────────────────────────────────────────────────

export type TemplateKey =
  'claimReceived' | 'claimAdmin' | 'activatedPaid' | 'activatedGranted' | 'revoked';

export const TEMPLATE_KEYS: TemplateKey[] = [
  'claimReceived', 'claimAdmin', 'activatedPaid', 'activatedGranted', 'revoked',
];

export function isTemplateKey(v: unknown): v is TemplateKey {
  return typeof v === 'string' && (TEMPLATE_KEYS as string[]).includes(v);
}

export interface AccessTemplate {
  pushTitle: string;
  pushBody: string;
  emailSubject: string;
  emailBody: string;
}

/** Spec §9 table, verbatim. Email bodies are plain text; blank lines are
 *  paragraphs (emailHtml renders them). */
export const TEMPLATE_DEFAULTS: Record<TemplateKey, AccessTemplate> = {
  claimReceived: {
    pushTitle: 'Payment noted',
    pushBody: "Thanks {name} — we'll confirm your {method} payment for {season} Fantasy shortly.",
    emailSubject: '{season} Fantasy — payment noted',
    emailBody: 'Hi {name}, we received your note that you paid {amount} by {method} ' +
      "for {season} Fantasy access. Zaya will confirm it shortly and you'll get a " +
      "message the moment you're in.",
  },
  claimAdmin: {
    pushTitle: 'Fantasy access — {method} payment to confirm',
    pushBody: '{name} says they paid {amount} by {method} for {season} Fantasy access.',
    emailSubject: 'Fantasy access — {method} payment to confirm — {name}',
    emailBody: '{name} says they paid {amount} by {method} for {season} Fantasy access.\n\n' +
      'Open the Manager → Fantasy → Access & payments to approve.',
  },
  activatedPaid: {
    pushTitle: "You're in!",
    pushBody: 'Your {season} Fantasy season pass is active. Build your team!',
    emailSubject: 'Receipt — {season} Fantasy season pass',
    emailBody: 'Hi {name}, your {season} Fantasy season pass is active.\n\nAmount: {amount}\n' +
      'Method: {method}\nDate: {date}\nSeason: {season}\n\nOpen the app → ' +
      'Fantasy → My Team to name your team and build your squad. Good luck!',
  },
  activatedGranted: {
    pushTitle: "You're in!",
    pushBody: 'Your {season} Fantasy access is active. Build your team!',
    emailSubject: "You're in — {season} Fantasy",
    emailBody: 'Hi {name}, your access to {season} Fantasy is active. ' +
      'Open the app → Fantasy → My Team to build your squad.',
  },
  revoked: {
    pushTitle: 'Fantasy access removed',
    pushBody: 'Your {season} Fantasy access was removed. Pay again in the app to keep playing.',
    emailSubject: '{season} Fantasy — access removed',
    emailBody: 'Hi {name}, your {season} Fantasy access was removed on ' +
      "{date}. You can pay again from the app's Fantasy tab to keep playing. Reply " +
      'to this email if you think this is a mistake.',
  },
};

/** Fantasy/Templates/Access/AdminEmail default (§9). */
export const ADMIN_EMAIL_DEFAULT = 'support@infinitesports.org';

/** Root path of the owner-editable templates. */
export const TEMPLATES_PATH = 'Fantasy/Templates/Access';

export interface ResolvedTemplate {
  template: AccessTemplate;
  /** The RTDB field names that fell back to the default, in node order. */
  fallbacks: string[];
  /** Whether the node existed at all (absent = never customised, expected). */
  present: boolean;
}

const TEMPLATE_FIELDS: Array<[keyof AccessTemplate, string]> = [
  ['pushTitle', 'PushTitle'], ['pushBody', 'PushBody'],
  ['emailSubject', 'EmailSubject'], ['emailBody', 'EmailBody'],
];

/** One template with code defaults field by field (§7): a blank, missing
 *  or non-string field falls back; [fallbacks] names them so the caller can
 *  log once. */
export function templateFrom(key: TemplateKey, raw: unknown): ResolvedTemplate {
  const present = isPlainMap(raw);
  const m = present ? raw : {};
  const dflt = TEMPLATE_DEFAULTS[key];
  const template: AccessTemplate = { ...dflt };
  const fallbacks: string[] = [];
  for (const [field, node] of TEMPLATE_FIELDS) {
    const v = nonBlank(m[node]);
    if (v === null) {
      fallbacks.push(node);
    } else {
      template[field] = v;
    }
  }
  return { template, fallbacks, present };
}

export type TemplateVars = Partial<Record<
  'name' | 'teamName' | 'amount' | 'season' | 'method' | 'date' | 'reason', string>>;

const PLACEHOLDERS: Array<keyof TemplateVars> =
  ['name', 'teamName', 'amount', 'season', 'method', 'date', 'reason'];

/** Replaces the seven known placeholders (a missing var reads ''); unknown
 *  `{things}` stay literal. Values are never treated as patterns. */
export function fillTemplate(text: string, vars: TemplateVars): string {
  let out = text;
  for (const key of PLACEHOLDERS) {
    out = out.split(`{${key}}`).join(vars[key] ?? '');
  }
  return out;
}

// ── Labels ──────────────────────────────────────────────────────────────────

/** Integer cents -> "$1,234.56". */
export function formatAmount(cents: number): string {
  const dollars = Math.round(cents) / 100;
  return '$' + dollars.toLocaleString('en-US', {
    minimumFractionDigits: 2, maximumFractionDigits: 2,
  });
}

/** Dollars -> integer cents, nearest cent (stripe_pay.ts toCents twin). */
export function dollarsToCents(dollars: number): number {
  return Math.round(dollars * 100);
}

/** "Futsal Season 16" — the {season} placeholder and the Checkout line. */
export function seasonLabel(sport: string, season: string | number): string {
  return `${sport} Season ${season}`;
}

/** The {method} placeholder (§7): fan-facing names for the paid vias; '' for
 *  the rest (no fan template ever names a grant). */
export function methodLabel(via: AccessVia | ClaimMethod | string): string {
  switch (via) {
    case 'card': return 'card';
    case 'venmo': return 'Venmo';
    case 'zelle': return 'Zelle';
    case 'cash': return 'cash';
    default: return '';
  }
}

/** The league runs on America/Los_Angeles (league_time.ts); receipts show
 *  that calendar day: "Nov 1, 2026". */
export function formatAccessDate(ms: number): string {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Los_Angeles', month: 'short', day: 'numeric', year: 'numeric',
  }).format(new Date(ms));
}

// ── Stripe Checkout (§7) ────────────────────────────────────────────────────

export const HOSTING_BASE = 'https://infinite-sports-app.web.app';

/** The one Checkout line item, at the SERVER's amount. */
export function checkoutLineItem(
  cfg: AccessConfig, sport: string, season: string | number,
): { name: string; unit_amount: number; currency: 'usd' } {
  return {
    name: `Infinite Fantasy — ${seasonLabel(sport, season)} season pass`,
    unit_amount: dollarsToCents(cfg.amountDollars),
    currency: 'usd',
  };
}

/** The hosting landing pages (§10). */
export function checkoutUrls(hostingBase: string): { success_url: string; cancel_url: string } {
  const base = hostingBase.replace(/\/+$/, '');
  return {
    success_url: `${base}/fantasy/paid.html`,
    cancel_url: `${base}/fantasy/cancelled.html`,
  };
}

// ── Email rendering ─────────────────────────────────────────────────────────

const BRAND = '#D00000'; // infiniteSportsPrimaryColor (RGB 208,0,0)

/** A plain-text template body as branded HTML: blank lines = paragraphs,
 *  single newlines = line breaks, every character escaped (support.ts
 *  emailShell look; the footer is the fantasy's, not the support desk's). */
export function emailHtml(bodyText: string): string {
  const paragraphs = bodyText.replace(/\r\n/g, '\n').split(/\n{2,}/)
    .map((p) => p.trim()).filter((p) => p.length > 0)
    .map((p) => `<p>${p.split('\n').map((l) => escapeHtml(l)).join('<br>')}</p>`)
    .join('');
  return `<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;` +
    `max-width:560px;margin:0 auto;padding:16px;color:#1a1a1a;">` +
    `<h2 style="color:${BRAND};margin:0 0 12px;">Infinite Sports</h2>${paragraphs}` +
    `<p style="color:#888;font-size:12px;margin-top:24px;">Infinite Fantasy — ` +
    `Infinite Sports</p></div>`;
}

// ── Push payload ────────────────────────────────────────────────────────────

/** Every access push carries this (§7); the fan app routes the tap to the
 *  hub's My Team tab. */
export function accessPushData(sport: string, season: string): Record<string, string> {
  return { type: 'fantasyAccess', sport, season };
}

// ── Registration config (for the Paid-flip grant) ───────────────────────────

/** Registrations/<regId>/Config as legacyTarget needs it — tolerant, and
 *  WITHOUT createRegistrationPaymentIntent's "Stripe must be on" rule (a
 *  Venmo-only registration's players play free too). */
export function registrationTargetFrom(raw: unknown): { league: string; season: string } | null {
  if (!isPlainMap(raw)) return null;
  const cfg: RegistrationConfigLike = {
    targetType: raw['TargetType'] === 'tournament' ? 'tournament' : 'league',
    sport: String(raw['Sport'] ?? ''),
    season: String(raw['Season'] ?? ''),
    tournamentId: String(raw['TournamentId'] ?? ''),
    tournamentName: String(raw['TournamentName'] ?? ''),
    fee: 0, teamFee: 0, paymentMode: 'perPlayer',
  };
  const target = legacyTarget(cfg);
  if (!target.league || !target.season) return null;
  return target;
}

// ── Seams for the impure edges ──────────────────────────────────────────────

/** One email out (the real one is sendSupportMail; tests capture). */
export interface AccessMailer {
  send(to: string, subject: string, html: string): Promise<void>;
}

/** Firebase Auth's email for a uid; null when none on file / unknown uid. */
export interface AccessAuth {
  emailOf(uid: string): Promise<string | null>;
}

export interface AccessDeps {
  db: FantasyDb;
  pusher: FantasyPusher;
  mailer: AccessMailer;
  auth: AccessAuth;
  nowMs: number;
  log?: FantasyLogger;
}

// ── Shared orchestration pieces ─────────────────────────────────────────────

/** Fantasy/Templates/Access/<key> with defaults; logs the fallback once per
 *  resolve: a partial node warns (the owner left a field blank), an absent
 *  node is the expected "never customised" case and only logs info. */
export async function resolveTemplate(
  db: FantasyDb, key: TemplateKey, log: FantasyLogger,
): Promise<AccessTemplate> {
  const r = templateFrom(key, await db.read(`${TEMPLATES_PATH}/${key}`));
  if (r.fallbacks.length > 0) {
    if (r.present) {
      log.warn('fantasy access: template field(s) blank — using defaults',
        { template: key, fields: r.fallbacks });
    } else {
      log.info('fantasy access: template not customised — using defaults', { template: key });
    }
  }
  return r.template;
}

/** The admin inbox for claim emails (§9): Fantasy/Templates/Access/AdminEmail
 *  or the support inbox. */
export async function resolveAdminEmail(db: FantasyDb): Promise<string> {
  return nonBlank(await db.read(`${TEMPLATES_PATH}/AdminEmail`))?.trim() ?? ADMIN_EMAIL_DEFAULT;
}

/** The fan's name for a template: team name first (Managers/<uid>/TeamName),
 *  else the public profile's "First Last", else [fallback]. teamName is ''
 *  when they have none. */
export async function resolveFanName(
  db: FantasyDb, root: string, uid: string, fallback: string,
): Promise<{ name: string; teamName: string }> {
  const teamName = nonBlank(await db.read(`${root}/Managers/${uid}/TeamName`))?.trim() ?? '';
  if (teamName) return { name: teamName, teamName };
  const profile = await db.read(`PublicProfiles/${uid}`);
  const p = isPlainMap(profile) ? profile : {};
  const real = `${nonBlank(p['First Name']) ?? ''} ${nonBlank(p['Last Name']) ?? ''}`.trim();
  return { name: real || fallback, teamName: '' };
}

/** Marks every unresolved AccessClaims/<uid>/* as superseded (an activation
 *  by another route, or a newer claim). Returns the keys touched. */
export async function supersedeOpenClaims(
  db: FantasyDb, root: string, uid: string, by: string, nowMs: number,
  except?: string,
): Promise<string[]> {
  const touched: string[] = [];
  for (const [key, raw] of childEntries(await db.read(`${root}/AccessClaims/${uid}`))) {
    if (key === except) continue;
    if (!isPlainMap(raw) || raw['Resolved'] != null) continue;
    await db.write(`${root}/AccessClaims/${uid}/${key}/Resolved`, 'superseded');
    await db.write(`${root}/AccessClaims/${uid}/${key}/ResolvedAt`, nowMs);
    await db.write(`${root}/AccessClaims/${uid}/${key}/ResolvedBy`, by);
    touched.push(key);
  }
  return touched;
}

/** The Notified map an Access rewrite must keep (so a pending -> active
 *  rewrite can't re-notify an already-sent key). */
function keepNotified(current: unknown): Record<string, unknown> {
  return isPlainMap(current) && isPlainMap(current['Notified'])
    ? { Notified: current['Notified'] } : {};
}

// ── Card activation + refund (the webhook's pure halves, §7) ────────────────

export interface ActivateArgs {
  sport: string;
  season: string;
  uid: string;
  amountCents: number;
  paymentIntent: string;
  nowMs: number;
  log?: FantasyLogger;
}

/** payment_intent.succeeded with the fantasy kind: a transaction on
 *  Access/<uid> — already active -> untouched (a replay); else the card
 *  activation, keeping Notified. Open claims are then superseded. */
export async function activateFantasyAccess(
  db: FantasyDb, args: ActivateArgs,
): Promise<{ activated: boolean }> {
  const log = args.log ?? silent;
  const root = fantasyRoot(args.sport, args.season);
  const ctx = { sport: args.sport, season: args.season, uid: args.uid, pi: args.paymentIntent };
  const res = await db.transaction(`${root}/Access/${args.uid}`, (current) => {
    if (isPlainMap(current) && current['Status'] === 'active') return undefined;
    return {
      ...activationFor('card', args.amountCents, args.nowMs, 'stripe',
        { StripePaymentIntent: args.paymentIntent }),
      ...keepNotified(current),
    };
  });
  if (!res.committed) {
    log.info('fantasy access: already active — card activation replayed, no-op', ctx);
    return { activated: false };
  }
  const superseded = await supersedeOpenClaims(db, root, args.uid, 'stripe', args.nowMs);
  log.info('fantasy access: activated', {
    ...ctx, via: 'card', by: 'stripe', amountCents: args.amountCents, superseded,
  });
  return { activated: true };
}

export interface RefundArgs {
  sport: string;
  season: string;
  uid: string;
  /** The refunded charge's PaymentIntent id; null when Stripe sent none. */
  paymentIntent: string | null;
  nowMs: number;
  log?: FantasyLogger;
}

/** charge.refunded (full) with the fantasy kind: active -> revoked by
 *  'stripe'. Only the record that THIS payment activated is revoked: a
 *  StripePaymentIntent on the record must match (a replayed refund of an
 *  old card payment must never revoke a pass the fan has since paid for by
 *  Venmo or been granted); a record with no PaymentIntent on file matches
 *  only when its Via is card and Stripe gave no id to compare. */
export async function revokeFantasyAccessOnRefund(
  db: FantasyDb, args: RefundArgs,
): Promise<{ revoked: boolean }> {
  const log = args.log ?? silent;
  const root = fantasyRoot(args.sport, args.season);
  const ctx = { sport: args.sport, season: args.season, uid: args.uid, pi: args.paymentIntent };
  let why = '';
  const res = await db.transaction(`${root}/Access/${args.uid}`, (current) => {
    why = '';
    if (!isPlainMap(current) || current['Status'] !== 'active') {
      why = 'not active';
      return undefined;
    }
    const onFile = current['StripePaymentIntent'];
    const matches = typeof onFile === 'string' && onFile.length > 0
      ? onFile === args.paymentIntent
      : current['Via'] === 'card' && args.paymentIntent === null;
    if (!matches) {
      why = 'payment does not match the active record';
      return undefined;
    }
    return { ...current, ...revokedPatch(args.nowMs, 'stripe') };
  });
  if (!res.committed) {
    log.info(`fantasy access: refund ignored — ${why}`, ctx);
    return { revoked: false };
  }
  log.info('fantasy access: revoked', { ...ctx, by: 'stripe' });
  return { revoked: true };
}

// ── Claim created (§7 onFantasyAccessClaimCreated) ──────────────────────────

export interface ClaimCreatedArgs {
  sport: string;
  season: string;
  uid: string;
  key: string;
}

export interface ClaimCreatedResult {
  pending: boolean;
  adminPushes: number;
  adminEmailed: boolean;
  fanEmailed: boolean;
}

/** A fan's "I sent it": Access/<uid> -> pending (unless active), once-only
 *  Notified on the claim, then one push per admin + the admin email
 *  (claimAdmin) and the fan's push + email (claimReceived). A stray claim on
 *  an active record is logged, marked superseded and never notifies. */
export async function handleAccessClaimCreated(
  deps: AccessDeps, args: ClaimCreatedArgs,
): Promise<ClaimCreatedResult | null> {
  const { db, pusher, mailer, auth, nowMs } = deps;
  const log = deps.log ?? silent;
  const { sport, season, uid, key } = args;
  const root = fantasyRoot(sport, season);
  const claimPath = `${root}/AccessClaims/${uid}/${key}`;
  const ctx = { sport, season, uid, key };

  const claim = claimFrom(await db.read(claimPath));
  if (claim === null) {
    log.warn('fantasy access: claim unreadable or not venmo/zelle — ignored', ctx);
    return null;
  }
  if (claim.resolved !== null) {
    log.info('fantasy access: claim already resolved — ignored', { ...ctx, resolved: claim.resolved });
    return null;
  }

  const res = await db.transaction(`${root}/Access/${uid}`, (current) => {
    if (isPlainMap(current) && current['Status'] === 'active') return undefined;
    return { ...pendingFor(claim, nowMs), ...keepNotified(current) };
  });
  if (!res.committed) {
    log.info('fantasy access: claim on an active record — ignored', ctx);
    await db.write(`${claimPath}/Resolved`, 'superseded');
    await db.write(`${claimPath}/ResolvedAt`, nowMs);
    await db.write(`${claimPath}/ResolvedBy`, 'system');
    return null;
  }
  // A second claim replaces the first for the admin (§6).
  const superseded = await supersedeOpenClaims(db, root, uid, 'system', nowMs, key);
  log.info('fantasy access: claim opened — pending', {
    ...ctx, method: claim.method, amountDollars: claim.amountDollars, superseded,
  });

  if (!(await db.writeIfAbsent(`${claimPath}/Notified`, true))) {
    log.info('fantasy access: claim already notified — skip', ctx);
    return null;
  }

  const who = await resolveFanName(db, root, uid, 'a manager');
  const vars: TemplateVars = {
    name: who.name,
    teamName: who.teamName,
    amount: formatAmount(dollarsToCents(claim.amountDollars)),
    season: seasonLabel(sport, season),
    method: methodLabel(claim.method),
    date: formatAccessDate(nowMs),
  };
  const data = accessPushData(sport, season);

  // (a) + (b): the admins.
  const adminT = await resolveTemplate(db, 'claimAdmin', log);
  const admins = adminUidsOf(await db.read('Admins'));
  const adminPushes = admins.length === 0 ? 0 : await pusher.sendToUsers(admins.map((a) => ({
    uid: a,
    title: fillTemplate(adminT.pushTitle, vars),
    body: fillTemplate(adminT.pushBody, vars),
    data,
  })));
  const adminEmail = await resolveAdminEmail(db);
  await mailer.send(adminEmail, fillTemplate(adminT.emailSubject, vars),
    emailHtml(fillTemplate(adminT.emailBody, vars)));

  // (c): the fan — push + email (claimReceived).
  const fanT = await resolveTemplate(db, 'claimReceived', log);
  const fanVars: TemplateVars = { ...vars, name: who.teamName ? who.name : firstNameOf(who.name) };
  await pusher.sendToUsers([{
    uid,
    title: fillTemplate(fanT.pushTitle, fanVars),
    body: fillTemplate(fanT.pushBody, fanVars),
    data,
  }]);
  const fanEmail = await auth.emailOf(uid);
  if (fanEmail) {
    await mailer.send(fanEmail, fillTemplate(fanT.emailSubject, fanVars),
      emailHtml(fillTemplate(fanT.emailBody, fanVars)));
  } else {
    log.info('fantasy access: no email on file — push only', ctx);
  }
  log.info('fantasy access: claim notified', {
    ...ctx, admins: admins.length, adminPushes, adminEmail, fanEmailed: fanEmail !== null,
  });
  return { pending: true, adminPushes, adminEmailed: true, fanEmailed: fanEmail !== null };
}

/** "Hi {name}" for a fan without a team name reads the first name only. */
function firstNameOf(name: string): string {
  return name.split(/\s+/)[0] ?? name;
}

// ── Status written (§7 onFantasyAccessStatusWritten) ────────────────────────

export interface StatusWrittenArgs {
  sport: string;
  season: string;
  uid: string;
  before: unknown;
  after: unknown;
}

export interface StatusWrittenResult {
  template: TemplateKey;
  pushed: number;
  emailed: boolean;
}

/** Status became 'active' or 'revoked': once per PaidAt / RefundedAt
 *  (Access/<uid>/Notified/<key>), push + email the fan with activatedPaid
 *  (card/venmo/zelle — the receipt) / activatedGranted (the rest) /
 *  revoked. No email on file -> push only. */
export async function handleAccessStatusWritten(
  deps: AccessDeps, args: StatusWrittenArgs,
): Promise<StatusWrittenResult | null> {
  const { db, pusher, mailer, auth, nowMs } = deps;
  const log = deps.log ?? silent;
  const { sport, season, uid, before, after } = args;
  if ((after !== 'active' && after !== 'revoked') || before === after) return null;
  const root = fantasyRoot(sport, season);
  const ctx = { sport, season, uid, status: after };

  const rec = accessRecordFrom(await db.read(`${root}/Access/${uid}`));
  if (rec === null || rec.status !== after) {
    log.info('fantasy access: record gone or changed again — skip notify', ctx);
    return null;
  }
  const key = notifyKeyFor(after, rec);
  if (key.endsWith('_unknown')) {
    log.warn('fantasy access: record has no PaidAt/RefundedAt stamp — notifying once ever', ctx);
  }
  if (!(await db.writeIfAbsent(`${root}/Access/${uid}/Notified/${key}`, true))) {
    log.info('fantasy access: already notified — skip', { ...ctx, key });
    return null;
  }

  const template: TemplateKey = after === 'revoked'
    ? 'revoked'
    : PAID_VIAS.includes(rec.via) ? 'activatedPaid' : 'activatedGranted';
  const t = await resolveTemplate(db, template, log);
  const who = await resolveFanName(db, root, uid, 'there');
  const stamp = after === 'active' ? rec.paidAt : rec.refundedAt ?? null;
  const vars: TemplateVars = {
    name: who.teamName ? who.name : firstNameOf(who.name),
    teamName: who.teamName,
    amount: formatAmount(rec.amountCents),
    season: seasonLabel(sport, season),
    method: methodLabel(rec.via),
    date: formatAccessDate(stamp ?? nowMs),
    // {reason} is admin-only — never filled for a fan template.
  };
  const pushed = await pusher.sendToUsers([{
    uid,
    title: fillTemplate(t.pushTitle, vars),
    body: fillTemplate(t.pushBody, vars),
    data: accessPushData(sport, season),
  }]);
  const email = await auth.emailOf(uid);
  if (email) {
    await mailer.send(email, fillTemplate(t.emailSubject, vars),
      emailHtml(fillTemplate(t.emailBody, vars)));
  } else {
    log.info('fantasy access: no email on file — push only', ctx);
  }
  log.info('fantasy access: status notified', {
    ...ctx, key, template, via: rec.via, by: rec.by, pushed, emailed: email !== null,
  });
  return { template, pushed, emailed: email !== null };
}

// ── Registration Paid flip (§7 onRegistrationPaidGrantFantasy) ──────────────

export interface RegistrationPaidArgs {
  regId: string;
  uid: string;
  /** The Paid value after the write. */
  paid: unknown;
  nowMs: number;
  log?: FantasyLogger;
}

/** A registration submission flipped to Paid: when the matching fantasy
 *  season is in pass mode with RegisteredPlayersFree and the uid is not
 *  active, grant {active, player, 0, system}. Unpaid flips never remove
 *  access. */
export async function grantFantasyAccessForRegistration(
  db: FantasyDb, args: RegistrationPaidArgs,
): Promise<{ granted: boolean }> {
  const log = args.log ?? silent;
  const ctx: Record<string, unknown> = { regId: args.regId, uid: args.uid };
  if (args.paid !== true) return { granted: false };

  const target = registrationTargetFrom(await db.read(`Registrations/${args.regId}/Config`));
  if (target === null) {
    log.info('fantasy access: registration config unreadable — no grant', ctx);
    return { granted: false };
  }
  const root = fantasyRoot(target.league, target.season);
  ctx['sport'] = target.league;
  ctx['season'] = target.season;
  const cfg = accessConfigFrom(await db.read(`${root}/Config/Access`));
  if (!isPassMode(cfg)) {
    log.info('fantasy access: season not in pass mode — no grant', ctx);
    return { granted: false };
  }
  if (!cfg.registeredPlayersFree) {
    log.info('fantasy access: registered players do not play free — no grant', ctx);
    return { granted: false };
  }
  const res = await db.transaction(`${root}/Access/${args.uid}`, (current) => {
    if (isPlainMap(current) && current['Status'] === 'active') return undefined;
    return { ...activationFor('player', 0, args.nowMs, 'system'), ...keepNotified(current) };
  });
  if (!res.committed) {
    log.info('fantasy access: already active — no grant', ctx);
    return { granted: false };
  }
  const superseded = await supersedeOpenClaims(db, root, args.uid, 'system', args.nowMs);
  log.info('fantasy access: granted', { ...ctx, via: 'player', by: 'system', superseded });
  return { granted: true };
}

// ── "Send me a test" (§7 sendFantasyAccessTest) ─────────────────────────────

export interface AccessTestArgs {
  sport: string;
  season: string;
  /** The admin caller — the push and email go to them. */
  uid: string;
  template: TemplateKey;
  /** The caller's display name; blank -> "Zaya". */
  displayName: string;
}

/** Fills [template] with sample values and sends its push + email to the
 *  caller. {pushed} = a device took it; {emailed} = an email was on file. */
export async function sendAccessTestMessage(
  deps: AccessDeps, args: AccessTestArgs,
): Promise<{ pushed: boolean; emailed: boolean }> {
  const { db, pusher, mailer, auth, nowMs } = deps;
  const log = deps.log ?? silent;
  const root = fantasyRoot(args.sport, args.season);
  const cfg = accessConfigFrom(await db.read(`${root}/Config/Access`));
  const name = args.displayName.trim() || 'Zaya';
  const vars: TemplateVars = {
    name,
    teamName: `${name} FC`,
    amount: formatAmount(dollarsToCents(cfg.amountDollars)),
    season: seasonLabel(args.sport, args.season),
    method: 'Venmo',
    date: formatAccessDate(nowMs),
    reason: 'Test message',
  };
  const t = await resolveTemplate(db, args.template, log);
  const pushed = await pusher.sendToUsers([{
    uid: args.uid,
    title: fillTemplate(t.pushTitle, vars),
    body: fillTemplate(t.pushBody, vars),
    data: accessPushData(args.sport, args.season),
  }]);
  const email = await auth.emailOf(args.uid);
  if (email) {
    await mailer.send(email, `[Test] ${fillTemplate(t.emailSubject, vars)}`,
      emailHtml(fillTemplate(t.emailBody, vars)));
  }
  log.info('fantasy access: test message sent', {
    sport: args.sport, season: args.season, uid: args.uid, template: args.template,
    pushed, emailed: email !== null,
  });
  return { pushed: pushed > 0, emailed: email !== null };
}

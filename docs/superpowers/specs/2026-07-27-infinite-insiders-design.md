# Infinite Insiders — Final Engineering Spec (v3, owner-approved decisions)

**Date:** 2026-07-27 · **Repos:** infinite_sports_flutter (fan) + InfiniteSportsManagerFlutter (Manager) + functions (fan repo `functions/src`) · **Status:** design locked, awaiting build kickoff.

Supersedes the owner's v1 TXT and v2 PDF drafts. Every rule below reflects an explicit owner decision (2026-07-26/27) reconciled with the app's real architecture (RTDB, Riverpod Manager, auth-walled fan app, Stripe-test + Venmo/Zelle/cash manual payments).

## 1. Program summary

Insiders are approved members who recruit players into Infinite Sports leagues, tournaments, and events. Each Insider has a unique promo code. New players enter the code at registration; the Insider's referral count grows; tiers unlock growing discounts on the Insider's OWN registrations. An optional, per-registration "first-timer promo" gives the referred newcomer a percentage discount. Everything is real-time in both apps and fully audited.

## 2. Tiers (five, cross-sport, cumulative)

| Tier | Referrals | Insider's own-fee discount |
|---|---|---|
| Bronze | 5 | 5% (permanent floor — never drops below) |
| Silver | 10 | 10% |
| Gold | 15 | 15% |
| Platinum | 20 | 20% |
| Infinite | 25+ | 25% |

- Referrals count across ALL sports/offerings into one global ladder.
- **Two public numbers per Insider:** `totalReferred` (lifetime; only decreases on refund-voids) and `currentStanding` (ladder progress counter; this is what tiers read).
- **Inactivity (Silver and above):** zero new counted referrals for 6 consecutive months → drop one tier. On a drop, `currentStanding` resets to the dropped-to tier's threshold (Silver→Bronze lands at 5; 5 more reaches Silver again). Bronze never drops.
- **Infinite maintenance:** needs 5 counted referrals per calendar year (America/Los_Angeles) to stay; otherwise drop to Platinum (standing resets to 20; 5 more re-earns Infinite).
- Reminders: 5-month nudge, 2-weeks-left warning, drop notice — via existing FCM infra.
- Tier discount applies to the Insider's **individual** registration fees only (never team fees). Non-stacking rules in §5.

## 3. Referral lifecycle (owner-simplified — no participation gate)

- **COUNTED** the moment the referred registration is marked **fully paid** (Stripe webhook success, or admin flips Paid for Venmo/Zelle/cash). No attendance requirement.
- **VOIDED** if that registration is later refunded/cancelled: the referral is removed, `totalReferred` and `currentStanding` decrease by 1, and the tier recomputes (may drop). Already-redeemed Insider discounts are NOT clawed back. Every void is logged with reason.
- **VERIFIED (automatic bonus flag):** when the referred player records their first stat in any game, the referral is auto-marked "verified on the field" (a ✓ in dashboards). Purely informational integrity signal — gates nothing, costs the owner zero effort.
- **Unique-person rule (anti-farming, owner-confirmed):** a given user can be referred ONCE, globally, ever — their first fully-paid registration with a valid code — and can USE a referral code only once. A second attempt shows an error at entry time ("A referral code has already been used on this account."). Duplicate-identity attempts (new account, same/similar name or recycled phone/email) are surfaced as flags in the Manager referral list; when the owner catches one, the **manual void** (§6) removes the referral and decrements the Insider — this is the designed recovery path for fraud that slips through.
- **Team registrations:** the paying captain = ONE referral (config `allowTeamMultiCredit`, default off). Team members who later register and pay individually count as themselves.
- Existing (non-first-time) players entering a code: **no newcomer discount** (friendly message), and per the unique-person rule, credit only if this person was never referred before.

## 4. First-timer promo engine (per-registration, toggleable)

- Manager registration wizard gains: `promoEnabled` (default off), `promoPercent`, optional start/end dates, optional `maxRedemptions`. Live-editable; changes take effect immediately.
- First-time check (deterministic only): normalized email (lowercase, trimmed) and normalized phone (digits-only) against ALL prior registration submissions + existing accounts. Match on either → existing. Name-only matches against paper-era rosters are IGNORED (owner-accepted win-back: returning old-timers may pass as new).
- Result UX: eligible → "Registering with [Insider]'s code — X% off applied!" + itemized receipt (Base fee | Promo −$Z | Total). Not eligible → "Welcome back! This promo is for first-time players, so the discount doesn't apply."
- Discount math runs **server-side** for Stripe (`functions` payment callable computes the charge). Manual methods (Venmo/Zelle/cash) show the discounted amount owed; admin verifies on receipt as today.
- Discounts compute against the registration's eligible fee only.

## 5. Discount stacking & ceiling

- Sources: Insider tier discount (own registrations) · first-timer promo (newcomer registrations) · manual admin adjustment.
- Automatic discounts NEVER stack: best-discount-wins. Manual adjustment overrides everything but is capped by `maxTotalDiscountPct` (default 25; admin warned on cap). Comp-to-$0 allowed, audited.

## 6. Manager app — admin controls

- **Insider Applications inbox** with red badge counts on the dashboard tile (matching pending-registrations badges, also added). Approve → code generated `[INITIALS][6 alphanumeric]` (editable before save) → Insider activated + FCM notification with code. Decline → polite notification; reapply allowed.
- **Insiders list:** search, tier/standing/totals, per-sport breakdown, code, status (active/suspended). Suspend disables the code; already-counted referrals stand. Manual tier/standing adjustment and manual referral add/void — all with required reason.
- **Manual payment adjustment (independent P1 item):** on any registration submission — edit amount owed / apply discount / comp, required reason, immutable audit (admin, timestamp, old→new). Fan payment/status screens already stream live, so changes appear on the player's phone instantly with no refresh.
- First-timer status grant/revoke per submission (fixes wrong automated determinations).

## 7. Fan app — Insider experience

- **Profile-area card** "Infinite Insiders": info + terms → Accept & Apply (name, email, sports of interest). Status shown while pending.
- **On approval, a 5th bottom-nav tab appears** (Insider-only — the app visibly "unlocks" it): tier badge + progress bar, `totalReferred` / `currentStanding`, promo code with copy + share button (share sheet invite text), referral list (name, sport, date, counted/voided/✓verified), per-sport breakdown, Infinite-maintenance meter, inactivity countdown, link to the public leaderboard hub.
- **Push notifications:** +1 referral ("🎉 Sara joined Futsal with your code"), tier up/down, maintenance reminders.
- **Privacy model (owner-approved):** the tab is PRIVATE to the Insider (its referral list contains other users' data). Public exposure = leaderboard row + an **Infinite Insider box on the public profile, placed between the player-info section and the Current Team section**, showing exactly two lines: `Status: <Tier>` and `Total Referrals: <N>` (anything deeper lives in the Insider Hub). Both leaderboard row and profile box individually opt-out-able in the Insider tab settings.

## 8. Public leaderboard (Search hub)

- Lives in the Search/hub page alongside Around You. Ranks active Insiders by counted referrals; shows display name, tier + icon, totals, per-sport breakdown; program-wide stats header (total insiders, total players brought in, this month); Top 3 highlight; filters by sport/tier/period. Opt-out respected. Real-time stream.

## 9. Data (RTDB)

```
/Insiders/<uid>: { Code, Status(pending/active/suspended/declined), Tier, CurrentStanding,
  TotalReferred, CurrentYearCount, LastReferralAt, PublicLeaderboardOptIn, ProfileBadgeOptIn,
  ApprovedBy, ApprovedAt, SportsOfInterest, AppliedAt }
/InsiderCodes/<CODE>: <uid>                      # O(1) validation lookup
/Referrals/<pushId>: { InsiderUid, ReferredUid, RegistrationId, Sport, OfferingType,
  IsTeamRegistration, State(counted/voided), Verified(bool), CountedAt, VoidedAt, VoidReason }
/ReferredUsers/<uid>: <referralId>               # global once-ever guard
/Registrations/<regId>/Promo: { Enabled, Percent, Start, End, MaxRedemptions, Used }
/Registrations/.../submissions/<id>: + { InsiderCode, FirstTimer, DiscountSource, DiscountPct,
  DiscountAmount, EligibleFee }
/InsiderAudit/<pushId>: { AdminUid, Target, Field, Old, New, Reason, At }   # immutable
```

## 10. Automation (functions)

- Payment watcher: submission flips to fully-paid + valid code + not-already-referred → create counted referral, bump counters, recompute tier, notify. Refund/unpaid flip → void + recompute + notify.
- Stat watcher: referred player's first recorded stat → set Verified.
- Daily scheduled job (existing scheduler pattern): inactivity reminders/warnings/drops; Infinite annual maintenance; year rollover.
- Monthly: leaderboard "top insiders" highlight refresh.
- All Stripe amounts computed server-side; code validation via `/InsiderCodes` single read.

## 11. Edge cases (test list)

- Paid → refunded after tier-up (void, tier drops, no clawback of redeemed discounts)
- Same person tries a second code / re-registers next season (once-ever guard blocks credit)
- Captain pays for 10 (one referral; config flip = many)
- Two discounts eligible (best wins; ceiling caps manual overrides)
- Promo on for Futsal 16, off for a tournament (scope isolation)
- Suspended insider's code entered (rejected with message; history stands)
- First-timer false negative (admin grant + manual referral add)
- Paper-era player passes as first-timer (accepted by design)
- Comp to $0 (allowed, audited, streams live)
- Self-referral: own code on own registration → rejected

## 12. Delivery phases

- **P1** — Manual payment adjustment + audit (standalone value, ships first); Insider models/paths; application flow + Manager inbox with badges; code generation/approval.
- **P2** — Registration promo-code field + first-timer engine + per-registration promo config; payment watcher counting/voiding; once-ever guard.
- **P3** — Insider 5th tab (dashboard, share, notifications); tier engine + insider self-discount at checkout; stat-verify watcher.
- **P4** — Public leaderboard in Search hub + profile tier badge; scheduled inactivity/maintenance jobs; polish + full e2e with owner.

Standards throughout: real-time streams, light+dark correctness, TDD for all pure logic, twins byte-identical where shared, functions deploy owner-gated, all commits local until owner says push.

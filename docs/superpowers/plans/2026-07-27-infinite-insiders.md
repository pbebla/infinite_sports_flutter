# Infinite Insiders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Infinite Insiders referral program per the locked spec `docs/superpowers/specs/2026-07-27-infinite-insiders-design.md` (v3 + owner's profile-box/once-per-person amendments).

**Architecture:** RTDB nodes (`/Insiders`, `/InsiderCodes`, `/Referrals`, `/ReferredUsers`, `/InsiderAudit`, per-registration `Promo`), pure Dart helpers TDD'd in both apps, functions watchers for counting/voiding/verify + scheduled tier-maintenance job, real-time streams everywhere, light+dark.

**Branches:** `zaya-insiders` off `zaya-features` in BOTH repos. Fan = release builds, Manager = debug. Commits local; functions deploy owner-gated.

---

### Phase P1 — Manual payment adjustment + Insider foundation

**Task M1 (Manager): manual fee adjustment + audit**
- [ ] Pure helpers (TDD): `adjustedTotal(submission)` honoring `AdjustedFee`/`DiscountAmount`/`DiscountSource(manual)`; validation (0 ≤ adjusted ≤ original; ceiling from config `maxTotalDiscountPct` default 25 unless comp-to-0 confirmed)
- [ ] Submission editor: "Adjust payment" action — set new amount OR percent off OR comp $0, REQUIRED reason field; writes submission fields + `/InsiderAudit` entry (admin uid, old→new, reason, timestamp)
- [ ] Providers refresh; verify Manager submissions row shows adjusted amount + audit history sheet

**Task F1 (fan): adjusted amount display**
- [ ] Payment/status screens show adjusted total with line item ("Adjusted by Infinite Sports −$X") — screens already stream live, so no refresh work needed; verify with a manual RTDB edit

**Task M2 (Manager): Insider models + application inbox + approval**
- [ ] Models (TDD parsers): Insider, Referral; FirebasePaths additions per spec §9
- [ ] `codeFor(initials)` generator `[INITIALS][6 alphanumeric]` (TDD, collision-checked against `/InsiderCodes`)
- [ ] Applications inbox page (pending list, live stream) + Approve (generate/edit code, activate, write `/InsiderCodes`, FCM notify) / Decline (notify)
- [ ] Insiders list page: search, tier/standing/totals, suspend/reactivate, manual referral add/void with reason (audit), manual tier/standing adjust (audit)
- [ ] Dashboard tiles gain red badge counts (pending Insider applications; pending registrations tile too)

**Task F2 (fan): application flow**
- [ ] Profile-area "Infinite Insiders" card → info/terms page → Accept & Apply (name/email prefilled, sports of interest chips) → writes `/Insiders/<uid>` status pending → pending/declined states shown on card

### Phase P2 — Promo engine + referral counting

**Task F3 (fan): promo-code field + first-timer engine**
- [ ] Pure (TDD): `normalizeEmail`, `normalizePhone`, `firstTimerCheck(email, phone, priorSubmissions)`, `discountedFee(eligible, pct)`, once-ever guard check against `/ReferredUsers`
- [ ] Registration form: optional "Insider Promo Code" field (individual + team-captain paths); validate via `/InsiderCodes` + Insider active; self-referral rejected; already-referred → error per spec; first-timer + promo enabled → show % applied + itemized receipt; existing player → friendly no-discount message
- [ ] Submission writes: InsiderCode, FirstTimer, DiscountSource/Pct/Amount, EligibleFee

**Task M3 (Manager): per-registration promo config**
- [ ] Registration wizard + edit page: promo toggle, percent, optional dates/max redemptions (live-editable)
- [ ] Submissions page surfaces code used, first-timer flag, discount source; first-timer grant/revoke action (audit)

**Task X1 (functions): counting/voiding watcher**
- [ ] TDD (vitest): pure decide fns — onPaidFlip(create counted referral if code valid + once-ever passes), onRefundOrUnpaid(void + decrement + recompute), tier recompute from currentStanding
- [ ] RTDB triggers on submission payment-status changes; writes `/Referrals`, `/ReferredUsers`, Insider counters; FCM "+1 referral" to Insider; Stripe callable applies server-side discount math

### Phase P3 — Insider tab + tier engine

**Task F4 (fan): 5th nav tab (Insider-only)**
- [ ] Nav conditionally adds Insider tab when `/Insiders/<uid>` status==active (live stream — appears the moment approval lands)
- [ ] Dashboard page: tier badge + progress bar, totalReferred/currentStanding, code + copy + share sheet, referral list (name, sport, date, counted/voided/✓verified), per-sport breakdown, Infinite maintenance meter, inactivity countdown, leaderboard link, opt-out toggles (leaderboard, profile box)
- [ ] Tier-up celebration banner + FCM handling

**Task X2 (functions): tier maintenance + verify watcher**
- [ ] Scheduled daily job: inactivity 5mo reminder / 5.5mo warning / 6mo drop (floor Bronze), Infinite annual maintenance (America/Los_Angeles), notifications on change
- [ ] Stat watcher: referred player's first stat → `Verified: true`

**Task F5/M4: insider self-discount at checkout**
- [ ] Fan individual-registration payment applies active Insider's tier % (best-discount-wins vs promo; server-side for Stripe); receipt line

### Phase P4 — Public surfaces + ship

- [ ] F6: Leaderboard in Search hub (rank by counted referrals, tier icons, per-sport, program stats header, Top 3, filters, opt-out respected, live)
- [ ] F7: Profile "Infinite Insider" box between player info and Current Team: `Status: <Tier>` / `Total Referrals: <N>` (opt-out respected)
- [ ] Full verification both repos + functions; builds to owner phone; owner e2e script (apply→approve→code→referred signup w/ promo→pay→+1→refund→void→tier flows); deploy functions on owner's word; merge on owner's word

**Every task:** TDD pure logic first, flutter test green (fan 688 / Manager 743 baselines), analyze zero-net-new, stage only named files, commits local with Co-Authored-By trailer, light+dark, real-time.

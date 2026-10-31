# Fantasy Achievement Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Automatic + owner-assignable achievement badges for fantasy managers, shown in the fan app and managed in the Manager.

**Architecture:** The finalize pipeline computes weekly auto awards per manager (deterministic ids, rerun-safe) and a sweep check awards season-end badges (also into the existing trophy cabinet); a create-trigger pushes each new award once. The fan app streams the catalog + awards into a badge shelf, sheet and leaderboard count; the Manager edits the catalog and gives/removes badges.

**Tech Stack:** Cloud Functions v2 (TypeScript, vitest), Flutter (fan: plain streams; Manager: Riverpod), RTDB, Storage.

**Spec:** `docs/superpowers/specs/2026-10-30-fantasy-badges-design.md` — every shape, rule and copy lives there; read it first.

## Global Constraints
- No RTDB `.get()` in Flutter (Manager guard test); live streams; light + dark via colorScheme; names wrap; one fade reveal; destructive actions confirm; never delete files; iOS parity; commits local with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; never push/deploy (controller deploys).
- Finalize stays rerun-idempotent; manual awards are never modified by the engine; voided weeks award nothing; pushes once-only.
- Test-season fill writes only under `Fantasy/Futsal/15/`.

## Review Focus
1. A score correction re-runs week N: auto awards for N must match the new scores exactly (added AND removed); manual awards untouched.
2. Ties: two managers tied for top of the week / champion → both get it; captain tied with another starter → still Captain Genius.
3. Bench Boost week → no Bench Boss; Free Hit / Wildcard weeks score normally.
4. Paused season (lockOverride open/locked) → no auto awards computed, but a manual award still pushes once.
5. Long badge names / many badges at 360 px in light + dark — shelf and count chip wrap without overflow.

---

### Task B1: Engine + rules + push (fan repo functions/)
**Files:** create `functions/src/lib/fantasy/badges.ts` (+ `badges.test.ts`), `functions/src/fantasy_badges.ts` (create-trigger); modify `orchestration.ts` (finalize hook + sweep season-end check + catalog seeding), `index.ts`, both rules files, `functions/tools/fill_test_season_logic.ts` + `rehearse_s15.ts` (read `Futsal/15/Finished`; allowlist `Badges`, `BadgePushClaims`).
**Interfaces (Produces):** pure `weeklyAutoAwards(input: {gw, squadsByUid, historyByUid, playerWeeks, dreamTeamNames, ownershipPctByName, gameweekBoard, voided, chipByUid, catalog}) → Record<uid, Record<awardId, AwardRow>>`; `seasonAutoAwards(input: {overallBoard, historyWeeksByUid, allWeeks, catalog}) → same`; `STARTER_CATALOG: Record<badgeId, CatalogEntry>`; award row `{Badge, Gw?, At, Source:'auto'}`; cabinet award via the deterministic-id helper (port `deterministicAwardId` from the Manager's `lib/services/award_engine.dart`).
- [ ] Failing tests for each rule + Review Focus 1–4 → implement → `npm test`, `npm run build`, `npm run rehearse:s15 -- --offline` (invariants), `npm run fill:s15` dry run (plan builds) → commit.

### Task B2: Fan app (lib/fantasy/…)
**Files:** parsers + `FantasyService.watchBadgeCatalog()` / `watchBadges(sport, season)`; create `lib/fantasy/hub/badge_shelf.dart` (shelf, chip, detail sheet, count chip); modify `lib/profile/fantasy_profile_tab.dart` (manager section shelf), `lib/fantasy/hub/manager_squad_viewer.dart` (shelf at top), `lib/fantasy/hub/leaderboard_rows.dart` (count chip on Overall + Gameweek rows); trophy cabinet renders `ScopeType 'fantasy'` awards.
- [ ] Failing tests (parsers, grouping ×N, sheet text, count chip, 360 px light/dark) → implement → `flutter test` full + analyze → commit.

### Task B3: Manager
**Files:** models/providers/service for catalog + awards; create `lib/ui/fantasy/fantasy_badges_page.dart` (+ route `/fantasy/badges`, section tile); modify `lib/ui/fantasy/fantasy_profile_detail_page.dart` (Badges section: list, Give badge dialog as a StatefulWidget owning its controllers, remove with confirm); Storage upload for badge pictures.
- [ ] Failing tests (catalog CRUD writes, never delete — Active off, give/remove paths + confirm, guard test) → implement → `flutter test` full + analyze → commit.

### Task B4 (controller): deploy all fantasy functions + new trigger + rules; re-fill S15 (clear with the current backup, apply); build + install both apps; owner walkthrough.

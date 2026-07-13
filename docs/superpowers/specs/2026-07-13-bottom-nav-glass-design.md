# Bottom Nav Redesign + Glass Foundation — Design Spec

**Date:** 2026-07-13
**Epic:** Calendar & Events (piece 1 of 5)
**Repo:** infinite_sports_flutter (fan app only; no manager-app changes in this piece)
**Owner decisions captured from brainstorming session with Zayaa.**

## Goal

Replace the current docked Material 3 `NavigationBar` with a floating frosted-glass
pill (FotMob-style): four tabs — Matches, Leagues, Tournaments, Calendar — plus a
separate round search button that opens a new Search + Hub page. Around You moves
off the bottom bar into the hub. This piece also establishes the reusable "glass"
style component the rest of the app will adopt.

## Epic context (agreed build order)

1. **This piece** — new bottom nav + glass foundation.
2. Calendar screen + upgraded event data (categories, flyers) + manager form upgrade.
3. Event detail page rebuild (flyer, contact organizer, share, add-to-phone-calendar, remind me).
4. Smart notifications (favorite sports onboarding, audience targeting, scheduled sends).
5. Growth extras (deep links that open the app, etc.).

Each piece: own feature branch in a separate git worktree (another session works in
the main checkout) → build → owner tests on phone → merge to `zaya-features`.

## Design

### 1. Floating glass bar

- Frosted translucent pill containing 4 destinations: Matches, Leagues, Tournaments,
  Calendar. A detached circular glass search button sits to its right.
- Implemented with `BackdropFilter` blur over app content; `Scaffold.extendBody: true`
  so pages scroll underneath the bar and blur through it.
- Active tab tinted Infinite Sports red (`infiniteSportsPrimaryColor`); inactive
  items muted. Labels under icons, short label "Tourneys" only if "Tournaments"
  doesn't fit.
- Dark AND light mode: translucent-dark glass over dark theme, translucent-light
  glass over light theme. No hardcoded single-mode fills (standing owner rule).
- Existing tab behavior unchanged: `IndexedStack` + the existing
  `CurrentLivescoreNavigation`, `LeaguesNavigation`, `TournamentsNavigation`
  (lazy-built) stay as-is. Drawer (`lib/navbar.dart`) unchanged.
- Every page that sits under the bar needs bottom padding/safe-area handling so
  list content isn't permanently hidden behind the pill.

### 2. Calendar tab — temporary version

- Real calendar ships in piece 2. Until then the Calendar tab shows a simple
  "Upcoming events" list backed by the existing `getEvents()` / `Events` RTDB list,
  reusing the existing event row UI where practical. Tapping an event opens the
  existing `eventpage.dart`.
- This placeholder screen is built to be swapped wholesale for the piece-2 calendar.

### 3. Search + Hub page

- Opened by the round glass button. Layout: search field on top, hub cards below.
- Hub cards at launch: **Around You only** (owner decision — grows one card per
  future section). Tapping it opens the existing `AroundYou` screen (pushed, since
  it no longer owns a bottom tab).
- Search scope: teams, players, leagues/tournaments, and events — matching against
  data the app already caches/fetches (team names + logos, lineup player names,
  tournament/league names, event titles). Results grouped by type as you type.
  Client-side filtering only; no backend/search index in this piece.
- Tapping a result deep-links to the right existing page (team page, player page,
  tournament detail, event page) where a route exists; types without a sensible
  destination are omitted from results rather than dead-ending.

### 4. Glass foundation (reusable)

- One reusable glass surface widget (blur + translucent tint + hairline border,
  theme-aware) lives in `lib/widgets/`. The nav pill and search button are its
  first two consumers; later pieces (calendar chrome, event pages) reuse it so the
  look stays consistent app-wide.

### 5. Out of scope for this piece

- The real calendar UI, event categories/filters, flyer upload (piece 2).
- Event page rebuild, contact/share/reminders (piece 3).
- Notification targeting, favorite sports onboarding (piece 4).
- Deep links / social share improvements (piece 5).
- Manager app changes.

## Error handling

- Search over data that hasn't loaded yet: show a lightweight loading state, never
  crash on empty caches; results simply appear as sources finish loading.
- Events list unavailable/offline: Calendar placeholder shows a friendly empty
  state ("No upcoming events") rather than an error.

## Testing

- `flutter analyze` clean on changed files.
- Manual matrix on device (owner + Claude): all 4 tabs navigate; content scrolls
  under the glass and stays reachable (bottom padding); dark/light both look right;
  search finds a known team, player, tournament, and event and opens each; Around
  You fully works from the hub; drawer unaffected; notifications deep links still
  open match pages.

## Delivery

- Branch `zaya-nav-glass` in a separate worktree (main checkout stays free for the
  other session). Build → install on owner's phone → owner sign-off → merge to
  `zaya-features`.

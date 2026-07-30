# Growth Links (Epic P5) — Design Spec

**Date:** 2026-07-15
**Epic:** Calendar & Events (piece 5 of 5 — final)
**Owner facts:** app live on Google Play + Apple App Store; no control of
infinitesports.org hosting (smart universal links deferred until that exists).

## Goal

Every shared event becomes a download funnel: the share message ends with
store links so a recipient without the app can get it in one tap. Links are
owner-configurable in the manager (no app release needed to change them).

## Data

`AppConfig/StoreLinks { Android: <url>, iOS: <url> }` in RTDB.
Fan app falls back to the derivable Play URL
(https://play.google.com/store/apps/details?id=com.infinitesports.Infinite_Sports_App)
when the node is absent; iOS omitted until set.

## Fan app

- `lib/misc/app_config.dart`: `getStoreLinks()` — one read, session-cached,
  fallback as above.
- `event_share.dart`: CTA becomes
  "Download the Infinite Sports app for details and to sign up!" plus
  "Android: <link>" / "iPhone: <link>" lines for whichever links exist.
  `buildShareMessage` stays pure (links passed in); event page fetches links
  before sharing.

## Manager app

- Drawer → "App Links": two labeled fields (Google Play URL, App Store URL)
  with Save + confirm; writes `AppConfig/StoreLinks`. MenuButton in the bar.

## Later (needs website control)

infinitesports.org/event/<id> universal links: tap opens the app straight to
the event when installed, else a flyer page with store buttons. Requires
hosting assetlinks.json + apple-app-site-association. The share format keeps
a single-link upgrade path.

## Testing

Unit: CTA with both/one/no links; fallback link logic. Manual: share an
event → message ends with tappable store links; edit links in manager →
next share uses them.

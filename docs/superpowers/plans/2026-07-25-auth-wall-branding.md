# Auth Wall + Branding Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hard login wall (Volo/IG-style) with Google sign-in + dormant Apple, 3-step signup with About-You profile questions, and full branding refresh (welcome/splash/header/launcher icon) — per spec `docs/superpowers/specs/2026-07-25-auth-wall-branding-design.md`.

**Architecture:** Auth-state stream gates root widget (WelcomePage vs MyHomePage). Reusable AboutYouPage serves email signup step 2, Google/Apple first-run, and existing-user one-time completion (ProfileCompleted flag, FavoriteSportsAnswered pattern). Art processed offline via PIL from owner's `Downloads/Logo` files.

**Tech stack:** Flutter (fan repo only), firebase_auth, google_sign_in, sign_in_with_apple (iOS-gated), flutter_launcher_icons (already configured), flutter_native_splash (already a dev dep), Python PIL for art.

**Branch:** `zaya-auth-wall` off `zaya-features`. Fan = release builds to owner phone. Commits local.

---

### Phase A — Branding (orchestrator does art inline; subagent wires)

**Task A1 (orchestrator, inline): produce processed art**
- [ ] `assets/welcome_logo.png` — circle logo, downscaled ≤900px, transparency verified
- [ ] `assets/infinite_mark.png` — no-circle mark: gray-gradient bg removed (saturation-based alpha mask; mark is saturated red/blue/yellow, bg is desaturated), cropped to mark only (no wordmark text), transparency verified visually
- [ ] `assets/icon_foreground.png` — mark centered on transparent 1024×1024 canvas at ~60% width (adaptive-icon safe zone)
- [ ] Visual QA via image reads (no stretched/eaten artwork; BoxFit.contain rendering downstream)

**Task A2 (subagent): wire branding**
- [ ] pubspec: `flutter_launcher_icons` image paths → icon_foreground (adaptive fg, white bg; keep `ios: true`); add `flutter_native_splash` config (white bg + welcome_logo; dark variant `#000000` + same logo); run both generators
- [ ] Swap header asset at ALL `infinitelarge_dark.png` call sites → `infinite_mark.png`, header `height: 30` → `32` (≈5%; share cards 34 → keep proportional look)
- [ ] `login.dart` + `settings.dart` old `infinite.png` → circle/mark per spec
- [ ] flutter test + analyze green; commit

### Phase B — Auth wall core

**Task B1 (subagent): WelcomePage + root gate**
- [ ] New `lib/onboarding/welcome_page.dart`: fixed dark branded (both themes), circle logo, headline, buttons: Sign up with Google (wired in Phase C — placeholder callback param now), iOS-only Apple slot, Sign up with Email → CreateAccountPage, "Already have an account? Log In" → LoginPage
- [ ] `main.dart`: root = auth-state gate (`authStateChanges()` StreamBuilder): signed-out → WelcomePage, signed-in → MyHomePage. Auto sign-in ALWAYS on (remove checkbox + pref branching); logout → stream flips → wall
- [ ] Login page: remove Auto Sign In checkbox, add `AutofillHints` (email/password), verify Forgot Password sends reset email (fix if broken), circle logo
- [ ] Drawer/navbar: remove anonymous-mode login entry points (wall guarantees signed-in)
- [ ] Widget tests: welcome buttons render; gate shows WelcomePage when signed out. flutter test + analyze; commit

**Task B2 (subagent): About You page + 3-step signup + existing-user gate**
- [ ] Pure helpers (TDD): DOB/ZIP validators, referral options list, `profileCompleted(Map)` check, post-auth routing decision fn (needsAboutYou/needsFavorites/home)
- [ ] `lib/onboarding/about_you_page.dart` (reusable): DOB picker, City, ZIP, Gender (Male/Female), referral chips (Instagram, Facebook, TikTok, Friend or family, Flyer / promo, At a game or event, Google / app store search, Other), optional phone field (`askPhone` param for Google/Apple first-run); writes Users/<uid> {DOB MM/DD/YYYY, City, Zip, Gender, ReferralSource, ProfileCompleted:true} (+Phone when asked); mandatory (no skip)
- [ ] CreateAccountPage → step 1 of 3 (progress indicator) → AboutYou (step 2) → FavoriteSportsPage (step 3)
- [ ] Existing users: signed-in gate order = ProfileCompleted missing → AboutYou; then FavoriteSportsAnswered missing → favorites (reuse main.dart one-time prompt pattern)
- [ ] Tests green; commit

### Phase C — Google sign-in

**Task C1 (orchestrator, inline): Firebase enablement**
- [ ] Enable Google provider (Identity Toolkit API via CLI token; fallback: walk owner through console)
- [ ] Add debug + release keystore SHA-1/SHA-256 to Firebase Android app; refresh `android/app/google-services.json`

**Task C2 (subagent): flow**
- [ ] `google_sign_in` dep; `signInWithGoogle()` in firebase_auth_services (credential flow, try/catch parity with email methods)
- [ ] Welcome button wiring: new user (`additionalUserInfo.isNewUser` OR missing Users/<uid>) → create profile (names/email from Google) → AboutYou(askPhone:true) → favorites; returning → home
- [ ] Tests + analyze; commit

### Phase D — Apple (dormant) + handoff

**Task D1 (subagent):**
- [ ] `sign_in_with_apple` dep; button rendered only `Platform.isIOS`; credential flow parallel to Google (new-user → AboutYou askPhone → favorites)
- [ ] iOS entitlements entry (`ios/Runner/Runner.entitlements` + Xcode project reference if trivially editable; else document)
- [ ] Handoff doc `docs/superpowers/plans/2026-07-25-apple-signin-ios-handoff.md`: Apple Developer capability + Services ID/key, Firebase Apple provider, device test checklist
- [ ] Tests + analyze; commit

### Phase E — Verify + ship

- [ ] Full flutter test + analyze; release APK → owner phone
- [ ] Owner e2e: fresh signup (email + Google), returning login, existing-account one-time About You, logout→wall, forgot password, splash/header/icon visuals in light+dark
- [ ] Owner sign-off → merge `zaya-auth-wall` → `zaya-features`

**Verification per task:** flutter test green (baseline fan 609), `flutter analyze` clean on touched files, twin rules n/a (fan-only). Standards: light+dark, real-time auth stream, autofill hints.

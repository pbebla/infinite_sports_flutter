# Auth Wall + Branding Refresh — Design Spec

**Date:** 2026-07-25 · **Repo:** infinite_sports_flutter (fan app only — Manager already requires login) · **Branch:** `zaya-auth-wall` off `zaya-features`.

## Goal

Nobody uses the app without an account (Volo/Instagram-style hard gate). Modernize signup (Google one-tap + richer profile questions), pre-build Apple sign-in for the future iOS build, and refresh branding (welcome screen, splash, in-app header logo, launcher icon) using the owner's two new logo files.

## Owner decisions (resolved)

1. **Hard gate:** every screen requires login. Logout returns to the welcome screen instantly (auth-state stream). No guest mode.
2. **Sign-in methods:** Email/password + **Sign up with Google** (Android, live now). **Sign in with Apple** button is BUILT now but renders only on iOS (`Platform.isIOS`) — dormant until Bronsin/Pauldin's iOS work; ship a handoff doc for the Apple Developer + Firebase console steps.
3. **Signup = 3 steps:**
   - Step 1 — Account: first name, last name, email, phone, password (existing page, restyled as step 1 of 3).
   - Step 2 — About you (NEW, reusable page): date of birth (date picker), city (text), ZIP (5-digit), gender (**Male / Female** — owner's explicit spec), "How did you hear about us?" single-select chips: Instagram, Facebook, TikTok, Friend or family, Flyer / promo, At a game or event, Google / app store search, Other. All required.
   - Step 3 — Your interests: existing FavoriteSportsPage (unchanged).
4. **Google signups** skip Step 1 (name/email from Google) → Step 2 additionally collects **phone** (required) → Step 3. Returning Google users go straight into the app.
5. **Existing users:** one-time **mandatory** "Complete your profile" (= Step 2) on next app open, gated by a `ProfileCompleted` flag — same pattern as `FavoriteSportsAnswered`. Not skippable (owner choice).
6. **Session behavior:** auto sign-in becomes the DEFAULT and only behavior (checkbox removed). Signed in stays signed in until explicit logout. Login/signup fields get autofill hints (`AutofillHints.email/password/newPassword` etc.) so Google Password Manager saves/fills credentials.
7. **No biometrics in v1** (auto-login makes Face ID redundant as a login method; optional "App lock" could be a future settings add).
8. **Forgot password** must work on the login page (verify existing link sends the Firebase reset email; fix if broken).

## Branding (owner files in `C:\Users\zayaa\Downloads\Logo\`)

- **`Infinite Sports circle.png`** (transparent, circular badge w/ wordmark): used on the **welcome screen** and the **launch/splash screen** (flutter_native_splash: white background in light, dark variant for dark mode).
- **`Infinite Sports no circle.png`** (mark + wordmark on OPAQUE gray gradient): needs **background removal** (Python PIL pipeline — luminance/edge-aware since bg is a gradient with glow; glows may clip slightly, acceptable) and **crop to mark only** (no INFINITE SPORTS text):
  - **In-app header everywhere** (all `Image.asset('assets/infinitelarge_dark.png', height: 30)` call sites): replace asset with the new mark, height ~31–32 (~5% larger; owner: scale back if too big). Keep one asset name to minimize churn (new file, swap references).
  - **Launcher icon:** flutter_launcher_icons regenerated with the mark (no circle, no text) as adaptive foreground on white background. NOTE: Android launchers mask all icons into circles/squircles — the artwork carries no ring, the OS draws its own. Config already covers iOS (`ios: true`) for the future build.
  - Share cards (`share_match_card.dart`, `share_profile_card.dart`) keep working with the swapped asset.

## Architecture

- **Gate:** `main.dart` — root becomes a `StreamBuilder`/listener on `FirebaseAuth.instance.authStateChanges()`: signed-in → `MyHomePage`; signed-out → new `WelcomePage`. Remove drawer's optional login/`signedIn` branching where it implied anonymous browsing; logout signs out → stream flips → wall. Auto-sign-in preference paths simplified (always on).
- **WelcomePage** (new, full-screen, fixed dark branded look in BOTH themes — like Volo): circle logo, headline, buttons: `Sign up with Google` (white), iOS-only `Sign up with Apple`, `Sign up with Email` (gold/brand), "Already have an account? **Log In**".
- **Google:** `google_sign_in` + `FirebaseAuth.signInWithCredential`. New-user detection via `additionalUserInfo.isNewUser` OR missing `Users/<uid>` node → create profile (names from displayName, email) → Step 2 → Step 3. Setup: enable Google provider in Firebase console (attempt via CLI/API, else walk owner through), register debug+release SHA-1/SHA-256 fingerprints on the Android app, refresh `google-services.json`.
- **Apple (dormant):** `sign_in_with_apple` package, button gated `Platform.isIOS`, same credential flow; `ios/Runner` entitlements entry added; handoff doc `docs/superpowers/plans/2026-07-25-apple-signin-ios-handoff.md` for Bronsin/Pauldin (Apple Developer capability + Services ID + Firebase Apple provider + test on device).
- **About You page:** one reusable widget serving (a) signup step 2, (b) Google/Apple first-run, (c) existing-user completion gate. Writes `Users/<uid>`: `DOB` (MM/DD/YYYY string), `City`, `Zip`, `Gender`, `ReferralSource`, `ProfileCompleted: true`.
- **Gate ordering on app open (signed in):** ProfileCompleted missing → About You (mandatory) → FavoriteSportsAnswered missing → favorites (existing logic) → home.

## Out of scope

- Biometric app lock; account deletion/verification-email flows beyond what exists; Manager app changes; any RTDB security-rules tightening (rules unchanged this round).

## Testing & rollout

- Pure/unit: validators (DOB/ZIP/phone), referral options list, profile-completeness helper, new-user routing decision fn. Widget tests: WelcomePage buttons, About You validation, login autofill hints present.
- Standards: light+dark (welcome stays branded-dark by design), real-time auth stream, `flutter test` + analyze green, release APK to owner's phone.
- Owner e2e: fresh-install signup (email + Google), existing-account login (one-time About You), logout→wall, forgot password, new logos/splash/icon visible.
- Google provider enablement + SHA fingerprints happen BEFORE owner testing of Google sign-in.

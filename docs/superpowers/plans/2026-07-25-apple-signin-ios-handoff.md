# Sign in with Apple — iOS Activation Handoff (auth-wall D1)

**For:** Bronsin & Pauldin, when you pick up the iOS build.
**Status of the Dart/Flutter side:** code-complete, dormant. `lib/onboarding/welcome_page.dart`'s
Apple button only renders when `Platform.isIOS` is true, so on the Android builds this repo ships
today it never shows and `signInWithApple()` never runs. Everything below is what's needed on the
Apple Developer / Firebase / Xcode side before it lights up — none of it touches Dart code.

**iOS bundle ID (verified from `ios/Runner.xcodeproj/project.pbxproj`, `PRODUCT_BUNDLE_IDENTIFIER`):**

```
com.infinitesports.Infinite-Sports
```

Note this is **not** the same string as the Android `applicationId`
(`com.infinitesports.Infinite_Sports_App`, from `android/app/build.gradle`). Use the iOS one
(`com.infinitesports.Infinite-Sports`) for every Apple Developer / Firebase step below — don't
copy-paste the Android id.

---

## (a) Apple Developer portal — App ID capability

1. developer.apple.com → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Open the App ID for `com.infinitesports.Infinite-Sports` (create it first if it doesn't exist
   yet as a registered identifier).
3. Enable the **Sign In with Apple** capability on that App ID → Save.
4. If Firebase Auth's Apple provider is configured in "service ID" mode (needed for anything beyond
   native iOS — e.g. if a web/Android OAuth fallback is ever added later), also create:
   - A **Services ID** (separate identifier, type "Services IDs") with Sign In with Apple enabled,
     configured with your web redirect domain if you add one.
   - A **Sign In with Apple key** (Keys → new key → enable Sign In with Apple, associate with the
     App ID above) — download the `.p8` once, it can't be re-downloaded. Note the **Key ID** and
     your **Team ID** (top-right of the developer portal) — Firebase asks for both.
   - For the native-iOS-only flow this repo implements (`getAppleIDCredential` +
     `OAuthProvider('apple.com').credential(...)`, no web redirect), the Services ID/key are only
     strictly required if Firebase's Apple provider setup insists on them — check step (b) first;
     some Firebase project configs accept native Apple sign-in without a Services ID.

## (b) Firebase console — enable the Apple provider

1. Firebase console → project **infinite-sports-app** → **Authentication** → **Sign-in method**.
2. Enable **Apple**.
3. If prompted for Services ID / Apple Team ID / Key ID / private key, fill in the values from (a).
4. Save.

## (c) Xcode — add the capability

1. Open `ios/Runner.xcworkspace` (not `.xcodeproj` — CocoaPods) in Xcode.
2. Select the **Runner** target → **Signing & Capabilities** tab → **+ Capability** → **Sign In
   with Apple**.
3. Xcode will point at the existing `ios/Runner/Runner.entitlements` file (already wired into all
   three build configs via `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` in
   `project.pbxproj` — used today for the `aps-environment` push-notification entitlement) and add
   the `com.apple.developer.applesignin` key there. **That key has already been added by this task**
   (`<key>com.apple.developer.applesignin</key>` / `<array><string>Default</string></array>`) so
   this step in Xcode should be a no-op confirmation, not a fresh edit — but the one-click "+
   Capability" flow is the safest way to also sync the entitlement to your provisioning profile,
   which a hand-edited `.entitlements` file alone does not do. Xcode may prompt you to update your
   provisioning profile / re-register the App ID capability from (a) at this point if it hasn't
   propagated yet.
4. Rebuild and confirm the entitlement shows up under the target's **Signing & Capabilities** with
   no red warning icon.

## (d) Device test checklist

Run on a **real device** (Sign In with Apple does not work reliably in the iOS Simulator on most
Xcode versions):

- [ ] Fresh install, tap **Sign up with Apple** → Face ID / Apple ID sheet appears → complete it →
      lands on the **About You** page (new-user path; `ProfileCompleted` not yet set) → complete it
      → **Favorite Sports** page → home tabs.
- [ ] Force-quit and relaunch → auto-signed-in straight to home tabs (no wall).
- [ ] Log out (drawer) → wall (`WelcomePage`) appears instantly.
- [ ] Sign in with Apple again (same Apple ID) → **returning-user path**: straight to home tabs, no
      About You / Favorites re-prompt.
- [ ] Tap **Sign up with Apple** and cancel the Face ID / Apple ID sheet (swipe down / tap Cancel)
      → returns quietly to the welcome wall with a "Apple sign-in cancelled or failed." snackbar —
      no crash, no stuck spinner.
- [ ] Check `Users/<uid>` in the Firebase RTDB console after the fresh-install run above: `First
      Name`/`Last Name` populated from Apple's name-on-first-authorization (if the test Apple ID
      has "Share My Name" enabled in the sheet — Apple lets the user turn this off, in which case
      both fields legitimately come through empty, same as an empty Google `displayName` would).

## (e) Why Apple sign-in is required, not optional, once Google sign-in ships

Apple App Store Review Guideline **4.8 (Sign in with Apple)**: apps that offer a third-party or
social login option (this app offers **Google**) must also offer Sign in with Apple as an
equivalent option, unless one of the guideline's narrow exemptions applies (this app doesn't
qualify for any of them — it's a general consumer app, not enterprise/education/employer-badge
software). This is why the button — dormant as it is on Android — needs to actually work before
this app can ship an iOS build with Google sign-in present. Practically: **do not submit an iOS
build with the Apple button removed or non-functional while the Google button is present** — that
combination is a guideline-4.8 rejection risk.

## (f) Android note: Play App Signing SHA fingerprints (separate from Apple, flagging while here)

Not an Apple/iOS item, but relevant to the same "Google sign-in must work in the store build"
concern this handoff doc's guideline-4.8 note raises for iOS: on Android, **Google Sign-In only
works in Play Store–distributed builds if the Play App Signing SHA-1/SHA-256 fingerprints are
registered on the Firebase Android app** (Firebase console → Project settings → Your apps →
`com.infinitesports.Infinite_Sports_App` → Add fingerprint). Get the Play-side fingerprints from
**Play Console → your app → Setup → App integrity → App signing key certificate** (this is a
*different* certificate than your local debug/upload keystore — Play re-signs the APK/AAB with its
own key before distributing). Some fingerprints may already be registered from earlier debug-build
testing (`google_sign_in`'s serverClientId flow in
`lib/firebase_auth/firebase_auth_services.dart` needs a matching fingerprint to mint an ID token) —
**verify the Play App Signing cert specifically is one of them** before the first store release
that includes Google sign-in, since a debug-keystore fingerprint alone won't cover Play-distributed
builds.

---

## Reference — what's already done (Dart side, this task)

- `pubspec.yaml`: `sign_in_with_apple: ^8.1.0` (resolved from `flutter pub add`; no `^6.1.0` version
  of this package resolved cleanly against the installed Flutter 3.44 / Dart 3.12 SDK without
  dependency conflicts, so the latest cleanly-resolving version was used instead — API surface used
  here, `SignInWithApple.getAppleIDCredential` / `AuthorizationCredentialAppleID` /
  `SignInWithAppleAuthorizationException`, is unchanged since 6.x).
- `lib/firebase_auth/firebase_auth_services.dart`: `signInWithApple()` — requests
  `[AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName]`, builds an
  `OAuthProvider('apple.com')` credential from `identityToken`/`authorizationCode`, signs in via
  Firebase, and (when Apple supplied a name on this first authorization) calls
  `updateDisplayName` before returning so the existing Google name-splitting path works unchanged.
- `lib/onboarding/google_profile.dart`: `combineAppleName(givenName, familyName)` — pure helper,
  unit-tested in `test/google_profile_test.dart`.
- `lib/main.dart`: `_handleAppleSignIn` — a straight mirror of `_handleGoogleSignIn`, wired to
  `WelcomePage(onApple: ...)` in `AuthGate`.
- `ios/Runner/Runner.entitlements`: `com.apple.developer.applesignin` / `Default` key added.
- `lib/onboarding/welcome_page.dart`: Apple button (black background, white text/icon, `Icons.apple`,
  "Sign up with Apple" label) already existed from an earlier task (B1) and was verified here to be
  correctly gated behind `Platform.isIOS` — no change needed.

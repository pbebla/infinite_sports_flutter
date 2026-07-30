import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../onboarding/google_profile.dart';

/// Public web OAuth client ID for the Firebase project (Identity Toolkit
/// "Web client (auto created by Google Service)"). This app has no
/// `google-services.json`/Gradle GMS plugin (Firebase is wired via
/// lib/firebase_options.dart instead), so `GoogleSignIn` needs this passed
/// explicitly as `serverClientId` — without it, Android can't find an OAuth
/// client to mint an ID token against. Client IDs are public identifiers
/// (safe to embed); this is NOT a client secret.
const _googleServerClientId =
    '248087010229-u4lsjnu68lid7bj82v82d3pcr9t6r1oe.apps.googleusercontent.com';

class FirebaseAuthService {

  Future<User?> signUpWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      return credential.user;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      return credential.user;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    // Also end the Google session (auth-wall C2 follow-up) so a
    // Google-signed-in user who logs out gets the account picker again
    // next time, instead of GoogleSignIn silently re-authenticating them
    // with the same cached account. Wrapped in try/catch: this is a
    // harmless no-op for users who never went through Google sign-in, and
    // must never block/crash the (already-completed) Firebase sign-out.
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      // ignore: avoid_print
      print(e.toString());
    }
  }

  /// Google credential sign-in (auth-wall C2). Returns `null` — quietly, no
  /// exception — when the user cancels the account picker, matching the
  /// email methods' "null means didn't work, caller decides what to show"
  /// convention. Any other failure (network, malformed token, etc.) is also
  /// swallowed to `null` after logging, same as `signUpWithEmailAndPassword`/
  /// `signInWithEmailAndPassword` above.
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(serverClientId: _googleServerClientId);
      final account = await googleSignIn.signIn();
      if (account == null) return null; // user cancelled the picker
      final googleAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      return await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  /// Apple credential sign-in (auth-wall D1) — code-complete but DORMANT: the
  /// only call site, `WelcomePage`'s Apple button (lib/onboarding/welcome_page.dart),
  /// renders exclusively on `Platform.isIOS`, so this never actually runs on
  /// the Android builds this repo ships today. It exists now so Bronsin/
  /// Pauldin's iOS build can flip it on without touching Dart — see the
  /// handoff doc (docs/superpowers/plans/2026-07-25-apple-signin-ios-handoff.md)
  /// for the Apple Developer/Firebase console steps still required first.
  ///
  /// Mirrors `signInWithGoogle` above as closely as Apple's API allows:
  /// - Same `null`-on-cancel-or-failure convention as every method in this
  ///   file — `SignInWithAppleAuthorizationException` with
  ///   `AuthorizationErrorCode.canceled` (user dismissed the Face ID/Apple ID
  ///   sheet) is caught quietly and returns `null`, same as a `catch (e)`
  ///   falling through below would for any other failure.
  /// - Apple only supplies `givenName`/`familyName` on the FIRST authorization
  ///   ever between this user and this app; every sign-in after that gets
  ///   `null` for both. Rather than plumb a separate name payload through the
  ///   return type, this updates `FirebaseAuth`'s own `displayName` on the
  ///   credential's user BEFORE returning whenever Apple did provide a name
  ///   (`combineAppleName`, lib/onboarding/google_profile.dart) — so the
  ///   existing `splitDisplayName`-based base-profile write in main.dart's
  ///   `_handleGoogleSignIn`-mirroring Apple handler works completely
  ///   unchanged, exactly like it does for Google's `displayName`.
  Future<UserCredential?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(oauthCredential);

      final name = combineAppleName(
        appleCredential.givenName,
        appleCredential.familyName,
      );
      if (name != null) {
        await userCredential.user?.updateDisplayName(name);
      }

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null; // user backed out of the Face ID/Apple ID sheet
      }
      // ignore: avoid_print
      print(e.toString());
      return null;
    } catch (e) {
      // ignore: avoid_print
      print(e.toString());
      return null;
    }
  }
}
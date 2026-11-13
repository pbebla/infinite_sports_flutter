import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
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

/// The person backed out of the re-authentication step (closed the Google or
/// Apple sheet, or cancelled the password dialog). Not an error: the Delete
/// account page just goes back to idle.
class ReauthCancelled implements Exception {
  const ReauthCancelled();
}

/// Re-authentication could not be completed (no supported provider, a
/// different Google account was picked, network, too many attempts...).
/// Carries no message for the screen: the page shows its own plain wording.
class ReauthFailed implements Exception {
  final ReauthFailureReason reason;

  const ReauthFailed({this.reason = ReauthFailureReason.other});
}

enum ReauthFailureReason {
  /// The person picked a different Google account than the signed-in one
  /// (Firebase `user-mismatch`).
  googleAccountMismatch,

  /// The only sign-in on the account is Apple and this is Android, where
  /// Sign in with Apple cannot run: the person deletes from an iPhone or
  /// emails support.
  appleOnlyOnAndroid,

  /// Firebase said the account no longer exists or is disabled
  /// (`user-not-found` / `user-disabled`): a previous delete may already
  /// have gone through, so the page checks before showing an error.
  userGone,

  other,
}

/// Which provider re-signs the person in before deletion: Apple first (iOS
/// only: Sign in with Apple cannot run on Android, so a linked Apple +
/// password account falls through to its other provider there), then Google,
/// then password (only with an email on the account). null = none usable.
String? reauthProviderFor(
  Iterable<String> providerIds, {
  required bool isIOS,
  required bool hasEmail,
}) {
  final ids = providerIds.toSet();
  if (isIOS && ids.contains('apple.com')) return 'apple.com';
  if (ids.contains('google.com')) return 'google.com';
  if (ids.contains('password') && hasEmail) return 'password';
  return null;
}

/// Why [reauthProviderFor] found no usable provider: Apple is on the account
/// but this is Android (so it cannot run here), or anything else.
ReauthFailureReason reauthUnavailableReason(
  Iterable<String> providerIds, {
  required bool isIOS,
  required bool hasEmail,
}) {
  final ids = providerIds.toSet();
  if (!isIOS &&
      ids.contains('apple.com') &&
      reauthProviderFor(ids, isIOS: isIOS, hasEmail: hasEmail) == null) {
    return ReauthFailureReason.appleOnlyOnAndroid;
  }
  return ReauthFailureReason.other;
}

/// The Apple credential for re-signing in before deletion: the identity token
/// ONLY. The authorization code is single-use and is kept for
/// `revokeTokenWithAuthorizationCode`, which runs right after the re-auth
/// (passing it here as the access token could spend it first).
OAuthCredential appleReauthCredential(String? identityToken) =>
    OAuthProvider('apple.com').credential(idToken: identityToken);

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

  /// Fresh sign-in for "Delete account" (account deletion, design D3): the
  /// `deleteAccount` callable only runs for a sign-in from the last five
  /// minutes. Picks the provider from the signed-in user's `providerData`,
  /// Apple first, then Google, then email/password.
  ///
  /// - Apple: a new Apple ID credential re-authenticates, then (iOS only) its
  ///   authorization code revokes the app's Apple token, which Apple requires
  ///   when an account is deleted. A revoke failure is logged and never blocks
  ///   the deletion.
  /// - Google: the account picker; closing it cancels.
  /// - Password: [askPassword] is called with `null` the first time and with
  ///   `'Wrong password'` after a rejected password; it returns the typed
  ///   password, or `null` when the person cancels.
  ///
  /// Completes normally once re-authenticated. Throws [ReauthCancelled] when
  /// the person backs out and [ReauthFailed] for anything else.
  Future<void> reauthenticateForDeletion({
    required Future<String?> Function(String? errorText) askPassword,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ReauthFailed();
    final providerIds = user.providerData.map((p) => p.providerId).toList();
    final provider = reauthProviderFor(
      providerIds,
      isIOS: Platform.isIOS,
      hasEmail: user.email != null,
    );
    try {
      if (provider == 'apple.com') {
        await _reauthWithApple(user);
      } else if (provider == 'google.com') {
        await _reauthWithGoogle(user);
      } else if (provider == 'password') {
        await _reauthWithPassword(user, askPassword);
      } else {
        throw ReauthFailed(
          reason: reauthUnavailableReason(
            providerIds,
            isIOS: Platform.isIOS,
            hasEmail: user.email != null,
          ),
        );
      }
    } on ReauthCancelled {
      rethrow;
    } on ReauthFailed {
      rethrow;
    } on FirebaseAuthException catch (e) {
      debugPrint('Re-authentication for deletion failed: ${e.code}');
      // The account may already be gone (a delete whose answer was lost).
      if (e.code == 'user-not-found' || e.code == 'user-disabled') {
        throw const ReauthFailed(reason: ReauthFailureReason.userGone);
      }
      throw const ReauthFailed();
    } catch (e) {
      debugPrint('Re-authentication for deletion failed: '
          '${e is FirebaseAuthException ? e.code : e.runtimeType}');
      throw const ReauthFailed();
    }
  }

  /// Deletes an account created moments ago (the under-13 exit on the About
  /// You signup step): Apple's token is revoked first (iOS, Apple accounts),
  /// then the `deleteAccount` callable removes the data and the Auth user.
  /// The sign-in is only minutes old, so no password or Google re-auth is
  /// needed. Never throws: every failure is logged, and the caller signs the
  /// person out regardless.
  Future<void> deleteFreshAccount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      if (Platform.isIOS &&
          user.providerData.any((p) => p.providerId == 'apple.com')) {
        try {
          final apple = await _appleIdCredential();
          await _revokeAppleToken(apple.authorizationCode);
        } catch (e) {
          debugPrint('Apple revoke before fresh-account deletion skipped: '
              '${e.runtimeType}');
        }
      }
      await FirebaseFunctions.instance
          .httpsCallable('deleteAccount')
          .call<Object?>();
    } catch (e) {
      debugPrint('Fresh-account deletion failed: '
          '${e is FirebaseFunctionsException ? e.code : e.runtimeType}');
    }
  }

  /// A new Apple ID credential (the Apple sheet). Throws [ReauthCancelled]
  /// when the person closes it.
  Future<AuthorizationCredentialAppleID> _appleIdCredential() async {
    try {
      return await SignInWithApple.getAppleIDCredential(scopes: const []);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const ReauthCancelled();
      }
      rethrow;
    }
  }

  /// Revokes the app's Apple token (Apple requires it when an account is
  /// deleted). iOS only; a failure is logged and never blocks the deletion.
  Future<void> _revokeAppleToken(String authorizationCode) async {
    if (!Platform.isIOS) return;
    try {
      await FirebaseAuth.instance
          .revokeTokenWithAuthorizationCode(authorizationCode);
    } catch (e) {
      debugPrint('Apple token revoke failed (deletion continues): '
          '${e is FirebaseAuthException ? e.code : e.runtimeType}');
    }
  }

  Future<void> _reauthWithApple(User user) async {
    final apple = await _appleIdCredential();
    await user.reauthenticateWithCredential(
        appleReauthCredential(apple.identityToken));
    // The revoke runs here, BEFORE the server call, because it needs the live
    // re-authenticated session (once the server deletes the Auth user it can
    // no longer run). On a recent-login-required retry the whole re-auth,
    // revoke included, runs a second time; a second revoke of an already
    // revoked token just fails and is logged.
    await _revokeAppleToken(apple.authorizationCode);
  }

  Future<void> _reauthWithGoogle(User user) async {
    final GoogleSignInAccount? account;
    try {
      account =
          await GoogleSignIn(serverClientId: _googleServerClientId).signIn();
    } on PlatformException catch (e) {
      // iOS reports a closed sheet as an error rather than a null account.
      if (e.code == GoogleSignIn.kSignInCanceledError) {
        throw const ReauthCancelled();
      }
      rethrow;
    }
    if (account == null) throw const ReauthCancelled();
    final googleAuth = await account.authentication;
    try {
      await user.reauthenticateWithCredential(GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      ));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-mismatch') {
        // Sign the picker out so the next try offers the account list again
        // instead of silently reusing the wrong account.
        try {
          await GoogleSignIn(serverClientId: _googleServerClientId).signOut();
        } catch (_) {}
        throw const ReauthFailed(
            reason: ReauthFailureReason.googleAccountMismatch);
      }
      rethrow;
    }
  }

  Future<void> _reauthWithPassword(
    User user,
    Future<String?> Function(String? errorText) askPassword,
  ) async {
    String? errorText;
    while (true) {
      final password = await askPassword(errorText);
      if (password == null) throw const ReauthCancelled();
      try {
        await user.reauthenticateWithCredential(EmailAuthProvider.credential(
            email: user.email!, password: password));
        return;
      } on FirebaseAuthException catch (e) {
        // With email-enumeration protection on, a wrong password comes back
        // as invalid-credential rather than wrong-password.
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          errorText = 'Wrong password';
          continue;
        }
        rethrow;
      }
    }
  }
}

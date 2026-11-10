// The real Firebase wiring behind [DeleteAccountPage] (account deletion,
// design D3): re-sign-in per provider, the `deleteAccount` callable, and what
// happens once the account is gone. The page itself stays Firebase-free.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/account/delete_account_page.dart';
import 'package:infinite_sports_flutter/account/password_reauth_dialog.dart';
import 'package:infinite_sports_flutter/account/session_sign_out.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

/// The page with its production closures; Settings pushes this.
Widget buildDeleteAccountPage() => const DeleteAccountPage(
      reauth: reauthForDeletion,
      callDelete: callDeleteAccount,
      onDeleted: onAccountDeleted,
    );

/// Re-signs the current user in with their own provider (Apple, Google or
/// password; see `FirebaseAuthService.reauthenticateForDeletion`).
Future<void> reauthForDeletion(BuildContext context) =>
    auth.reauthenticateForDeletion(
      askPassword: (errorText) => showDialog<String>(
        context: context,
        builder: (_) => PasswordReauthDialog(errorText: errorText),
      ),
    );

/// Calls `deleteAccount` (the uid is the caller's, server-side). On success
/// the server has already deleted the Firebase Auth user.
Future<void> callDeleteAccount() async {
  try {
    await FirebaseFunctions.instance
        .httpsCallable('deleteAccount')
        .call<Object?>();
  } on FirebaseFunctionsException catch (e) {
    throw deleteAccountErrorFrom(e);
  }
}

/// Reduces a `deleteAccount` failure to the server's `details.code`. An
/// `already-merged` without a usable hint is treated as a generic failure
/// (the page would otherwise say "Sign in with null").
DeleteAccountError deleteAccountErrorFrom(FirebaseFunctionsException e) {
  final details = e.details;
  final code = details is Map ? details['code'] : null;
  switch (code) {
    case DeleteAccountError.recentLogin:
      return const DeleteAccountError(DeleteAccountError.recentLogin);
    case DeleteAccountError.incomplete:
      return const DeleteAccountError(DeleteAccountError.incomplete);
    case DeleteAccountError.alreadyMerged:
      final hint = (details as Map)['keepHint'];
      if (hint is String && hint.trim().isNotEmpty) {
        return DeleteAccountError(DeleteAccountError.alreadyMerged,
            keepHint: hint.trim());
      }
      return const DeleteAccountError(DeleteAccountError.other);
    default:
      debugPrint('deleteAccount failed: ${e.code}/$code');
      return const DeleteAccountError(DeleteAccountError.other);
  }
}

/// After the server deleted the account: back to the root route FIRST
/// (closes this page and Settings), then the app's one sign-out, which
/// flips AuthGate to the welcome wall; then a one-line snackbar there.
///
/// The snackbar goes through the MaterialApp's root ScaffoldMessenger (the
/// one above the root navigator, the same one main.dart's sign-in handlers
/// use), captured before anything is popped. It sits above AuthGate, so it
/// survives the swap and shows on the welcome wall's Scaffold.
Future<void> onAccountDeleted(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(navigator.context);
  navigator.popUntil((r) => r.isFirst);
  try {
    await signOutAndClearSession();
  } catch (e) {
    // The Auth user is already gone server-side; a sign-out hiccup must not
    // leave the person staring at a dead page.
    debugPrint('Sign-out after account deletion failed: ${e.runtimeType}');
  }
  messenger?.showSnackBar(
    const SnackBar(content: Text('Your account was deleted.')),
  );
}

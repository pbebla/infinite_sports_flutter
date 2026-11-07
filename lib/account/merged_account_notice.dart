// "Your accounts were combined" notice (Merge Duplicate Player Accounts,
// design D9).
//
// When the owner merges a duplicate account into the real one, the OLD
// account is stamped `Users/<old>/MergedInto = <kept uid>` and
// `Users/<old>/MergedHint = <kept email, partly hidden>` (D5/D6). Anyone still
// signed in on that old account sees ONE plain dialog telling them which email
// to use, then is signed out. [MergedAccountWatcher] wraps the signed-in home
// (main.dart) and does exactly that.
//
// Live `onValue` streams only (never get()/once()); colors come from the
// theme (AlertDialog defaults), so light and dark both fit.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/account/session_sign_out.dart';

/// What the dialog says.
class MergedNotice {
  final String title;
  final String body;

  const MergedNotice({required this.title, required this.body});
}

/// The notice for this account's two stamp leaves, or null when the account
/// was not merged. Only a non-empty STRING [mergedInto] counts (the same test
/// the public-profile mirror applies); a [hint] that is not a non-blank string
/// is treated as absent, which gives the "your other email" wording.
MergedNotice? mergedNoticeFor(Object? mergedInto, Object? hint) {
  if (mergedInto is! String || mergedInto.isEmpty) return null;
  final shownHint = hint is String ? hint.trim() : '';
  return MergedNotice(
    title: 'Your accounts were combined',
    body: shownHint.isEmpty
        ? 'All your seasons are now on your other Infinite Sports account. '
            'Please sign in with your other email.'
        : 'All your seasons are now on your Infinite Sports account for '
            '$shownHint. Please sign in with that email.',
  );
}

/// Joins the two stamp leaves into one `{MergedInto, MergedHint}` stream.
///
/// Waits until BOTH leaves have reported once, then waits [settle] after the
/// latest change before emitting: the merge tool writes the leaves one after
/// another, and the app can receive `MergedInto` a moment before `MergedHint`
/// — without the pause the notice could open with the "other email" wording
/// while the real hint is milliseconds away. A leaf stream that errors counts
/// as an empty leaf (never blocks the other one).
Stream<Map<String, Object?>> combineMergedLeaves(
  Stream<Object?> mergedInto,
  Stream<Object?> hint, {
  Duration settle = const Duration(milliseconds: 300),
}) {
  late final StreamController<Map<String, Object?>> out;
  StreamSubscription<Object?>? intoSub;
  StreamSubscription<Object?>? hintSub;
  Timer? timer;
  var haveInto = false;
  var haveHint = false;
  Object? intoValue;
  Object? hintValue;

  void schedule() {
    if (!haveInto || !haveHint) return;
    timer?.cancel();
    timer = Timer(settle, () {
      if (out.isClosed) return;
      out.add({'MergedInto': intoValue, 'MergedHint': hintValue});
    });
  }

  out = StreamController<Map<String, Object?>>(
    onListen: () {
      intoSub = mergedInto.listen(
        (v) {
          haveInto = true;
          intoValue = v;
          schedule();
        },
        onError: (Object e) {
          debugPrint('MergedInto watch failed: $e');
          haveInto = true;
          intoValue = null;
          schedule();
        },
      );
      hintSub = hint.listen(
        (v) {
          haveHint = true;
          hintValue = v;
          schedule();
        },
        onError: (Object e) {
          debugPrint('MergedHint watch failed: $e');
          haveHint = true;
          hintValue = null;
          schedule();
        },
      );
    },
    onCancel: () async {
      timer?.cancel();
      await intoSub?.cancel();
      await hintSub?.cancel();
    },
  );
  return out.stream;
}

/// Watches the signed-in user's merge stamp and, when it appears, shows the
/// notice dialog once and signs the user out on OK.
///
/// [states] and [onSignOut] are test seams. Defaults: the live `onValue` of
/// `Users/<me>/MergedInto` + `MergedHint` (see [combineMergedLeaves]), and
/// [signOutAndClearSession].
class MergedAccountWatcher extends StatefulWidget {
  final Widget child;
  final Stream<Map<String, Object?>>? states;
  final Future<void> Function()? onSignOut;

  const MergedAccountWatcher({
    super.key,
    required this.child,
    this.states,
    this.onSignOut,
  });

  @override
  State<MergedAccountWatcher> createState() => _MergedAccountWatcherState();
}

class _MergedAccountWatcherState extends State<MergedAccountWatcher> {
  StreamSubscription<Map<String, Object?>>? _sub;
  // True from the moment the dialog opens until a failed sign-out hands it
  // back: later emissions never stack a second dialog.
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _sub = (widget.states ?? _liveStates()).listen(_onState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static Stream<Map<String, Object?>> _liveStates() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const Stream.empty();
    final users = FirebaseDatabase.instance.ref('Users/$uid');
    return combineMergedLeaves(
      users.child('MergedInto').onValue.map((e) => e.snapshot.value),
      users.child('MergedHint').onValue.map((e) => e.snapshot.value),
    );
  }

  void _onState(Map<String, Object?> state) {
    if (_shown || !mounted) return;
    final notice = mergedNoticeFor(state['MergedInto'], state['MergedHint']);
    if (notice == null) return;
    _show(notice);
  }

  void _show(MergedNotice notice) {
    _shown = true;
    // Captured now: signing out swaps the whole signed-in tree away, which
    // disposes this State before the sign-out future completes.
    final signOut = widget.onSignOut ?? signOutAndClearSession;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          title: Text(notice.title),
          content: Text(notice.body),
          actions: [
            TextButton(
              onPressed: () {
                // Close the dialog FIRST: sign-out flips authStateChanges()
                // and AuthGate can swap the content (and this dialog's
                // ancestors) the instant it resolves.
                Navigator.of(dialogContext).pop();
                _signOut(signOut, notice);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut(
    Future<void> Function() signOut,
    MergedNotice notice,
  ) async {
    try {
      await signOut();
    } catch (e) {
      debugPrint('Sign-out after merge notice failed: $e');
      // Still signed in on a merged account: tell them again rather than
      // leave them in it silently.
      if (mounted) _show(notice);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

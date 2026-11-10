// "Delete account" page (account deletion, design D3).
//
// Explains what is deleted and what is kept (the same lines as the hosted
// page public/delete-account/index.html), asks the person to type DELETE
// (not their email: Apple relay users don't know theirs), then re-signs them
// in and calls the server. Every Firebase step is an injected closure, so the
// page is testable without Firebase; lib/account/delete_account_flow.dart
// supplies the real ones. Colours come from the theme (light + dark).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/firebase_auth/firebase_auth_services.dart';

/// A `deleteAccount` failure, already reduced to the server's `details.code`
/// (see `deleteAccountErrorFrom` in delete_account_flow.dart).
class DeleteAccountError implements Exception {
  static const recentLogin = 'recent-login-required';
  static const alreadyMerged = 'already-merged';
  static const incomplete = 'deletion-incomplete';
  static const other = 'other';

  final String code;

  /// The kept account's masked email, only for [alreadyMerged].
  final String? keepHint;

  const DeleteAccountError(this.code, {this.keepHint});
}

const _supportEmail = 'contact@infinitesports.org';
const _genericError =
    'Something went wrong. Please try again or email $_supportEmail.';

const _deletedLines = [
  'Your sign-in (email, Google or Apple) and password.',
  'Your name, email address, phone number, date of birth, gender, city, ZIP '
      'code and profile photo.',
  'Your player profile details and public profile.',
  'Your fantasy teams, picks and mini-league memberships.',
  'Your notification tokens and preferences.',
  'Your support requests.',
];

const _keptLines = [
  'Payment records, for as long as our accounting rules require (typically '
      'seven years).',
  'League records (rosters, results, standings and statistics), which are the '
      "league's history. On request we remove your photo and personal details "
      'from them and can replace your name with a generic entry.',
];

class DeleteAccountPage extends StatefulWidget {
  /// Signs the person in again. Completes when done; throws
  /// [ReauthCancelled] when they back out (the page returns to idle quietly).
  final Future<void> Function(BuildContext context) reauth;

  /// Calls the server. Throws [DeleteAccountError] on a server failure.
  final Future<void> Function() callDelete;

  /// Runs once, after the server deleted the account.
  final Future<void> Function(BuildContext context) onDeleted;

  const DeleteAccountPage({
    super.key,
    required this.reauth,
    required this.callDelete,
    required this.onDeleted,
  });

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _confirmed => _confirm.text.trim() == 'DELETE';

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || !_confirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.reauth(context);
      try {
        await widget.callDelete();
      } on DeleteAccountError catch (e) {
        // The sign-in was a little too old by the server's clock: once more.
        if (e.code != DeleteAccountError.recentLogin || !mounted) rethrow;
        await widget.reauth(context);
        await widget.callDelete();
      }
      // Stays busy: onDeleted takes the person out of the signed-in app.
      if (!mounted) return;
      await widget.onDeleted(context);
    } on ReauthCancelled {
      if (mounted) setState(() => _busy = false);
    } on ReauthFailed catch (e) {
      _fail(e.reason == ReauthFailureReason.googleAccountMismatch
          ? 'Please choose the same Google account you signed in with.'
          : _genericError);
    } on DeleteAccountError catch (e) {
      _fail(_messageFor(e));
    } catch (e) {
      debugPrint('Delete account failed: ${e.runtimeType}');
      _fail(_genericError);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  static String _messageFor(DeleteAccountError e) {
    switch (e.code) {
      case DeleteAccountError.alreadyMerged:
        return 'This account was combined into another one. Sign in with '
            '${e.keepHint} and delete that account instead.';
      case DeleteAccountError.incomplete:
        return 'Some data could not be removed. Please try again; if it keeps '
            'failing, email $_supportEmail.';
      default:
        return _genericError;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: SafeArea(
        // A plain scroll view (not a lazy ListView): the page is short, and
        // every row, the field and the button included, always exists.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This permanently deletes your Infinite Sports account. It '
                'cannot be undone.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 20),
              Text('What is deleted', style: text.titleMedium),
              const SizedBox(height: 8),
              for (final line in _deletedLines) _Bullet(line),
              const SizedBox(height: 16),
              Text('What is kept', style: text.titleMedium),
              const SizedBox(height: 8),
              for (final line in _keptLines) _Bullet(line),
              const SizedBox(height: 24),
              Text(
                'You will be asked to sign in again before the account is '
                'deleted.',
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('delete_account_confirm_field'),
                controller: _confirm,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Type DELETE to confirm',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: const ValueKey('delete_account_button'),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.disabled)
                            ? scheme.onSurface.withValues(alpha: 0.12)
                            : scheme.error),
                    foregroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.disabled)
                            ? scheme.onSurface.withValues(alpha: 0.38)
                            : scheme.onError),
                  ),
                  onPressed: (_busy || !_confirmed) ? null : _delete,
                  child: _busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: scheme.onSurface,
                          ),
                        )
                      : const Text('Delete my account'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

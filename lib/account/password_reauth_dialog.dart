// Password prompt for re-signing in before "Delete account" (account
// deletion, design D3). A StatefulWidget that owns its controller (standing
// rule: never dispose a controller right after `await showDialog`). Pops with
// the typed password, or null on Cancel.

import 'package:flutter/material.dart';

class PasswordReauthDialog extends StatefulWidget {
  /// Shown under the field, e.g. "Wrong password" after a rejected attempt.
  final String? errorText;

  const PasswordReauthDialog({super.key, this.errorText});

  @override
  State<PasswordReauthDialog> createState() => _PasswordReauthDialogState();
}

class _PasswordReauthDialogState extends State<PasswordReauthDialog> {
  final TextEditingController _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Confirm it is you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter your password to delete your account.'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('reauth_password_field'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Password',
              errorText: widget.errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _password.text.isEmpty ? null : _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

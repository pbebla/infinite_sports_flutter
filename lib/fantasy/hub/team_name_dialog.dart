// The name-your-team / rename dialog (P3a feedback, spec §10b). House rule
// (feedback_dialog_controller_crash): a dialog with a TextField is a
// StatefulWidget that OWNS its TextEditingController — never a controller
// disposed by the caller right after `await showDialog`.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/name_check.dart';

/// Shows [TeamNameDialog]; resolves true after a successful save.
Future<bool?> showTeamNameDialog(
  BuildContext context, {
  String initialName = '',
  required Future<void> Function(String name) onSave,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) =>
        TeamNameDialog(initialName: initialName, onSave: onSave),
  );
}

class TeamNameDialog extends StatefulWidget {
  const TeamNameDialog({
    super.key,
    this.initialName = '',
    required this.onSave,
  });

  /// Pre-filled for renames; empty on first naming.
  final String initialName;

  /// Performs the actual write (FantasyService.saveTeamName in production,
  /// a fake in tests). The dialog pops with `true` once it completes.
  final Future<void> Function(String name) onSave;

  @override
  State<TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<TeamNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _controller.text.trim();
    final check = checkTeamName(name);
    if (!check.ok) {
      setState(() => _error = check.reason);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save that name — please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final renaming = widget.initialName.isNotEmpty;
    return AlertDialog(
      title: Text(renaming ? 'Rename your team' : 'Name your team'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your team name shows on leaderboards, so keep it '
            'league-friendly. $kTeamNameMinLength–$kTeamNameMaxLength '
            'characters.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('team_name_field'),
            controller: _controller,
            autofocus: true,
            maxLength: kTeamNameMaxLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Team name',
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('team_name_save'),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: scheme.onPrimary),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

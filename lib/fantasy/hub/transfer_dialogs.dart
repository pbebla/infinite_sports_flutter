// The two questions the transfers flow asks before it does something that
// costs the manager (plan 2026-11-03, spec §5–§6): "Take a points hit?"
// before a save that ADDS a points cost, and "Play your Wildcard?" / "Play
// your Free Hit?" before either chip is armed. The words are the owner's;
// the numbers come from the transfer preview and the live config (never
// hard-coded). Each resolves true only on the yes — "Cancel" / "Not now",
// the barrier and the back button are all a no, so nothing is ever saved or
// armed by dismissing.
//
// House rule (feedback_dialog_controller_crash): no text fields here, so
// these are plain stateless dialogs — nothing to dispose after
// `await showDialog`.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/transfer_preview.dart';

/// "This team uses 3 transfers and you have 2 free, so it costs 4 points
/// this week." — singular for exactly one ("1 transfer", "1 point").
String pointsHitBody(TransferPreview p) =>
    'This team uses ${p.used} ${p.used == 1 ? 'transfer' : 'transfers'} and '
    'you have ${p.free} free, so it costs ${p.costPoints} '
    '${p.costPoints == 1 ? 'point' : 'points'} this week.';

/// "Save (−4 pts)" — the confirm button carries the cost.
String pointsHitSaveLabel(TransferPreview p) =>
    'Save (−${pointsText(p.costPoints)})';

/// Asks before a save whose cost went UP. [preview] is the counted preview
/// of the squad about to be saved. true = save it; anything else = don't.
Future<bool> showPointsHitDialog(
    BuildContext context, TransferPreview preview) {
  return _ask(
    context,
    keyPrefix: 'points_hit',
    title: 'Take a points hit?',
    body: pointsHitBody(preview),
    cancelLabel: 'Cancel',
    confirmLabel: pointsHitSaveLabel(preview),
  );
}

/// The title, body and play button of the arm-a-chip question for [chip]
/// (`wildcard` | `freeHit`). The Wildcard body names the two sets from the
/// live [cfg] (`chipSet1EndGw`).
({String title, String body, String play}) chipConfirmCopy(
    String chip, FantasyConfig cfg) {
  switch (chip) {
    case 'wildcard':
      return (
        title: 'Play your Wildcard?',
        body: 'Every transfer this week is free and your new team stays. You '
            'can switch it off until the deadline. You get one Wildcard for '
            'Gameweeks 1–${cfg.chipSet1EndGw} and one for the rest of the '
            'season.',
        play: 'Play Wildcard',
      );
    case 'freeHit':
      return (
        title: 'Play your Free Hit?',
        body: 'Every transfer this week is free. After this week\'s games, '
            'the team you have now comes back. You can switch it off until '
            'the deadline.',
        play: 'Play Free Hit',
      );
  }
  throw ArgumentError.value(chip, 'chip', 'not a transfer chip');
}

/// Asks before arming [chip] (`wildcard` | `freeHit`). true = arm it.
Future<bool> showChipConfirmDialog(
  BuildContext context, {
  required String chip,
  required FantasyConfig config,
}) {
  final copy = chipConfirmCopy(chip, config);
  return _ask(
    context,
    keyPrefix: 'chip_confirm',
    title: copy.title,
    body: copy.body,
    cancelLabel: 'Not now',
    confirmLabel: copy.play,
  );
}

Future<bool> _ask(
  BuildContext context, {
  required String keyPrefix,
  required String title,
  required String body,
  required String cancelLabel,
  required String confirmLabel,
}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmDialog(
      keyPrefix: keyPrefix,
      title: title,
      body: body,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
  return yes ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.keyPrefix,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String keyPrefix;
  final String title;
  final String body;
  final String cancelLabel;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: ValueKey('${keyPrefix}_dialog'),
      title: Text(title),
      content: Text(body, softWrap: true),
      actions: [
        TextButton(
          key: ValueKey('${keyPrefix}_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          child: Text(cancelLabel),
        ),
        // The same gold / primary pairing as the Save button it stands in
        // for (readable in both themes).
        FilledButton(
          key: ValueKey('${keyPrefix}_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: fantasyAccent(context),
            foregroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black
                : scheme.onPrimary,
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

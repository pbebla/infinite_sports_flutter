// The Infinite Fantasy "Share" action (Team of the Week header, "Your rank
// this season" panel): owns its busy state — a small spinner in place of the
// icon and no second sheet while the story image renders — and hands the
// share its OWN BuildContext, which anchors the iPad share popover
// (share_card_service.shareOriginFor).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

class FantasyShareButton extends StatefulWidget {
  const FantasyShareButton({
    super.key,
    required this.onShare,
    required this.tooltip,
    this.label,
  });

  /// Renders and shares; the button stays busy until it completes.
  final Future<void> Function(BuildContext buttonContext) onShare;

  /// The icon-only button's tooltip (and its screen-reader label).
  final String tooltip;

  /// null = an icon-only button; otherwise a text button with this label.
  final String? label;

  @override
  State<FantasyShareButton> createState() => _FantasyShareButtonState();
}

class _FantasyShareButtonState extends State<FantasyShareButton> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onShare(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = fantasyAccent(context);
    final Widget icon = _busy
        ? SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent),
          )
        : const Icon(Icons.ios_share, size: 18);
    final onPressed = _busy ? null : _share;
    final label = widget.label;
    if (label == null) {
      return IconButton(
        tooltip: widget.tooltip,
        visualDensity: VisualDensity.compact,
        color: accent,
        onPressed: onPressed,
        icon: icon,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: accent,
        visualDensity: VisualDensity.compact,
      ),
      icon: icon,
      label: Text(label),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';

/// Slim dark banner that slides down from the top for ~4 seconds to announce a
/// goal in a followed match while the app is foregrounded. Tap opens the match.
///
/// Presentation only — the caller decides when to show it (e.g. on an FCM
/// foreground goal message) and supplies the [onTap] navigation.
class GoalToast {
  static OverlayEntry? _current;

  static void show({
    required BuildContext context,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    // Replace any visible toast so rapid goals don't stack on screen.
    _current?.remove();
    _current = null;
    late OverlayEntry entry;
    void close() {
      if (_current == entry) {
        entry.remove();
        _current = null;
      }
    }

    entry = OverlayEntry(
      builder: (context) => _GoalToastCard(
        title: title,
        body: body,
        onTap: () {
          close();
          onTap();
        },
        onDismissed: close,
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _GoalToastCard extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  const _GoalToastCard({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  State<_GoalToastCard> createState() => _GoalToastCardState();
}

class _GoalToastCardState extends State<_GoalToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, -1.3), end: Offset.zero)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  Timer? _dismissTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _dismissTimer = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _dismissTimer?.cancel();
    if (mounted) await _c.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPad + 6,
      left: 8,
      right: 8,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 14,
                      offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  const Text('⚽', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        if (widget.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(widget.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _dismiss,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.close, color: Colors.white38, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

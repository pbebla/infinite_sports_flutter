import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';

/// AppBar bell that follows/unfollows one channel (tournament, league
/// season, or team). Outline = not following, filled = following —
/// FotMob-style.
class FollowBell extends StatefulWidget {
  final String topic;
  final String label;
  final String kind; // 'tournament' | 'team' | 'league'

  const FollowBell({
    super.key,
    required this.topic,
    required this.label,
    required this.kind,
  });

  @override
  State<FollowBell> createState() => _FollowBellState();
}

class _FollowBellState extends State<FollowBell> {
  final FollowStore _store = FollowStore();
  bool _followed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store.isFollowed(widget.topic).then((value) {
      if (mounted) setState(() => _followed = value);
    });
  }

  Future<bool> _ensurePermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notifications are off'),
          content: const Text(
              'Notifications are turned off for Infinite Sports in your '
              "phone's Settings. Turn them on there, then tap the bell again."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_followed) {
        await _store.unfollow(widget.topic);
        if (!mounted) return;
        setState(() => _followed = false);
        messenger.showSnackBar(SnackBar(
            content: Text('Alerts for ${widget.label} turned off.')));
      } else {
        if (!await _ensurePermission()) return;
        await _store.follow(FollowedChannel(
            topic: widget.topic, label: widget.label, kind: widget.kind));
        if (!mounted) return;
        setState(() => _followed = true);
        final message = switch (widget.kind) {
          'tournament' =>
            "You'll get goal, kickoff and full-time alerts for this tournament.",
          'league' =>
            "You'll get goal, kickoff and full-time alerts for every game this season.",
          _ => "You'll get alerts when ${widget.label} plays.",
        };
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _followed
          ? 'Stop alerts for ${widget.label}'
          : 'Get alerts for ${widget.label}',
      icon: Icon(
          _followed ? Icons.notifications_active : Icons.notifications_none),
      onPressed: _toggle,
    );
  }
}

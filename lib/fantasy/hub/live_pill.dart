// The shared LIVE pill (live everywhere, Task 5): a red dot + "LIVE" that
// marks numbers which are still moving (a gameweek being played). When the
// week settles the pill is simply not drawn and the official numbers take
// over.
//
// Theme: the bright fantasy "down" red pair (fantasyDownRed — #FF5252 dark /
// #D32F2F light; never Material's soft dark-mode error pink), the tint
// derived from it so the pill sits on any surface in both themes. The dot
// pulses with a 1.2 s period; under reduced motion it is static and the
// controller never runs (nothing keeps scheduling frames).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart'
    show fantasyDownRed;

/// How long one full pulse (bright → faded → bright) takes.
const Duration kLivePillPulse = Duration(milliseconds: 1200);

class FantasyLivePill extends StatefulWidget {
  const FantasyLivePill({super.key});

  @override
  State<FantasyLivePill> createState() => _FantasyLivePillState();
}

class _FantasyLivePillState extends State<FantasyLivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: kLivePillPulse);

  /// Bright at the start and end of a period, faded in the middle.
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.3)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1),
    TweenSequenceItem(
        tween: Tween(begin: 0.3, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1),
  ]).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: stand still on the bright frame, schedule nothing.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = fantasyDownRed(context);
    return Semantics(
      label: 'Live',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: red.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: red.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              key: const ValueKey('live_pill_dot'),
              opacity: _opacity,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: red),
                child: const SizedBox(width: 7, height: 7),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                height: 1.1,
                color: red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

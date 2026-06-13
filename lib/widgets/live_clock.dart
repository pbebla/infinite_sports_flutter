import 'dart:async';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/match_clock.dart';

mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  void startTicking(bool active) {
    _timer?.cancel();
    if (active) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Green circle showing the live minute (e.g. "37'") for match-list rows.
/// If [clock] is null (older matches) it shows "LIVE".
class MinuteBall extends StatefulWidget {
  final MatchClock? clock;
  const MinuteBall({super.key, required this.clock});

  @override
  State<MinuteBall> createState() => _MinuteBallState();
}

class _MinuteBallState extends State<MinuteBall> with _Ticking {
  static const _green = Color(0xFF0A7D2C);

  @override
  void initState() {
    super.initState();
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  void didUpdateWidget(covariant MinuteBall old) {
    super.didUpdateWidget(old);
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    final label = clock == null
        ? 'LIVE'
        : minuteLabel(clock.elapsedAt(DateTime.now().millisecondsSinceEpoch));
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: label == 'LIVE' ? 8 : 11,
        ),
      ),
    );
  }
}

/// Green mm:ss clock text for the game-card header. Hidden (shrinks to nothing)
/// if [clock] is null.
class MatchClockText extends StatefulWidget {
  final MatchClock? clock;
  const MatchClockText({super.key, required this.clock});

  @override
  State<MatchClockText> createState() => _MatchClockTextState();
}

class _MatchClockTextState extends State<MatchClockText> with _Ticking {
  static const _green = Color(0xFF7CFC9A);

  @override
  void initState() {
    super.initState();
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  void didUpdateWidget(covariant MatchClockText old) {
    super.didUpdateWidget(old);
    startTicking(widget.clock != null && !widget.clock!.isPaused);
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    if (clock == null) return const SizedBox.shrink();
    final label =
        clockLabel(clock.elapsedAt(DateTime.now().millisecondsSinceEpoch));
    return Text(
      label,
      style: const TextStyle(
        color: _green,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    );
  }
}

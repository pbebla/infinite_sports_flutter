// The in-season Infinite Fantasy home banner (P6, spec §10/§10b hub
// entries): a slim strip on the front page's league tab — the shared
// FantasyBanner brand surface with the logo, "Fantasy is live — set your
// squad" and a deadline countdown chip while the current gameweek is open
// under the automatic lock. Tapping opens the hub (the league entry card's
// push). Shown while `Fantasy/<sport>/<season>/Config` exists — the same
// live stream gate as the league page's Fantasy tab — and gone otherwise,
// so the front page carries NO per-user state (not dismissible by design).
//
// House rules: streams only; theme-safe both modes via the single-sourced
// brand surface; text wraps, never underlined; the countdown line is
// INFORMATION (a 60s refresh, nothing animates per tick, timer cancelled on
// dispose — reconnects can't replay anything).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

class FantasyHomeBanner extends StatefulWidget {
  const FantasyHomeBanner({
    super.key,
    required this.sport,
    required this.season,
    this.configStates,
    this.gameweeksStates,
    this.onOpen,
    this.nowUtc,
  });

  final String sport;
  final String season;

  /// Test seams — null = the real FantasyService streams.
  final Stream<FantasyConfigState?>? configStates;
  final Stream<List<Gameweek>>? gameweeksStates;

  /// Test seam replacing the real `Navigator.push(... FantasyHubPage ...)`.
  final VoidCallback? onOpen;

  /// Test seam: injected clock. Production leaves it null (real UTC now).
  final DateTime Function()? nowUtc;

  @override
  State<FantasyHomeBanner> createState() => _FantasyHomeBannerState();
}

class _FantasyHomeBannerState extends State<FantasyHomeBanner> {
  FantasyConfigState? _config;
  List<Gameweek> _gameweeks = const [];
  int? _gameweeksLockHour; // lockHour the gameweek stream was derived with

  StreamSubscription<FantasyConfigState?>? _configSub;
  StreamSubscription<List<Gameweek>>? _gameweeksSub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _configSub = (widget.configStates ??
            FantasyService.watchConfig(widget.sport, widget.season))
        .listen((s) {
      if (!mounted) return;
      setState(() => _config = s);
      if (s != null) _subscribeGameweeks(s);
    }, onError: (Object _) {
      // Offline/unreachable: the banner simply stays hidden.
      if (mounted) setState(() => _config = null);
    });
    // 60s refresh keeps the countdown text honest (information, not
    // decoration — no per-tick animation); cancelled in dispose.
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _config != null) setState(() {});
    });
  }

  /// Gameweeks derive from the real schedule WITH the config's lock hour —
  /// resubscribe only when that hour actually changes (hub pattern).
  void _subscribeGameweeks(FantasyConfigState s) {
    if (widget.gameweeksStates == null &&
        _gameweeksLockHour == s.config.lockHour) {
      return;
    }
    if (widget.gameweeksStates != null && _gameweeksSub != null) return;
    _gameweeksLockHour = s.config.lockHour;
    _gameweeksSub?.cancel();
    _gameweeksSub = (widget.gameweeksStates ??
            FantasyService.watchGameweeks(
                widget.sport, widget.season, s.config))
        .listen((gws) {
      if (mounted) setState(() => _gameweeks = gws);
    });
  }

  @override
  void dispose() {
    _configSub?.cancel();
    _gameweeksSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  void _openHub() {
    final open = widget.onOpen;
    if (open != null) {
      open();
      return;
    }
    // Root navigator, matching the front page's other header pushes.
    Navigator.push(
      mainContext ?? context,
      MaterialPageRoute(
        builder: (_) =>
            FantasyHubPage(sport: widget.sport, season: widget.season),
      ),
    );
  }

  /// "GW3 locks in 2d 4h" while the current gameweek is OPEN under the
  /// automatic lock; null in every other state (the banner stays slim).
  String? _deadlineText() {
    final config = _config;
    if (config == null || config.lockOverride != FantasyLockOverride.auto) {
      return null;
    }
    final now = _now;
    final gw = currentGameweek(_gameweeks, now);
    if (gw == null || gw.statusAt(now) != GameweekStatus.open) return null;
    return 'GW${gw.number} locks in '
        '${formatCountdown(gw.lockUtc.difference(now))}';
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null) return const SizedBox.shrink();
    final accent = FantasyBanner.accent(context);
    final deadline = _deadlineText();

    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 4, 19, 0),
      child: Container(
        decoration: FantasyBanner.cardDecoration(context, radius: 16),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const ValueKey('fantasy_home_banner'),
            borderRadius: BorderRadius.circular(16),
            onTap: _openHub,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  FantasyBanner.logo(
                    context,
                    height: 30,
                    backdropPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fantasy is live — set your squad',
                          // Wraps, never underlined (house rules).
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: FantasyBanner.foreground(context),
                          ),
                        ),
                        if (deadline != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            key: const ValueKey(
                                'fantasy_home_banner_deadline'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.45)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined,
                                    size: 13, color: accent),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    deadline,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          FantasyBanner.foreground(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      size: 20,
                      color: FantasyBanner.foregroundMuted(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

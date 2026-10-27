// The Infinite Fantasy Hub (P3a Task 2) — banner, deadline chip, and the five
// tabs: My Team · Players · Leaderboards · News · Rules (spec §10). My Team /
// Players / Leaderboards / News are tasteful placeholders until P3b–P3d; the
// Rules tab renders live from the streamed config (Task 3).
//
// House rules honored here: streams only; SINGLE fade reveal once
// config+players first arrive (no piecemeal pops — a skeleton holds the
// layout until both streams have emitted); light+dark via colorScheme with
// the fantasy banner staying a dark gradient in both themes; scrollables
// clear the floating glass navbar (base + MediaQuery.paddingOf(context)
// .bottom).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_walkthrough.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rules_tab.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

class FantasyHubPage extends StatefulWidget {
  const FantasyHubPage({
    super.key,
    required this.sport,
    required this.season,
  });

  final String sport;
  final String season;

  @override
  State<FantasyHubPage> createState() => _FantasyHubPageState();
}

class _FantasyHubPageState extends State<FantasyHubPage> {
  FantasyConfigState? _configState;
  List<FantasyPlayer>? _players;
  List<Gameweek> _gameweeks = const [];
  int? _gameweeksLockHour; // lockHour the gameweek stream was derived with

  /// First-open walkthrough (spec §10a): null while the prefs flag loads,
  /// false = show the intro, true = straight to the hub.
  bool? _walkthroughSeen;

  StreamSubscription<FantasyConfigState?>? _configSub;
  StreamSubscription<List<FantasyPlayer>>? _playersSub;
  StreamSubscription<List<Gameweek>>? _gameweeksSub;

  bool get _ready => _configState != null && _players != null;

  @override
  void initState() {
    super.initState();
    FantasyPrefs.hasSeenWalkthrough().then((seen) {
      if (mounted) setState(() => _walkthroughSeen = seen);
    });
    _configSub =
        FantasyService.watchConfig(widget.sport, widget.season).listen((s) {
      if (!mounted) return;
      setState(() => _configState = s);
      if (s != null) _subscribeGameweeks(s);
    });
    _playersSub =
        FantasyService.watchPlayers(widget.sport, widget.season).listen((p) {
      if (mounted) setState(() => _players = p);
    });
  }

  /// Gameweeks derive from the real schedule WITH the config's lock hour —
  /// resubscribe only when that hour actually changes (config tweaks that
  /// don't move deadlines shouldn't restart the stream).
  void _subscribeGameweeks(FantasyConfigState s) {
    if (_gameweeksLockHour == s.config.lockHour) return;
    _gameweeksLockHour = s.config.lockHour;
    _gameweeksSub?.cancel();
    _gameweeksSub = FantasyService.watchGameweeks(
            widget.sport, widget.season, s.config)
        .listen((gws) {
      if (mounted) setState(() => _gameweeks = gws);
    });
  }

  @override
  void dispose() {
    _configSub?.cancel();
    _playersSub?.cancel();
    _gameweeksSub?.cancel();
    super.dispose();
  }

  void _finishWalkthrough() {
    FantasyPrefs.markWalkthroughSeen();
    setState(() => _walkthroughSeen = true);
  }

  @override
  Widget build(BuildContext context) {
    // The walkthrough needs no network: it shows immediately on first open
    // (config numbers fall back to the launch defaults until the stream
    // lands) and never again after Skip/finish.
    final Widget body;
    if (_walkthroughSeen == false) {
      body = FantasyWalkthrough(
        key: const ValueKey('walkthrough'),
        config: _configState?.config ?? FantasyConfig.futsalDefault(),
        onDone: _finishWalkthrough,
      );
    } else if (_ready && _walkthroughSeen != null) {
      body = _HubBody(
        key: const ValueKey('hub'),
        sport: widget.sport,
        season: widget.season,
        configState: _configState!,
        gameweeks: _gameweeks,
      );
    } else {
      body = const _HubSkeleton(key: ValueKey('skeleton'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Infinite Fantasy')),
      // Single fade reveal: skeleton until config+players BOTH arrived,
      // then the whole hub fades in at once.
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: body,
      ),
    );
  }
}

class _HubSkeleton extends StatelessWidget {
  const _HubSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: double.infinity, height: 120, radius: 20),
            SizedBox(height: 16),
            SkeletonLines(count: 2),
            SizedBox(height: 16),
            SkeletonList(count: 6),
          ],
        ),
      ),
    );
  }
}

class _HubBody extends StatelessWidget {
  const _HubBody({
    super.key,
    required this.sport,
    required this.season,
    required this.configState,
    required this.gameweeks,
  });

  final String sport;
  final String season;
  final FantasyConfigState configState;
  final List<Gameweek> gameweeks;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: FantasyBanner(
              subtitle: '$sport · Season $season',
              bottom: FantasyDeadlineChip(
                gameweeks: gameweeks,
                lockOverride: configState.lockOverride,
              ),
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'My Team'),
              Tab(text: 'Players'),
              Tab(text: 'Leaderboards'),
              Tab(text: 'News'),
              Tab(text: 'Rules'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _PlaceholderTab(
                  icon: Icons.sports_soccer,
                  title: 'My Team',
                  message: 'The squad builder lands here next — pick your '
                      'seven, set the armband, beat the deadline.',
                ),
                const _PlaceholderTab(
                  icon: Icons.storefront,
                  title: 'Players',
                  message: 'The player market is on its way — prices, form '
                      'and transfers for every player in the league.',
                ),
                const _PlaceholderTab(
                  icon: Icons.emoji_events_outlined,
                  title: 'Leaderboards',
                  message: 'Season and weekly standings plus private '
                      'mini-leagues will live here.',
                ),
                const _PlaceholderTab(
                  icon: Icons.newspaper,
                  title: 'News',
                  message: 'Gameweek stories, price movers and the Dream '
                      'Team of the Week are coming soon.',
                ),
                // Rendered ENTIRELY from the live config (spec §10a): a
                // tuned value re-renders this page by itself.
                FantasyRulesTab(
                  configStates: FantasyService.watchConfig(sport, season),
                  initialState: configState,
                  gameweeks: gameweeks,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme-safe placeholder body for a tab whose slice hasn't shipped yet —
/// short copy + icon, scrolling clear of the glass navbar.
class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

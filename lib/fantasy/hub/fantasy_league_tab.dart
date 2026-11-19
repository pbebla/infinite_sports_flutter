// The Fantasy Hub's League tab: who plays whom while the fan picks players.
// A Fixtures / Table switch over the league's own widgets (LeagueFixturesTab,
// LeagueTableTab), fed by the shared games feed and the shared table feed
// (fantasy_schedule_feed.dart) — live streams only, session caches so a
// revisit paints at once.
//
// ONE reveal: a skeleton until the games AND the table (with its crests) have
// answered or failed, then one fade. An error is not a fact: a failed read
// shows "Couldn't load the league" with Try again, never "No fixtures
// available" or an empty table (the feeds keep the last good data).
//
// Only the chosen view is mounted: CollapsingTabShell reads the active tab's
// scroll notifications at depth 0 to collapse the header, so two lists in one
// Hub tab would feed it conflicting metrics. The picked day and the switch
// live in this State, so they survive the switch and, as Hub tabs are kept
// alive, a trip to a game and back.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/league_tabs/league_fixtures_tab.dart';
import 'package:infinite_sports_flutter/league_tabs/league_table_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_navigation.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Test seams — null = the real LeagueService feeds and the league routes.
class FantasyLeagueSeams {
  const FantasyLeagueSeams({
    this.gamesStates,
    this.leagueGamesFor,
    this.loadStartHour,
    this.standingsFor,
    this.watchLogos,
    this.openMatch,
    this.openTeam,
  });

  final Stream<List<TournamentMatch>>? gamesStates;
  final Stream<List<TournamentMatch>> Function(int startHour)? leagueGamesFor;
  final Future<int> Function()? loadStartHour;
  final Stream<List<TournamentTeam>> Function(Map<String, String> logos)?
      standingsFor;
  final VoidCallback Function(void Function(Map<String, String> logos) onLogos)?
      watchLogos;
  final void Function(BuildContext context, TournamentMatch match)? openMatch;
  final void Function(BuildContext context, String teamName)? openTeam;
}

class FantasyLeagueTab extends StatefulWidget {
  const FantasyLeagueTab({
    super.key,
    required this.sport,
    required this.season,
    this.seams = const FantasyLeagueSeams(),
    this.now,
  });

  final String sport;
  final String season;
  final FantasyLeagueSeams seams;

  /// Test seam for "today" (LeagueFixturesTab's default-day logic).
  final DateTime? now;

  @override
  State<FantasyLeagueTab> createState() => _FantasyLeagueTabState();
}

class _FantasyLeagueTabState extends State<FantasyLeagueTab> {
  late FantasyLeagueGamesFeed _games;
  late FantasyLeagueTableFeed _table;
  bool _showTable = false;
  String? _pickedDay;

  /// True once both feeds have been ready (or a revisit was seeded from the
  /// session): the full-tab skeleton is the FIRST load only. After that a
  /// feed's "Try again" blanks only its own view, never the other one.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _startFeeds();
  }

  void _startFeeds() {
    final seams = widget.seams;
    void changed() {
      if (mounted) setState(() {});
    }

    _games = FantasyLeagueGamesFeed(
      sport: widget.sport,
      season: widget.season,
      owner: 'FantasyLeagueTab',
      onChanged: changed,
      gamesStates: seams.gamesStates,
      gamesFor: seams.leagueGamesFor,
      loadStartHour: seams.loadStartHour,
    );
    _table = FantasyLeagueTableFeed(
      sport: widget.sport,
      season: widget.season,
      owner: 'FantasyLeagueTab',
      onChanged: changed,
      standingsFor: seams.standingsFor,
      watchLogos: seams.watchLogos,
    );
    _games.start();
    _table.start();
  }

  @override
  void didUpdateWidget(FantasyLeagueTab old) {
    super.didUpdateWidget(old);
    if (old.sport != widget.sport || old.season != widget.season) {
      _games.dispose();
      _table.dispose();
      _pickedDay = null;
      _revealed = false;
      _startFeeds();
    }
  }

  @override
  void dispose() {
    _games.dispose();
    _table.dispose();
    super.dispose();
  }

  bool get _ready {
    if (!_revealed && _games.ready && _table.ready) _revealed = true;
    return _revealed;
  }

  void _openMatch(BuildContext context, TournamentMatch match) {
    final open = widget.seams.openMatch;
    if (open != null) {
      open(context, match);
      return;
    }
    openLeagueMatch(context,
        sport: widget.sport, season: widget.season, match: match);
  }

  void _openTeam(BuildContext context, String name) {
    final open = widget.seams.openTeam;
    if (open != null) {
      open(context, name);
      return;
    }
    openLeagueTeam(context,
        sport: widget.sport, season: widget.season, teamName: name);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Keyed by league: on a season change the switcher is a NEW one, so the
    // old season's content never fades out under the new skeleton.
    return KeyedSubtree(
      key: ValueKey('${widget.sport}|${widget.season}'),
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        child: _ready
            ? _content(context)
            : const _LeagueSkeleton(key: ValueKey('league_tab_skeleton')),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final failed = _showTable ? _table.failed : _games.failed;
    final loading = _showTable ? !_table.ready : !_games.ready;
    final empty = _showTable ? _table.standings.isEmpty : _games.games.isEmpty;
    return Column(
      key: const ValueKey('league_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SegmentedButton<bool>(
            key: const ValueKey('league_view_switch'),
            showSelectedIcon: false,
            // The picked half is filled with the theme primary (the Hub's
            // gold in dark mode), so it reads as ON — the default tonal fill
            // looked greyed out (owner, 2026-11-16).
            style: leagueSwitchStyle(context),
            segments: const [
              ButtonSegment(value: false, label: Text('Fixtures')),
              ButtonSegment(value: true, label: Text('Table')),
            ],
            selected: {_showTable},
            onSelectionChanged: (s) => setState(() => _showTable = s.first),
          ),
        ),
        Expanded(
          child: failed
              ? _LeagueError(
                  onRetry: _showTable ? _table.retry : _games.retry,
                )
              : loading
                  ? const _LeagueSkeleton(
                      key: ValueKey('league_view_skeleton'), withSwitch: false)
                  : empty
                      ? _ScrollableFace(child: _view(context))
                      : _view(context),
        ),
      ],
    );
  }

  Widget _view(BuildContext context) {
    return _showTable
        ? LeagueTableTab(
            sport: widget.sport,
            standings: _table.standings,
            onOpenTeam: (name) => _openTeam(context, name),
          )
        : LeagueFixturesTab(
            matches: _games.games,
            teams:
                leagueCardTeams(_games.games, _table.standings, _table.logos),
            rosters: const {},
            sport: widget.sport,
            predictionsOpen: false,
            pickedDay: _pickedDay,
            onDayPicked: (d) => setState(() => _pickedDay = d),
            now: widget.now,
            onMatchTap: (m) => _openMatch(context, m),
          );
  }
}

/// Gives a face that has no list of its own (the empty states, the error)
/// a scrollable that fills the available space. Why: CollapsingTabShell
/// collapses the Hub header from the active tab's scroll notifications and
/// keeps the last metrics it was told; a view with no scrollable would leave
/// the previous list's metrics in force, so the header would stay collapsed
/// with no way to re-open it. A scrollable that has nothing to scroll reports
/// its metrics, and the shell's "nothing to scroll" escape re-opens the
/// header.
class _ScrollableFace extends StatelessWidget {
  const _ScrollableFace({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(height: constraints.maxHeight, child: child),
      ),
    );
  }
}

/// The Fixtures / Table switch's style: the picked half filled with the
/// theme primary — the same gold as the Hub's tab underline and the picked
/// day box in dark mode, the app red in light — with its onPrimary text; the
/// other half keeps the default look.
@visibleForTesting
ButtonStyle leagueSwitchStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final accent = scheme.primary;
  final onAccent = scheme.onPrimary;
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : null),
    foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? onAccent : null),
  );
}

class _LeagueError extends StatelessWidget {
  const _LeagueError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ScrollableFace(
        key: const ValueKey('league_tab_error'),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Couldn't load the league",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ));
  }
}

class _LeagueSkeleton extends StatelessWidget {
  const _LeagueSkeleton({super.key, this.withSwitch = true});

  /// The first-load skeleton also stands in for the Fixtures/Table switch; a
  /// single view's skeleton sits under the real switch.
  final bool withSwitch;

  @override
  Widget build(BuildContext context) {
    // A scrollable that fills the tab (see _ScrollableFace for why).
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(children: [
        if (withSwitch) ...const [
          SkeletonBox(width: double.infinity, height: 40, radius: 20),
          SizedBox(height: 12),
        ],
        const SkeletonBox(width: double.infinity, height: 56, radius: 12),
        const SizedBox(height: 12),
        const SkeletonBox(width: double.infinity, height: 84, radius: 12),
        const SizedBox(height: 10),
        const SkeletonBox(width: double.infinity, height: 84, radius: 12),
        const SizedBox(height: 10),
        const SkeletonBox(width: double.infinity, height: 84, radius: 12),
      ]),
    );
  }
}

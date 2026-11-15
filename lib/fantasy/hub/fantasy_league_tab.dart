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
      _startFeeds();
    }
  }

  @override
  void dispose() {
    _games.dispose();
    _table.dispose();
    super.dispose();
  }

  bool get _ready => _games.ready && _table.ready;

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
    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: _ready
          ? _content(context)
          : const _LeagueSkeleton(key: ValueKey('league_tab_skeleton')),
    );
  }

  Widget _content(BuildContext context) {
    final failed = _showTable ? _table.failed : _games.failed;
    return Column(
      key: const ValueKey('league_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SegmentedButton<bool>(
            key: const ValueKey('league_view_switch'),
            showSelectedIcon: false,
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
              : _showTable
                  ? LeagueTableTab(
                      sport: widget.sport,
                      standings: _table.standings,
                      onOpenTeam: (name) => _openTeam(context, name),
                    )
                  : LeagueFixturesTab(
                      matches: _games.games,
                      teams: leagueCardTeams(
                          _games.games, _table.standings, _table.logos),
                      rosters: const {},
                      sport: widget.sport,
                      predictionsOpen: false,
                      pickedDay: _pickedDay,
                      onDayPicked: (d) => setState(() => _pickedDay = d),
                      now: widget.now,
                      onMatchTap: (m) => _openMatch(context, m),
                    ),
        ),
      ],
    );
  }
}

class _LeagueError extends StatelessWidget {
  const _LeagueError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('league_tab_error'),
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
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _LeagueSkeleton extends StatelessWidget {
  const _LeagueSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      children: const [
        SkeletonBox(width: double.infinity, height: 40, radius: 20),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 56, radius: 12),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 84, radius: 12),
        SizedBox(height: 10),
        SkeletonBox(width: double.infinity, height: 84, radius: 12),
        SizedBox(height: 10),
        SkeletonBox(width: double.infinity, height: 84, radius: 12),
      ],
    );
  }
}

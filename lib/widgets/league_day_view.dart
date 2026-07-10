import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/scorepage.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Matches-tab league day view (League Experience P2.1): the current league
/// section's games for ONE date as live-streamed tournament-style compact
/// cards (LIVE badge, MinuteBall clock, flashing ScoreText, stage/Friendly
/// chip) — replaces the legacy 240/270px LiveScorePage cards.
///
/// - Streams the single date node via [LeagueService.watchDateGames], so
///   score/clock/status changes arrive without a refresh.
/// - Skeleton rows ([SkeletonMatchList]) while the first snapshot loads.
/// - Tap: Futsal -> [LeagueMatchDetailPage] (same routing livescore.dart
///   wired in P2); other league sports -> legacy [ScorePage] until P4
///   (the legacy Game object is fetched one-shot at tap time).
///
/// AFC San Jose does NOT use this view (different RTDB layout under
/// /AFC San Jose/Seasons and startTime/location/type semantics) — it stays
/// on the legacy LiveScorePage.
class LeagueDayView extends StatefulWidget {
  final String sport;
  final String season;

  /// MMDDYYYY database date key.
  final String date;

  const LeagueDayView({
    super.key,
    required this.sport,
    required this.season,
    required this.date,
  });

  @override
  State<LeagueDayView> createState() => _LeagueDayViewState();
}

class _LeagueDayViewState extends State<LeagueDayView> {
  List<TournamentMatch>? _matches; // null = first paint -> skeleton
  Map<String, String> _logos = {};
  StreamSubscription<List<TournamentMatch>>? _gamesSub;

  /// Guards the tap-time legacy fetch so a double tap doesn't push twice.
  bool _openingLegacy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (widget.date.isEmpty) {
      // No current date (legacy getGames returned [] for this too).
      setState(() => _matches = const []);
      return;
    }
    final results = await Future.wait([
      LeagueService.getStartHour(widget.sport, widget.season),
      LeagueService.leagueLogoUrls(widget.sport, widget.season),
    ]);
    if (!mounted) return;
    final startHour = results[0] as int;
    _logos = results[1] as Map<String, String>;
    _gamesSub = LeagueService.watchDateGames(
      widget.sport,
      widget.season,
      widget.date,
      startHour: startHour,
    ).listen((m) {
      if (mounted) setState(() => _matches = m);
    });
  }

  @override
  void dispose() {
    _gamesSub?.cancel();
    super.dispose();
  }

  void _openMatch(TournamentMatch m) {
    final ref = parseLeagueGameId(m.id);
    if (ref == null) return;
    // Same futsal-vs-legacy branch livescore.dart used: futsal opens the
    // live league match page; basketball/flag football keep the legacy
    // ScorePage (with its voting UI) until P4.
    if (widget.sport == 'Futsal') {
      Navigator.push(
        mainContext!,
        MaterialPageRoute(
          builder: (_) => LeagueMatchDetailPage(
            sport: widget.sport,
            season: widget.season,
            dateKey: ref.dateKey,
            gameIndex: ref.index,
            initialMatch: m,
          ),
        ),
      );
      return;
    }
    _openLegacyScorePage(ref.index);
  }

  Future<void> _openLegacyScorePage(int index) async {
    if (_openingLegacy) return;
    _openingLegacy = true;
    try {
      // ScorePage renders the legacy Game model, so fetch it one-shot at tap
      // time (the card list itself stays on the live stream).
      final times = <String, Map<String, int>>{};
      final games =
          await getGames(widget.sport, widget.season, widget.date, times);
      if (!mounted || index < 0 || index >= games.length) return;
      final game = games[index];
      Navigator.push(
        mainContext!,
        MaterialPageRoute(
          builder: (_) => Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) {
                  return ScorePage(
                    sport: widget.sport,
                    season: widget.season,
                    game: game,
                    times: times,
                    // The day-view list live-streams its date node, so
                    // there is nothing to refetch here.
                    refreshCallback: () {},
                  );
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      _openingLegacy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    if (matches == null) {
      return const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 8),
          child: SkeletonMatchList(count: 6),
        ),
      );
    }
    if (matches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No Upcoming Games, Stay Tuned for Next Season!',
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return FixturesTab(
      matches: matches,
      teams: leagueTeamsById(const [], _logos),
      rosters: const {},
      tournamentId: '',
      sport: widget.sport,
      onMatchTap: _openMatch,
    );
  }
}

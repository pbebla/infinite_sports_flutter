import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/game_day.dart';
import 'package:infinite_sports_flutter/misc/match_days.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/widgets/day_pill_strip.dart';

/// League Fixtures tab (League Experience P2.1): the tournament-style
/// [DayPillStrip] date boxes on top of the shared [FixturesTab], showing
/// ONLY the selected day's games. Day list and default selection are
/// recomputed from the live match stream on every build:
/// - default day = a live day if any, else today / nearest upcoming day,
///   else the season's last day ([defaultFixturesDay]);
/// - a day the user tapped sticks for the life of the tab.
class LeagueFixturesTab extends StatefulWidget {
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final Map<String, List<TournamentPlayer>> rosters;
  final String sport;
  final void Function(TournamentMatch match)? onMatchTap;

  /// Test seam for "today"; production callers leave it null (DateTime.now()).
  final DateTime? now;

  const LeagueFixturesTab({
    super.key,
    required this.matches,
    required this.teams,
    required this.rosters,
    required this.sport,
    this.onMatchTap,
    this.now,
  });

  @override
  State<LeagueFixturesTab> createState() => _LeagueFixturesTabState();
}

class _LeagueFixturesTabState extends State<LeagueFixturesTab> {
  /// Day the user explicitly tapped; null = follow the computed default
  /// (so the tab tracks live days / date rollover until the user picks one).
  String? _pickedDay;

  @override
  Widget build(BuildContext context) {
    final days = sortedMatchDays(widget.matches.map((m) => m.date));
    final liveDays = <String>{
      for (final m in widget.matches)
        if (m.matchStatus.isLive) m.date,
    };
    final selected = (_pickedDay != null && days.contains(_pickedDay))
        ? _pickedDay
        : defaultFixturesDay(days, liveDays, now: widget.now);

    // No selectable day (no matches / malformed dates): plain full list —
    // FixturesTab renders its own 'No fixtures available' when empty.
    final visible = selected == null
        ? widget.matches
        : widget.matches.where((m) => m.date == selected).toList();

    return Column(
      children: [
        if (selected != null)
          DayPillStrip(
            days: days,
            selectedDay: selected,
            onSelect: (day) => setState(() => _pickedDay = day),
          ),
        Expanded(
          child: FixturesTab(
            matches: visible,
            teams: widget.teams,
            rosters: widget.rosters,
            tournamentId: '',
            sport: widget.sport,
            onMatchTap: widget.onMatchTap,
          ),
        ),
      ],
    );
  }
}

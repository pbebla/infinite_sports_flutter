import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/match_days.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/widgets/day_pill_strip.dart';

/// Home-tab tournament view: a swipeable strip of day pills on top of the
/// shared [FixturesTab]. [matches] is the tournament's FULL match list;
/// [initialDay] (MMDDYYYY) is the day to open on (the current game day computed
/// by the caller). Only the selected day's matches are passed to [FixturesTab],
/// matching the existing home-tab behavior. The day boxes themselves live in
/// the shared [DayPillStrip] (P2.1: reused by the league Fixtures tab).
class TournamentDayView extends StatefulWidget {
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final Map<String, List<TournamentPlayer>> rosters;
  final String tournamentId;
  final String sport;
  final String initialDay;

  const TournamentDayView({
    super.key,
    required this.matches,
    required this.teams,
    required this.rosters,
    required this.tournamentId,
    required this.sport,
    required this.initialDay,
  });

  @override
  State<TournamentDayView> createState() => _TournamentDayViewState();
}

class _TournamentDayViewState extends State<TournamentDayView> {
  late final List<String> _days;
  late String _selectedDay;

  @override
  void initState() {
    super.initState();
    _days = sortedMatchDays(widget.matches.map((m) => m.date));
    // Open on the provided day when it is a real match day; otherwise fall back
    // to the first day (defensive — initialDay is normally present).
    _selectedDay = _days.contains(widget.initialDay)
        ? widget.initialDay
        : (_days.isNotEmpty ? _days.first : widget.initialDay);
  }

  List<TournamentMatch> get _matchesForSelectedDay =>
      widget.matches.where((m) => m.date == _selectedDay).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DayPillStrip(
          days: _days,
          selectedDay: _selectedDay,
          onSelect: (day) => setState(() => _selectedDay = day),
        ),
        Expanded(
          child: FixturesTab(
            matches: _matchesForSelectedDay,
            teams: widget.teams,
            rosters: widget.rosters,
            tournamentId: widget.tournamentId,
            sport: widget.sport,
          ),
        ),
      ],
    );
  }
}

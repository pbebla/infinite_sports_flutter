import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/match_days.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:intl/intl.dart';

/// Home-tab tournament view: a swipeable strip of day pills on top of the
/// shared [FixturesTab]. [matches] is the tournament's FULL match list;
/// [initialDay] (MMDDYYYY) is the day to open on (the current game day computed
/// by the caller). Only the selected day's matches are passed to [FixturesTab],
/// matching the existing home-tab behavior.
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
  // Pill box (52) + horizontal margin (4 each side) = 60 logical px per pill.
  static const double _pillExtent = 60;

  late final List<String> _days;
  late String _selectedDay;
  final ScrollController _stripController = ScrollController();

  @override
  void initState() {
    super.initState();
    _days = sortedMatchDays(widget.matches.map((m) => m.date));
    // Open on the provided day when it is a real match day; otherwise fall back
    // to the first day (defensive — initialDay is normally present).
    _selectedDay = _days.contains(widget.initialDay)
        ? widget.initialDay
        : (_days.isNotEmpty ? _days.first : widget.initialDay);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollSelectedIntoView();
    });
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  void _scrollSelectedIntoView() {
    if (!_stripController.hasClients) return;
    final index = _days.indexOf(_selectedDay);
    if (index < 0) return;
    final viewport = _stripController.position.viewportDimension;
    final target = (index * _pillExtent) - (viewport / 2) + (_pillExtent / 2);
    final max = _stripController.position.maxScrollExtent;
    _stripController.jumpTo(target.clamp(0.0, max).toDouble());
  }

  List<TournamentMatch> get _matchesForSelectedDay =>
      widget.matches.where((m) => m.date == _selectedDay).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildStrip(context),
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

  Widget _buildStrip(BuildContext context) {
    // Nothing to switch between when there is a single day.
    if (_days.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 66,
      child: ListView.builder(
        controller: _stripController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _days.length,
        itemBuilder: (context, index) => _buildPill(context, _days[index]),
      ),
    );
  }

  Widget _buildPill(BuildContext context, String day) {
    final selected = day == _selectedDay;
    final dt = parseDatabaseDate(day);
    final dow = dt != null ? DateFormat('EEE').format(dt).toUpperCase() : '';
    final dayNumber = dt != null ? DateFormat('d').format(dt) : day;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: () {
        if (day == _selectedDay) return;
        setState(() => _selectedDay = day);
      },
      child: Container(
        width: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? infiniteSportsPrimaryColor
              : onSurface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dow,
              style: TextStyle(
                fontSize: 10,
                color:
                    selected ? Colors.white : onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dayNumber,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

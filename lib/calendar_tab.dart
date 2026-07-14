import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/league_detail_page.dart';
import 'package:infinite_sports_flutter/misc/calendar_sources.dart';
import 'package:infinite_sports_flutter/misc/event_repo.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';
import 'package:intl/intl.dart';

/// Calendar tab: vertically scrolling month grids. Opens on the current
/// month, scrolls back [_monthsBack] months and forward [_monthsForward].
/// Days with events show accent dots; tapping one opens a sheet listing that
/// day's events. Sport filters arrive with event categories in the next
/// piece of the epic.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  static const _monthsBack = 12;
  static const _monthsForward = 15;
  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  final Key _centerKey = const ValueKey('calendar-current-month');
  final ScrollController _scroll = ScrollController();
  final Set<String> _selectedCategories = {};
  // Live: three sources (events, league match days, tournament days) each
  // update in place whenever their data changes — no refresh anywhere.
  Map<DateTime, List<CalendarEntry>> _events = {};
  Map<DateTime, List<CalendarEntry>> _leagueDays = {};
  Map<DateTime, List<CalendarEntry>> _tournamentDays = {};
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(watchAllEvents().map(eventsByDay).listen((byDay) {
      if (mounted) setState(() => _events = byDay);
    }));
    _subs.add(watchLeagueDays().listen((byDay) {
      if (mounted) setState(() => _leagueDays = byDay);
    }));
    _subs.add(watchTournamentDays().listen((byDay) {
      if (mounted) setState(() => _tournamentDays = byDay);
    }));
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// Scroll offset 0 is the top of the current month (the center sliver),
  /// so "Today" is a plain glide back to origin.
  void _jumpToToday() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const ImageIcon(AssetImage('assets/profile.png')),
              onPressed: () {
                Scaffold.of(mainScaffoldContext!).openDrawer();
              },
            );
          },
        ),
        centerTitle: true,
        title: Image.asset('assets/infinitelarge_dark.png', height: 30),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _jumpToToday,
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              child: const Text('Today',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          // No spinner: the month grid renders immediately and dots stream
          // in per source as data arrives (instantly from cache offline).
          final all = mergeDayMaps([_events, _leagueDays, _tournamentDays]);
          final byDay = filterByCategories(all, _selectedCategories);
          final now = DateTime.now();
          final currentMonth = DateTime(now.year, now.month, 1);
          return Column(
            children: [
              _CategoryChips(
                selected: _selectedCategories,
                onChanged: (category) {
                  setState(() {
                    if (category == null) {
                      _selectedCategories.clear();
                    } else if (!_selectedCategories.remove(category)) {
                      _selectedCategories.add(category);
                    }
                  });
                },
              ),
              _WeekdayHeader(labels: _weekdayLabels),
              Expanded(
                child: CustomScrollView(
                  controller: _scroll,
                  center: _centerKey,
                  slivers: [
                    // Months before today, built upward from the current month.
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => CalendarMonthView(
                          month: DateTime(currentMonth.year, currentMonth.month - (i + 1), 1),
                          eventsByDay: byDay,
                          onDayTap: _showDaySheet,
                        ),
                        childCount: _monthsBack,
                      ),
                    ),
                    SliverList(
                      key: _centerKey,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => CalendarMonthView(
                          month: DateTime(currentMonth.year, currentMonth.month + i, 1),
                          eventsByDay: byDay,
                          onDayTap: _showDaySheet,
                        ),
                        childCount: _monthsForward + 1,
                      ),
                    ),
                    // Keep the last month scrollable above the glass bar.
                    SliverPadding(
                      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDaySheet(DateTime day, List<CalendarEntry> events) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  DateFormat('EEEE, MMMM d').format(day),
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final entry = events[i];
                    final accent = Theme.of(context).colorScheme.primary;
                    switch (entry.kind) {
                      case CalendarKind.league:
                        return ListTile(
                          leading: Icon(Icons.sports_soccer, color: accent),
                          title: Text(entry.displayTitle),
                          subtitle: Text('Match day · Season ${entry.season}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) {
                              return LeagueDetailPage(
                                  sport: entry.sport ?? 'Futsal',
                                  season: entry.season ?? '');
                            }));
                          },
                        );
                      case CalendarKind.tournament:
                        return ListTile(
                          leading: Icon(Icons.emoji_events, color: accent),
                          title: Text(entry.displayTitle),
                          subtitle: const Text('Tournament match day'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) {
                              return TournamentDetailPage(
                                  tournamentId: entry.tournamentId ?? '',
                                  tournamentName: entry.displayTitle);
                            }));
                          },
                        );
                      case CalendarKind.event:
                        final event = entry.event!;
                        return ListTile(
                          leading: event.imageSrc == null
                              ? Icon(Icons.event, color: accent)
                              : SizedBox(width: 48, height: 48,
                                  child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: event.imageSrc!)),
                          title: Text(event.title ?? ''),
                          subtitle: Text('${entry.category} · ${event.startTime} - ${event.endTime}\n${event.location}'),
                          isThreeLine: true,
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) {
                              return entry.v2Id != null
                                  ? EventPage(v2Id: entry.v2Id)
                                  : EventPage(index: entry.legacyIndex);
                            }));
                          },
                        );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Horizontal category filter row. "All" clears the selection; category
/// chips toggle independently (multi-select).
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onChanged});

  final Set<String> selected;
  /// Called with a category to toggle, or null for "All".
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: const Text('All'),
              selected: selected.isEmpty,
              onSelected: (_) => onChanged(null),
              selectedColor: scheme.primary,
              labelStyle: TextStyle(
                  color: selected.isEmpty ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: FontWeight.bold),
              showCheckmark: false,
            ),
          ),
          for (final category in kEventCategories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(category),
                selected: selected.contains(category),
                onSelected: (_) => onChanged(category),
                selectedColor: scheme.primary,
                labelStyle: TextStyle(
                    color: selected.contains(category)
                        ? scheme.onPrimary
                        : scheme.onSurface,
                    fontWeight: FontWeight.bold),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

class CalendarMonthView extends StatelessWidget {
  const CalendarMonthView({
    super.key,
    required this.month,
    required this.eventsByDay,
    required this.onDayTap,
  });

  /// First day of the month shown.
  final DateTime month;
  final Map<DateTime, List<CalendarEntry>> eventsByDay;
  final void Function(DateTime day, List<CalendarEntry> events) onDayTap;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Sunday-first grid: DateTime.weekday is Mon=1..Sun=7.
    final leadingBlanks = month.weekday % 7;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      cells.add(Expanded(
        child: _DayCell(
          day: day,
          isToday: day == today,
          events: eventsByDay[day] ?? const [],
          onDayTap: onDayTap,
        ),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox()));
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(Row(children: cells.sublist(i, i + 7)));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              DateFormat('MMMM yyyy').format(month),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: month.year == today.year && month.month == today.month
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.events,
    required this.onDayTap,
  });

  final DateTime day;
  final bool isToday;
  final List<CalendarEntry> events;
  final void Function(DateTime day, List<CalendarEntry> events) onDayTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasEvents = events.isNotEmpty;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: hasEvents ? () => onDayTap(day, events) : null,
      child: SizedBox(
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isToday || hasEvents ? FontWeight.bold : FontWeight.normal,
                  color: isToday ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
            SizedBox(
              height: 6,
              child: hasEvents
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Fully-past events grey out so people can spot
                        // "there was something here" without mistaking it
                        // for an upcoming event.
                        for (var i = 0; i < (events.length > 3 ? 3 : events.length); i++)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: events[i].isPastOn(DateTime.now())
                                  ? scheme.onSurface.withValues(alpha: 0.35)
                                  : (isToday ? scheme.onSurface : scheme.primary),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

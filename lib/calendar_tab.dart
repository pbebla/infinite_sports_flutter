import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/event.dart';
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
  Future<Map<DateTime, List<MapEntry<int, Event>>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scroll offset 0 is the top of the current month (the center sliver),
  /// so "Today" is a plain glide back to origin. Also re-checks for new
  /// events while we're at it.
  void _jumpToToday() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
    setState(() { _future = _load(); });
  }

  Future<Map<DateTime, List<MapEntry<int, Event>>>> _load() async {
    try {
      return eventsByDay(await getEvents());
    } catch (_) {
      // Offline or Events unavailable: still show the calendar, just bare.
      return {};
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
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final byDay = snapshot.data ?? const <DateTime, List<MapEntry<int, Event>>>{};
          final now = DateTime.now();
          final currentMonth = DateTime(now.year, now.month, 1);
          return Column(
            children: [
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

  void _showDaySheet(DateTime day, List<MapEntry<int, Event>> events) {
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
                    final event = events[i].value;
                    return ListTile(
                      leading: event.imageSrc == null
                          ? Icon(Icons.event, color: Theme.of(context).colorScheme.primary)
                          : SizedBox(width: 48, height: 48,
                              child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: event.imageSrc!)),
                      title: Text(event.title ?? ''),
                      subtitle: Text('${event.startTime} - ${event.endTime}\n${event.location}'),
                      isThreeLine: true,
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) {
                          return EventPage(index: events[i].key);
                        }));
                      },
                    );
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
  final Map<DateTime, List<MapEntry<int, Event>>> eventsByDay;
  final void Function(DateTime day, List<MapEntry<int, Event>> events) onDayTap;

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
  final List<MapEntry<int, Event>> events;
  final void Function(DateTime day, List<MapEntry<int, Event>> events) onDayTap;

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
                        for (var i = 0; i < (events.length > 3 ? 3 : events.length); i++)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: isToday ? scheme.onSurface : scheme.primary,
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

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/event.dart';

/// Temporary Calendar tab: a simple upcoming-events list backed by the
/// existing Events node. Swapped wholesale for the real calendar in the next
/// piece of the epic (see docs/superpowers/specs/2026-07-13-bottom-nav-glass-design.md).
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  Future<List<MapEntry<int, Event>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MapEntry<int, Event>>> _load() async {
    final events = await getEvents();
    return upcomingEvents(events, DateTime.now());
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
          IconButton(
            onPressed: () => setState(() { _future = _load(); }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final upcoming = snapshot.data ?? const <MapEntry<int, Event>>[];
          if (upcoming.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_month_outlined, size: 56,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  const Text('No upcoming events — stay tuned!'),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: upcoming.length,
            itemBuilder: (context, i) {
              final event = upcoming[i].value;
              return ListTile(
                leading: event.imageSrc == null
                    ? const Icon(Icons.event)
                    : SizedBox(width: 48, height: 48,
                        child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: event.imageSrc!)),
                title: Text(event.title ?? ''),
                subtitle: Text('on ${event.eventDate}\nat ${event.location}\n${event.startTime} - ${event.endTime}'),
                isThreeLine: true,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) {
                    return EventPage(index: upcoming[i].key);
                  }));
                },
              );
            },
          );
        },
      ),
    );
  }
}

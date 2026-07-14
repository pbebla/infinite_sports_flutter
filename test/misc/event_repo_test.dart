import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/event_repo.dart';
import 'package:infinite_sports_flutter/model/event.dart';

Event _legacy(String title) {
  final e = Event();
  e.title = title;
  e.eventDateTime = DateTime(2026, 8, 1);
  return e;
}

Map<String, dynamic> _v2Json(String title, {int? legacyIndex}) => {
      'Title': title,
      'Category': 'Futsal',
      'StartDate': '08072026',
      'StartTime': '6:00PM',
      'EndTime': '9:00PM',
      'Location': 'Gym',
      if (legacyIndex != null) 'LegacyIndex': legacyIndex,
    };

void main() {
  test('v2 records parse with id, category and start date', () {
    final merged = mergeEvents({'abc': _v2Json('Futsal Night')}, []);
    final event = merged.single;
    expect(event.id, 'abc');
    expect(event.category, 'Futsal');
    expect(event.startDate, DateTime.utc(2026, 8, 7));
  });

  test('legacy mirror rows are hidden, real indexes preserved', () {
    final merged = mergeEvents(
      {'abc': _v2Json('New Event', legacyIndex: 1)},
      [_legacy('old 0'), _legacy('mirror of abc'), _legacy('old 2')],
    );
    expect(merged.map((e) => e.title).toList(),
        ['New Event', 'old 0', 'old 2']);
    // 'old 2' keeps its true Events-list index even though a row before it
    // was hidden — EventPage depends on it.
    expect(merged.last.legacyIndex, 2);
  });

  test('unparseable v2 records are skipped, not fatal', () {
    final merged = mergeEvents(
      {'bad': {'Title': 'no date'}, 'good': _v2Json('ok')},
      [],
    );
    expect(merged.single.title, 'ok');
  });
}

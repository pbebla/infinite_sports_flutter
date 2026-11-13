// Opus audit items 3 + 11 — the ONE per-gameweek multi-listener behind the
// chip history (`History/<gw>/<uid>`) and a player's week stats
// (`PlayerWeekStats/<gw>/<name>`), proved with fake per-week streams (no
// Firebase): exactly one listener per wanted week (never another), one
// emission once EVERY week has answered (no piecemeal pops), the session
// seed painting a revisit before any week answers, errors forwarded, and
// cancel releasing every listener.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/per_week_stream.dart';

void main() {
  late Map<int, StreamController<Object?>> weeks;
  late List<int> listened;
  late List<int> cancelled;
  late Map<String, Map<int, String>> cache;

  setUp(() {
    weeks = {};
    listened = [];
    cancelled = [];
    cache = {};
  });

  tearDown(() {
    for (final c in weeks.values) {
      c.close();
    }
  });

  Stream<Object?> watchWeek(int w) {
    final c = StreamController<Object?>(
      onListen: () => listened.add(w),
      onCancel: () => cancelled.add(w),
    );
    weeks[w] = c;
    return c.stream;
  }

  /// Node → value: a map node carries its 'v'; anything else is "no record".
  String? parse(Object? node) => node is Map ? node['v'] as String? : null;

  Stream<Map<int, String>> stream(List<int> wanted) => perWeekStream<String>(
        weeks: wanted,
        cache: cache,
        cacheKey: 'Fantasy/Futsal/15|me',
        watchWeek: watchWeek,
        parse: parse,
      );

  test('one listener per wanted week — and only those', () async {
    final sub = stream([1, 2, 3]).listen((_) {});
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(listened..sort(), [1, 2, 3]);
    expect(weeks.keys.toSet(), {1, 2, 3});
  });

  test('emits once EVERY week has answered, then on every change; weeks '
      'without a record are left out', () async {
    final seen = <Map<int, String>>[];
    final sub = stream([1, 2, 3]).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    weeks[1]!.add({'v': 'tripleCaptain'});
    weeks[2]!.add(null); // no record that week
    await pumpEventQueue();
    expect(seen, isEmpty); // week 3 hasn't answered: nothing pops

    weeks[3]!.add({'v': 'benchBoost'});
    await pumpEventQueue();
    expect(seen, [
      {1: 'tripleCaptain', 3: 'benchBoost'},
    ]);

    weeks[2]!.add({'v': 'wildcard'});
    await pumpEventQueue();
    expect(seen.last, {1: 'tripleCaptain', 2: 'wildcard', 3: 'benchBoost'});
  });

  test('a revisit paints from the session seed before any week answers '
      '(filtered to the wanted weeks)', () async {
    final first = stream([1, 2]).listen((_) {});
    await pumpEventQueue();
    weeks[1]!.add({'v': 'tripleCaptain'});
    weeks[2]!.add({'v': 'freeHit'});
    await pumpEventQueue();
    await first.cancel();
    expect(cache['Fantasy/Futsal/15|me'], {1: 'tripleCaptain', 2: 'freeHit'});

    final seen = <Map<int, String>>[];
    final revisit = stream([1]).listen(seen.add);
    addTearDown(revisit.cancel);
    await pumpEventQueue();
    // Nothing answered on this visit yet — the seed is already there.
    expect(seen, [
      {1: 'tripleCaptain'},
    ]);
  });

  test('no weeks: a single empty map, no listener at all', () async {
    expect(await stream(const []).first, isEmpty);
    expect(listened, isEmpty);
  });

  test('errors are forwarded (the caller logs them) — including a week feed '
      'that cannot even be created', () async {
    final errors = <Object>[];
    final sub = stream([1]).listen((_) {}, onError: errors.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    weeks[1]!.addError(StateError('denied'));
    await pumpEventQueue();
    expect(errors.single, isA<StateError>());

    final noApp = perWeekStream<String>(
      weeks: const [1],
      cache: cache,
      cacheKey: 'k',
      watchWeek: (_) => throw StateError('no app'),
      parse: parse,
    ).listen((_) {}, onError: errors.add);
    addTearDown(noApp.cancel);
    await pumpEventQueue();
    expect(errors.last.toString(), contains('no app'));
  });

  test('cancel releases every week listener', () async {
    final sub = stream([1, 2]).listen((_) {});
    await pumpEventQueue();
    await sub.cancel();
    expect(cancelled..sort(), [1, 2]);
  });
}

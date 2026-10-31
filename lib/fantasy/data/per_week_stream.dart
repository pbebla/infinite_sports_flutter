// ONE per-gameweek multi-listener (Opus audit items 3 + 11) behind
// FantasyService.watchChipHistoryFor (`History/<gw>/<uid>`) and
// watchPlayerWeekStatsFor (`PlayerWeekStats/<gw>/<name>`) — they were two
// hand-rolled copies, and only one of them had a session seed.
//
// One onValue listener per wanted gameweek on that week's small node (never
// a season's whole node for everyone); the map is emitted only once EVERY
// week has answered (no piecemeal "1 left" → "Used" pops), then on every
// change. A session cache seeds the first frame, so a revisit paints before
// any week answers. Which weeks to listen to is the caller's business
// (FantasyScheduleFeed passes only weeks up to the current gameweek — a
// week that hasn't locked can't have a record yet).
//
// Pure Dart (the RTDB read arrives through [watchWeek]), so the listener
// count, the seed and the all-answered rule are unit-tested in
// test/fantasy/per_week_stream_test.dart.

import 'dart:async';

/// One listener per week in [weeks] (via [watchWeek]: that week's raw node
/// values), each parsed with [parse] — null = no record that week (left out
/// of the map). Emits once every week has answered, then on every change;
/// each full emission is written to [cache] under [cacheKey], and a cached
/// map (filtered to [weeks]) is emitted first on listen. Errors — including
/// a [watchWeek] that throws (no Firebase app) — are forwarded as stream
/// errors for the caller to log. Empty [weeks]: a single empty map.
Stream<Map<int, T>> perWeekStream<T extends Object>({
  required List<int> weeks,
  required Map<String, Map<int, T>> cache,
  required String cacheKey,
  required Stream<Object?> Function(int week) watchWeek,
  required T? Function(Object? node) parse,
}) {
  final wanted = weeks.toSet();
  if (wanted.isEmpty) return Stream<Map<int, T>>.value(const {});
  final subs = <StreamSubscription<Object?>>[];
  final latest = <int, T?>{};
  late final StreamController<Map<int, T>> controller;
  controller = StreamController<Map<int, T>>(
    onListen: () {
      final seed = cache[cacheKey];
      if (seed != null) {
        controller.add({
          for (final e in seed.entries)
            if (wanted.contains(e.key)) e.key: e.value,
        });
      }
      for (final w in wanted) {
        try {
          subs.add(watchWeek(w).listen((node) {
            latest[w] = parse(node);
            if (latest.length < wanted.length) return; // not all answered
            final map = <int, T>{
              for (final e in latest.entries)
                if (e.value != null) e.key: e.value as T,
            };
            cache[cacheKey] = map;
            controller.add(map);
          }, onError: controller.addError));
        } catch (e, s) {
          controller.addError(e, s);
          return;
        }
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}

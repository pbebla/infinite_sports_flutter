// Fix round 1, I2: the league's season-over flag is a three-way answer —
// running / over / unknown. A failed read is not a fact: with no real answer
// yet it is UNKNOWN (never "running"), and the feed re-subscribes after a
// stream error on a bounded back-off so one blip does not pin the answer for
// the session (an RTDB onValue stream ends after an error).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';

void main() {
  setUp(FantasySeasonFinishedFeed.clearSessionCache);

  FantasySeasonFinishedFeed feedOf(Stream<bool> s, List<int> changes) =>
      FantasySeasonFinishedFeed(
        sport: 'Futsal',
        season: '15',
        owner: 'test',
        onChanged: () => changes.add(1),
        finishedStates: s,
      );

  testWidgets('a read error before any answer = ready but UNKNOWN; the feed '
      're-subscribes and the next answer lands', (tester) async {
    final flag = StreamController<bool>.broadcast(sync: true);
    addTearDown(flag.close);
    final changes = <int>[];
    final feed = feedOf(flag.stream, changes)..start();
    addTearDown(feed.dispose);
    expect(feed.ready, isFalse);

    flag.addError(StateError('permission-denied'));
    expect(feed.ready, isTrue);
    expect(feed.phase, FantasySeasonPhase.unknown);
    expect(feed.finished, isFalse);
    expect(flag.hasListener, isFalse, reason: 'the errored stream is dropped');

    // Bounded back-off, then a fresh subscription.
    await tester.pump(const Duration(seconds: 3));
    expect(flag.hasListener, isTrue);
    flag.add(true);
    expect(feed.phase, FantasySeasonPhase.over);
    expect(feed.finished, isTrue);
  });

  testWidgets('an error AFTER a real answer keeps that answer', (tester) async {
    final flag = StreamController<bool>.broadcast(sync: true);
    addTearDown(flag.close);
    final feed = feedOf(flag.stream, [])..start();
    addTearDown(feed.dispose);
    flag.add(false);
    expect(feed.phase, FantasySeasonPhase.running);
    flag.addError(StateError('blip'));
    expect(feed.phase, FantasySeasonPhase.running);
    await tester.pump(const Duration(seconds: 3));
    expect(flag.hasListener, isTrue);
  });

  testWidgets('retries are bounded, and a failure never poisons the session '
      'cache (the next open asks again)', (tester) async {
    final flag = StreamController<bool>.broadcast(sync: true);
    addTearDown(flag.close);
    final feed = feedOf(flag.stream, [])..start();
    for (var i = 0; i < 20; i++) {
      flag.addError(StateError('down'));
      await tester.pump(const Duration(minutes: 5));
    }
    expect(feed.phase, FantasySeasonPhase.unknown);
    expect(flag.hasListener, isFalse, reason: 'gave up after the last retry');
    feed.dispose();

    // A new screen: no seeded (wrong) answer, a fresh read.
    final again = feedOf(flag.stream, [])..start();
    addTearDown(again.dispose);
    expect(again.ready, isFalse);
    flag.add(false);
    expect(again.phase, FantasySeasonPhase.running);
  });

  testWidgets('dispose cancels a pending retry', (tester) async {
    final flag = StreamController<bool>.broadcast(sync: true);
    addTearDown(flag.close);
    final feed = feedOf(flag.stream, [])..start();
    flag.addError(StateError('x'));
    feed.dispose();
    await tester.pump(const Duration(minutes: 5));
    expect(flag.hasListener, isFalse);
  });
}

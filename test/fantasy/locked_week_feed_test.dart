// Live everywhere, Task 5 — the locked My Team's feed
// (lib/fantasy/hub/locked_week_feed.dart): the five small streams the locked
// week needs (the live feed, the manager's own Live/Squads/<uid>, his
// PublishedPicks/<gw>/<uid> — the squad that was LOCKED — his
// History/<gw>/<uid> and his Leaderboards/Overall/<uid>), subscribed ONLY
// while a week is locked, gating the hub's reveal until all five have
// answered (an error counts as an answer, "no data") — but never longer than
// the global 2 s live bound — and saying whether everything was really read
// (`complete`), so the strip never claims "waiting for kickoff" on a load
// that failed.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/locked_week_feed.dart';

class _Probe<T> {
  _Probe() {
    controller = StreamController<T>.broadcast(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
  }
  late final StreamController<T> controller;
  int listens = 0;
  int cancels = 0;
  bool get listening => listens > cancels;
}

void main() {
  late _Probe<FantasyLiveState> live;
  late _Probe<LiveSquad?> squad;
  late _Probe<OverallStanding?> overall;
  late Map<int, _Probe<HistoryWeek?>> history;
  late Map<int, _Probe<FantasySquad?>> published;
  late List<int> historyRequests;
  late List<int> publishedRequests;
  late int changes;
  late String? uid;

  setUp(() {
    live = _Probe();
    squad = _Probe();
    overall = _Probe();
    history = {};
    published = {};
    historyRequests = [];
    publishedRequests = [];
    changes = 0;
    uid = 'me';
  });

  tearDown(() {
    live.controller.close();
    squad.controller.close();
    overall.controller.close();
    for (final p in history.values) {
      p.controller.close();
    }
    for (final p in published.values) {
      p.controller.close();
    }
  });

  FantasyLockedWeekFeed makeFeed() => FantasyLockedWeekFeed(
        sport: 'Futsal',
        season: '15',
        uid: () => uid,
        onChanged: () => changes++,
        liveStates: live.controller.stream,
        liveSquadStates: squad.controller.stream,
        historyWeekFor: (week) {
          historyRequests.add(week);
          return (history[week] ??= _Probe()).controller.stream;
        },
        publishedPicksFor: (week) {
          publishedRequests.add(week);
          return (published[week] ??= _Probe()).controller.stream;
        },
        overallStates: overall.controller.stream,
      );

  bool anyListening() =>
      live.listening ||
      squad.listening ||
      overall.listening ||
      history.values.any((p) => p.listening) ||
      published.values.any((p) => p.listening);

  const meta = LiveMeta(gw: 3, state: LiveState.live);

  const lockedSquad = FantasySquad(
    picks: [
      SquadPick(
          playerId: 'Ava', position: FantasyPosition.att, priceTenths: 50),
    ],
    captainId: 'Ava',
    viceId: 'Ava',
  );

  Future<void> answerAll(WidgetTester tester, int week) async {
    live.controller.add(const FantasyLiveState(meta: meta));
    squad.controller
        .add(const LiveSquad(totalTenths: 340, week: 34, slots: []));
    history[week]!.controller.add(null);
    published[week]!.controller.add(lockedSquad);
    overall.controller.add(const OverallStanding(rank: 5));
    await tester.pump();
  }

  testWidgets('no locked week: nothing is subscribed and nothing gates',
      (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    expect(feed.week, isNull);
    expect(feed.ready, isTrue);
    expect(live.listens + squad.listens + overall.listens, 0);
    expect(historyRequests, isEmpty);
    expect(publishedRequests, isEmpty);
  });

  testWidgets(
      'a locked week subscribes to the five streams and gates until '
      'every one has answered', (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    expect(feed.week, 3);
    expect(historyRequests, [3]);
    expect(publishedRequests, [3]);
    expect(live.listening && squad.listening && overall.listening, isTrue);
    expect(feed.ready, isFalse);

    live.controller.add(const FantasyLiveState(meta: meta));
    squad.controller.add(null);
    history[3]!.controller.add(null);
    overall.controller.add(null);
    await tester.pump();
    expect(feed.ready, isFalse, reason: 'PublishedPicks has not answered');

    published[3]!.controller.add(null);
    await tester.pump();
    expect(feed.ready, isTrue);
  });

  testWidgets(
      'the sources carry what each stream said, and re-emit on every '
      'change', (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    await answerAll(tester, 3);

    final s = feed.sources;
    expect(s.live.meta?.gw, 3);
    expect(s.liveSquad?.week, 34);
    expect(s.history, isNull);
    expect(identical(s.published, lockedSquad), isTrue);
    expect(s.overall?.rank, 5);
    expect(s.complete, isTrue);

    final before = changes;
    squad.controller
        .add(const LiveSquad(totalTenths: 410, week: 41, slots: []));
    await tester.pump();
    expect(feed.sources.liveSquad?.week, 41);
    expect(changes, greaterThan(before));
  });

  testWidgets(
      'a stream that errors counts as answered (no data) — the hub '
      'is never held by a failing feed — but the load is NOT complete',
      (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    live.controller.add(const FantasyLiveState(meta: meta));
    squad.controller.addError(StateError('denied'));
    history[3]!.controller.addError(StateError('denied'));
    published[3]!.controller.addError(StateError('denied'));
    overall.controller.addError(StateError('denied'));
    await tester.pump();
    expect(feed.ready, isTrue);
    expect(feed.sources.liveSquad, isNull);
    expect(feed.sources.overall, isNull);
    expect(feed.sources.published, isNull);
    expect(feed.sources.complete, isFalse,
        reason: 'the strip must not read a failed load as "no data yet"');
  });

  testWidgets(
      'one failed stream makes it incomplete until that stream delivers '
      'again', (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    live.controller.add(const FantasyLiveState(meta: meta));
    squad.controller.add(null);
    history[3]!.controller.addError(StateError('denied'));
    published[3]!.controller.add(null);
    overall.controller.add(null);
    await tester.pump();
    expect(feed.ready, isTrue);
    expect(feed.sources.complete, isFalse);

    history[3]!.controller.add(null);
    await tester.pump();
    expect(feed.sources.complete, isTrue);
  });

  testWidgets('a stream that cannot even be created is an answer too',
      (tester) async {
    final feed = FantasyLockedWeekFeed(
      sport: 'Futsal',
      season: '15',
      uid: () => uid,
      onChanged: () => changes++,
      liveStates: live.controller.stream,
      liveSquadStates: squad.controller.stream,
      historyWeekFor: (_) => throw StateError('no Firebase app'),
      publishedPicksFor: (week) =>
          (published[week] ??= _Probe()).controller.stream,
      overallStates: overall.controller.stream,
    );
    addTearDown(feed.dispose);
    feed.setWeek(3);
    live.controller.add(const FantasyLiveState(meta: meta));
    squad.controller.add(null);
    published[3]!.controller.add(null);
    overall.controller.add(null);
    await tester.pump();
    expect(feed.ready, isTrue);
    expect(feed.sources.complete, isFalse);
  });

  testWidgets(
      'the gate is bounded at 2 s: a silent stream never holds the '
      'reveal longer (the load is then incomplete) — and its late value '
      'still lands', (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    squad.controller.add(null);
    history[3]!.controller.add(null);
    published[3]!.controller.add(null);
    overall.controller.add(null);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(feed.ready, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    expect(feed.ready, isTrue);
    expect(feed.sources.live.meta, isNull, reason: 'live treated as none');
    expect(feed.sources.complete, isFalse);

    live.controller.add(const FantasyLiveState(meta: meta));
    await tester.pump();
    expect(feed.sources.live.meta?.gw, 3);
    expect(feed.sources.complete, isTrue);
  });

  testWidgets('live answering in time cancels the bound (no stray timer)',
      (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    await answerAll(tester, 3);
    expect(feed.ready, isTrue);
    // testWidgets itself fails on a timer left pending.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the same week again is a no-op (no resubscribe)',
      (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    feed.setWeek(3);
    await tester.pump();
    expect(live.listens, 1);
    expect(historyRequests, [3]);
    expect(publishedRequests, [3]);
    feed.dispose(); // the 2 s bound is still pending (a test must not leak it)
  });

  testWidgets(
      'a new week drops the old week\'s data at once and listens to '
      'the new week\'s History and PublishedPicks', (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    await answerAll(tester, 3);
    expect(feed.ready, isTrue);

    feed.setWeek(4);
    await tester.pump();
    expect(historyRequests, [3, 4]);
    expect(publishedRequests, [3, 4]);
    expect(history[3]!.listening, isFalse);
    expect(published[3]!.listening, isFalse);
    expect(feed.sources.liveSquad, isNull, reason: 'never last week\'s squad');
    expect(feed.sources.published, isNull,
        reason: 'never last week\'s locked squad');
    expect(feed.ready, isFalse);
    feed.dispose(); // the new week's 2 s bound is still pending
  });

  testWidgets(
      'no week again (editing reopened): everything is cancelled and '
      'cleared, nothing gates', (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    await answerAll(tester, 3);
    feed.setWeek(null);
    await tester.pump();
    expect(feed.week, isNull);
    expect(feed.ready, isTrue);
    expect(anyListening(), isFalse);
    expect(feed.sources.liveSquad, isNull);
    expect(feed.sources.published, isNull);
  });

  testWidgets(
      'signed out: nothing to subscribe to, nothing to wait for — and '
      'nothing was read, so the load is not complete', (tester) async {
    uid = null;
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3);
    await tester.pump();
    expect(feed.ready, isTrue);
    expect(live.listens + squad.listens + overall.listens, 0);
    expect(historyRequests, isEmpty);
    expect(publishedRequests, isEmpty);
    expect(feed.sources.complete, isFalse);
  });

  testWidgets('notify: false never calls onChanged (initState)',
      (tester) async {
    final feed = makeFeed();
    addTearDown(feed.dispose);
    feed.setWeek(3, notify: false);
    expect(changes, 0);
    feed.setWeek(null);
    expect(changes, 1);
  });

  testWidgets(
      'dispose cancels every stream and the bound; late events are '
      'ignored', (tester) async {
    final feed = makeFeed();
    feed.setWeek(3);
    await tester.pump();
    feed.dispose();
    expect(anyListening(), isFalse);
    final before = changes;
    squad.controller.add(null);
    await tester.pump(const Duration(seconds: 3));
    expect(changes, before);
    feed.setWeek(4); // a no-op once disposed
    expect(historyRequests, [3]);
    expect(publishedRequests, [3]);
  });
}

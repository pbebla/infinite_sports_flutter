import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/misc/utility.dart'
    show UserTokenNode, uploadTokenForUid;
import 'package:shared_preferences/shared_preferences.dart';

class FakeMessaging implements TopicMessaging {
  final List<String> subscribed = [];
  final List<String> unsubscribed = [];
  @override
  Future<void> subscribeToTopic(String topic) async => subscribed.add(topic);
  @override
  Future<void> unsubscribeFromTopic(String topic) async =>
      unsubscribed.add(topic);
}

class _RecordingTokenNode implements UserTokenNode {
  final List<String> calls = [];
  @override
  Future<void> write(String uid, String token) async => calls.add('write');
  @override
  Future<bool> removeIf(
      String uid, bool Function(Object? current) shouldRemove) async {
    calls.add('removeIf');
    return false;
  }
}

void main() {
  late FakeMessaging messaging;
  late FollowStore store;
  late List<String> tokenCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messaging = FakeMessaging();
    tokenCalls = [];
    store = FollowStore(
      messaging: messaging,
      detachToken: () async => tokenCalls.add('detach'),
      attachToken: () async => tokenCalls.add('attach'),
    );
  });

  test('starts empty with master enabled', () async {
    expect(await store.follows(), isEmpty);
    expect(await store.masterEnabled(), isTrue);
  });

  test('follow stores the channel and subscribes', () async {
    await store.follow(const FollowedChannel(
        topic: 'tournament_T1', label: 'Test Tournament 2026', kind: 'tournament'));
    expect(await store.isFollowed('tournament_T1'), isTrue);
    expect(messaging.subscribed, ['tournament_T1']);
    final follows = await store.follows();
    expect(follows.single.label, 'Test Tournament 2026');
    expect(follows.single.kind, 'tournament');
  });

  test('unfollow removes and unsubscribes', () async {
    await store.follow(const FollowedChannel(
        topic: 'tournament_T1_team_a', label: 'Eagles', kind: 'team'));
    await store.unfollow('tournament_T1_team_a');
    expect(await store.isFollowed('tournament_T1_team_a'), isFalse);
    expect(messaging.unsubscribed, ['tournament_T1_team_a']);
  });

  test('master off unsubscribes all but keeps the list', () async {
    await store.follow(const FollowedChannel(
        topic: 't1', label: 'A', kind: 'tournament'));
    await store.follow(const FollowedChannel(topic: 't2', label: 'B', kind: 'team'));
    await store.setMasterEnabled(false);
    expect(messaging.unsubscribed, containsAll(['t1', 't2']));
    expect((await store.follows()).length, 2); // list preserved
    expect(await store.masterEnabled(), isFalse);
  });

  test('master off also leaves the everyone topic and detaches the token',
      () async {
    await store.setMasterEnabled(false);
    expect(messaging.unsubscribed, contains(allUsersTopic));
    expect(tokenCalls, ['detach']);
  });

  test('master back on rejoins the everyone topic and uploads the token',
      () async {
    await store.setMasterEnabled(false);
    tokenCalls.clear();
    await store.setMasterEnabled(true);
    expect(messaging.subscribed, contains(allUsersTopic));
    expect(tokenCalls, ['attach']);
  });

  test('master off is saved BEFORE the token detach (no re-upload race)',
      () async {
    bool? masterDuringDetach;
    final s = FollowStore(
      messaging: messaging,
      detachToken: () async => masterDuringDetach = await store.masterEnabled(),
      attachToken: () async {},
    );
    await s.setMasterEnabled(false);
    expect(masterDuringDetach, isFalse);
  });

  test('a failing token step never surfaces as an error', () async {
    final s = FollowStore(
      messaging: messaging,
      detachToken: () async => throw Exception('offline'),
      attachToken: () async => throw Exception('offline'),
    );
    await s.setMasterEnabled(false);
    await s.setMasterEnabled(true);
    expect(await s.masterEnabled(), isTrue);
  });

  test('a never-completing token write (offline) cannot freeze the switch',
      () async {
    final s = FollowStore(
      messaging: messaging,
      detachToken: () => Completer<void>().future,
      attachToken: () => Completer<void>().future,
    );
    final sw = Stopwatch()..start();
    await s.setMasterEnabled(true);
    await s.setMasterEnabled(false);
    expect(sw.elapsed, lessThan(const Duration(seconds: 6)));
    expect(await s.masterEnabled(), isFalse);
  });

  test(
      'app launch with the switch OFF: no everyone-topic join and no token '
      'write', () async {
    await store.setMasterEnabled(false);
    messaging.subscribed.clear();
    // The two launch-time steps main.dart runs.
    await store.joinEveryoneTopicIfEnabled();
    final node = _RecordingTokenNode();
    await uploadTokenForUid('uid_alice', 'tok_phone', node: node);
    expect(messaging.subscribed, isEmpty);
    expect(node.calls, isEmpty);
  });

  test('app launch with the switch ON: joins the everyone topic', () async {
    var custom = 0;
    await store.joinEveryoneTopicIfEnabled();
    await store.joinEveryoneTopicIfEnabled(subscribe: () async => custom++);
    expect(messaging.subscribed, [allUsersTopic]);
    expect(custom, 1);
  });

  test('signed out / no Firebase: default token steps do not crash',
      () async {
    final s = FollowStore(messaging: messaging);
    await s.setMasterEnabled(false);
    await s.setMasterEnabled(true);
    expect(await s.masterEnabled(), isTrue);
  });

  test('master back on resubscribes the whole list', () async {
    await store.follow(const FollowedChannel(
        topic: 't1', label: 'A', kind: 'tournament'));
    await store.setMasterEnabled(false);
    messaging.subscribed.clear();
    await store.setMasterEnabled(true);
    expect(messaging.subscribed, containsAll(['t1']));
    expect(messaging.subscribed.where((t) => t != allUsersTopic), ['t1']);
  });

  test('following while master is off re-enables master', () async {
    await store.setMasterEnabled(false);
    await store.follow(const FollowedChannel(
        topic: 't9', label: 'C', kind: 'team'));
    expect(await store.masterEnabled(), isTrue);
    expect(messaging.subscribed, contains('t9'));
  });

  test('follows survive a new store instance (persisted)', () async {
    await store.follow(const FollowedChannel(
        topic: 't1', label: 'A', kind: 'tournament'));
    final fresh = FollowStore(messaging: messaging);
    expect(await fresh.isFollowed('t1'), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';
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

void main() {
  late FakeMessaging messaging;
  late FollowStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messaging = FakeMessaging();
    store = FollowStore(messaging: messaging);
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

  test('master back on resubscribes the whole list', () async {
    await store.follow(const FollowedChannel(
        topic: 't1', label: 'A', kind: 'tournament'));
    await store.setMasterEnabled(false);
    messaging.subscribed.clear();
    await store.setMasterEnabled(true);
    expect(messaging.subscribed, ['t1']);
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

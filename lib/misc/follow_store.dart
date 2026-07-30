import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin seam over FCM topic calls so FollowStore is unit-testable.
abstract class TopicMessaging {
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
}

class FirebaseTopicMessaging implements TopicMessaging {
  @override
  Future<void> subscribeToTopic(String topic) =>
      FirebaseMessaging.instance.subscribeToTopic(topic);
  @override
  Future<void> unsubscribeFromTopic(String topic) =>
      FirebaseMessaging.instance.unsubscribeFromTopic(topic);
}

class FollowedChannel {
  final String topic;
  final String label;
  final String kind; // 'tournament' | 'team' | 'league'

  const FollowedChannel(
      {required this.topic, required this.label, required this.kind});

  Map<String, String> toJson() => {'topic': topic, 'label': label, 'kind': kind};

  factory FollowedChannel.fromJson(Map<String, dynamic> json) =>
      FollowedChannel(
        topic: json['topic']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'tournament',
      );
}

/// Device-local list of followed channels + the master notifications switch.
/// Master OFF unsubscribes every topic but keeps the stored list, so turning
/// it back ON restores all bells exactly as they were.
class FollowStore {
  static const _followsKey = 'followedChannels';
  static const _masterKey = 'notificationsMasterEnabled';

  final TopicMessaging _messaging;

  FollowStore({TopicMessaging? messaging})
      : _messaging = messaging ?? FirebaseTopicMessaging();

  Future<List<FollowedChannel>> follows() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_followsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => FollowedChannel.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.topic.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isFollowed(String topic) async =>
      (await follows()).any((c) => c.topic == topic);

  Future<bool> masterEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_masterKey) ?? true;
  }

  /// FCM topic calls are best-effort: the persisted list is the source of
  /// truth, and subscriptions are re-applied via the master switch or on the
  /// next follow, so a flaky network must never surface as a UI error.
  Future<void> _tryMessaging(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // Swallow: intent is persisted; FCM will catch up on a later call.
    }
  }

  Future<void> follow(FollowedChannel channel) async {
    final current = await follows();
    if (!current.any((c) => c.topic == channel.topic)) {
      current.add(channel);
      await _save(current);
    }
    if (!await masterEnabled()) {
      // A fresh follow means the fan wants alerts again.
      await setMasterEnabled(true);
    } else {
      await _tryMessaging(() => _messaging.subscribeToTopic(channel.topic));
    }
  }

  Future<void> unfollow(String topic) async {
    final current = await follows();
    current.removeWhere((c) => c.topic == topic);
    await _save(current);
    await _tryMessaging(() => _messaging.unsubscribeFromTopic(topic));
  }

  Future<void> setMasterEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_masterKey, enabled);
    final current = await follows();
    for (final c in current) {
      if (enabled) {
        await _tryMessaging(() => _messaging.subscribeToTopic(c.topic));
      } else {
        await _tryMessaging(() => _messaging.unsubscribeFromTopic(c.topic));
      }
    }
  }

  Future<void> _save(List<FollowedChannel> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _followsKey, jsonEncode(list.map((c) => c.toJson()).toList()));
  }
}

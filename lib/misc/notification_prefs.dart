import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';

/// Notification categories a user can favorite. Mirrors the event categories
/// (kEventCategories) so a favorite maps cleanly to events and campaigns.
const List<String> kNotificationCategories = [
  'Futsal',
  'Basketball',
  'Flag Football',
  'Soccer',
  'Volleyball',
  'Pickleball',
  'Tournaments',
  'Community',
];

/// Bridges a user's category preferences to BOTH:
/// - the server (`Users/<uid>/FavoriteSports/<Category>=true`) so the campaign
///   sender can target "everyone who likes Futsal", and
/// - device FCM topics (`sport_<Category>`) so those campaigns actually arrive.
/// Device topic state is held in [FollowStore]; the DB write only happens when
/// a uid is known (signed in).
class NotificationPrefs {
  final FollowStore _store;
  NotificationPrefs({FollowStore? store}) : _store = store ?? FollowStore();

  /// Turn a category on/off. Subscribes/unsubscribes the topic and (when
  /// [uid] is provided) records it server-side for campaign targeting.
  Future<void> setCategory(String category, bool on, {String? uid}) async {
    final topic = sportTopic(category);
    if (on) {
      await _store.follow(
          FollowedChannel(topic: topic, label: category, kind: 'sport'));
    } else {
      await _store.unfollow(topic);
    }
    if (uid != null) {
      final ref =
          FirebaseDatabase.instance.ref('Users/$uid/FavoriteSports/$category');
      await (on ? ref.set(true) : ref.remove());
    }
  }

  /// Applies a full set of chosen categories at once (onboarding). Every
  /// category in [universe] (the live category list) not in [chosen] is turned
  /// off; defaults to the built-in list when no universe is given.
  Future<void> setFavorites(Set<String> chosen,
      {String? uid, List<String>? universe}) async {
    for (final category in (universe ?? kNotificationCategories)) {
      await setCategory(category, chosen.contains(category), uid: uid);
    }
  }

  /// Whether the device is currently subscribed to a category's topic.
  Future<bool> isCategoryOn(String category) =>
      _store.isFollowed(sportTopic(category));

  /// The categories currently on, from device topic state.
  Future<Set<String>> currentCategories() async {
    final result = <String>{};
    for (final category in kNotificationCategories) {
      if (await isCategoryOn(category)) result.add(category);
    }
    return result;
  }

  /// Whether [uid] already answered the one-time favorites prompt (fresh
  /// reads, Task 3 — replaces the old one-shot `hasAnswered` +
  /// `serverFavorites` pair): true when `FavoriteSportsAnswered` is true or
  /// any `FavoriteSports` node exists (even empty = skipped) — trusted from
  /// ANY source, so a fan who answered is never asked again; false only when
  /// the server confirmed both are missing; null when that could not be
  /// confirmed (saved copy or failed read) — no prompt this launch, asked
  /// again next launch. Both reads run together, server-first.
  Future<bool?> favoritesAnswered(String uid) async {
    Future<FreshValue> read(String path) async {
      try {
        return await serverFirstValue(path);
      } catch (_) {
        return const FreshValue(null, fromServer: false);
      }
    }

    final reads = await Future.wait([
      read('Users/$uid/FavoriteSportsAnswered'),
      read('Users/$uid/FavoriteSports'),
    ]);
    final answered = reads[0];
    final favorites = reads[1];
    if (answered.value == true || favorites.value != null) return true;
    if (answered.fromServer && favorites.fromServer) return false;
    return null;
  }

  /// Marks onboarding answered even when the user picks nothing, so the
  /// one-time prompt won't reappear.
  Future<void> markAnswered(String uid) async {
    try {
      await FirebaseDatabase.instance
          .ref('Users/$uid/FavoriteSportsAnswered')
          .set(true);
    } catch (_) {}
  }

  /// Whether the device is subscribed to an event's reminder topic.
  Future<bool> isEventReminderOn(String eventId) =>
      _store.isFollowed(eventTopic(eventId));

  /// Turn an event's reminders on/off. Subscribes the topic and (when signed
  /// in) records the uid under the event so campaigns can target attendees.
  Future<void> setEventReminder(String eventId, bool on, {String? uid}) async {
    final topic = eventTopic(eventId);
    if (on) {
      await _store.follow(
          FollowedChannel(topic: topic, label: 'Event reminder', kind: 'event'));
    } else {
      await _store.unfollow(topic);
    }
    if (uid != null) {
      final ref =
          FirebaseDatabase.instance.ref('EventsV2/$eventId/Reminders/$uid');
      await (on ? ref.set(true) : ref.remove());
    }
  }

  /// A fan's write-in for a sport/category we don't offer yet ("Other" on the
  /// favorites picker). Lands in /CategorySuggestions for the owner to review
  /// in the manager's Categories screen and promote to a real category.
  Future<void> submitCategorySuggestion(String text, {String? uid}) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('CategorySuggestions').push().set({
        'Text': cleaned,
        'Uid': uid ?? '',
        'CreatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  /// Every install listens to the app-wide channel so campaigns to "Everyone"
  /// reach them. Safe to call on each launch.
  Future<void> subscribeAllUsers() async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(allUsersTopic);
    } catch (_) {}
  }
}

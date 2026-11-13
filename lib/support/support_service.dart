import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:infinite_sports_flutter/support/support_models.dart';

/// Thrown by [SupportService.createTicket] when the soft 6-tickets/hour gate
/// trips (spec decision #3). The message is user-facing — the form shows it
/// verbatim in a SnackBar.
class SupportRateLimitException implements Exception {
  final String message;
  const SupportRateLimitException(
      [this.message =
          "You've sent quite a few tickets in the last hour — give it a "
          'little time and try again.']);

  @override
  String toString() => message;
}

/// What [SupportService.createTicket] hands back: the reference number and
/// how many screenshots could NOT be attached (uploads are best-effort, but
/// a dropped screenshot is never silent — the success screen says so).
typedef SupportTicketResult = ({int num, int failedScreenshots});

/// Uploads [count] screenshots one by one through [upload] (index -> the
/// download URL), best-effort: a failed upload is skipped and counted, the
/// rest still go through.
Future<({List<String> urls, int failed})> uploadScreenshotsBestEffort(
    int count, Future<String> Function(int index) upload) async {
  final urls = <String>[];
  var failed = 0;
  for (var i = 0; i < count; i++) {
    try {
      urls.add(await upload(i));
    } catch (_) {
      failed++;
    }
  }
  return (urls: urls, failed: failed);
}

/// Ticket creation + live reads + replies for the player-facing support
/// system (zaya-support). Static-method service in the house style of
/// lib/misc/insider_service.dart — and like it, iOS-parity clean: `.once()`
/// / `onValue` streams only, never `.get()` (firebase-ios-sdk wrong-node
/// bug).
///
/// Spec: docs/superpowers/specs/2026-10-13-support-tickets-design.md
/// ("Data (RTDB)" + "Fan app" sections). The ticket node carries the first
/// message as `Message`; Thread/ starts empty and holds only replies.
class SupportService {
  static DatabaseReference get _root => FirebaseDatabase.instance.ref();

  /// Creates a ticket end-to-end and returns its reference number plus the
  /// count of screenshots that failed to upload:
  /// 1. soft rate-limit check (6/hour per account — throws
  ///    [SupportRateLimitException], never blocks on read errors),
  /// 2. transaction-increments `Support/Counter` → n,
  /// 3. uploads [screenshots] to Storage `support/<n>/img_<i>.jpg`
  ///    (individually best-effort — a failed upload is skipped and counted,
  ///    the ticket still goes through with the ones that made it),
  /// 4. writes `Support/Tickets/<n>` + `Support/UserTickets/<uid>/<n>` in a
  ///    single multi-path update, so the ticket and its index entry can
  ///    never exist without each other.
  static Future<SupportTicketResult> createTicket({
    required String uid,
    required String name,
    required String email,
    required String category,
    required String message,
    required String appVersion,
    required String platform,
    required String device,
    required String screen,
    List<File> screenshots = const [],
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final recent = recentTicketCount(await _myRecentCreatedAts(uid), nowMs);
    if (recent >= kSupportRateLimitPerHour) {
      throw const SupportRateLimitException();
    }

    final result =
        await _root.child('Support/Counter').runTransaction((current) {
      final value = current is num ? current.toInt() : 0;
      return Transaction.success(value + 1);
    });
    final n = result.snapshot.value is num
        ? (result.snapshot.value as num).toInt()
        : 0;
    if (!result.committed || n <= 0) {
      throw Exception('Could not reserve a ticket number.');
    }

    // Best-effort (spec: "skip failed uploads gracefully") — a broken
    // upload never sinks the ticket itself, but it is counted and reported.
    final uploads =
        await uploadScreenshotsBestEffort(screenshots.length, (i) async {
      final ref = FirebaseStorage.instance.ref('support/$n/img_$i.jpg');
      // The uid tag is what storage.rules checks: the path carries no
      // owner, so create requires it to match the uploader and get is
      // limited to that uploader (plus admins).
      await ref.putFile(
          screenshots[i],
          SettableMetadata(
              contentType: 'image/jpeg', customMetadata: {'uid': uid}));
      return ref.getDownloadURL();
    });
    final urls = uploads.urls;

    await _root.update({
      'Support/Tickets/$n': {
        'Num': n,
        'Uid': uid,
        'Name': name,
        'Email': email,
        'Category': category,
        'Message': message,
        'Status': 'open',
        'CreatedAt': ServerValue.timestamp,
        'UpdatedAt': ServerValue.timestamp,
        'AppVersion': appVersion,
        'Platform': platform,
        'Device': device,
        'Screen': screen,
        'Screenshots': urls,
      },
      'Support/UserTickets/$uid/$n': true,
    });
    return (num: n, failedScreenshots: uploads.failed);
  }

  /// Live ticket numbers for [uid], newest first — the My Tickets list spine.
  static Stream<List<int>> watchMyTicketNums(String uid) => _root
      .child('Support/UserTickets/$uid')
      .onValue
      .map((event) => ticketNumsFromIndex(event.snapshot.value));

  /// Live view of one ticket (null while absent/unreadable).
  static Stream<SupportTicket?> watchTicket(int num) => _root
      .child('Support/Tickets/$num')
      .onValue
      .map((event) => SupportTicket.fromFirebase(num, event.snapshot.value));

  /// Pushes a user reply onto the ticket's Thread. The functions trigger
  /// (onTicketThreadMessage) flips Status back to 'open' and emails the
  /// support inbox — the client only writes the message itself.
  static Future<void> addUserReply(
    int num, {
    required String uid,
    required String name,
    required String text,
  }) =>
      _root.child('Support/Tickets/$num/Thread').push().set({
        'From': 'user',
        'Uid': uid,
        'Name': name,
        'Text': text,
        'At': ServerValue.timestamp,
      });

  /// CreatedAt stamps of the user's most recent tickets (soft-rate-limit
  /// input). Only the newest [kSupportRateLimitPerHour]+ handful matter, and
  /// ticket numbers are a monotonic counter, so numeric-descending keys ARE
  /// newest-first — reading more would be waste. Errors degrade to an empty
  /// list (silent-failure convention): a broken read must never block a
  /// player from reporting that very breakage.
  static Future<List<int>> _myRecentCreatedAts(String uid) async {
    try {
      final index =
          (await _root.child('Support/UserTickets/$uid').once()).snapshot;
      final nums = ticketNumsFromIndex(index.value);
      final out = <int>[];
      for (final n in nums.take(kSupportRateLimitPerHour + 2)) {
        final created =
            (await _root.child('Support/Tickets/$n/CreatedAt').once())
                .snapshot
                .value;
        if (created is num) out.add(created.toInt());
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

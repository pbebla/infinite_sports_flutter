// Pure fan-side support-ticket model + helpers (zaya-support).
//
// NO Flutter/Firebase imports — unit-tested directly
// (test/support_models_test.dart), mirroring lib/model/insider.dart's
// tolerant-parse conventions. Field names are PascalCase to match the
// functions side (functions/src/lib/support.ts parseTicket) and the spec:
// docs/superpowers/specs/2026-10-13-support-tickets-design.md ("Data (RTDB)").
//
// One addition over the spec the functions side requires: the ticket node
// carries the FIRST message as `Message` — Thread/ starts empty and holds
// only replies.

// ---------------------------------------------------------------------------
// Limits (spec decision #1 + #3)
// ---------------------------------------------------------------------------

/// Required message cap (spec decision #1: "required message (≤5,000 chars)").
const int kSupportMessageMaxLength = 5000;

/// Screenshot cap per ticket (spec decision #1: "up to 5 screenshots").
const int kMaxScreenshots = 5;

/// Client-side downscale bound: the longest screenshot side never exceeds
/// this before upload (spec decision #1 — image_picker's maxWidth/maxHeight
/// re-encode does the scaling at pick time, so nothing oversized ever even
/// reaches memory, let alone Storage).
const int kScreenshotMaxDimension = 1600;

/// JPEG re-encode quality for the downscale above ("~80 quality").
const int kScreenshotJpegQuality = 80;

/// Soft per-account rate limit (spec decision #3: "6 tickets/hour").
const int kSupportRateLimitPerHour = 6;

const int _kHourMs = 60 * 60 * 1000;

/// How many of [createdAtsMs] (epoch-ms CreatedAt stamps) fall within the
/// hour before [nowMs]. Future timestamps (clock skew) count too — defensive,
/// they're still "recent". Drives the soft 6-tickets/hour gate in
/// SupportService.createTicket.
int recentTicketCount(Iterable<int> createdAtsMs, int nowMs) =>
    createdAtsMs.where((at) => nowMs - at < _kHourMs).length;

/// Appends [picked] onto [current] without ever exceeding [max] — the
/// client-side screenshot cap. Returns a NEW list; never mutates inputs.
/// Items beyond the cap are dropped in pick order (callers can compare
/// lengths to know whether to tell the user something was dropped).
List<T> capScreenshots<T>(List<T> current, List<T> picked,
    {int max = kMaxScreenshots}) {
  final out = List<T>.of(current);
  for (final p in picked) {
    if (out.length >= max) break;
    out.add(p);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Categories (spec decision #2) — stored as the lowercase key.
// ---------------------------------------------------------------------------

class SupportCategory {
  final String key;
  final String emoji;
  final String title;
  final String helper;

  const SupportCategory(this.key, this.emoji, this.title, this.helper);
}

/// The six owner-locked categories, in display order (spec decision #2).
const List<SupportCategory> kSupportCategories = [
  SupportCategory('suggestion', '💡', 'A suggestion',
      'Something you wish the app did'),
  SupportCategory('comment', '💬', 'A comment',
      'What is working, what feels wrong'),
  SupportCategory('bug', '🐞', 'Something is broken',
      'A bug or something that will not work'),
  SupportCategory('help', '❓', 'I need help', 'How do I…?'),
  SupportCategory('account', '🔑', 'Account or access',
      'Sign-in, registration, payments'),
  SupportCategory('other', '✨', 'Something else',
      'Anything else on your mind'),
];

SupportCategory _categoryFor(String key) {
  final v = key.trim().toLowerCase();
  for (final c in kSupportCategories) {
    if (c.key == v || c.title.toLowerCase() == v) return c;
  }
  return kSupportCategories.last; // 'other'
}

/// Emoji for a stored Category value (key or display label; unknown → ✨).
String categoryEmoji(String key) => _categoryFor(key).emoji;

/// Display title for a stored Category value (unknown → 'Something else').
String categoryTitle(String key) => _categoryFor(key).title;

// ---------------------------------------------------------------------------
// Statuses — plain words only, never raw keys (spec decision #6)
// ---------------------------------------------------------------------------

/// open | in_progress | waiting | answered | closed → the plain words the
/// owner locked in (spec decision #6). Unknown/missing reads as 'Open' —
/// every ticket is born open.
String supportStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'in_progress':
      return 'In progress';
    case 'waiting':
      return 'Waiting for your reply';
    case 'answered':
      return 'Answered';
    case 'closed':
      return 'Closed';
    default:
      return 'Open';
  }
}

/// The first line of a (possibly multi-line) message, trimmed — the My
/// Tickets list row preview.
String firstMessageLine(String message) {
  for (final line in message.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

// ---------------------------------------------------------------------------
// Thread messages (RTDB: Support/Tickets/<n>/Thread/<pushId>)
// ---------------------------------------------------------------------------

/// One Thread entry: {From: user|admin, Uid, Name, Text, At, Screenshots[]?}.
/// Internal notes live in the admin-only Notes/ subtree, NOT in Thread (spec
/// "Security rules"), so a fan client never even receives them — but the
/// thread UI still skips any From it doesn't recognize, defensively.
class SupportThreadMessage {
  final String id; // pushId — assigned from the node key
  final String from; // 'user' | 'admin' (anything else is skipped by the UI)
  final String uid;
  final String name;
  final String text;
  final int at; // millisecondsSinceEpoch
  final List<String> screenshots;

  const SupportThreadMessage({
    required this.id,
    required this.from,
    this.uid = '',
    this.name = '',
    this.text = '',
    this.at = 0,
    this.screenshots = const [],
  });

  bool get isUser => from == 'user';
  bool get isAdmin => from == 'admin';

  static SupportThreadMessage? fromFirebase(String id, Object? raw) {
    if (raw is! Map) return null;
    return SupportThreadMessage(
      id: id,
      from: raw['From']?.toString() ?? '',
      uid: raw['Uid']?.toString() ?? '',
      name: raw['Name']?.toString() ?? '',
      text: raw['Text']?.toString() ?? '',
      at: _asInt(raw['At']),
      screenshots: parseScreenshotUrls(raw['Screenshots']),
    );
  }
}

// ---------------------------------------------------------------------------
// Tickets (RTDB: Support/Tickets/<n>)
// ---------------------------------------------------------------------------

class SupportTicket {
  final int num;
  final String uid;
  final String name;
  final String email;
  final String category; // lowercase key ('bug', ...)
  final String message; // the opening message (PascalCase `Message` node)
  final String status; // open | in_progress | waiting | answered | closed
  final int createdAt; // millisecondsSinceEpoch
  final int updatedAt;
  final String appVersion;
  final String platform; // 'iOS' | 'Android'
  final String device;
  final String screen;
  final List<String> screenshots;
  final List<SupportThreadMessage> thread; // replies only, oldest first

  const SupportTicket({
    required this.num,
    this.uid = '',
    this.name = '',
    this.email = '',
    this.category = 'other',
    this.message = '',
    this.status = 'open',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.appVersion = '',
    this.platform = '',
    this.device = '',
    this.screen = '',
    this.screenshots = const [],
    this.thread = const [],
  });

  bool get isClosed => status == 'closed';

  /// Tolerant parse; null only when [raw] isn't a Map at all.
  static SupportTicket? fromFirebase(int num, Object? raw) {
    if (raw is! Map) return null;
    final thread = <SupportThreadMessage>[];
    final rawThread = raw['Thread'];
    if (rawThread is Map) {
      rawThread.forEach((id, value) {
        final msg = SupportThreadMessage.fromFirebase(id.toString(), value);
        if (msg != null) thread.add(msg);
      });
    }
    // Oldest first (conversation order); push ids tie-break equal stamps.
    thread.sort((a, b) {
      final byAt = a.at.compareTo(b.at);
      return byAt != 0 ? byAt : a.id.compareTo(b.id);
    });
    return SupportTicket(
      num: num,
      uid: raw['Uid']?.toString() ?? '',
      name: raw['Name']?.toString() ?? '',
      email: raw['Email']?.toString() ?? '',
      category: raw['Category']?.toString() ?? 'other',
      message: raw['Message']?.toString() ?? '',
      status: raw['Status']?.toString() ?? 'open',
      createdAt: _asInt(raw['CreatedAt']),
      updatedAt: _asInt(raw['UpdatedAt']),
      appVersion: raw['AppVersion']?.toString() ?? '',
      platform: raw['Platform']?.toString() ?? '',
      device: raw['Device']?.toString() ?? '',
      screen: raw['Screen']?.toString() ?? '',
      screenshots: parseScreenshotUrls(raw['Screenshots']),
      thread: thread,
    );
  }
}

/// Parses a `Support/UserTickets/<uid>` index node into ticket numbers, newest
/// (highest counter) first — ticket ids are monotonically increasing counter
/// values, so numeric descending IS chronological descending.
List<int> ticketNumsFromIndex(Object? raw) {
  final out = <int>[];
  if (raw is Map) {
    raw.forEach((key, value) {
      if (value == null || value == false) return;
      final n = int.tryParse(key.toString());
      if (n != null) out.add(n);
    });
  }
  out.sort((a, b) => b.compareTo(a));
  return out;
}

/// Screenshots arrive from RTDB as a real List OR as a {0: url, 1: url}
/// map depending on keys (same quirk functions/src/lib/support.ts
/// screenshotCount handles) — normalize both, skipping null holes.
List<String> parseScreenshotUrls(Object? raw) {
  if (raw is List) {
    return raw.where((v) => v != null).map((v) => v.toString()).toList();
  }
  if (raw is Map) {
    final keys = raw.keys.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a.toString());
        final bi = int.tryParse(b.toString());
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.toString().compareTo(b.toString());
      });
    return [
      for (final k in keys)
        if (raw[k] != null) raw[k].toString(),
    ];
  }
  return const [];
}

int _asInt(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

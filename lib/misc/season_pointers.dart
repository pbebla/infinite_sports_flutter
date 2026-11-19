// Season pointers that stay live (fresh-reads plan, Task 2).
//
// `Current League`, `<Sport> Season` and `AFC San Jose/Current Season` say
// which league and season the whole app shows: the Matches tab, the top-bar
// Table and Leaderboard (`headerNotifier`), the calendar's league days, the
// Leagues season list, the profile and the fantasy resolver. They used to be
// read with one-shot `once()` calls, which answer from the phone's saved copy
// and never renew it — so a phone last opened in Season 15 could stay on
// Season 15 after the league moved to 16 (survey rows #37, #38, #40, #2).
//
// Now ONE live listener per pointer, started by the first read and kept for
// the app's lifetime (five tiny nodes), feeds [SeasonPointers]:
//   • the getters (`getCurrentSport`, `getCurrentSeason`,
//     `getAFCCurrentSeason`, the fantasy resolver's pointer read) keep their
//     signatures and answer from it: the first answer waits for the first
//     event of every pointer (the saved copy, so opening stays instant),
//     bounded by [kRevealReadTimeout];
//   • a listener that stays attached receives the server's value a few
//     hundred ms after the connection is up (fresh-read probe, phase 4), so
//     a stale saved copy is corrected within the first second online;
//   • every later change is published on [SeasonPointers.listenable] ONCE,
//     after [SeasonPointers.settle] (pointer edits made together — a new
//     league and its season — arrive as one update), and bumps
//     [SeasonPointers.version]. Consumers re-read in one coordinated update:
//     FrontPage (Matches tab + headerNotifier), the calendar's league days,
//     the Leagues season list, the fantasy resolver memo, the profile career
//     cache.
//   • a failed or timed-out pointer is NOT "no season": [SeasonPointers.read]
//     throws for it, and the stream re-subscribes on the next read.
//
// Test seams: [SeasonPointers.sourceOverride] (path → stream of raw values),
// [SeasonPointers.firstEventTimeout], [SeasonPointers.settle],
// [SeasonPointers.debugReset].

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/misc/bounded_read.dart';

/// The pointer naming the current league (a sport name).
const String kCurrentLeaguePointer = 'Current League';

/// AFC San Jose's own current-season pointer.
const String kAfcSeasonPointer = 'AFC San Jose/Current Season';

/// The league sports whose `<Sport> Season` pointer is always watched.
const List<String> kSeasonPointerSports = [
  'Futsal',
  'Basketball',
  'Flag Football',
];

/// `<Sport> Season`.
String seasonPointerPath(String sport) => '$sport Season';

/// Every pointer watched from the start.
List<String> get kSeasonPointerPaths => [
      kCurrentLeaguePointer,
      for (final s in kSeasonPointerSports) seasonPointerPath(s),
      kAfcSeasonPointer,
    ];

/// One immutable view of every pointer: path → value as text (null =
/// absent at the path).
@immutable
class SeasonPointerValues {
  const SeasonPointerValues(this.byPath);
  final Map<String, String?> byPath;

  String? get currentLeague => byPath[kCurrentLeaguePointer];
  String? seasonFor(String sport) => byPath[seasonPointerPath(sport)];
  String? get afcSeason => byPath[kAfcSeasonPointer];

  /// The current league's current season.
  String? get currentSeason {
    final league = currentLeague;
    return league == null ? null : seasonFor(league);
  }

  @override
  bool operator ==(Object other) =>
      other is SeasonPointerValues && mapEquals(other.byPath, byPath);

  @override
  int get hashCode => Object.hashAllUnordered(
      byPath.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'SeasonPointerValues($byPath)';
}

class _Pointer {
  _Pointer(this.path);
  final String path;
  StreamSubscription<Object?>? sub;
  bool hasValue = false;
  String? value;
  Object? error;
  Completer<void> first = Completer<void>();
}

class SeasonPointers {
  SeasonPointers._();

  /// Test seam: path → a stream of the pointer's raw values (null = real).
  @visibleForTesting
  static Stream<Object?> Function(String path)? sourceOverride;

  /// How long the first read waits for the first events.
  static Duration firstEventTimeout = kRevealReadTimeout;

  /// How long a change waits for companion changes before it is published.
  static Duration settle = const Duration(milliseconds: 250);

  static final Map<String, _Pointer> _pointers = {};
  static final ValueNotifier<SeasonPointerValues> _published =
      ValueNotifier(const SeasonPointerValues({}));
  static Future<void>? _ready;
  static bool _isReady = false;
  static Timer? _settleTimer;
  static int _version = 0;

  /// The published pointers; notifies once per coordinated change.
  static ValueListenable<SeasonPointerValues> get listenable => _published;

  /// Bumped on every published change (memos compare it).
  static int get version => _version;

  /// The latest values seen (synchronous; may be newer than [listenable]
  /// during the settle window).
  static SeasonPointerValues get current => SeasonPointerValues({
        for (final p in _pointers.values)
          if (p.hasValue) p.path: p.value,
      });

  /// Starts every pointer listener (once) and completes when each has
  /// answered or failed, or [firstEventTimeout] passed. Never throws.
  static Future<void> ensureStarted() {
    for (final path in kSeasonPointerPaths) {
      _subscribe(path);
    }
    return _ready ??= _waitReady();
  }

  static Future<void> _waitReady() async {
    final firsts = [for (final p in _pointers.values) p.first.future];
    try {
      await Future.wait(firsts).bounded('Season pointers',
          orElse: () => const <void>[], timeout: firstEventTimeout);
    } catch (_) {
      // bounded() with orElse never throws; belt and braces.
    }
    _isReady = true;
    _published.value = current;
  }

  /// The pointer at [path] as text (null = absent). Throws when the pointer
  /// could not be read (stream error or no first answer within the bound):
  /// a failed read is not "no season".
  static Future<String?> read(String path) async {
    // A pointer outside the standard set (another sport) is subscribed here;
    // a standard one whose stream failed earlier is re-subscribed by
    // ensureStarted. A failure during THIS read is reported, not retried.
    if (!kSeasonPointerPaths.contains(path)) _subscribe(path);
    await ensureStarted();
    final p = _pointers[path]!;
    if (!p.hasValue && p.error == null && !p.first.isCompleted) {
      await p.first.future.bounded('Season pointer $path',
          orElse: () {}, timeout: firstEventTimeout);
    }
    if (p.hasValue) return p.value;
    final error = p.error;
    if (error != null) throw error;
    throw TimeoutException(
        'Season pointer $path: no answer', firstEventTimeout);
  }

  static _Pointer _subscribe(String path) {
    final p = _pointers.putIfAbsent(path, () => _Pointer(path));
    if (p.sub != null) return p;
    if (p.first.isCompleted && !p.hasValue) p.first = Completer<void>();
    p.error = null;
    try {
      final source = sourceOverride ?? _firebaseSource;
      p.sub = source(path).listen((raw) => _onValue(p, raw), onError: (e) {
        debugPrint('Season pointer $path: stream failed: $e');
        p.error = e;
        p.sub?.cancel();
        p.sub = null; // the next read re-subscribes
        if (!p.first.isCompleted) p.first.complete();
      });
    } catch (e) {
      debugPrint('Season pointer $path: unavailable: $e');
      p.error = e;
      p.sub = null;
      if (!p.first.isCompleted) p.first.complete();
    }
    return p;
  }

  static Stream<Object?> _firebaseSource(String path) =>
      FirebaseDatabase.instance.ref(path).onValue.map((e) => e.snapshot.value);

  static void _onValue(_Pointer p, Object? raw) {
    final text = raw?.toString();
    final changed = !p.hasValue || p.value != text;
    p.value = text;
    p.hasValue = true;
    p.error = null;
    if (!p.first.isCompleted) p.first.complete();
    if (!changed || !_isReady) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, _publish);
  }

  static void _publish() {
    _settleTimer = null;
    final now = current;
    if (now == _published.value) return;
    _version++;
    _published.value = now;
  }

  /// Cancels everything (tests).
  @visibleForTesting
  static void debugReset() {
    for (final p in _pointers.values) {
      p.sub?.cancel();
    }
    _pointers.clear();
    _settleTimer?.cancel();
    _settleTimer = null;
    _ready = null;
    _isReady = false;
    _version = 0;
    _published.value = const SeasonPointerValues({});
  }
}

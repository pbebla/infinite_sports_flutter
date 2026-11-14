// Team logos that stay fresh (S16 Task 1).
//
// `Logo Urls` (+ `AFC San Jose/Logo URL`) used to be read ONCE per session
// with `once()` and memoised in the global [teamLogos]. With the on-disk
// RTDB cache on, `once()` answers from the phone's saved copy and never
// refreshes it, so crests added after install (Futsal Season 16) stayed
// blank shields across cold starts.
//
// Now ONE live subscription ([TeamLogoFeed]), started by the first
// `getAllTeamLogo()` call and kept for the app's lifetime, replaces
// [teamLogos] on every event and bumps [teamLogosVersion]:
//   • `getAllTeamLogo()` (= [TeamLogoFeed.ensureStarted]) completes on the
//     FIRST event (the saved copy, as before), bounded by the reveal-read
//     convention ([kRevealReadTimeout]); a timeout, an error or a source that
//     cannot be created is logged and leaves the map as it was — never
//     thrown. A later event still fills the map in.
//   • a stream error keeps the last good map; the next `getAllTeamLogo()`
//     call re-subscribes.
//   • crest-showing league screens use [watchSeasonLogos] and repaint when
//     their season's map actually changes; legacy screens read the refreshed
//     global the next time they build/open.
//
// Test seam: [TeamLogoFeed.sourceOverride] (a stream of whole logo maps,
// shaped like the global) and [TeamLogoFeed.debugReset].

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/misc/bounded_read.dart';

/// Every team logo url: `teamLogos[sport][season][team]`, plus
/// `teamLogos['AFC San Jose']` (one url). Replaced (never mutated) on each
/// live event — re-read it after [teamLogosVersion] changes.
Map teamLogos = {};

/// Bumped every time [teamLogos] is replaced by a live event.
final ValueNotifier<int> teamLogosVersion = ValueNotifier<int>(0);

/// A stream of whole logo maps shaped like [teamLogos].
typedef TeamLogoSource = Stream<Map> Function();

class TeamLogoFeed {
  TeamLogoFeed._();

  /// Test seam: replaces the Firebase source (null = real).
  static TeamLogoSource? sourceOverride;

  /// How long the first `getAllTeamLogo()` waits for the first event.
  static Duration firstEventTimeout = kRevealReadTimeout;

  static StreamSubscription<Map>? _sub;
  static Completer<void>? _first;
  static Timer? _firstTimer;

  /// Starts the live subscription if it is not running and completes when
  /// the first event has arrived (or the first wait gave up). Never throws.
  static Future<void> ensureStarted() {
    if (_sub == null) _start();
    return _first!.future;
  }

  static void _start() {
    final first = _first ??= Completer<void>();
    if (!first.isCompleted && _firstTimer == null) {
      final bound = firstEventTimeout;
      _firstTimer = Timer(bound, () {
        _firstTimer = null;
        if (first.isCompleted) return;
        final after = bound.inMilliseconds % 1000 == 0
            ? '${bound.inSeconds}s'
            : '${bound.inMilliseconds}ms';
        debugPrint('Team logos: no answer after $after — degrading');
        first.complete();
      });
    }
    try {
      final source = sourceOverride ?? _firebaseSource;
      _sub = source().listen(_onLogos, onError: (Object e) {
        debugPrint('Team logos: stream failed: $e');
        _sub?.cancel();
        _sub = null; // the next getAllTeamLogo() re-subscribes
        _openFirstGate();
      }, onDone: () {
        _sub = null;
        _openFirstGate();
      });
    } catch (e) {
      debugPrint('Team logos: stream failed: $e');
      _sub = null;
      _openFirstGate();
    }
  }

  static void _onLogos(Map logos) {
    teamLogos = logos;
    teamLogosVersion.value++;
    _openFirstGate();
  }

  static void _openFirstGate() {
    _firstTimer?.cancel();
    _firstTimer = null;
    final first = _first;
    if (first != null && !first.isCompleted) first.complete();
  }

  /// `Logo Urls` merged with `AFC San Jose/Logo URL`. Emits once both have
  /// answered (the AFC url failing counts as answered: it is optional), then
  /// on every change of either. An error on `Logo Urls` is forwarded.
  static Stream<Map> _firebaseSource() {
    // Resolved HERE (not in onListen) so a missing Firebase app throws
    // synchronously into _start's catch instead of into the zone.
    final db = FirebaseDatabase.instance;
    final logosEvents = db.ref('Logo Urls').onValue;
    final afcEvents = db.ref('AFC San Jose/Logo URL').onValue;
    late final StreamController<Map> out;
    StreamSubscription<DatabaseEvent>? logosSub;
    StreamSubscription<DatabaseEvent>? afcSub;
    Map? logos;
    Object? afc;
    var afcAnswered = false;

    void emit() {
      if (logos == null || !afcAnswered) return;
      final merged = Map.of(logos!);
      if (afc != null) merged['AFC San Jose'] = afc.toString();
      out.add(merged);
    }

    out = StreamController<Map>(
      onListen: () {
        logosSub = logosEvents.listen((e) {
          final v = e.snapshot.value;
          logos = v is Map ? v : {};
          emit();
        }, onError: out.addError);
        afcSub = afcEvents.listen((e) {
          afc = e.snapshot.value;
          afcAnswered = true;
          emit();
        }, onError: (Object e) {
          debugPrint('Team logos: AFC San Jose logo failed: $e');
          afcAnswered = true;
          emit();
        });
      },
      onCancel: () async {
        await logosSub?.cancel();
        await afcSub?.cancel();
      },
    );
    return out.stream;
  }

  /// Test seam: drops the subscription and the cached map.
  @visibleForTesting
  static void debugReset() {
    _sub?.cancel();
    _sub = null;
    _firstTimer?.cancel();
    _firstTimer = null;
    _first = null;
    sourceOverride = null;
    firstEventTimeout = kRevealReadTimeout;
    teamLogos = {};
    teamLogosVersion.value = 0;
  }
}

/// One season's logos (team name → url) out of a [teamLogos]-shaped map;
/// `{}` when the sport or season is missing or not a map.
Map<String, String> seasonLogoUrlsFrom(Map logos, String sport, String season) {
  final bySport = logos[sport];
  if (bySport is! Map) return {};
  final bySeason = bySport[season];
  if (bySeason is! Map) return {};
  return {
    for (final e in bySeason.entries)
      if (e.value != null) e.key.toString(): e.value.toString(),
  };
}

/// Live season logos for a crest screen: starts the feed if needed, reports
/// the season's map once the first event is in, then again whenever it
/// really changes (a crest added in the database fills in with no
/// restart). Never reports synchronously. Returns the stop function — call
/// it from dispose.
VoidCallback watchSeasonLogos(String sport, String season,
    void Function(Map<String, String> logos) onLogos) {
  var stopped = false;
  Map<String, String>? last;
  void report() {
    if (stopped) return;
    final now = seasonLogoUrlsFrom(teamLogos, sport, season);
    if (last != null && mapEquals(last, now)) return;
    last = now;
    onLogos(now);
  }

  var ready = false;
  void onVersion() {
    if (ready) report();
  }

  teamLogosVersion.addListener(onVersion);
  TeamLogoFeed.ensureStarted().then((_) {
    ready = true;
    report();
  });
  return () {
    stopped = true;
    teamLogosVersion.removeListener(onVersion);
  };
}

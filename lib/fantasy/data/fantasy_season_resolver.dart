// "The current fantasy season" (round 3, spec §7) — the same resolution the
// home banner / search hub use, for callers that have no sport/season handed
// to them (the Infinite profile's Fantasy tab):
//
//   1. the current league's current season (the `Current League` pointer and
//      its `<Sport> Season` pointer, exactly as frontpage.dart / the search
//      hub read them) when `Fantasy/<sport>/<season>/Config` exists — the
//      same existence gate as the banner and the league page's Fantasy tab;
//   2. otherwise the newest earlier season of that sport that has a Config.
//
// RTDB has no cheap "list the child keys" read (a plain read of
// `Fantasy/<sport>` would pull every season's squads and weekly records), so
// step 2 probes the tiny `Config` nodes of the seasons just below the current
// one, newest first, in small parallel batches — one extra read in the usual
// "new season created, Fantasy not set up yet" case. `once()` reads only —
// NEVER `.get()` (house rule; the Manager's guard test enforces it there).
//
// The answer is THREE-way ([FantasySeasonResolution]): a season, a real
// "none", or an error. A failed read (a network blip, a permission hiccup)
// is not "there is no fantasy season" — callers that remember a "none" (the
// profile's Fantasy tab) must only remember the real one and retry an error.
//
// The decision logic is the pure [pickFantasySeason] / [resolveFantasySeasonWith]
// (unit-tested with injected reads in
// test/fantasy/fantasy_season_resolver_test.dart); the Firebase readers in
// [resolveFantasySeason] are not (repo convention).

import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart'
    show kFantasyReservedRootKeys;
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';

/// A resolved fantasy season.
typedef FantasySeasonKey = ({String sport, String season});

/// What resolving the current fantasy season answered: [season] (found), a
/// real "none" ([isNone] — no pointer set, or no season in reach has a
/// Config), or a failure ([failed] — a read errored; the truth is unknown).
class FantasySeasonResolution {
  const FantasySeasonResolution.found(FantasySeasonKey this.season)
      : error = null;
  const FantasySeasonResolution.none()
      : season = null,
        error = null;
  const FantasySeasonResolution.failed(Object this.error) : season = null;

  /// The season; null for none AND for an error.
  final FantasySeasonKey? season;

  /// What failed; null unless [failed].
  final Object? error;

  bool get failed => error != null;
  bool get isNone => season == null && error == null;

  @override
  String toString() => failed
      ? 'FantasySeasonResolution.failed($error)'
      : isNone
          ? 'FantasySeasonResolution.none()'
          : 'FantasySeasonResolution.found(${season!.sport}/${season!.season})';
}

/// RTDB key characters that can never appear in a path segment — also what
/// the pointer readers' error text (`e.toString()` on failure) always contains.
final RegExp _illegalPathChars = RegExp(r'[.$#\[\]/]');

bool _usableSegment(String s) {
  final t = s.trim();
  return t.isNotEmpty && t != 'null' && !_illegalPathChars.hasMatch(t);
}

/// How many seasons below the current one the fallback inspects.
const int kFantasySeasonProbeWindow = 30;

const int _probeBatch = 6;

/// Pure decision core. [hasConfig] answers "does
/// `Fantasy/<sport>/<season>/Config` exist?" (a failing probe propagates).
/// Returns null when [sport]/[currentSeason] aren't usable path segments (an
/// unset pointer, or the pointer reader's error text), when [sport] is one of
/// the non-sport keys under `Fantasy/` (`BadgeCatalog` — the global badge
/// catalog sits beside the sports), or when no season in reach has a Config.
/// A non-numeric [currentSeason] can only be checked directly — there is no
/// season to count down from.
Future<FantasySeasonKey?> pickFantasySeason({
  required String sport,
  required String currentSeason,
  required Future<bool> Function(String sport, String season) hasConfig,
  int maxSeasonsBack = kFantasySeasonProbeWindow,
}) async {
  final s = sport.trim();
  final current = currentSeason.trim();
  if (!_usableSegment(s) ||
      !_usableSegment(current) ||
      kFantasyReservedRootKeys.contains(s)) {
    return null;
  }

  if (await hasConfig(s, current)) return (sport: s, season: current);

  final number = int.tryParse(current);
  if (number == null) return null;

  // Newest first, batch by batch so the common case stays one extra read.
  final lowest = (number - maxSeasonsBack) < 1 ? 1 : number - maxSeasonsBack;
  for (var top = number - 1; top >= lowest; top -= _probeBatch) {
    final batch = [
      for (var n = top; n > top - _probeBatch && n >= lowest; n--) n,
    ];
    final found =
        await Future.wait([for (final n in batch) hasConfig(s, n.toString())]);
    final hit = found.indexOf(true);
    if (hit != -1) return (sport: s, season: batch[hit].toString());
  }
  return null;
}

FantasySeasonKey? _lastResolved;

/// The last successfully resolved season this session (null before the first
/// resolve) — lets a screen paint its first frame without waiting on the
/// pointer reads (session-cache convention; not user-specific, so nothing to
/// clear on sign-out).
FantasySeasonKey? get lastResolvedFantasySeason => _lastResolved;

Future<bool> _configExists(String sport, String season) async {
  final snap = (await FirebaseDatabase.instance
          .ref('Fantasy/$sport/$season/Config')
          .once())
      .snapshot;
  // Same gate as FantasyService.watchConfig: absent/malformed = no fantasy.
  return configStateFromNode(snap.value) != null;
}

/// A top-level pointer node (`Current League`, `<Sport> Season`) — the same
/// nodes frontpage.dart / the search hub read, but read here directly so a
/// FAILED read throws instead of coming back as error text (utility.dart's
/// getCurrentSport/getCurrentSeason swallow errors into the returned
/// string, which would be indistinguishable from "no pointer"). '' = absent.
Future<String> _readPointer(String path) async {
  final snap = (await FirebaseDatabase.instance.ref(path).once()).snapshot;
  return snap.value?.toString() ?? '';
}

/// Pure three-way core: [readSport] / [readSeason] read the pointers (a
/// throw = a failed read), [hasConfig] probes Config nodes (see
/// [pickFantasySeason]). Never throws: any failure is
/// [FantasySeasonResolution.failed].
Future<FantasySeasonResolution> resolveFantasySeasonWith({
  required Future<String> Function() readSport,
  required Future<String> Function(String sport) readSeason,
  required Future<bool> Function(String sport, String season) hasConfig,
}) async {
  try {
    final sport = (await readSport()).trim();
    if (!_usableSegment(sport)) return const FantasySeasonResolution.none();
    final season = await readSeason(sport);
    final resolved = await pickFantasySeason(
      sport: sport,
      currentSeason: season,
      hasConfig: hasConfig,
    );
    return resolved == null
        ? const FantasySeasonResolution.none()
        : FantasySeasonResolution.found(resolved);
  } catch (e) {
    return FantasySeasonResolution.failed(e);
  }
}

/// The current fantasy season as a three-way answer (season / none /
/// error). Never throws. A found season is memoized
/// ([lastResolvedFantasySeason]).
Future<FantasySeasonResolution> resolveFantasySeason() async {
  final result = await resolveFantasySeasonWith(
    readSport: () => _readPointer('Current League'),
    readSeason: (sport) => _readPointer('$sport Season'),
    hasConfig: _configExists,
  );
  final season = result.season;
  if (season != null) _lastResolved = season;
  return result;
}

/// The current fantasy season, or null when there is none OR the reads
/// failed (never throws). Kept for callers that only need "a season or
/// not"; anything that REMEMBERS a "none" must use [resolveFantasySeason]
/// so an error is never cached as "no season".
Future<FantasySeasonKey?> resolveCurrentFantasySeason() async =>
    (await resolveFantasySeason()).season;

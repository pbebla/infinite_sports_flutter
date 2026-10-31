// Fantasy round 3, Task 4 — the "current fantasy season" resolver's PURE
// core (spec §7): the current league's current season when it has a Fantasy
// Config, else the newest season under Fantasy/<sport> that has one. The
// Firebase-touching wrapper (resolveCurrentFantasySeason) is not unit-tested
// (repo convention); the decision logic is, via injected probes.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_season_resolver.dart';

void main() {
  /// A fake `Fantasy/<sport>/<season>/Config` existence probe that records
  /// every call.
  ({
    Future<bool> Function(String, String) probe,
    List<String> calls,
  }) fake(Set<String> withConfig) {
    final calls = <String>[];
    return (
      probe: (sport, season) async {
        calls.add('$sport/$season');
        return withConfig.contains('$sport/$season');
      },
      calls: calls,
    );
  }

  test('the current season wins when it has a Config (one read)', () async {
    final f = fake({'Futsal/15', 'Futsal/14'});
    final r = await pickFantasySeason(
        sport: 'Futsal', currentSeason: '15', hasConfig: f.probe);
    expect(r, (sport: 'Futsal', season: '15'));
    expect(f.calls, ['Futsal/15']);
  });

  test('falls back to the newest older season that has a Config', () async {
    final f = fake({'Futsal/15', 'Futsal/12'});
    final r = await pickFantasySeason(
        sport: 'Futsal', currentSeason: '17', hasConfig: f.probe);
    expect(r, (sport: 'Futsal', season: '15'));
  });

  test('picks the NEWEST of several older Config seasons', () async {
    final f = fake({'Futsal/9', 'Futsal/13', 'Futsal/11'});
    final r = await pickFantasySeason(
        sport: 'Futsal', currentSeason: '16', hasConfig: f.probe);
    expect(r, (sport: 'Futsal', season: '13'));
  });

  test('no Config anywhere in the window → null', () async {
    final f = fake({});
    expect(
        await pickFantasySeason(
            sport: 'Basketball', currentSeason: '4', hasConfig: f.probe),
        isNull);
    // Never probes below season 1 or negative numbers.
    expect(f.calls.every((c) => int.parse(c.split('/').last) >= 1), isTrue);
  });

  test('a Config older than the probe window is not found', () async {
    final f = fake({'Futsal/2'});
    expect(
        await pickFantasySeason(
            sport: 'Futsal',
            currentSeason: '100',
            hasConfig: f.probe,
            maxSeasonsBack: 10),
        isNull);
  });

  test('a non-numeric current season can only be checked directly', () async {
    final f = fake({'Futsal/Spring'});
    expect(
        await pickFantasySeason(
            sport: 'Futsal', currentSeason: 'Spring', hasConfig: f.probe),
        (sport: 'Futsal', season: 'Spring'));
    final none = fake({'Futsal/15'});
    expect(
        await pickFantasySeason(
            sport: 'Futsal', currentSeason: 'Summer', hasConfig: none.probe),
        isNull);
    expect(none.calls, ['Futsal/Summer']); // no season to count down from
  });

  test('unusable pointers (null / error text / empty) never reach the DB',
      () async {
    for (final bad in [
      ('', '15'),
      ('null', '15'),
      ('[firebase_database/network-error] oops', '15'),
      ('Futsal', ''),
      ('Futsal', 'null'),
      ('Futsal', '1/2'),
      ('Fut.sal', '15'),
    ]) {
      final f = fake({'Futsal/15'});
      expect(
          await pickFantasySeason(
              sport: bad.$1, currentSeason: bad.$2, hasConfig: f.probe),
          isNull,
          reason: '$bad');
      expect(f.calls, isEmpty, reason: '$bad');
    }
  });

  test('badges: Fantasy/BadgeCatalog sits beside the sports — a pointer that '
      'names it is never a sport (no probe)', () async {
    final f = fake({'BadgeCatalog/15', 'BadgeCatalog/captainGenius'});
    for (final season in ['15', 'captainGenius']) {
      expect(
          await pickFantasySeason(
              sport: ' BadgeCatalog ',
              currentSeason: season,
              hasConfig: f.probe),
          isNull);
    }
    expect(f.calls, isEmpty);
    final r = await resolveFantasySeasonWith(
      readSport: () async => 'BadgeCatalog',
      readSeason: (_) async => '15',
      hasConfig: f.probe,
    );
    expect(r.isNone, isTrue);
  });

  test('a failing probe propagates (the wrapper turns it into an error)', () {
    expect(
        pickFantasySeason(
          sport: 'Futsal',
          currentSeason: '15',
          hasConfig: (_, __) async => throw StateError('offline'),
        ),
        throwsStateError);
  });

  // ── The three-way answer: season / none / error ─────────────────────────
  // A failed read (network blip, permission hiccup) must never be mistaken
  // for "there is no fantasy season" — only a real "none" may be cached.
  group('resolveFantasySeasonWith', () {
    test('found: the season', () async {
      final f = fake({'Futsal/15'});
      final r = await resolveFantasySeasonWith(
        readSport: () async => 'Futsal',
        readSeason: (sport) async => '15',
        hasConfig: f.probe,
      );
      expect(r.season, (sport: 'Futsal', season: '15'));
      expect(r.isNone, isFalse);
      expect(r.failed, isFalse);
    });

    test('none: unset pointers, or no Config in reach', () async {
      for (final pointers in [('', '15'), ('Futsal', ''), ('Futsal', '15')]) {
        final r = await resolveFantasySeasonWith(
          readSport: () async => pointers.$1,
          readSeason: (sport) async => pointers.$2,
          hasConfig: fake({}).probe,
        );
        expect(r.isNone, isTrue, reason: '$pointers');
        expect(r.failed, isFalse, reason: '$pointers');
        expect(r.season, isNull, reason: '$pointers');
      }
    });

    test('error: a failing pointer read or Config probe is NOT "none"',
        () async {
      final sportFails = await resolveFantasySeasonWith(
        readSport: () async => throw StateError('offline'),
        readSeason: (sport) async => '15',
        hasConfig: fake({'Futsal/15'}).probe,
      );
      final seasonFails = await resolveFantasySeasonWith(
        readSport: () async => 'Futsal',
        readSeason: (sport) async => throw StateError('denied'),
        hasConfig: fake({'Futsal/15'}).probe,
      );
      final probeFails = await resolveFantasySeasonWith(
        readSport: () async => 'Futsal',
        readSeason: (sport) async => '16',
        hasConfig: (_, __) async => throw StateError('blip'),
      );
      for (final r in [sportFails, seasonFails, probeFails]) {
        expect(r.failed, isTrue);
        expect(r.isNone, isFalse);
        expect(r.season, isNull);
        expect(r.error, isA<StateError>());
      }
    });
  });
}

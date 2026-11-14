import 'dart:async';

// Second review, Important 1: the player profile's in-place reload rebuilds
// the career into FRESH collections and swaps them in with one setState —
// it never appends to what is shown. Driven through the real load and the
// real reload (ProfilePage.careerSources seam) with newer values reported as
// a lingering listener would (FreshReads.debugReportNewer).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/season_pointers.dart';
import 'package:infinite_sports_flutter/misc/team_logos.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/profile/fantasy_profile_source.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';

const _uid = 'u1';
const _teamPath = 'Futsal/16/Line Ups/Lions';

void main() {
  late int goals;
  late int reads;

  tearDown(() {
    SeasonPointers.debugReset();
    SeasonPointers.sourceOverride = null;
    TeamLogoFeed.debugReset();
  });

  setUp(() {
    ProfilePage.clearCareerCache();
    // Hermetic logo feed (a cross-test feed restart would hold the logo
    // gate for its bound).
    TeamLogoFeed.debugReset();
    TeamLogoFeed.sourceOverride = () => Stream<Map>.value(const {});
    // Hermetic season pointers (no Firebase): Futsal is on Season 17, so
    // the profile's Season 16 stint is a finished one.
    SeasonPointers.debugReset();
    SeasonPointers.sourceOverride = (path) =>
        Stream<Object?>.value(path == kCurrentLeaguePointer ? 'Futsal' : '17');
    goals = 3;
    reads = 0;
  });

  ProfileCareerSources sources() => ProfileCareerSources(
        read: (path) async {
          switch (path) {
            case 'PublicProfiles/$_uid':
              return {
                'First Name': 'Sam',
                'Last Name': 'Lee',
                'Played': {
                  'Futsal': {'Season 16': 'Lions'},
                },
              };
            case _teamPath:
              reads++;
              return {
                'Sam Lee': {'UID': _uid, 'Goals': goals, 'number': '9'},
              };
            case 'PublicProfiles/$_uid/TournamentsPlayed':
              return {'t1': true};
          }
          return null;
        },
        tournamentBundle: (id) async => TournamentBundle(
          tournament: const Tournament(
            id: 't1',
            name: 'Infinite Cup',
            sport: 'Futsal',
            edition: '2026',
            status: 'Group Stage',
            finished: false,
          ),
          teams: const {},
          matches: const [],
          config: PredictionConfig.fromFirebase(const {}),
          rosters: const {
            'teamA': [
              TournamentPlayer(
                name: 'Sam Lee',
                teamId: 'teamA',
                teamName: 'Team A',
                uid: _uid,
                goals: 2,
                assists: 0,
                saves: 0,
                dpl: 0,
                cleanSheets: 0,
                yellowCards: 0,
                redCards: 0,
              ),
            ],
          },
        ),
        afcSeasons: () async => <String>[],
        afcRoster: (_) async => <String, SoccerPlayer>{},
      );

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ProfilePage(
        uid: _uid,
        careerSources: sources(),
        fantasySeams: FantasyProfileSeams(resolveSeason: () async => null),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// One league season + one tournament: two stints, two competitions, one
  /// tournament appearance.
  void expectNoDuplicates() {
    final c = ProfilePage.debugCachedCounts(_uid);
    expect(c, isNotNull);
    expect(c!.appearances, 1);
    expect(c.stints, 2);
    expect(c.competitions, 2);
  }

  Future<void> newer(WidgetTester tester) async {
    FreshReads.debugReportNewer(_teamPath, {'changed': goals});
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pump(ProfilePage.kProfileReloadGap);
    await tester.pumpAndSettle();
  }

  testWidgets('two newer values: each stint and competition exactly once',
      (tester) async {
    await pumpProfile(tester);
    expectNoDuplicates();
    goals = 4;
    await newer(tester);
    expectNoDuplicates();
    goals = 5;
    await newer(tester);
    expectNoDuplicates();
    expect(reads, greaterThanOrEqualTo(3), reason: 'it really reloaded');
  });

  testWidgets(
      'five newer values in a burst: one queued reload at a time, never '
      'duplicates, scroll kept', (tester) async {
    await pumpProfile(tester);
    final scrollable = find
        .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position
        .jumpTo(position.maxScrollExtent > 60 ? 60 : position.maxScrollExtent);
    await tester.pump();
    final before = position.pixels;
    for (var i = 0; i < 5; i++) {
      goals = 10 + i;
      FreshReads.debugReportNewer(_teamPath, {'changed': goals});
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(ProfilePage.kProfileReloadGap);
    await tester.pump(ProfilePage.kProfileReloadGap);
    await tester.pumpAndSettle();
    expectNoDuplicates();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, before);
    // Debounced burst: far fewer reloads than newer values.
    expect(reads, lessThanOrEqualTo(3));
  });

  testWidgets('another team\'s newer lineups do not reload this profile',
      (tester) async {
    await pumpProfile(tester);
    final before = reads;
    FreshReads.debugReportNewer('Futsal/16/Line Ups/Tigers', {'x': 1});
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(ProfilePage.kProfileReloadGap);
    await tester.pumpAndSettle();
    expect(reads, before);
  });

  // Final round, item 1: a newer value that arrives DURING the first load
  // (before the career appears) is remembered: exactly one reload runs
  // right after the first commit, and the cache holds the reloaded career.
  group('first load', () {
    testWidgets(
        'a newer value before the first commit: the screen ends on '
        'the newer stats and the cache holds them', (tester) async {
      final bundleGate = Completer<void>();
      final base = sources();
      final gated = ProfileCareerSources(
        read: base.read,
        tournamentBundle: (id) async {
          await bundleGate.future; // phase 2 is still running
          return base.tournamentBundle(id);
        },
        afcSeasons: base.afcSeasons,
        afcRoster: base.afcRoster,
      );
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ProfilePage(
          uid: _uid,
          careerSources: gated,
          fantasySeams: FantasyProfileSeams(resolveSeason: () async => null),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(reads, 1, reason: 'the first load read the team (saved copy)');
      goals = 7; // the server's newer value
      FreshReads.debugReportNewer(_teamPath, {'changed': 7});
      await tester.pump(const Duration(milliseconds: 50));
      bundleGate.complete(); // first load commits with goals 3
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(ProfilePage.kProfileReloadGap);
      await tester.pumpAndSettle();
      expect(reads, 2, reason: 'exactly one reload after the first commit');
      expect(ProfilePage.debugShownLeagueGoals(), 7);
      expect(ProfilePage.debugCachedLeagueGoals(_uid), 7);
      expectNoDuplicates();
    });

    testWidgets('no newer value: no extra reload', (tester) async {
      await pumpProfile(tester);
      await tester.pump(ProfilePage.kProfileReloadGap);
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(ProfilePage.debugShownLeagueGoals(), 3);
    });
  });
}

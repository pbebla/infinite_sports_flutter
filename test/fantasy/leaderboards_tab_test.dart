// P3d — the Leaderboards tab proved with fake streams (no Firebase): single
// fade reveal; podium top-3 with ranked rows below; movement arrows on the
// Overall scope only; the signed-in manager's row PINNED to the bottom when
// its natural place is scrolled away and released when it scrolls into view;
// the Gameweek scope's week chips (1..N from the schedule) with per-week
// empty copy; the friendly empty state while the node is absent; and row
// taps opening the squad viewer (via the builder seam).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';

FantasyLeaderboardEntry entry(String uid, int points,
        {int? rank, int? movement}) =>
    FantasyLeaderboardEntry(
        uid: uid, points: points, rank: rank, movement: movement);

FantasyManager manager(String name) =>
    FantasyManager(teamName: name, nameFlagged: false);

List<Gameweek> gameweeks(int count) => [
      for (var i = 1; i <= count; i++)
        Gameweek(
          number: i,
          date: '0${i}012026',
          lockUtc: DateTime.utc(2026, i, 1, 23),
          opensUtc: null,
        ),
    ];

void main() {
  late StreamController<FantasyLeaderboards> boards;
  late StreamController<Map<String, FantasyManager>> managers;
  late StreamController<List<FantasyMiniLeague>> leagues;
  late StreamController<FantasySquad?> squads;
  late StreamController<Map<int, FantasyDreamTeam>> dreams;
  late List<LeaderboardRowData> openedRows;

  setUp(() {
    FantasyLeaderboardsTab.sessionScope = LeaderboardScope.overall;
    FantasyLeaderboardsTab.sessionWeek = null;
    FantasyLeaderboardsTab.profilesSession = null;
    DreamTeamCard.sessionWeek = null;
    boards = StreamController<FantasyLeaderboards>.broadcast();
    managers = StreamController<Map<String, FantasyManager>>.broadcast();
    leagues = StreamController<List<FantasyMiniLeague>>.broadcast();
    squads = StreamController<FantasySquad?>.broadcast();
    dreams = StreamController<Map<int, FantasyDreamTeam>>.broadcast();
    openedRows = [];
  });

  tearDown(() {
    boards.close();
    managers.close();
    leagues.close();
    squads.close();
    dreams.close();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    String selfUid = 'me',
    List<Gameweek>? weeks,
    Size size = const Size(420, 760),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyLeaderboardsTab(
          sport: 'Futsal',
          season: '15',
          configState: FantasyConfigState(
            config: FantasyConfig.futsalDefault(),
            lockOverride: FantasyLockOverride.open,
          ),
          players: const [],
          gameweeks: weeks ?? gameweeks(3),
          squadStates: squads.stream,
          leaderboardsStates: boards.stream,
          managersStates: managers.stream,
          miniLeaguesStates: leagues.stream,
          dreamTeamsStates: dreams.stream,
          loadProfiles: () async => {
            'u9': const PublicProfile(
                uid: 'u9', firstName: 'Fallback', lastName: 'Fran'),
          },
          selfUidOverride: selfUid,
          squadViewerBuilder: (row) {
            openedRows.add(row);
            return Scaffold(
                appBar: AppBar(), body: const Text('viewer page'));
          },
        ),
      ),
    ));
  }

  Future<void> emitAll(
    WidgetTester tester, {
    FantasyLeaderboards data = FantasyLeaderboards.empty,
    Map<String, FantasyManager> names = const {},
    List<FantasyMiniLeague> miniLeagues = const [],
    Map<int, FantasyDreamTeam> dreamTeams = const {},
  }) async {
    boards.add(data);
    managers.add(names);
    leagues.add(miniLeagues);
    dreams.add(dreamTeams);
    await tester.pumpAndSettle();
  }

  group('reveal + empty state', () {
    testWidgets('skeleton until every source lands, then ONE fade to the '
        'friendly empty state', (tester) async {
      await pumpTab(tester);
      expect(find.byKey(const ValueKey('leaderboards_skeleton')),
          findsOneWidget);

      boards.add(FantasyLeaderboards.empty);
      managers.add(const {});
      await tester.pump();
      // Leagues + dream teams + profiles haven't landed: still the skeleton.
      expect(find.byKey(const ValueKey('leaderboards_skeleton')),
          findsOneWidget);

      leagues.add(const []);
      dreams.add(const {});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leaderboards_ready')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboards_empty')), findsOneWidget);
      expect(find.text('Leaderboards light up after the first gameweek.'),
          findsOneWidget);
      // No DreamTeam node: the Team of the Week card is hidden entirely.
      expect(find.byKey(const ValueKey('dream_team_card')), findsNothing);
    });
  });

  group('dream team of the week (P6)', () {
    Map<int, FantasyDreamTeam> twoWeeks() => dreamTeamsFromNode({
          '1': {
            'Players': [
              {'name': 'Gale', 'position': 'GK', 'points': 9},
              {'name': 'Dana', 'position': 'DEF', 'points': 7},
              {'name': 'Yara', 'position': 'DEF', 'points': 6},
              {'name': 'Alex', 'position': 'ATT', 'points': 8},
              {'name': 'Wren', 'position': 'ATT', 'points': 5},
            ],
          },
          '2': {
            'Players': [
              {'name': 'Kit', 'position': 'GK', 'points': 14},
              {'name': 'Dana', 'position': 'DEF', 'points': 12},
              {'name': 'Yara', 'position': 'DEF', 'points': 9},
              {'name': 'Alex', 'position': 'ATT', 'points': 11},
              {'name': 'Bo', 'position': 'ATT', 'points': 8},
            ],
          },
        });

    testWidgets('card tops the Overall scroll on the latest week; the week '
        'chips step back through prior weeks', (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1},
          },
        }),
        names: {'u1': manager('Top Cats')},
        dreamTeams: twoWeeks(),
      );

      // Latest week (GW2) by default, above the board rows.
      expect(find.byKey(const ValueKey('dream_team_card')), findsOneWidget);
      expect(find.text('Team of the Week · GW2'), findsOneWidget);
      expect(find.text('Kit'), findsOneWidget);
      expect(find.text('14 pts'), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsOneWidget);

      // Step back to GW1.
      await tester.tap(find.byKey(const ValueKey('dream_week_1')));
      await tester.pumpAndSettle();
      expect(find.text('Team of the Week · GW1'), findsOneWidget);
      expect(find.text('Gale'), findsOneWidget);
      expect(find.text('9 pts'), findsOneWidget);
      expect(find.text('Kit'), findsNothing);
    });

    testWidgets('card shows above the friendly empty state when a DreamTeam '
        'exists before any board does', (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(tester, dreamTeams: twoWeeks());
      expect(find.byKey(const ValueKey('dream_team_card')), findsOneWidget);
      expect(find.text('Leaderboards light up after the first gameweek.'),
          findsOneWidget);
    });
  });

  group('overall scope', () {
    testWidgets('podium top-3 + ranked rows with movement arrows and names '
        'resolved Managers-first, profiles-fallback', (tester) async {
      await pumpTab(tester);
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1, 'movement': 1},
            'u2': {'points': 40, 'rank': 2, 'movement': -1},
            'u3': {'points': 30, 'rank': 3, 'movement': 0},
            'u9': {'points': 20, 'rank': 4},
          },
        }),
        names: {
          'u1': manager('Top Cats'),
          'u2': manager('Chasers'),
          'u3': manager('Thirds'),
        },
      );

      // Podium holds the top 3; the 4th is a ranked tile below.
      expect(find.byKey(const ValueKey('leaderboard_podium')), findsOneWidget);
      expect(find.byKey(const ValueKey('podium_u1')), findsOneWidget);
      expect(find.byKey(const ValueKey('podium_u3')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard_row_u9')), findsOneWidget);
      expect(find.text('Top Cats'), findsOneWidget);
      // u9 has no Managers entry: the PublicProfiles name steps in.
      expect(find.text('Fallback Fran'), findsOneWidget);

      // Movement arrows on the tile rows (u9 has no movement → neutral).
      final glyph =
          tester.widget<Text>(find.byKey(const ValueKey('movement_u9')));
      expect(glyph.data, '—');
    });

    testWidgets('own row pins to the bottom while scrolled away and releases '
        'when visible (FPL-style)', (tester) async {
      await pumpTab(tester, selfUid: 'u18');
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            for (var i = 1; i <= 20; i++)
              'u$i': {'points': 100 - i, 'rank': i},
          },
        }),
        names: {for (var i = 1; i <= 20; i++) 'u$i': manager('Team $i')},
      );

      // Rank 18 sits far below the viewport → pinned row shows.
      expect(find.byKey(const ValueKey('pinned_own_row')), findsOneWidget);

      // Scroll to the bottom: the natural row comes into view → pin releases.
      await tester.drag(
          find.byKey(const ValueKey('leaderboard_row_u5')),
          const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leaderboard_row_u18')), findsOneWidget);
      expect(find.byKey(const ValueKey('pinned_own_row')), findsNothing);
    });

    testWidgets('tapping a row opens that manager squad viewer', (tester) async {
      await pumpTab(tester);
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1},
            'u2': {'points': 40, 'rank': 2},
            'u3': {'points': 30, 'rank': 3},
            'u4': {'points': 20, 'rank': 4},
          },
        }),
        names: {for (var i = 1; i <= 4; i++) 'u$i': manager('Team $i')},
      );

      await tester.tap(find.byKey(const ValueKey('leaderboard_row_u4')));
      await tester.pumpAndSettle();
      expect(openedRows.single.uid, 'u4');
      expect(openedRows.single.name, 'Team 4');
      expect(find.text('viewer page'), findsOneWidget);

      // Podium spots open the viewer too.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('podium_u1')));
      await tester.pumpAndSettle();
      expect(openedRows.last.uid, 'u1');
    });
  });

  group('gameweek scope', () {
    testWidgets('week chips 1..N from the schedule; defaults to the latest '
        'scored week; unscored weeks get their own copy; no movement '
        'arrows', (tester) async {
      await pumpTab(tester);
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Gameweek': {
            '1': {
              'u1': {'points': 9, 'rank': 1},
              'u2': {'points': 7, 'rank': 2},
            },
            '2': {
              'u2': {'points': 11, 'rank': 1},
              'u1': {'points': 5, 'rank': 2},
            },
          },
        }),
        names: {'u1': manager('Alpha'), 'u2': manager('Beta')},
      );

      await tester.tap(find.text('Gameweek'));
      await tester.pumpAndSettle();

      // Chips for every scheduled gameweek, selection on the latest scored.
      for (var w = 1; w <= 3; w++) {
        expect(find.byKey(ValueKey('leaderboard_week_$w')), findsOneWidget);
      }
      expect(
          tester
              .widget<ChoiceChip>(
                  find.byKey(const ValueKey('leaderboard_week_2')))
              .selected,
          isTrue);
      // GW2's winner listed; no movement glyphs in this scope.
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byKey(const ValueKey('movement_u2')), findsNothing);

      // GW3 exists on the schedule but has no scores yet.
      await tester.tap(find.byKey(const ValueKey('leaderboard_week_3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leaderboard_week_unscored')),
          findsOneWidget);

      // The selection persists for the session (scope swap and back).
      await tester.tap(find.text('Overall'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gameweek'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ChoiceChip>(
                  find.byKey(const ValueKey('leaderboard_week_3')))
              .selected,
          isTrue);
    });
  });
}

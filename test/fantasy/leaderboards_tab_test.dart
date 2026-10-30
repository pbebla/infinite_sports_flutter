// P3d + round 3 (Task 8) — the Leaderboards tab proved with fake streams (no
// Firebase): single fade reveal; plain ranked rows (the podium is gone) with
// a movement cell on the Overall scope only (▲n green / ▼n red / — muted);
// two-line manager cells (real name, team name under it — team name alone
// when no real name exists); Overall + Gameweek are the only scopes (My
// Leagues hidden behind kShowMiniLeagues, a stale session scope falls back
// to Overall); the signed-in manager's row gold-highlighted and PINNED to the
// bottom when its natural place is scrolled away and released when it
// scrolls into view; the Gameweek scope's week chips (1..N from the
// schedule) with per-week empty copy; the friendly empty state while the node
// is absent; row taps opening the squad viewer (via the builder seam); and
// 360 px long names wrapping without overflow in light AND dark.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/mini_leagues_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
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
    void Function(String playerName)? onOpenPlayer,
    Map<String, PublicProfile>? profiles,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
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
          loadProfiles: () async =>
              profiles ??
              {
                'u9': const PublicProfile(
                    uid: 'u9', firstName: 'Fallback', lastName: 'Fran'),
              },
          selfUidOverride: selfUid,
          onOpenPlayer: onOpenPlayer,
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
      // Dream teams + profiles haven't landed: still the skeleton. (The
      // hidden mini-leagues feed is NOT a source any more — Task 8.)
      expect(find.byKey(const ValueKey('leaderboards_skeleton')),
          findsOneWidget);

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

    testWidgets('round 3: tapping a Team of the Week player opens his '
        'profile through the hub callback', (tester) async {
      final opened = <String>[];
      await pumpTab(tester,
          size: const Size(420, 1400), onOpenPlayer: opened.add);
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
      await tester.tap(find.byKey(const ValueKey('squad_chip_Kit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('squad_chip_Alex')));
      await tester.pumpAndSettle();
      expect(opened, ['Kit', 'Alex']);
      // The manager row still opens the squad viewer, not a profile.
      expect(openedRows, isEmpty);
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

  group('scopes (My Leagues hidden)', () {
    testWidgets('the segments are exactly Overall + Gameweek', (tester) async {
      await pumpTab(tester);
      await emitAll(tester);

      final segmented = tester.widget<SegmentedButton<LeaderboardScope>>(
          find.byKey(const ValueKey('leaderboard_scope')));
      expect(segmented.segments.map((s) => s.value),
          [LeaderboardScope.overall, LeaderboardScope.gameweek]);
      expect(find.text('Overall'), findsOneWidget);
      expect(find.text('Gameweek'), findsOneWidget);
      expect(find.text('My Leagues'), findsNothing);
    });

    testWidgets('the hidden mini-leagues feed is never subscribed to',
        (tester) async {
      expect(kShowMiniLeagues, isFalse);
      await pumpTab(tester);
      await emitAll(tester);
      expect(leagues.hasListener, isFalse);
    });

    testWidgets('a stale My Leagues session scope falls back to Overall',
        (tester) async {
      FantasyLeaderboardsTab.sessionScope = LeaderboardScope.leagues;
      await pumpTab(tester);
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1},
          },
        }),
        names: {'u1': manager('Top Cats')},
      );

      expect(find.byType(MiniLeaguesView), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsOneWidget);
      final segmented = tester.widget<SegmentedButton<LeaderboardScope>>(
          find.byKey(const ValueKey('leaderboard_scope')));
      expect(segmented.selected, {LeaderboardScope.overall});
    });
  });

  group('overall scope', () {
    testWidgets('no podium — every manager is a plain ranked row, ranks '
        'resolved in order', (tester) async {
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

      expect(find.byKey(const ValueKey('leaderboard_podium')), findsNothing);
      for (final uid in ['u1', 'u2', 'u3', 'u9']) {
        expect(find.byKey(ValueKey('podium_$uid')), findsNothing);
        expect(find.byKey(ValueKey('leaderboard_row_$uid')), findsOneWidget);
      }
      expect(find.text('Top Cats'), findsOneWidget);
      // u9 has no Managers entry: the PublicProfiles name steps in.
      expect(find.text('Fallback Fran'), findsOneWidget);
      // Rank numbers 1..4, in the row order.
      final ys = [
        for (final uid in ['u1', 'u2', 'u3', 'u9'])
          tester.getTopLeft(find.byKey(ValueKey('leaderboard_row_$uid'))).dy
      ];
      expect(ys, [...ys]..sort());
      for (final rank in ['1', '2', '3', '4']) {
        expect(find.text(rank), findsOneWidget);
      }
    });

    for (final brightness in Brightness.values) {
      testWidgets('movement cell: ▲n green, ▼n red, — muted (0 and absent '
          'both show —) — $brightness', (tester) async {
        await pumpTab(tester, brightness: brightness);
        await emitAll(
          tester,
          data: leaderboardsFromNode({
            'Overall': {
              'u1': {'points': 50, 'rank': 1, 'movement': 2},
              'u2': {'points': 40, 'rank': 2, 'movement': -1},
              'u3': {'points': 30, 'rank': 3, 'movement': 0},
              'u4': {'points': 20, 'rank': 4},
            },
          }),
          names: {for (var i = 1; i <= 4; i++) 'u$i': manager('Team $i')},
        );

        Text cell(String uid) =>
            tester.widget<Text>(find.byKey(ValueKey('movement_$uid')));
        final context =
            tester.element(find.byKey(const ValueKey('leaderboard_row_u1')));
        final scheme = Theme.of(context).colorScheme;

        expect(cell('u1').data, '▲2');
        expect(cell('u1').style!.color, fantasyPitchGreen(context));
        expect(cell('u2').data, '▼1');
        expect(cell('u2').style!.color, scheme.error);
        expect(cell('u3').data, '—');
        expect(cell('u3').style!.color, scheme.onSurfaceVariant);
        expect(cell('u4').data, '—');
        expect(cell('u4').style!.color, scheme.onSurfaceVariant);
      });
    }

    testWidgets('two-line manager cell: the real name on top, the team name '
        'UNDER it', (tester) async {
      await pumpTab(tester, profiles: {
        'u1': const PublicProfile(uid: 'u1', firstName: 'Zoe', lastName: 'Park'),
      });
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1, 'movement': 1},
          },
        }),
        names: {'u1': manager('Top Cats')},
      );

      final real = find.byKey(const ValueKey('leaderboard_name_u1'));
      final team = find.byKey(const ValueKey('leaderboard_team_u1'));
      expect(tester.widget<Text>(real).data, 'Zoe Park');
      expect(tester.widget<Text>(team).data, 'Top Cats');
      // Same column, team name below the real name.
      expect(tester.getTopLeft(team).dx, tester.getTopLeft(real).dx);
      expect(tester.getTopLeft(team).dy, greaterThan(tester.getBottomLeft(real).dy - 1));
    });

    testWidgets('Review Focus 5: fake managers (a team name, NO PublicProfiles '
        'entry) show the team name alone — one line', (tester) async {
      await pumpTab(tester, profiles: const {});
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'test-01': {'points': 50, 'rank': 1},
          },
        }),
        names: {'test-01': manager('Fake FC 1')},
      );

      expect(find.byKey(const ValueKey('leaderboard_name_test-01')),
          findsOneWidget);
      expect(tester
          .widget<Text>(find.byKey(const ValueKey('leaderboard_name_test-01')))
          .data, 'Fake FC 1');
      expect(find.byKey(const ValueKey('leaderboard_team_test-01')),
          findsNothing);
      expect(find.text('Unnamed manager'), findsNothing);
    });

    testWidgets('a FLAGGED team name never shows — the real name stands '
        'alone; flagged with no profile → "Unnamed manager"', (tester) async {
      await pumpTab(tester, profiles: {
        'u1': const PublicProfile(uid: 'u1', firstName: 'Pat', lastName: 'Lee'),
      });
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1},
            'u2': {'points': 40, 'rank': 2},
          },
        }),
        names: {
          'u1': const FantasyManager(teamName: 'Rude FC', nameFlagged: true),
          'u2': const FantasyManager(teamName: 'Rude FC 2', nameFlagged: true),
        },
      );

      expect(find.text('Pat Lee'), findsOneWidget);
      expect(find.text('Unnamed manager'), findsOneWidget);
      expect(find.textContaining('Rude FC'), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_team_u1')), findsNothing);
    });

    testWidgets('the signed-in manager\'s row is gold-highlighted; the '
        'others are not', (tester) async {
      await pumpTab(tester, selfUid: 'u2');
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1},
            'u2': {'points': 40, 'rank': 2},
          },
        }),
        names: {'u1': manager('Top Cats'), 'u2': manager('Chasers')},
      );

      Color? fill(String uid) => tester
          .widget<Material>(find
              .ancestor(
                  of: find.byKey(ValueKey('leaderboard_row_$uid')),
                  matching: find.byType(Material))
              .first)
          .color;
      expect(fill('u1'), Colors.transparent);
      final context =
          tester.element(find.byKey(const ValueKey('leaderboard_row_u2')));
      final accent = fantasyAccent(context);
      expect(fill('u2')!.withValues(alpha: 1), accent.withValues(alpha: 1));
      expect(fill('u2')!.a, greaterThan(0.1));
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

      // The top three open the viewer too (they are plain rows now).
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('leaderboard_row_u1')));
      await tester.pumpAndSettle();
      expect(openedRows.last.uid, 'u1');
    });
  });

  group('Review Focus 4 — 360 px, long names wrap, never overflow', () {
    const longReal = 'Maximiliano Bartholomew Featherstonehaugh-Smythe';
    const longTeam = 'The Unbelievably Long Team Name Football Club Of Doom';

    for (final brightness in Brightness.values) {
      testWidgets('two-line cells (rows + the pinned own row) wrap — '
          '$brightness', (tester) async {
        await pumpTab(
          tester,
          selfUid: 'u18',
          size: const Size(360, 760),
          brightness: brightness,
          profiles: {
            'u1': const PublicProfile(
                uid: 'u1', firstName: 'Maximiliano', lastName: 'Bartholomew '
                    'Featherstonehaugh-Smythe'),
            'u2': const PublicProfile(uid: 'u2', firstName: 'Zoe', lastName: 'Park'),
            'u18': const PublicProfile(
                uid: 'u18', firstName: 'Maximiliano', lastName: 'Bartholomew '
                    'Featherstonehaugh-Smythe'),
          },
        );
        await emitAll(
          tester,
          data: leaderboardsFromNode({
            'Overall': {
              'u1': {'points': 1234, 'rank': 1, 'movement': 12},
              'u2': {'points': 1200, 'rank': 2, 'movement': -10},
              'u3': {'points': 1100, 'rank': 3},
              for (var i = 4; i <= 20; i++)
                'u$i': {'points': 1000 - i, 'rank': i, 'movement': i % 3 - 1},
            },
          }),
          names: {
            'u1': manager(longTeam),
            'u2': manager(longTeam),
            // A long team name with NO real name: the single line wraps too.
            'u3': manager(longTeam),
            for (var i = 4; i <= 20; i++) 'u$i': manager('Team $i'),
            'u18': manager(longTeam),
          },
        );

        // Own row rank 18 is far off-screen → the pinned tile renders too.
        expect(find.byKey(const ValueKey('pinned_own_row')), findsOneWidget);
        expect(tester.takeException(), isNull);

        for (final key in ['leaderboard_name_u1', 'leaderboard_team_u1']) {
          final text = tester.widget<Text>(find.byKey(ValueKey(key)));
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(text.maxLines, isNull);
        }
        // Both long lines took more than one line (wrapped, not clipped).
        expect(
            tester.getSize(find.byKey(const ValueKey('leaderboard_name_u1'))).height,
            greaterThan(36));
        expect(
            tester.getSize(find.byKey(const ValueKey('leaderboard_team_u1'))).height,
            greaterThan(30));
        expect(find.text(longReal), findsWidgets);
        expect(find.text(longTeam), findsWidgets);
        // The row stays inside the 360 px viewport.
        final rowBox = tester.getRect(find.byKey(const ValueKey('leaderboard_row_u1')));
        expect(rowBox.left, greaterThanOrEqualTo(0));
        expect(rowBox.right, lessThanOrEqualTo(360));
      });
    }
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

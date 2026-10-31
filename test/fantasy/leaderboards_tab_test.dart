// P3d + round 3 (Task 8) + the follow-up split — the Leaderboards tab proved
// with fake streams (no Firebase): single fade reveal; plain ranked rows (the
// podium is gone) with a movement cell on the Overall scope only (▲n green /
// ▼n red / — muted); two-line manager cells (real name, team name under it —
// team name alone when no real name exists); THREE scopes — Overall,
// Gameweek, Team of the week (My Leagues hidden behind kShowMiniLeagues, a
// stale session scope falls back to Overall); the Team of the Week card lives
// ONLY in its own scope (never above the Overall / Gameweek lists) and the
// selected week carries between Gameweek and Team of the week; the signed-in
// manager's row gold-highlighted and PINNED to the bottom when its natural
// place is scrolled away and released when it scrolls into view; the
// Gameweek scope's week chips (1..N from the schedule) with per-week empty
// copy; the friendly empty states; row taps opening the squad viewer (via the
// builder seam); and 360 px long names + segment labels fitting in light AND
// dark.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/mini_leagues_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rank_history_chart.dart';
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

/// The test environment draws every glyph as a 14 px Ahem square, which says
/// nothing about whether a label really fits. This registers the SDK's real
/// Roboto (the Android UI font) as 'RobotoReal' so a test can opt into true
/// text metrics without disturbing the Ahem-based layouts elsewhere in the
/// file. Returns false when the SDK's material_fonts folder can't be found.
const String kRealFont = 'RobotoReal';
bool? _realFontLoaded;

Directory? _materialFontsDir() {
  final candidates = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) candidates.add('$root/bin/cache/artifacts/material_fonts');
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    candidates.add('${dir.path}/material_fonts');
    dir = dir.parent;
  }
  for (final path in candidates) {
    final d = Directory(path);
    if (File('${d.path}/roboto-regular.ttf').existsSync()) return d;
  }
  return null;
}

Future<bool> loadRealFont() async {
  if (_realFontLoaded != null) return _realFontLoaded!;
  final dir = _materialFontsDir();
  if (dir == null) return _realFontLoaded = false;
  final loader = FontLoader(kRealFont);
  for (final file in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    final bytes = File('${dir.path}/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  return _realFontLoaded = true;
}

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
    String? fontFamily,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness, fontFamily: fontFamily),
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

  /// Taps one of the three scope segments by its label.
  Future<void> pickScope(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('leaderboard_scope')),
        matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  final overallData = leaderboardsFromNode({
    'Overall': {
      'u1': {'points': 50, 'rank': 1},
    },
  });

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

  group('Team of the week scope (P6, split out of the lists)', () {
    testWidgets('Overall and Gameweek do NOT contain the card; the Team of '
        'the week view does — and ONLY the card', (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1},
          },
          'Gameweek': {
            '2': {
              'u1': {'points': 11, 'rank': 1},
            },
          },
        }),
        names: {'u1': manager('Top Cats')},
        dreamTeams: twoWeeks(),
      );

      // Overall (the default scope): the list, no card.
      expect(find.byKey(const ValueKey('dream_team_card')), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard_column_header')),
          findsOneWidget);

      // Gameweek: week chips + that week's ranking, no card.
      await pickScope(tester, 'Gameweek');
      expect(find.byKey(const ValueKey('dream_team_card')), findsNothing);
      expect(find.text('Team of the Week · GW2'), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_week_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsOneWidget);

      // Team of the week: the card on the latest week, no list at all.
      await pickScope(tester, kTeamOfWeekSegmentLabel);
      expect(find.byKey(const ValueKey('dream_team_card')), findsOneWidget);
      expect(find.text('Team of the Week · GW2'), findsOneWidget);
      expect(find.text('Kit'), findsOneWidget);
      expect(find.text('14 pts'), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_column_header')),
          findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_week_2')), findsNothing);

      // And back: Overall is exactly the list again.
      await pickScope(tester, 'Overall');
      expect(find.byKey(const ValueKey('dream_team_card')), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsOneWidget);
    });

    testWidgets("the card's own week chips step back through prior weeks",
        (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(
        tester,
        data: overallData,
        names: {'u1': manager('Top Cats')},
        dreamTeams: twoWeeks(),
      );
      await pickScope(tester, kTeamOfWeekSegmentLabel);

      expect(find.text('Team of the Week · GW2'), findsOneWidget);

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
        data: overallData,
        names: {'u1': manager('Top Cats')},
        dreamTeams: twoWeeks(),
      );
      await pickScope(tester, kTeamOfWeekSegmentLabel);
      await tester.tap(find.byKey(const ValueKey('squad_chip_Kit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('squad_chip_Alex')));
      await tester.pumpAndSettle();
      expect(opened, ['Kit', 'Alex']);
      // Never the manager squad viewer from this view.
      expect(openedRows, isEmpty);
    });

    testWidgets('the card shows in its own scope even when no board exists '
        'yet — and the other scopes show only their empty state',
        (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(tester, dreamTeams: twoWeeks());

      // Overall: the friendly empty state, NOT the card.
      expect(find.byKey(const ValueKey('leaderboards_empty')), findsOneWidget);
      expect(find.text('Leaderboards light up after the first gameweek.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('dream_team_card')), findsNothing);

      await pickScope(tester, kTeamOfWeekSegmentLabel);
      expect(find.byKey(const ValueKey('dream_team_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('dream_team_empty')), findsNothing);
      expect(find.byKey(const ValueKey('leaderboards_empty')), findsNothing);
    });

    testWidgets('no DreamTeam yet: the Team of the week view shows a '
        'friendly one-liner (no card, no leaderboard copy)', (tester) async {
      await pumpTab(tester);
      await emitAll(
        tester,
        data: overallData,
        names: {'u1': manager('Top Cats')},
      );
      await pickScope(tester, kTeamOfWeekSegmentLabel);

      expect(find.byKey(const ValueKey('dream_team_empty')), findsOneWidget);
      expect(find.text('Team of the Week appears once Gameweek 1 is scored.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('dream_team_card')), findsNothing);
      expect(find.text('Leaderboards light up after the first gameweek.'),
          findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('the empty copy wraps and fits at 360 px — $brightness',
          (tester) async {
        await pumpTab(tester,
            size: const Size(360, 760), brightness: brightness);
        await emitAll(tester, data: overallData, names: {'u1': manager('A')});
        await pickScope(tester, kTeamOfWeekSegmentLabel);
        expect(find.byKey(const ValueKey('dream_team_empty')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the card fits at 360 px with no overflow — $brightness',
          (tester) async {
        await pumpTab(tester,
            size: const Size(360, 760), brightness: brightness);
        await emitAll(
          tester,
          data: overallData,
          names: {'u1': manager('A')},
          dreamTeams: twoWeeks(),
        );
        await pickScope(tester, kTeamOfWeekSegmentLabel);
        expect(find.byKey(const ValueKey('dream_team_card')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('week sync between Gameweek and Team of the week', () {
    /// A full five-man dream team for each week, named after the week.
    Map<int, FantasyDreamTeam> dreamWeeks(List<int> weeks) =>
        dreamTeamsFromNode({
          for (final w in weeks)
            '$w': {
              'Players': [
                {'name': 'Keeper$w', 'position': 'GK', 'points': 10 + w},
                {'name': 'DefA$w', 'position': 'DEF', 'points': 9},
                {'name': 'DefB$w', 'position': 'DEF', 'points': 8},
                {'name': 'AttA$w', 'position': 'ATT', 'points': 7},
                {'name': 'AttB$w', 'position': 'ATT', 'points': 6},
              ],
            },
        });

    final threeScoredWeeks = leaderboardsFromNode({
      'Overall': {
        'u1': {'points': 50, 'rank': 1},
      },
      'Gameweek': {
        for (var w = 1; w <= 3; w++)
          '$w': {
            'u1': {'points': 10 * w, 'rank': 1},
          },
      },
    });

    bool chipSelected(WidgetTester tester, String key) =>
        tester.widget<ChoiceChip>(find.byKey(ValueKey(key))).selected;

    testWidgets('Gameweek GW2 -> Team of the week opens on GW2 (not the '
        'latest, GW3)', (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(
        tester,
        data: threeScoredWeeks,
        names: {'u1': manager('Top Cats')},
        dreamTeams: dreamWeeks([1, 2, 3]),
      );

      await pickScope(tester, 'Gameweek');
      await tester.tap(find.byKey(const ValueKey('leaderboard_week_2')));
      await tester.pumpAndSettle();
      expect(chipSelected(tester, 'leaderboard_week_2'), isTrue);

      await pickScope(tester, kTeamOfWeekSegmentLabel);
      expect(find.text('Team of the Week · GW2'), findsOneWidget);
      expect(find.text('Keeper2'), findsOneWidget);
      expect(chipSelected(tester, 'dream_week_2'), isTrue);
    });

    testWidgets('Team of the week GW1 -> Gameweek opens on GW1 (not the '
        'latest scored week)', (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(
        tester,
        data: threeScoredWeeks,
        names: {'u1': manager('Top Cats')},
        dreamTeams: dreamWeeks([1, 2, 3]),
      );

      await pickScope(tester, kTeamOfWeekSegmentLabel);
      expect(find.text('Team of the Week · GW3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dream_week_1')));
      await tester.pumpAndSettle();
      expect(find.text('Team of the Week · GW1'), findsOneWidget);

      await pickScope(tester, 'Gameweek');
      expect(chipSelected(tester, 'leaderboard_week_1'), isTrue);
      expect(chipSelected(tester, 'leaderboard_week_3'), isFalse);
      // GW1's own ranking shows (u1 scored 10 that week).
      expect(find.text('10 pts'), findsOneWidget);
    });

    testWidgets("a week the target view does not have leaves the target's "
        'own selection alone', (tester) async {
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(
        tester,
        data: threeScoredWeeks,
        names: {'u1': manager('Top Cats')},
        // Dream teams only through GW2.
        dreamTeams: dreamWeeks([1, 2]),
      );

      // Gameweek GW3 has no Team of the Week -> the card stays on its latest.
      await pickScope(tester, 'Gameweek');
      await tester.tap(find.byKey(const ValueKey('leaderboard_week_3')));
      await tester.pumpAndSettle();
      await pickScope(tester, kTeamOfWeekSegmentLabel);
      expect(find.text('Team of the Week · GW2'), findsOneWidget);

      // The card steps back to GW1, then to Gameweek: GW1 carries over.
      await tester.tap(find.byKey(const ValueKey('dream_week_1')));
      await tester.pumpAndSettle();
      await pickScope(tester, 'Gameweek');
      expect(chipSelected(tester, 'leaderboard_week_1'), isTrue);

      // Gameweek picks GW3 again (the card has none): GW1 stays on the card.
      await tester.tap(find.byKey(const ValueKey('leaderboard_week_3')));
      await tester.pumpAndSettle();
      await pickScope(tester, kTeamOfWeekSegmentLabel);
      expect(find.text('Team of the Week · GW1'), findsOneWidget);
    });
  });

  group('scopes (My Leagues hidden)', () {
    testWidgets('the segments are exactly Overall + Gameweek + Team of the '
        'week', (tester) async {
      await pumpTab(tester);
      await emitAll(tester);

      final segmented = tester.widget<SegmentedButton<LeaderboardScope>>(
          find.byKey(const ValueKey('leaderboard_scope')));
      expect(segmented.segments.map((s) => s.value), [
        LeaderboardScope.overall,
        LeaderboardScope.gameweek,
        LeaderboardScope.teamOfWeek,
      ]);
      expect(find.text('Overall'), findsOneWidget);
      expect(find.text('Gameweek'), findsOneWidget);
      expect(find.text(kTeamOfWeekSegmentLabel), findsOneWidget);
      expect(find.text('My Leagues'), findsNothing);
    });

    // Real Roboto metrics (see loadRealFont): the three segments are equal
    // width (336 / 3 = 112 px at 360, minus padding), so a label that is too
    // long wraps to a second line on a real phone even though the Ahem test
    // font can't show it.
    for (final brightness in Brightness.values) {
      testWidgets('all three labels sit on ONE line, untruncated, at 360 px '
          'with real Roboto metrics — $brightness', (tester) async {
        if (!await loadRealFont()) {
          markTestSkipped('Flutter SDK material_fonts (Roboto) not found');
          return;
        }
        await pumpTab(tester,
            size: const Size(360, 760),
            brightness: brightness,
            fontFamily: kRealFont);
        await emitAll(tester);

        final bar =
            tester.getRect(find.byKey(const ValueKey('leaderboard_scope')));
        double? oneLine;
        for (final label in ['Overall', 'Gameweek', kTeamOfWeekSegmentLabel]) {
          final paragraph = tester.renderObject<RenderParagraph>(find
              .descendant(
                  of: find.text(label), matching: find.byType(RichText)));
          // The real font is actually in use (not the Ahem 14 px/glyph box).
          expect(paragraph.size.width, lessThan(label.length * 14.0 - 10),
              reason: 'still measuring with the Ahem test font');
          // Untruncated: it got its full natural width (an ellipsized or
          // wrapped label would be narrower than its max intrinsic width).
          final needed = paragraph.getMaxIntrinsicWidth(double.infinity);
          expect(paragraph.size.width, greaterThanOrEqualTo(needed - 0.01),
              reason: '$label was squeezed');
          // ...with a few px to spare, so a slightly wider system font (iOS
          // SF) can't tip it onto a second line.
          final available = paragraph.constraints.maxWidth;
          expect(available - needed, greaterThanOrEqualTo(4),
              reason: '$label has under 4 px to spare '
                  '(needs $needed of $available)');
          // One line: the same height as the others (a single text line).
          oneLine ??= paragraph.size.height;
          expect(paragraph.size.height, oneLine, reason: '$label wrapped');
          // And inside the segmented control, inside the screen.
          final box = tester.getRect(find.text(label));
          expect(box.left, greaterThanOrEqualTo(bar.left));
          expect(box.right, lessThanOrEqualTo(bar.right));
          expect(box.right, lessThanOrEqualTo(360));
        }
        expect(oneLine, lessThan(24));
        expect(tester.takeException(), isNull);
      });
    }

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
        dreamTeams: twoWeeks(),
      );

      expect(find.byType(MiniLeaguesView), findsNothing);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsOneWidget);
      // Overall, with no card above it.
      expect(find.byKey(const ValueKey('dream_team_card')), findsNothing);
      final segmented = tester.widget<SegmentedButton<LeaderboardScope>>(
          find.byKey(const ValueKey('leaderboard_scope')));
      expect(segmented.selected, {LeaderboardScope.overall});
    });

    testWidgets('a persisted Team of the week scope restores that view',
        (tester) async {
      FantasyLeaderboardsTab.sessionScope = LeaderboardScope.teamOfWeek;
      await pumpTab(tester, size: const Size(420, 1400));
      await emitAll(
        tester,
        data: overallData,
        names: {'u1': manager('Top Cats')},
        dreamTeams: twoWeeks(),
      );
      expect(find.byKey(const ValueKey('dream_team_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard_row_u1')), findsNothing);
      final segmented = tester.widget<SegmentedButton<LeaderboardScope>>(
          find.byKey(const ValueKey('leaderboard_scope')));
      expect(segmented.selected, {LeaderboardScope.teamOfWeek});
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
        expect(cell('u2').style!.color, fantasyDownRed(context));
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

  // ── Leaderboard extras (follow-up): your rank this season, biggest
  // climber / faller badges, the Gameweek week summary. ──────────────────

  final fourNames = {
    'u1': manager('Top Cats'),
    'me': manager('My Team'),
    'u3': manager('Thirds'),
    'u4': manager('Fourths'),
  };

  FantasyLeaderboards overallWith(Map<String, Object?>? history,
          {Map<String, Object?>? gameweek}) =>
      leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 90, 'rank': 1, 'movement': 1},
          'me': {'points': 80, 'rank': 2, 'movement': 2},
          'u3': {'points': 70, 'rank': 3, 'movement': -1},
          'u4': {'points': 60, 'rank': 4, 'movement': -2},
        },
        if (gameweek != null) 'Gameweek': gameweek,
        if (history != null) 'RankHistory': history,
      });

  Finder byKey(String key) => find.byKey(ValueKey(key));

  group('extra 1 — your rank this season (own row, Overall)', () {
    testWidgets('tapping YOUR row expands "Your rank this season" — the line '
        'chart and "#start → #now" — instead of the viewer; tapping again '
        'folds it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpTab(tester, size: const Size(420, 1000));
      await emitAll(
        tester,
        data: overallWith({
          'me': {'1': 14, '2': 12, '3': 10},
        }),
        names: fourNames,
      );
      expect(byKey('rank_history_panel'), findsNothing);

      await tester.tap(byKey('leaderboard_row_me'));
      await tester.pumpAndSettle();
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(find.text('Your rank this season'), findsOneWidget);
      expect(byKey('rank_history_chart'), findsOneWidget);
      expect(find.text('#14 → #10'), findsOneWidget);
      expect(byKey('rank_history_note'), findsNothing);
      expect(find.bySemanticsLabel('Your rank by gameweek: GW1 #14, GW2 #12, '
          'GW3 #10'), findsOneWidget);
      // Rank 1 at the top: the best rank's axis label sits above the worst;
      // the gameweeks run left to right.
      expect(tester.getTopLeft(find.text('#10')).dy,
          lessThan(tester.getTopLeft(find.text('#14')).dy));
      expect(tester.getTopLeft(find.text('GW1')).dx,
          lessThan(tester.getTopLeft(find.text('GW3')).dx));
      // The panel opens UNDER the own row, inside its highlight.
      expect(tester.getTopLeft(byKey('rank_history_panel')).dy,
          greaterThanOrEqualTo(
              tester.getBottomLeft(byKey('leaderboard_row_me')).dy - 0.5));
      // The squad viewer did NOT open.
      expect(openedRows, isEmpty);
      expect(find.text('viewer page'), findsNothing);

      await tester.tap(byKey('leaderboard_row_me'));
      await tester.pumpAndSettle();
      expect(byKey('rank_history_panel'), findsNothing);
      expect(openedRows, isEmpty);
      semantics.dispose();
    });

    testWidgets('"View team" inside the panel still opens your own squad '
        'viewer', (tester) async {
      await pumpTab(tester, size: const Size(420, 1000));
      await emitAll(
        tester,
        data: overallWith({
          'me': {'1': 3, '2': 2},
        }),
        names: fourNames,
      );
      await tester.tap(byKey('leaderboard_row_me'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('rank_history_view_team'));
      await tester.pumpAndSettle();
      expect(openedRows.single.uid, 'me');
      expect(openedRows.single.isSelf, isTrue);
      expect(find.text('viewer page'), findsOneWidget);
    });

    for (final (label, history) in [
      ('one week of history', <String, Object?>{
        'me': {'1': 4},
      }),
      ('no RankHistory at all', null),
    ]) {
      testWidgets('under two weeks ($label): a short muted note instead of a '
          'chart', (tester) async {
        await pumpTab(tester, size: const Size(420, 1000));
        await emitAll(tester, data: overallWith(history), names: fourNames);
        await tester.tap(byKey('leaderboard_row_me'));
        await tester.pumpAndSettle();

        expect(byKey('rank_history_panel'), findsOneWidget);
        expect(find.text('Your rank this season'), findsOneWidget);
        expect(byKey('rank_history_chart'), findsNothing);
        expect(find.textContaining('→'), findsNothing);
        final note = tester.widget<Text>(byKey('rank_history_note'));
        expect(note.data, kRankHistoryNote);
        final context = tester.element(byKey('rank_history_note'));
        expect(note.style!.color,
            Theme.of(context).colorScheme.onSurfaceVariant);
        // View team stays available.
        expect(byKey('rank_history_view_team'), findsOneWidget);
      });
    }

    testWidgets("other managers' rows still open their squad viewer; the "
        "Gameweek view's own row still opens yours", (tester) async {
      await pumpTab(tester, size: const Size(420, 1000));
      await emitAll(
        tester,
        data: overallWith(
          {
            'me': {'1': 3, '2': 2},
          },
          gameweek: {
            '1': {
              'u1': {'points': 20, 'rank': 1},
              'me': {'points': 10, 'rank': 2},
            },
          },
        ),
        names: fourNames,
      );

      await tester.tap(byKey('leaderboard_row_u3'));
      await tester.pumpAndSettle();
      expect(openedRows.single.uid, 'u3');
      expect(find.text('viewer page'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(byKey('rank_history_panel'), findsNothing);

      await pickScope(tester, 'Gameweek');
      await tester.tap(byKey('leaderboard_row_me'));
      await tester.pumpAndSettle();
      expect(openedRows.last.uid, 'me');
      expect(byKey('rank_history_panel'), findsNothing);
    });

    testWidgets('the PINNED copy of your row expands too', (tester) async {
      await pumpTab(tester, selfUid: 'u18');
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            for (var i = 1; i <= 20; i++)
              'u$i': {'points': 100 - i, 'rank': i},
          },
          'RankHistory': {
            'u18': {'1': 20, '2': 18},
          },
        }),
        names: {for (var i = 1; i <= 20; i++) 'u$i': manager('Team $i')},
      );
      final pinned = byKey('pinned_own_row');
      expect(pinned, findsOneWidget);

      await tester.tap(find.descendant(
          of: pinned, matching: byKey('leaderboard_row_u18')));
      await tester.pumpAndSettle();
      expect(
          find.descendant(of: pinned, matching: byKey('rank_history_panel')),
          findsOneWidget);
      expect(find.descendant(of: pinned, matching: find.text('#20 → #18')),
          findsOneWidget);
      expect(openedRows, isEmpty);
      expect(tester.takeException(), isNull);
    });

    test('chart geometry: rank 1 at the top, gameweeks left to right', () {
      final points = rankChartOffsets(
        [
          (gameweek: 1, rank: 14),
          (gameweek: 2, rank: 12),
          (gameweek: 4, rank: 10),
        ],
        const Size(200, 100),
        inset: 6,
      );
      // First week: worst rank (14) at the bottom-left.
      expect(points.first, const Offset(6, 94));
      // Latest week: best rank (10) at the top-right.
      expect(points.last, const Offset(194, 6));
      // GW2 sits a third of the way (weeks 1..4), rank 12 half-way down.
      expect(points[1].dx, closeTo(6 + 188 / 3, 1e-9));
      expect(points[1].dy, 50);
      // A flat line (same rank every week) runs through the middle.
      final flat = rankChartOffsets(
          [(gameweek: 1, rank: 3), (gameweek: 2, rank: 3)],
          const Size(100, 60),
          inset: 5);
      expect(flat.map((o) => o.dy), [30, 30]);
    });
  });

  group('extra 2 — biggest climber / faller badges (Overall)', () {
    final movers = leaderboardsFromNode({
      'Overall': {
        'u1': {'points': 50, 'rank': 1, 'movement': 3},
        'u2': {'points': 45, 'rank': 2, 'movement': 3},
        'u3': {'points': 40, 'rank': 3, 'movement': -2},
        'u4': {'points': 35, 'rank': 4, 'movement': -4},
        'u5': {'points': 30, 'rank': 5},
      },
      'Gameweek': {
        '1': {
          for (var i = 1; i <= 5; i++) 'u$i': {'points': 10 - i, 'rank': i},
        },
      },
    });
    final fiveNames = {for (var i = 1; i <= 5; i++) 'u$i': manager('Team $i')};

    for (final brightness in Brightness.values) {
      testWidgets('flame on the (tied) biggest climbers, down badge on the '
          'biggest drop, with semantics + tooltips — $brightness',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpTab(tester, brightness: brightness);
        await emitAll(tester, data: movers, names: fiveNames);

        for (final uid in ['u1', 'u2']) {
          expect(byKey('climber_badge_$uid'), findsOneWidget);
          expect(byKey('faller_badge_$uid'), findsNothing);
        }
        expect(byKey('faller_badge_u4'), findsOneWidget);
        expect(byKey('climber_badge_u4'), findsNothing);
        for (final uid in ['u3', 'u5']) {
          expect(byKey('climber_badge_$uid'), findsNothing);
          expect(byKey('faller_badge_$uid'), findsNothing);
        }

        expect(find.bySemanticsLabel('Biggest climber this week (▲3)'),
            findsNWidgets(2));
        expect(find.bySemanticsLabel('Biggest drop this week (▼4)'),
            findsOneWidget);
        expect(find.byTooltip('Biggest climber this week (▲3)'),
            findsNWidgets(2));
        expect(find.byTooltip('Biggest drop this week (▼4)'), findsOneWidget);

        final context = tester.element(byKey('leaderboard_row_u1'));
        Icon icon(String key) => tester.widget<Icon>(
            find.descendant(of: byKey(key), matching: find.byType(Icon)));
        expect(icon('climber_badge_u1').icon, Icons.local_fire_department);
        expect(icon('climber_badge_u1').color, fantasyFlameOrange(context));
        expect(icon('faller_badge_u4').icon, Icons.trending_down);
        expect(icon('faller_badge_u4').color, fantasyDownRed(context));
        // The flame never borrows the "down" red.
        expect(fantasyFlameOrange(context), isNot(fantasyDownRed(context)));

        // Beside the manager name (same line, to its right).
        final name = tester.getRect(byKey('leaderboard_name_u1'));
        final badge = tester.getRect(byKey('climber_badge_u1'));
        expect(badge.left, greaterThanOrEqualTo(name.right - 0.5));
        expect(badge.center.dy, inInclusiveRange(name.top, name.bottom));
        semantics.dispose();
      });
    }

    testWidgets('no badges when nobody moved; never on the Gameweek view',
        (tester) async {
      await pumpTab(tester);
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1, 'movement': 0},
            'u2': {'points': 40, 'rank': 2},
          },
        }),
        names: fiveNames,
      );
      for (final uid in ['u1', 'u2']) {
        expect(byKey('climber_badge_$uid'), findsNothing);
        expect(byKey('faller_badge_$uid'), findsNothing);
      }

      boards.add(movers);
      await tester.pumpAndSettle();
      expect(byKey('climber_badge_u1'), findsOneWidget);
      await pickScope(tester, 'Gameweek');
      for (var i = 1; i <= 5; i++) {
        expect(byKey('climber_badge_u$i'), findsNothing);
        expect(byKey('faller_badge_u$i'), findsNothing);
      }
    });
  });

  group('extra 3 — Gameweek week summary', () {
    final weeks = leaderboardsFromNode({
      'Overall': {
        'a': {'points': 106, 'rank': 1},
      },
      'Gameweek': {
        '1': {
          'a': {'points': 96, 'rank': 1},
          'me': {'points': 52, 'rank': 2},
          'b': {'points': 45, 'rank': 3},
          'd': {'points': 0, 'rank': 4},
        },
        '2': {
          'b': {'points': 20, 'rank': 1},
          'a': {'points': 10, 'rank': 2},
        },
      },
    });
    final summaryNames = {
      'a': manager('Sweeper Keepers'),
      'b': manager('Mid Table Mafia'),
      'me': manager('My Team'),
      'd': manager('Bench Warmers United'),
    };

    testWidgets('average · highest (name) · you, for the SELECTED week; no '
        '"You" without your row; none on an unscored week or on Overall',
        (tester) async {
      await pumpTab(tester);
      await emitAll(tester, data: weeks, names: summaryNames);
      expect(byKey('gameweek_summary'), findsNothing); // Overall

      await pickScope(tester, 'Gameweek');
      // Latest scored week (GW2): 10 + 20 = 30 / 2 = 15; no row for me.
      expect(find.text('Average 15 pts · Highest 20 (Mid Table Mafia)'),
          findsOneWidget);

      await tester.tap(byKey('leaderboard_week_1'));
      await tester.pumpAndSettle();
      // 96 + 52 + 45 + 0 = 193 / 4 = 48.25 -> 48.
      expect(
          find.text('Average 48 pts · Highest 96 (Sweeper Keepers) · You 52'),
          findsOneWidget);
      // At the top of the view: under the week chips, above the standings.
      final summary = tester.getRect(byKey('gameweek_summary'));
      expect(summary.top,
          greaterThan(tester.getRect(byKey('leaderboard_week_1')).bottom));
      expect(summary.bottom,
          lessThan(tester.getRect(byKey('leaderboard_column_header')).top));

      await tester.tap(byKey('leaderboard_week_3'));
      await tester.pumpAndSettle();
      expect(byKey('leaderboard_week_unscored'), findsOneWidget);
      expect(byKey('gameweek_summary'), findsNothing);
    });

    testWidgets('a tie for the top score names no one: "(2 managers)"',
        (tester) async {
      FantasyLeaderboardsTab.sessionScope = LeaderboardScope.gameweek;
      await pumpTab(tester);
      await emitAll(
        tester,
        data: leaderboardsFromNode({
          'Gameweek': {
            '1': {
              'a': {'points': 30, 'rank': 1},
              'b': {'points': 30, 'rank': 1},
              'me': {'points': 12, 'rank': 3},
            },
          },
        }),
        names: summaryNames,
      );
      expect(
          find.text('Average 24 pts · Highest 30 (2 managers) · You 12'),
          findsOneWidget);
    });
  });

  group('extras at 360 px — wrap, never overflow (light + dark)', () {
    const longReal = 'Maximiliano Bartholomew Featherstonehaugh-Smythe';
    const longTeam = 'The Unbelievably Long Team Name Football Club Of Doom';

    for (final brightness in Brightness.values) {
      testWidgets('badged long names, the expanded rank panel and the week '
          'summary — $brightness', (tester) async {
        await pumpTab(
          tester,
          selfUid: 'me',
          size: const Size(360, 760),
          brightness: brightness,
          profiles: {
            'u1': const PublicProfile(
                uid: 'u1',
                firstName: 'Maximiliano',
                lastName: 'Bartholomew Featherstonehaugh-Smythe'),
            'me': const PublicProfile(
                uid: 'me',
                firstName: 'Maximiliano',
                lastName: 'Bartholomew Featherstonehaugh-Smythe'),
          },
        );
        await emitAll(
          tester,
          data: leaderboardsFromNode({
            'Overall': {
              'u1': {'points': 1234, 'rank': 1, 'movement': 12},
              'me': {'points': 1200, 'rank': 2, 'movement': -9},
              'u3': {'points': 1100, 'rank': 3, 'movement': 1},
            },
            'Gameweek': {
              '1': {
                'u1': {'points': 96, 'rank': 1},
                'me': {'points': 52, 'rank': 2},
                'u3': {'points': 40, 'rank': 3},
              },
            },
            'RankHistory': {
              'me': {'1': 120, '2': 45, '3': 2},
            },
          }),
          names: {
            'u1': manager(longTeam),
            'me': manager(longTeam),
            'u3': manager(longTeam),
          },
        );

        expect(byKey('climber_badge_u1'), findsOneWidget);
        expect(byKey('faller_badge_me'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final key in [
          'climber_badge_u1',
          'faller_badge_me',
          'leaderboard_row_u1',
          'leaderboard_row_me',
        ]) {
          final r = tester.getRect(byKey(key));
          expect(r.left, greaterThanOrEqualTo(0), reason: key);
          expect(r.right, lessThanOrEqualTo(360), reason: key);
        }
        // The long name still wraps (never ellipsized).
        final name = tester.widget<Text>(byKey('leaderboard_name_u1'));
        expect(name.overflow, isNot(TextOverflow.ellipsis));
        expect(name.maxLines, isNull);

        // The wrapped long names push the own row down: bring it into view.
        await tester.ensureVisible(byKey('leaderboard_row_me'));
        await tester.pumpAndSettle();
        await tester.tap(byKey('leaderboard_row_me'));
        await tester.pumpAndSettle();
        expect(byKey('rank_history_chart'), findsOneWidget);
        expect(find.text('#120 → #2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final key in ['rank_history_panel', 'rank_history_chart']) {
          final r = tester.getRect(byKey(key));
          expect(r.left, greaterThanOrEqualTo(0), reason: key);
          expect(r.right, lessThanOrEqualTo(360), reason: key);
        }

        await pickScope(tester, 'Gameweek');
        final summaryText = tester.widget<Text>(byKey('gameweek_summary'));
        expect(summaryText.overflow, isNot(TextOverflow.ellipsis));
        expect(summaryText.maxLines, isNull);
        expect(
            find.text('Average 63 pts · Highest 96 ($longReal) · You 52'),
            findsOneWidget);
        final summary = tester.getRect(byKey('gameweek_summary'));
        expect(summary.left, greaterThanOrEqualTo(0));
        expect(summary.right, lessThanOrEqualTo(360));
        // Wrapped onto several lines rather than clipped.
        expect(summary.height, greaterThan(40));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

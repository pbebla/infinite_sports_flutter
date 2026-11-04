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
// builder seam) — YOUR own row (natural and pinned) included, with no
// expanding panel and no chevron: "Your rank this season" + "Share my rank"
// live on your own team page (the real viewer, handed the series by the
// tab); 360 px long names + segment labels fitting in light AND
// dark; and (badges, spec 2026-10-30 §5) the badge-count chip beside the
// manager name on Overall + Gameweek rows — its feed does NOT gate the reveal
// (Opus audit item 1: every row reserves the chip's fixed slot until the
// counts land, then they fill in without moving a row), 0 shows nothing, a
// failing feed never holds the board, and it wraps with the climber/drop
// badge at 360 px (light + dark, before and after the counts land).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/badge_shelf.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';
import 'package:infinite_sports_flutter/fantasy/hub/mini_leagues_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rank_history_chart.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';

import '../helpers/real_fonts.dart';
import '../helpers/share_capture.dart';

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
  late StreamController<Map<int, FantasySquad>> viewerPublished;
  late StreamController<Map<int, FantasySquad>> viewerHistory;
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
    viewerPublished = StreamController<Map<int, FantasySquad>>.broadcast();
    viewerHistory = StreamController<Map<int, FantasySquad>>.broadcast();
    openedRows = [];
  });

  tearDown(() {
    boards.close();
    managers.close();
    leagues.close();
    squads.close();
    dreams.close();
    viewerPublished.close();
    viewerHistory.close();
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
    SharePng? shareImage,
    Stream<Map<String, List<FantasyBadgeAward>>>? badgesStates,
    // true = no squadViewerBuilder seam: rows open the REAL
    // ManagerSquadViewerPage (fed by viewerPublished / viewerHistory / squads).
    bool realViewer = false,
    // The OS "reduce motion" setting (MediaQuery.disableAnimations).
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness, fontFamily: fontFamily),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
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
          shareImage: shareImage,
          // Default: nobody has a badge, answered at once.
          badgesStates: badgesStates ??
              Stream<Map<String, List<FantasyBadgeAward>>>.value(const {}),
          viewerPublishedStates: viewerPublished.stream,
          viewerHistoryStates: viewerHistory.stream,
          squadViewerBuilder: realViewer
              ? null
              : (row) {
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

    testWidgets('share: the card header carries a Share button; tapping it '
        'renders the 1080x1920 story PNG and hands it + the caption to the '
        'share sheet (for the week on screen)', (tester) async {
      final shares = ShareRecorder();
      await pumpTab(tester,
          size: const Size(420, 1400), shareImage: shares.call);
      await emitAll(
        tester,
        data: overallData,
        names: {'u1': manager('Top Cats')},
        dreamTeams: twoWeeks(),
      );
      await pickScope(tester, kTeamOfWeekSegmentLabel);

      final button = find.byKey(const ValueKey('dream_team_share'));
      expect(button, findsOneWidget);
      // In the card's HEADER: on the title's line, right of it.
      final title = tester.getRect(find.byKey(const ValueKey('dream_team_title')));
      final rect = tester.getRect(button);
      expect(rect.left, greaterThanOrEqualTo(title.right));
      expect(rect.center.dy, closeTo(title.center.dy, 14));

      // The week on screen is what gets shared: step back to GW1 first.
      await tester.tap(find.byKey(const ValueKey('dream_week_1')));
      await tester.pumpAndSettle();
      await tester.tap(button);
      await pumpUntil(tester, () => shares.calls.isNotEmpty);

      final call = shares.calls.single;
      expect(isPng(call.png), isTrue);
      expect(pngSize(call.png), const Size(1080, 1920));
      expect(call.caption,
          'Infinite Fantasy · Team of the Week · GW1 (Futsal Season 15)');
      expect(call.origin, tester.getRect(button));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      // Sharing never navigates anywhere.
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
        // The header's Share button stays on screen.
        final share =
            tester.getRect(find.byKey(const ValueKey('dream_team_share')));
        expect(share.left, greaterThanOrEqualTo(0));
        expect(share.right, lessThanOrEqualTo(360));
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

  group('extra 1 — your own row opens your team (rank card lives there)', () {
    /// Taps [uid]'s row, lets the REAL viewer mount (realViewer pump) and
    /// lands its feeds — the squad stream too when it is your own page.
    Future<void> openRealViewer(WidgetTester tester, String uid,
        {bool self = false}) async {
      await tester.tap(byKey('leaderboard_row_$uid'));
      await tester.pump(); // the route's first frame: the viewer subscribes
      await tester.pump(const Duration(milliseconds: 400));
      viewerPublished.add(const {});
      viewerHistory.add(const {});
      if (self) squads.add(null);
      await tester.pumpAndSettle();
    }

    testWidgets('tapping YOUR row opens your team exactly like any other row '
        '— no expanding panel, no chevron in the list', (tester) async {
      await pumpTab(tester, size: const Size(420, 1000));
      await emitAll(
        tester,
        data: overallWith({
          'me': {'1': 14, '2': 12, '3': 10},
        }),
        names: fourNames,
      );
      // No chevron anywhere (not on your row, not reserved on the others).
      expect(byKey('own_row_chevron_me'), findsNothing);
      expect(byKey('own_row_chevron_u1'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byIcon(Icons.expand_less), findsNothing);
      expect(byKey('rank_history_panel'), findsNothing);

      await tester.tap(byKey('leaderboard_row_me'));
      await tester.pumpAndSettle();
      // The squad viewer opened for YOUR row (isSelf), nothing folded open.
      expect(openedRows.single.uid, 'me');
      expect(openedRows.single.isSelf, isTrue);
      expect(find.text('viewer page'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsNothing);

      // Back on the list: still no panel under your row, and a second tap
      // is a plain tap (opens the viewer again), not a fold toggle.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(byKey('rank_history_panel'), findsNothing);
      expect(find.text('viewer page'), findsNothing);
      await tester.tap(byKey('leaderboard_row_me'));
      await tester.pumpAndSettle();
      expect(openedRows.map((r) => r.uid), ['me', 'me']);
      expect(byKey('rank_history_panel'), findsNothing);
    });

    testWidgets("other managers' rows open their squad viewer; the Gameweek "
        "view's own row opens yours — none of them grows a panel",
        (tester) async {
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
      expect(byKey('own_row_chevron_me'), findsNothing);
      await tester.tap(byKey('leaderboard_row_me'));
      await tester.pumpAndSettle();
      expect(openedRows.last.uid, 'me');
      expect(openedRows.last.isSelf, isTrue);
      expect(byKey('rank_history_panel'), findsNothing);
    });

    testWidgets('the PINNED copy of your row opens your team too — no panel, '
        'no chevron', (tester) async {
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
      expect(
          find.descendant(of: pinned, matching: byKey('own_row_chevron_u18')),
          findsNothing);

      await tester.tap(find.descendant(
          of: pinned, matching: byKey('leaderboard_row_u18')));
      await tester.pumpAndSettle();
      expect(openedRows.single.uid, 'u18');
      expect(openedRows.single.isSelf, isTrue);
      expect(find.text('viewer page'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('your own team page (the real viewer) carries "Your rank this '
        'season" + "Share my rank"; another manager\'s page carries neither',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final shares = ShareRecorder();
      await pumpTab(tester,
          size: const Size(420, 1400),
          realViewer: true,
          shareImage: shares.call);
      await emitAll(
        tester,
        data: overallWith({
          'me': {'1': 14, '2': 12, '3': 10},
        }),
        names: fourNames,
      );
      expect(byKey('rank_history_panel'), findsNothing);

      await openRealViewer(tester, 'me', self: true);
      expect(find.byType(ManagerSquadViewerPage), findsOneWidget);
      expect(byKey('viewer_content'), findsOneWidget);
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(find.text('Your rank this season'), findsOneWidget);
      expect(byKey('rank_history_chart'), findsOneWidget);
      expect(find.text('#14 → #10'), findsOneWidget);
      expect(byKey('rank_history_note'), findsNothing);
      expect(find.bySemanticsLabel('Your rank by gameweek: GW1 #14, GW2 #12, '
          'GW3 #10'), findsOneWidget);
      // No "View team": you are already on it.
      expect(byKey('rank_history_view_team'), findsNothing);
      expect(find.text('View team'), findsNothing);
      // Rank 1 at the top of the chart; gameweeks run left to right.
      expect(tester.getTopLeft(find.text('#10')).dy,
          lessThan(tester.getTopLeft(find.text('#14')).dy));
      expect(tester.getTopLeft(find.text('GW1')).dx,
          lessThan(tester.getTopLeft(find.text('GW3')).dx));
      // The card sits at the TOP: above the week chips and the court.
      expect(tester.getBottomLeft(byKey('rank_history_panel')).dy,
          lessThanOrEqualTo(tester.getTopLeft(byKey('viewer_week_now')).dy));

      // "Share my rank" renders the story PNG and hands it + the caption to
      // the same share seam, anchored to the tapped button.
      final share = byKey('rank_history_share');
      expect(share, findsOneWidget);
      expect(find.text('Share my rank'), findsOneWidget);
      await tester.tap(share);
      await pumpUntil(tester, () => shares.calls.isNotEmpty);
      final call = shares.calls.single;
      expect(isPng(call.png), isTrue);
      expect(pngSize(call.png), const Size(1080, 1920));
      expect(call.caption,
          'Infinite Fantasy · My rank · #2 of 4 · 80 pts (Futsal Season 15)');
      expect(call.origin, tester.getRect(share));
      await tester.pumpAndSettle();
      // Nothing navigated; the page is still your team.
      expect(find.byType(ManagerSquadViewerPage), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);

      // Another manager's page: no card, no share.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openRealViewer(tester, 'u3');
      expect(find.byType(ManagerSquadViewerPage), findsOneWidget);
      expect(byKey('rank_history_panel'), findsNothing);
      expect(byKey('rank_history_share'), findsNothing);
      expect(find.text('Your rank this season'), findsNothing);
      expect(shares.calls, hasLength(1));
      semantics.dispose();
    });

    testWidgets("your team page's rank card is LIVE off the tab's boards "
        'feed: a finalize while the page is open moves the chart',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpTab(tester, size: const Size(420, 1400), realViewer: true);
      await emitAll(
        tester,
        data: overallWith({
          'me': {'1': 14, '2': 12, '3': 10},
        }),
        names: fourNames,
      );
      await openRealViewer(tester, 'me', self: true);
      expect(find.text('#14 → #10'), findsOneWidget);

      // GW4 finalizes underneath the open page.
      boards.add(overallWith({
        'me': {'1': 14, '2': 12, '3': 10, '4': 7},
      }));
      await tester.pumpAndSettle();
      expect(find.byType(ManagerSquadViewerPage), findsOneWidget);
      expect(find.text('#14 → #7'), findsOneWidget);
      expect(find.text('#14 → #10'), findsNothing);
      expect(find.bySemanticsLabel('Your rank by gameweek: GW1 #14, GW2 #12, '
          'GW3 #10, GW4 #7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('the rank card shares your OVERALL row even when you opened '
        'your team from the Gameweek scope', (tester) async {
      final shares = ShareRecorder();
      await pumpTab(tester,
          size: const Size(420, 1400),
          realViewer: true,
          shareImage: shares.call);
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
      await pickScope(tester, 'Gameweek');
      await openRealViewer(tester, 'me', self: true);
      expect(byKey('rank_history_panel'), findsOneWidget);
      expect(find.text('#3 → #2'), findsOneWidget);

      await tester.tap(byKey('rank_history_share'));
      await pumpUntil(tester, () => shares.calls.isNotEmpty);
      // The season's rank + points (80), not the week's (10).
      expect(shares.calls.single.caption,
          'Infinite Fantasy · My rank · #2 of 4 · 80 pts (Futsal Season 15)');
      await tester.pumpAndSettle();
    });

    for (final (label, history) in [
      ('one week of history', <String, Object?>{
        'me': {'1': 4},
      }),
      ('no RankHistory at all', null),
    ]) {
      testWidgets('under two weeks ($label): your team page shows a short '
          'muted note instead of a chart', (tester) async {
        await pumpTab(tester, size: const Size(420, 1400), realViewer: true);
        await emitAll(tester, data: overallWith(history), names: fourNames);
        await openRealViewer(tester, 'me', self: true);

        expect(byKey('rank_history_panel'), findsOneWidget);
        expect(find.text('Your rank this season'), findsOneWidget);
        expect(byKey('rank_history_chart'), findsNothing);
        expect(find.textContaining('→'), findsNothing);
        final note = tester.widget<Text>(byKey('rank_history_note'));
        expect(note.data, kRankHistoryNote);
        final context = tester.element(byKey('rank_history_note'));
        expect(note.style!.color,
            Theme.of(context).colorScheme.onSurfaceVariant);
        // Sharing your rank still works from here.
        expect(byKey('rank_history_share'), findsOneWidget);
      });
    }

    testWidgets('review fix: your points never move out of the points column '
        '— the list is the plain layout (no reserved chevron width), and the '
        '"Pts" header sits over it', (tester) async {
      await pumpTab(tester, size: const Size(420, 1000));
      await emitAll(
        tester,
        data: overallWith({
          'me': {'1': 3, '2': 2},
        }),
        names: fourNames,
      );
      // Outer 10 + inner 12 = 22 px from the right edge, on EVERY row.
      final mine = tester.getTopRight(find.text('80 pts')).dx;
      expect(mine, closeTo(420 - 22, 0.01));
      for (final other in ['90 pts', '70 pts', '60 pts']) {
        expect(tester.getTopRight(find.text(other)).dx, mine, reason: other);
      }
      expect(tester.getTopRight(find.text('Pts')).dx, mine);
    });

    testWidgets('review fix: the pinned copy of your row lines up too',
        (tester) async {
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
      final pinned = byKey('pinned_own_row');
      expect(pinned, findsOneWidget);
      final pinnedPoints = tester.getTopRight(
          find.descendant(of: pinned, matching: find.text('82 pts')));
      expect(pinnedPoints.dx, tester.getTopRight(find.text('99 pts')).dx);
      expect(pinnedPoints.dx, closeTo(420 - 22, 0.01));
    });

    test('chart geometry: rank 1 at the top, gameweeks left to right', () {
      final points = rankChartOffsets(
        [
          (gameweek: 1, rank: 14, live: false),
          (gameweek: 2, rank: 12, live: false),
          (gameweek: 4, rank: 10, live: false),
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
          [(gameweek: 1, rank: 3, live: false), (gameweek: 2, rank: 3, live: false)],
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

  group('badges (spec 2026-10-30 §5) — the count chip', () {
    List<FantasyBadgeAward> n(String uid, int count) => [
          for (var i = 1; i <= count; i++)
            FantasyBadgeAward(
                id: 'captainGenius_gw$i', badgeId: 'captainGenius', gw: i),
        ];
    final data = leaderboardsFromNode({
      'Overall': {
        'u1': {'points': 50, 'rank': 1, 'movement': 3},
        'u2': {'points': 40, 'rank': 2},
        'me': {'points': 30, 'rank': 3, 'movement': -2},
      },
      'Gameweek': {
        '1': {
          'u1': {'points': 10, 'rank': 1},
          'u2': {'points': 8, 'rank': 2},
          'me': {'points': 6, 'rank': 3},
        },
      },
    });
    final names = {
      'u1': manager('Top Cats'),
      'u2': manager('Bench Warmers'),
      'me': manager('My Team'),
    };

    testWidgets('military_tech + N beside the name on Overall AND Gameweek; '
        'nothing for a manager with none', (tester) async {
      await pumpTab(tester,
          // Wide enough that name + chip share a line in the test font.
          size: const Size(800, 760),
          badgesStates: Stream.value({'u1': n('u1', 3), 'me': n('me', 1)}));
      await emitAll(tester, data: data, names: names);

      Finder chip(String uid) => byKey('badge_count_$uid');
      expect(chip('u1'), findsOneWidget);
      expect(chip('me'), findsWidgets); // natural (+ maybe the pinned copy)
      expect(chip('u2'), findsNothing);
      expect(
          find.descendant(of: chip('u1'), matching: find.text('3')),
          findsOneWidget);
      expect(
          tester
              .widget<Icon>(find.descendant(
                  of: chip('u1'), matching: find.byType(Icon)))
              .icon,
          Icons.military_tech);
      expect(find.byTooltip('3 badges'), findsOneWidget);
      // Beside the manager name: same line, to its right.
      final name = tester.getRect(byKey('leaderboard_name_u1'));
      final count = tester.getRect(chip('u1'));
      expect(count.left, greaterThanOrEqualTo(name.right - 0.5));
      expect(count.center.dy, inInclusiveRange(name.top, name.bottom));

      await pickScope(tester, 'Gameweek');
      expect(chip('u1'), findsOneWidget);
      expect(chip('u2'), findsNothing);
      expect(
          find.descendant(of: chip('u1'), matching: find.text('3')),
          findsOneWidget);
    });

    testWidgets(
        'the badges feed does NOT gate the reveal: every row reserves the '
        "chip's slot, the counts fill it in later without moving a row; live "
        'updates re-count', (tester) async {
      final badges = StreamController<Map<String, List<FantasyBadgeAward>>>();
      addTearDown(badges.close);
      await pumpTab(tester,
          size: const Size(800, 760), badgesStates: badges.stream);
      await emitAll(tester, data: data, names: names);
      // Revealed without the (whole-season) badges node.
      expect(byKey('leaderboards_ready'), findsOneWidget);
      expect(byKey('leaderboards_skeleton'), findsNothing);
      expect(find.byType(BadgeCountChip), findsNothing);
      final slot = tester.getRect(byKey('badge_slot_u1'));
      expect(slot.size, const Size(kBadgeCountChipWidth, kBadgeCountChipHeight));
      expect(byKey('badge_slot_u2'), findsOneWidget);
      final rowsBefore = {
        for (final uid in ['u1', 'u2'])
          uid: tester.getRect(byKey('leaderboard_row_$uid')),
      };
      final climberBefore = tester.getRect(byKey('climber_badge_u1'));

      badges.add({'u1': n('u1', 3)});
      await tester.pump(); // delivers the emission (setState)
      await tester.pump(); // one frame — no animation needed to settle
      // The number lands IN the reserved slot; nothing else moves.
      expect(tester.getRect(byKey('badge_count_u1')), slot);
      expect(
          find.descendant(of: byKey('badge_count_u1'), matching: find.text('3')),
          findsOneWidget);
      expect(tester.getRect(byKey('climber_badge_u1')), climberBefore);
      for (final uid in ['u1', 'u2']) {
        expect(tester.getRect(byKey('leaderboard_row_$uid')), rowsBefore[uid],
            reason: uid);
      }
      // A manager with none: the slot goes, no chip.
      expect(byKey('badge_slot_u2'), findsNothing);
      expect(byKey('badge_count_u2'), findsNothing);

      badges.add({'u2': n('u2', 2)});
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: byKey('badge_count_u2'), matching: find.text('2')),
          findsOneWidget);
      expect(byKey('badge_count_u1'), findsNothing);
    });

    testWidgets('a failing badges feed never holds the board (no chips)',
        (tester) async {
      await pumpTab(tester, badgesStates: Stream.error(StateError('denied')));
      await emitAll(tester, data: data, names: names);
      expect(byKey('leaderboards_ready'), findsOneWidget);
      expect(byKey('leaderboard_row_u1'), findsOneWidget);
      expect(byKey('badge_count_u1'), findsNothing);
      expect(byKey('badge_slot_u1'), findsNothing); // known: none
    });

    testWidgets('a mini-league style list (no counts passed) shows no chips',
        (tester) async {
      tester.view.physicalSize = const Size(420, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RankedLeaderboardList(
            rows: composeLeaderboardRows(
              entries: data.overall,
              managers: names,
              profiles: const {},
              selfUid: 'me',
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(byKey('leaderboard_row_u1'), findsOneWidget);
      expect(find.byType(BadgeCountChip), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px: a long name + count chip + climber badge wrap, '
          'never overflow — $brightness', (tester) async {
        const longTeam =
            'The Unbelievably Long Team Name Football Club Of Doom';
        await pumpTab(
          tester,
          size: const Size(360, 760),
          brightness: brightness,
          profiles: {
            'u1': const PublicProfile(
                uid: 'u1',
                firstName: 'Maximiliano',
                lastName: 'Bartholomew Featherstonehaugh-Smythe'),
          },
          badgesStates: Stream.value({'u1': n('u1', 128), 'me': n('me', 7)}),
        );
        await emitAll(tester,
            data: data,
            names: {'u1': manager(longTeam), 'me': manager(longTeam)});
        expect(tester.takeException(), isNull);
        expect(byKey('climber_badge_u1'), findsOneWidget);
        for (final key in [
          'badge_count_u1',
          'climber_badge_u1',
          'leaderboard_name_u1',
          'leaderboard_row_u1',
        ]) {
          final r = tester.getRect(byKey(key));
          expect(r.left, greaterThanOrEqualTo(0), reason: key);
          expect(r.right, lessThanOrEqualTo(360), reason: key);
        }
        final name = tester.widget<Text>(byKey('leaderboard_name_u1'));
        expect(name.overflow, isNot(TextOverflow.ellipsis));
        expect(name.maxLines, isNull);

        await pickScope(tester, 'Gameweek');
        expect(tester.takeException(), isNull);
        final r = tester.getRect(byKey('badge_count_u1'));
        expect(r.right, lessThanOrEqualTo(360));
      });

      testWidgets(
          '360 px: the reserved slot + climber badge before the counts land, '
          'then the 3-digit count in it — no overflow — $brightness',
          (tester) async {
        const longTeam =
            'The Unbelievably Long Team Name Football Club Of Doom';
        final badges =
            StreamController<Map<String, List<FantasyBadgeAward>>>();
        addTearDown(badges.close);
        await pumpTab(
          tester,
          size: const Size(360, 760),
          brightness: brightness,
          profiles: {
            'u1': const PublicProfile(
                uid: 'u1',
                firstName: 'Maximiliano',
                lastName: 'Bartholomew Featherstonehaugh-Smythe'),
          },
          badgesStates: badges.stream,
        );
        await emitAll(tester,
            data: data,
            names: {'u1': manager(longTeam), 'me': manager(longTeam)});
        expect(tester.takeException(), isNull);
        expect(byKey('climber_badge_u1'), findsOneWidget);
        final slot = tester.getRect(byKey('badge_slot_u1'));
        final row = tester.getRect(byKey('leaderboard_row_u1'));
        for (final r in [slot, row]) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
        }

        badges.add({'u1': n('u1', 128)});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(byKey('badge_count_u1')), slot);
        expect(tester.getRect(byKey('leaderboard_row_u1')), row);
        expect(
            find.descendant(
                of: byKey('badge_count_u1'), matching: find.text('128')),
            findsOneWidget);
      });
    }
  });

  group('extras at 360 px — wrap, never overflow (light + dark)', () {
    const longReal = 'Maximiliano Bartholomew Featherstonehaugh-Smythe';
    const longTeam = 'The Unbelievably Long Team Name Football Club Of Doom';

    for (final brightness in Brightness.values) {
      testWidgets('badged long names and the week summary — $brightness',
          (tester) async {
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
        // It opens your team (the rank card is on THAT page), never a panel.
        await tester.ensureVisible(byKey('leaderboard_row_me'));
        await tester.pumpAndSettle();
        expect(byKey('own_row_chevron_me'), findsNothing);
        await tester.tap(byKey('leaderboard_row_me'));
        await tester.pumpAndSettle();
        expect(openedRows.single.uid, 'me');
        expect(byKey('rank_history_panel'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();

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

  // ── Live everywhere (Task 6) ─────────────────────────────────────────────
  //
  // The owner's steady-order rule: numbers move in place at once, rows don't
  // jump — a sorted list re-orders at the top / on (re)open / on a scope pick,
  // else behind "Order changed · tap to refresh". Plus the LIVE pills, the
  // moved-row tint and the rank cross-fade.
  group('live everywhere (Task 6)', () {
    // 30 managers m01..m30 (a list long enough to scroll), best first.
    final uids = [
      for (var i = 1; i <= 30; i++) 'm${i.toString().padLeft(2, '0')}'
    ];
    final names = {for (final u in uids) u: manager('Team ${u.substring(1)}')};

    List<FantasyLeaderboardEntry> board(List<String> order,
            {bool live = true}) =>
        [
          for (final (i, uid) in order.indexed)
            FantasyLeaderboardEntry(
              uid: uid,
              points: 1000 - i * 10,
              rank: i + 1,
              movement: 0,
              live: live,
            ),
        ];

    FantasyLeaderboards boardsOf(List<FantasyLeaderboardEntry> overall,
            {Map<int, List<FantasyLeaderboardEntry>> byWeek = const {},
            Map<String, Map<int, int>> history = const {},
            Map<String, Set<int>> liveRank = const {}}) =>
        FantasyLeaderboards(
            overall: overall,
            byWeek: byWeek,
            rankHistory: history,
            liveRankPoints: liveRank);

    /// [uids] with [who] moved to the front: the new leader.
    List<String> withLeader(String who) =>
        [who, ...uids.where((u) => u != who)];

    /// Lets the feeds land WITHOUT pumpAndSettle (a live pill pulses
    /// forever, which never settles).
    Future<void> land(WidgetTester tester, FantasyLeaderboards data,
        {Map<int, FantasyDreamTeam> dreamTeams = const {}}) async {
      boards.add(data);
      managers.add(names);
      leagues.add(const []);
      dreams.add(dreamTeams);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// pickScope without pumpAndSettle (live pills never settle).
    Future<void> pickScopeLive(WidgetTester tester, String label) async {
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('leaderboard_scope')),
          matching: find.text(label)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// The row uids on screen (built rows), top to bottom.
    List<String> shownUids(WidgetTester tester) {
      final rows = find
          .byWidgetPredicate((w) =>
              w is InkWell &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>)
                  .value
                  .startsWith('leaderboard_row_'))
          .evaluate()
          .map((e) => (
                (e.widget.key! as ValueKey<String>)
                    .value
                    .substring('leaderboard_row_'.length),
                tester.getTopLeft(find.byWidget(e.widget)).dy,
              ))
          .toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final r in rows) r.$1];
    }

    Finder pill() => byKey('order_changed_pill');
    const pillText = 'Order changed · tap to refresh';

    Finder rankSwitcher(String uid) => byKey('leaderboard_rank_$uid');
    Finder rankText(String uid, String text) =>
        find.descendant(of: rankSwitcher(uid), matching: find.text(text));

    Finder list() => find.byType(ListView);

    Future<void> scrollDown(WidgetTester tester) async {
      await tester.drag(list(), const Offset(0, -700));
      await tester.pumpAndSettle();
    }

    group('the steady order', () {
      testWidgets(
          'scrolled down: numbers move in place, the rows do NOT jump, '
          '"Order changed · tap to refresh" appears, a tap re-orders',
          (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));
        await scrollDown(tester);
        final before = shownUids(tester);
        expect(before.first, isNot('m01'));
        expect(find.text(pillText), findsNothing);
        final probe = before[3]; // a row on screen
        final rank = uids.indexOf(probe) + 1;
        expect(rankText(probe, '$rank'), findsOneWidget);

        // m30 scores big: leader. Everyone else slides down one place.
        boards.add(boardsOf(board(withLeader('m30'))));
        await tester.pumpAndSettle();

        // Numbers moved in place…
        expect(rankText(probe, '${rank + 1}'), findsOneWidget);
        // …the rows did not.
        expect(shownUids(tester), before);
        expect(find.text(pillText), findsOneWidget);

        // Tap: the order is applied (the same window now shows the rows one
        // place earlier in the new order), the pill is gone.
        await tester.tap(pill());
        await tester.pumpAndSettle();
        final order2 = withLeader('m30');
        final first = uids.indexOf(before.first);
        expect(
            shownUids(tester), order2.sublist(first, first + before.length));
        expect(find.text(pillText), findsNothing);
      });

      testWidgets('at the top: the new order is applied at once, no pill',
          (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));
        expect(shownUids(tester).first, 'm01');

        boards.add(boardsOf(board(withLeader('m30'))));
        await tester.pumpAndSettle();

        expect(shownUids(tester).first, 'm30');
        expect(find.text(pillText), findsNothing);
      });

      testWidgets(
          'scrolling back to the top applies the waiting order by itself',
          (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));
        await scrollDown(tester);
        boards.add(boardsOf(board(withLeader('m30'))));
        await tester.pumpAndSettle();
        expect(find.text(pillText), findsOneWidget);

        await tester.drag(list(), const Offset(0, 1500));
        await tester.pumpAndSettle();

        expect(find.text(pillText), findsNothing);
        expect(shownUids(tester).first, 'm30');
      });

      testWidgets(
          'never re-orders under a moving finger: at the top but dragging, '
          'the order waits until the finger is up', (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));

        final gesture = await tester.startGesture(tester.getCenter(list()));
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
        boards.add(boardsOf(board(withLeader('m30'))));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(shownUids(tester).first, 'm01', reason: 'finger is down');
        expect(find.text(pillText), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(shownUids(tester).first, 'm30');
        expect(find.text(pillText), findsNothing);
      });

      testWidgets(
          'picking a scope re-orders at once: back on Overall the newest '
          'order shows and nothing waits', (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));
        await scrollDown(tester);
        boards.add(boardsOf(board(withLeader('m30'))));
        await tester.pumpAndSettle();
        expect(find.text(pillText), findsOneWidget);

        await pickScope(tester, kTeamOfWeekSegmentLabel);
        await pickScope(tester, 'Overall');

        expect(shownUids(tester).first, 'm30');
        expect(find.text(pillText), findsNothing);
      });

      testWidgets(
          'Overall and Gameweek are separate lists: from a scrolled Overall, '
          "picking Gameweek shows the week's own order at once, no pill",
          (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        // The week's order differs from the Overall one.
        final weekOrder = withLeader('m30');
        await land(
            tester, boardsOf(board(uids), byWeek: {2: board(weekOrder)}));
        await scrollDown(tester);
        expect(find.text(pillText), findsNothing);

        await pickScope(tester, 'Gameweek');

        expect(find.text(pillText), findsNothing);
        expect(find.byKey(const ValueKey('leaderboard_week_2')), findsOneWidget);
        expect(shownUids(tester).first, 'm30');
      });

      testWidgets(
          "picking another week chip shows that week's own order at once "
          '(each week is its own list)', (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(
            tester,
            boardsOf(board(uids), byWeek: {
              1: board(withLeader('m30')),
              2: board(uids),
            }));
        await pickScope(tester, 'Gameweek');
        expect(shownUids(tester).first, 'm01'); // GW2, the latest
        await scrollDown(tester);
        // Back to the top (the chips live in the list's own header).
        await tester.drag(list(), const Offset(0, 1500));
        await tester.pumpAndSettle();

        await tester.tap(byKey('leaderboard_week_1'));
        await tester.pumpAndSettle();

        expect(find.text(pillText), findsNothing);
        expect(shownUids(tester).first, 'm30');
      });

      testWidgets(
          "the list stays on the route's primary scroll controller (iOS "
          'status-bar tap scrolls it to the top)', (tester) async {
        final primary = ScrollController();
        addTearDown(primary.dispose);
        await tester.pumpWidget(MaterialApp(
          home: PrimaryScrollController(
            controller: primary,
            child: Scaffold(
              body: RankedLeaderboardList(
                rows: composeLeaderboardRows(
                  entries: board(uids),
                  managers: names,
                  profiles: const {},
                  selfUid: 'nobody',
                ),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        expect(primary.hasClients, isTrue);
      });

      testWidgets('(re)opening the tab shows the latest order at once',
          (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(withLeader('m30'))));
        expect(shownUids(tester).first, 'm30');
        expect(find.text(pillText), findsNothing);
      });

      testWidgets(
          'an order that comes back to the shown one withdraws the pill '
          '(nothing left to refresh)', (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));
        await scrollDown(tester);
        boards.add(boardsOf(board(withLeader('m30'))));
        await tester.pumpAndSettle();
        expect(find.text(pillText), findsOneWidget);

        boards.add(boardsOf(board(uids)));
        await tester.pumpAndSettle();
        expect(find.text(pillText), findsNothing);
      });

      testWidgets('the Gameweek scope follows the same rule', (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        FantasyLeaderboards data(List<String> order) =>
            boardsOf(board(uids), byWeek: {2: board(order)});
        await land(tester, data(uids));
        await pickScope(tester, 'Gameweek');
        await scrollDown(tester);
        final before = shownUids(tester);

        boards.add(data(withLeader('m30')));
        await tester.pumpAndSettle();

        expect(shownUids(tester), before);
        expect(find.text(pillText), findsOneWidget);
        await tester.tap(pill());
        await tester.pumpAndSettle();
        expect(find.text(pillText), findsNothing);
      });

      for (final brightness in Brightness.values) {
        testWidgets(
            'the pill is the accent colour, readable, at 360 px — $brightness',
            (tester) async {
          await pumpTab(tester,
              selfUid: 'nobody',
              size: const Size(360, 760),
              brightness: brightness,
              reduceMotion: true);
          await land(tester, boardsOf(board(uids)));
          await scrollDown(tester);
          boards.add(boardsOf(board(withLeader('m30'))));
          await tester.pumpAndSettle();

          final accent = fantasyAccent(tester.element(pill()));
          final material = tester.widget<Material>(
              find.descendant(of: pill(), matching: find.byType(Material))
                  .first);
          expect(material.color, accent);
          final label = tester.widget<Text>(
              find.descendant(of: pill(), matching: find.text(pillText)));
          final fg = label.style!.color!;
          final lighter = fg.computeLuminance() > accent.computeLuminance()
              ? fg
              : accent;
          final darker = identical(lighter, fg) ? accent : fg;
          final contrast = (lighter.computeLuminance() + 0.05) /
              (darker.computeLuminance() + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          final r = tester.getRect(pill());
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          // Under the fixed header, over the list's top.
          expect(r.top,
              greaterThan(tester.getRect(byKey('leaderboard_scope')).bottom));
          expect(tester.takeException(), isNull);
        });
      }
    });

    group('the moved-row tint and the rank cross-fade', () {
      Color? tintOf(WidgetTester tester, String uid) {
        final box = tester.widget<AnimatedContainer>(byKey('row_tint_$uid'));
        return (box.foregroundDecoration! as BoxDecoration).color;
      }

      List<String> swapped() {
        final order = [...uids];
        order[1] = 'm03';
        order[2] = 'm02';
        return order;
      }

      testWidgets(
          'only the rows whose rank changed tint — up in the up colour, '
          'down in the bright red, each at 18 %', (tester) async {
        await pumpTab(tester, selfUid: 'nobody');
        await land(tester, boardsOf(board(uids)));
        expect(tintOf(tester, 'm02')!.a, 0);

        boards.add(boardsOf(board(swapped())));
        await tester.pump();

        final context = tester.element(byKey('leaderboard_row_m02'));
        expect(tintOf(tester, 'm02'),
            fantasyDownRed(context).withValues(alpha: 0.18)); // 2 → 3
        expect(tintOf(tester, 'm03'),
            fantasyPitchGreen(context).withValues(alpha: 0.18)); // 3 → 2
        for (final still in ['m01', 'm04', 'm05']) {
          expect(tintOf(tester, still)!.a, 0, reason: still);
        }

        // It lasts 800 ms, then it is gone.
        await tester.pump(const Duration(milliseconds: 700));
        expect(tintOf(tester, 'm02')!.a, greaterThan(0));
        await tester.pump(const Duration(milliseconds: 150));
        expect(tintOf(tester, 'm02')!.a, 0);
        expect(tintOf(tester, 'm03')!.a, 0);
      });

      testWidgets('the rank number cross-fades over 250 ms', (tester) async {
        await pumpTab(tester, selfUid: 'nobody');
        await land(tester, boardsOf(board(uids)));
        final switcher =
            tester.widget<AnimatedSwitcher>(rankSwitcher('m02'));
        expect(switcher.duration, const Duration(milliseconds: 250));
        expect(rankText('m02', '2'), findsOneWidget);

        boards.add(boardsOf(board(swapped())));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Mid-fade: the old and the new number are both on screen.
        expect(rankText('m02', '2'), findsOneWidget);
        expect(rankText('m02', '3'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        expect(rankText('m02', '2'), findsNothing);
        expect(rankText('m02', '3'), findsOneWidget);
        // A row that did not change never fades.
        expect(
            find.descendant(
                of: rankSwitcher('m01'), matching: find.byType(Text)),
            findsOneWidget);
      });

      testWidgets(
          'reduced motion: no animation — the number is swapped and the '
          'tint switched on and off instantly', (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));
        expect(tester.widget<AnimatedSwitcher>(rankSwitcher('m02')).duration,
            Duration.zero);

        boards.add(boardsOf(board(swapped())));
        await tester.pump();

        // One frame later: only the new number, never a cross-fade.
        expect(rankText('m02', '2'), findsNothing);
        expect(rankText('m02', '3'), findsOneWidget);
        // The tint is on at once, with no fade in or out.
        expect(
            tester.widget<AnimatedContainer>(byKey('row_tint_m02')).duration,
            Duration.zero);
        expect(tintOf(tester, 'm02')!.a, greaterThan(0));
        await tester.pump(const Duration(milliseconds: 850));
        expect(tintOf(tester, 'm02')!.a, 0);
      });

      testWidgets(
          'a refresh tints the rows that changed place (their rank numbers '
          'had already moved)', (tester) async {
        await pumpTab(tester, selfUid: 'nobody', reduceMotion: true);
        await land(tester, boardsOf(board(uids)));
        await scrollDown(tester);
        boards.add(boardsOf(board(withLeader('m30'))));
        await tester.pumpAndSettle();
        // The numbers moved earlier; that tint is long gone.
        await tester.pump(const Duration(milliseconds: 900));
        final window = shownUids(tester);
        for (final u in window) {
          expect(tintOf(tester, u)!.a, 0, reason: u);
        }

        await tester.tap(pill());
        await tester.pump();

        // Every row in view now holds a different row's place: they tint.
        final context = tester.element(byKey('leaderboard_row_${window[3]}'));
        final moved = shownUids(tester)
            .where((u) => tintOf(tester, u)!.a > 0)
            .toList();
        expect(moved, isNotEmpty);
        expect(
            tintOf(tester, moved.first),
            anyOf(
              fantasyPitchGreen(context).withValues(alpha: 0.18),
              fantasyDownRed(context).withValues(alpha: 0.18),
            ));
        await tester.pump(const Duration(milliseconds: 900));
      });

      for (final brightness in Brightness.values) {
        testWidgets('the tint pair in $brightness', (tester) async {
          await pumpTab(tester, selfUid: 'nobody', brightness: brightness);
          await land(tester, boardsOf(board(uids)));
          boards.add(boardsOf(board(swapped())));
          await tester.pump();
          final dark = brightness == Brightness.dark;
          expect(
              tintOf(tester, 'm02'),
              (dark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F))
                  .withValues(alpha: 0.18));
          expect(
              tintOf(tester, 'm03'),
              (dark ? const Color(0xFF2E8B57) : const Color(0xFF2FA05A))
                  .withValues(alpha: 0.18));
          await tester.pump(const Duration(milliseconds: 900));
        });
      }
    });

    group('the LIVE pills (shown only while live)', () {
      Finder headerPill() => find.descendant(
          of: byKey('leaderboard_column_header'),
          matching: find.byType(FantasyLivePill));

      testWidgets(
          'Overall: a live board shows the pill in its header; an official '
          'one never does', (tester) async {
        await pumpTab(tester, selfUid: 'nobody');
        await land(tester, boardsOf(board(uids, live: false)));
        expect(find.byType(FantasyLivePill), findsNothing);

        boards.add(boardsOf(board(uids)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(headerPill(), findsOneWidget);

        // The week settles: the pill is simply not drawn any more.
        boards.add(boardsOf(board(uids, live: false)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(FantasyLivePill), findsNothing);
      });

      testWidgets(
          "Gameweek: the live week's chip carries a pill, the header only "
          'while the LIVE week is selected', (tester) async {
        await pumpTab(tester, selfUid: 'nobody');
        await land(
            tester,
            boardsOf(board(uids), byWeek: {
              1: board(uids, live: false),
              2: board(uids),
            }));
        await pickScopeLive(tester, 'Gameweek');

        Finder chipPill(int week) => find.descendant(
            of: byKey('leaderboard_week_$week'),
            matching: find.byType(FantasyLivePill));
        expect(chipPill(2), findsOneWidget);
        expect(chipPill(1), findsNothing);
        expect(chipPill(3), findsNothing);
        // Week 2 (the latest scored) is selected: its header says LIVE too.
        expect(headerPill(), findsOneWidget);

        await tester.tap(byKey('leaderboard_week_1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(headerPill(), findsNothing);
        expect(chipPill(2), findsOneWidget);
      });

      testWidgets('the Gameweek summary is the live numbers', (tester) async {
        await pumpTab(tester, selfUid: 'nobody');
        final live = [
          const FantasyLeaderboardEntry(
              uid: 'm01', points: 30, rank: 1, live: true),
          const FantasyLeaderboardEntry(
              uid: 'm02', points: 10, rank: 2, live: true),
        ];
        await land(tester, boardsOf(board(uids), byWeek: {2: live}));
        await pickScopeLive(tester, 'Gameweek');
        expect(find.text('Average 20 pts · Highest 30 (Team 01)'),
            findsOneWidget);
      });

      for (final brightness in Brightness.values) {
        testWidgets(
            '360 px: the live headers, the chip pill and the rows never '
            'overflow — $brightness', (tester) async {
          await pumpTab(tester,
              selfUid: 'm05',
              size: const Size(360, 760),
              brightness: brightness);
          await land(
              tester,
              boardsOf(board(uids),
                  byWeek: {1: board(uids, live: false), 2: board(uids)}));
          expect(tester.takeException(), isNull);
          expect(headerPill(), findsOneWidget);
          final header = tester.getRect(byKey('leaderboard_column_header'));
          expect(header.right, lessThanOrEqualTo(360));

          await pickScopeLive(tester, 'Gameweek');
          expect(tester.takeException(), isNull);
          expect(tester.getRect(byKey('leaderboard_week_2')).height,
              lessThan(60));
          expect(headerPill(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}

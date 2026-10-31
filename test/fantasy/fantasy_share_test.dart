// Infinite Fantasy share images (owner: "a share button on Team of the week
// and on your own rank — it makes a branded image people can post to
// Instagram stories or group chats"): the two story widgets render at the
// 9:16 story size (360x640 logical -> 1080x1920 at the pixel ratio the share
// uses), always in the fixed DARK brand style whatever the app theme, with
// the logo, the season label and the shared "Follow Infinite Sports" footer;
// long names wrap and never overflow; the captions; and the Team of the Week
// card's Share button only where the Leaderboards tab asks for one.
//
// Owner previews: run with
//   --dart-define=FANTASY_SHARE_PNG_DIR=<folder>
// to write share_totw.png and share_rank.png (real Roboto + icons) there.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_share.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rank_history_chart.dart';
import 'package:infinite_sports_flutter/widgets/share_card_footer.dart';

import '../helpers/real_fonts.dart';
import '../helpers/share_capture.dart';

const String kPngDir = String.fromEnvironment('FANTASY_SHARE_PNG_DIR');

const longTeam = 'The Unbelievably Long Team Name Football Club Of Doom';
const longReal = 'Maximiliano Bartholomew Featherstonehaugh-Smythe';

FantasyDreamTeam dreamTeam({bool longNames = false}) => dreamTeamsFromNode({
      '8': {
        'Players': [
          {
            'name': longNames ? 'Maximiliano Featherstonehaugh' : 'Kit Moreno',
            'position': 'GK',
            'points': 14,
          },
          {'name': 'Dana Okafor', 'position': 'DEF', 'points': 12},
          {
            'name': longNames ? 'Bartholomew Smythe-Jones' : 'Yara Haddad',
            'position': 'DEF',
            'points': 9,
          },
          {'name': 'Alex Rivera', 'position': 'ATT', 'points': 11},
          {'name': 'Bo Lindqvist', 'position': 'ATT', 'points': 8},
        ],
      },
    })[8]!;

LeaderboardRowData me({
  String? realName = 'Jordan Avery',
  String? teamName = 'Sweeper Keepers',
  int? movement = 1,
}) =>
    LeaderboardRowData(
      uid: 'me',
      realName: realName,
      teamName: teamName,
      points: 512,
      displayRank: 10,
      movement: movement,
      isSelf: true,
    );

const List<RankPoint> season = [
  (gameweek: 1, rank: 14),
  (gameweek: 2, rank: 12),
  (gameweek: 3, rank: 11),
  (gameweek: 4, rank: 13),
  (gameweek: 5, rank: 12),
  (gameweek: 6, rank: 11),
  (gameweek: 7, rank: 11),
  (gameweek: 8, rank: 10),
];

Widget totwStory({bool longNames = false, String label = 'Futsal Season 15'}) =>
    TeamOfWeekStoryCard(
      week: 8,
      seasonLabel: label,
      team: dreamTeam(longNames: longNames),
      config: FantasyConfig.futsalDefault(),
    );

Widget rankStory({
  LeaderboardRowData? row,
  List<RankPoint> series = season,
  String label = 'Futsal Season 15',
}) =>
    RankStoryCard(
      row: row ?? me(),
      managerCount: 21,
      series: series,
      seasonLabel: label,
    );

void main() {
  Future<void> pumpStory(WidgetTester tester, Widget story,
      {Brightness host = Brightness.light, String? fontFamily}) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: host, fontFamily: fontFamily),
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: story),
      ),
    ));
    await tester.pump();
  }

  /// Every rect of [finder] inside the story canvas.
  void expectInsideStory(WidgetTester tester, Finder finder) {
    final story = tester.getRect(find.byType(FantasyStoryFrame));
    for (final element in finder.evaluate()) {
      final box = element.renderObject! as RenderBox;
      // Through every transform (the rank story scales long names down).
      final rect = MatrixUtils.transformRect(
          box.getTransformTo(null), Offset.zero & box.size);
      expect(story.left - rect.left, lessThanOrEqualTo(0.01),
          reason: '$element');
      expect(rect.right - story.right, lessThanOrEqualTo(0.01),
          reason: '$element');
      expect(story.top - rect.top, lessThanOrEqualTo(0.01), reason: '$element');
      expect(rect.bottom - story.bottom, lessThanOrEqualTo(0.01),
          reason: '$element');
    }
  }

  test('captions', () {
    expect(teamOfWeekShareCaption(8, 'Futsal Season 15'),
        'Infinite Fantasy · Team of the Week · GW8 (Futsal Season 15)');
    expect(
        myRankShareCaption(
            rank: 10,
            managerCount: 21,
            points: 512,
            seasonLabel: 'Futsal Season 15'),
        'Infinite Fantasy · My rank · #10 of 21 · 512 pts (Futsal Season 15)');
    expect(fantasySeasonLabel('Futsal', '15'), 'Futsal Season 15');
  });

  test('the story is 9:16 and shares at 1080x1920', () {
    expect(kStoryWidth / kStoryHeight, 9 / 16);
    expect(kStoryWidth * kStoryPixelRatio, 1080);
    expect(kStoryHeight * kStoryPixelRatio, 1920);
  });

  group('Team of the Week story', () {
    for (final host in Brightness.values) {
      testWidgets(
          'story size, logo + title + "GW8 · season", the five '
          'players with position and points on the neon pitch, the footer; '
          'fixed dark in a $host app', (tester) async {
        await pumpStory(tester, totwStory(), host: host);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(FantasyStoryFrame)),
            const Size(kStoryWidth, kStoryHeight));

        expect(find.image(const AssetImage(kFantasyLogoAsset)), findsOneWidget);
        expect(find.image(const AssetImage(kNeonPitchAsset)), findsOneWidget);
        expect(find.text('Team of the Week'), findsOneWidget);
        expect(find.text('GW8 · Futsal Season 15'), findsOneWidget);
        for (final (name, points, position) in [
          ('Kit Moreno', 14, 'GK'),
          ('Dana Okafor', 12, 'DEF'),
          ('Yara Haddad', 9, 'DEF'),
          ('Alex Rivera', 11, 'ATT'),
          ('Bo Lindqvist', 8, 'ATT'),
        ]) {
          expect(find.text(name), findsOneWidget);
          expect(find.text('$points pts'), findsOneWidget);
          expect(
              find.descendant(
                  of: find.byKey(ValueKey('squad_chip_$name')),
                  matching: find.text(position)),
              findsOneWidget);
        }
        // Same court + chips as the card (reused, not redrawn), inert.
        expect(find.byType(FantasyCourtView), findsOneWidget);
        expect(find.byType(ShareCardFooter), findsOneWidget);
        expect(find.text('Follow Infinite Sports for live scores'),
            findsOneWidget);

        // Fixed dark: the image never follows the app theme.
        final title = tester.element(find.text('Team of the Week'));
        expect(Theme.of(title).brightness, Brightness.dark);
        expectInsideStory(tester, find.byType(Text));
      });

      testWidgets(
          'long names + a long season label wrap and never overflow '
          '— $host', (tester) async {
        await pumpStory(
          tester,
          totwStory(
              longNames: true,
              label: 'Flag Football Season 15 · Spring Showcase Edition'),
          host: host,
        );
        expect(tester.takeException(), isNull);
        final chipName =
            tester.widget<Text>(find.text('Maximiliano Featherstonehaugh'));
        expect(chipName.overflow, isNot(TextOverflow.ellipsis));
        final subtitle = tester.widget<Text>(find
            .text('GW8 · Flag Football Season 15 · Spring Showcase Edition'));
        expect(subtitle.overflow, isNot(TextOverflow.ellipsis));
        expect(subtitle.maxLines, isNull);
        expectInsideStory(tester, find.byType(Text));
      });
    }
  });

  group('My rank story', () {
    for (final host in Brightness.values) {
      testWidgets(
          'team name with the real name under it, "#10 of 21", total '
          'points, the week movement, the season rank line, season label, '
          'footer; fixed dark in a $host app', (tester) async {
        await pumpStory(tester, rankStory(), host: host);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(FantasyStoryFrame)),
            const Size(kStoryWidth, kStoryHeight));

        expect(find.image(const AssetImage(kFantasyLogoAsset)), findsOneWidget);
        expect(find.text('Futsal Season 15'), findsOneWidget);
        final team = find.text('Sweeper Keepers');
        final real = find.text('Jordan Avery');
        expect(team, findsOneWidget);
        expect(real, findsOneWidget);
        expect(tester.getTopLeft(real).dy,
            greaterThan(tester.getBottomLeft(team).dy - 0.5));
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('rank_story_rank')))
                .data,
            '#10');
        expect(find.text('of 21'), findsOneWidget);
        expect(find.text('512'), findsOneWidget);
        expect(find.text('▲1'), findsOneWidget);
        expect(find.byType(RankHistoryChart), findsOneWidget);
        expect(find.text('#14 → #10'), findsOneWidget);
        expect(find.byType(ShareCardFooter), findsOneWidget);

        final context = tester.element(find.text('▲1'));
        expect(Theme.of(context).brightness, Brightness.dark);
        expect(tester.widget<Text>(find.text('▲1')).style!.color,
            fantasyPitchGreen(context));
        expectInsideStory(tester, find.byType(Text));
      });
    }

    testWidgets('movement colors: ▼ red, — grey', (tester) async {
      await pumpStory(tester, rankStory(row: me(movement: -3)));
      final down = tester.element(find.text('▼3'));
      expect(tester.widget<Text>(find.text('▼3')).style!.color,
          fantasyDownRed(down));

      await pumpStory(tester, rankStory(row: me(movement: null)));
      final none = tester.element(find.text('—'));
      expect(tester.widget<Text>(find.text('—')).style!.color,
          Theme.of(none).colorScheme.onSurfaceVariant);
    });

    testWidgets(
        'no real name: the team name alone; no team name: the real '
        'name alone; under two weeks: no rank line', (tester) async {
      await pumpStory(
          tester, rankStory(row: me(realName: null), series: const []));
      expect(find.text('Sweeper Keepers'), findsOneWidget);
      expect(find.byType(RankHistoryChart), findsNothing);
      expect(tester.takeException(), isNull);

      await pumpStory(
          tester,
          rankStory(
              row: me(teamName: null), series: const [(gameweek: 1, rank: 3)]));
      expect(find.text('Jordan Avery'), findsOneWidget);
      expect(find.byType(RankHistoryChart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final host in Brightness.values) {
      testWidgets('long team + real names wrap and never overflow — $host',
          (tester) async {
        await pumpStory(
          tester,
          rankStory(
            row: LeaderboardRowData(
              uid: 'me',
              realName: longReal,
              teamName: '$longTeam And Friends Of The Doom Society',
              points: 123456,
              displayRank: 1234,
              movement: -120,
              isSelf: true,
            ),
          ),
          host: host,
        );
        expect(tester.takeException(), isNull);
        final team = tester.widget<Text>(
            find.text('$longTeam And Friends Of The Doom Society'));
        expect(team.overflow, isNot(TextOverflow.ellipsis));
        expect(team.maxLines, isNull);
        expectInsideStory(tester, find.byType(Text));
      });
    }
  });

  testWidgets(
      'the Team of the Week card shows Share only when the tab asks '
      'for it (a season label)', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    DreamTeamCard.sessionWeek = null;
    Future<void> pumpCard({String? seasonLabel}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DreamTeamCard(
                teams: {8: dreamTeam()},
                config: FantasyConfig.futsalDefault(),
                players: const [],
                seasonLabel: seasonLabel,
              ),
            ),
          ),
        ));
    await pumpCard();
    expect(find.byKey(const ValueKey('dream_team_share')), findsNothing);
    await pumpCard(seasonLabel: 'Futsal Season 15');
    expect(find.byKey(const ValueKey('dream_team_share')), findsOneWidget);
    expect(find.byTooltip('Share Team of the Week'), findsOneWidget);
  });

  testWidgets(
      'while the image renders/shares the button shows a spinner '
      'and ignores a second tap (one sheet per tap)', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    DreamTeamCard.sessionWeek = null;
    final release = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DreamTeamCard(
            teams: {8: dreamTeam()},
            config: FantasyConfig.futsalDefault(),
            players: const [],
            seasonLabel: 'Futsal Season 15',
            shareImage: (png, caption, origin) {
              calls++;
              return release.future;
            },
          ),
        ),
      ),
    ));
    final button = find.byKey(const ValueKey('dream_team_share'));
    await tester.tap(button);
    await pumpUntil(tester, () => calls > 0);
    expect(calls, 1);
    expect(
        find.descendant(
            of: button, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    release.complete();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: button, matching: find.byType(CircularProgressIndicator)),
        findsNothing);
    expect(find.descendant(of: button, matching: find.byIcon(Icons.ios_share)),
        findsOneWidget);
  });

  group('owner previews (only with --dart-define=FANTASY_SHARE_PNG_DIR)', () {
    for (final (file, build) in [
      ('share_totw.png', () => totwStory()),
      ('share_rank.png', () => rankStory()),
    ]) {
      testWidgets('renders $file through the real share pipeline',
          (tester) async {
        if (kPngDir.isEmpty) {
          markTestSkipped('set FANTASY_SHARE_PNG_DIR to write previews');
          return;
        }
        final fonts = await tester.runAsync(
            () async => await loadRealFont() && await loadMaterialIconsFont());
        if (fonts != true) {
          markTestSkipped('Flutter SDK material_fonts not found');
          return;
        }
        // ▲ ▼ → come from the OS on a phone; borrow a system symbol font.
        final symbols = await tester.runAsync(loadSymbolsFallbackFont);
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
            fontFamily: kRealFont,
            fontFamilyFallback: [if (symbols == true) kSymbolsFallbackFont],
          ),
          home: const Scaffold(body: SizedBox.expand()),
        ));
        final shares = ShareRecorder();
        final context = tester.element(find.byType(SizedBox).last);
        shareFantasyStory(context, build(),
            caption: 'preview', share: shares.call);
        await pumpUntil(tester, () => shares.calls.isNotEmpty);
        final png = shares.calls.single.png;
        expect(pngSize(png), const Size(1080, 1920));
        await tester.runAsync(
            () => File('$kPngDir/$file').writeAsBytes(png, flush: true));
      });
    }
  });
}

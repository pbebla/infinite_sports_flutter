// P3d — the My Leagues surface proved with seams (no Firebase, no platform
// channels): the membership-filtered list with member counts + your rank;
// the create flow (name in → fresh 6-char code shown BIG with a copy
// button); the join flow (PASTE button, live lookup, league PREVIEW card,
// already-member guard, Join writes own membership); the league detail's
// ranked member rows + Share-code row; signed-out face.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/mini_leagues_view.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';

FantasyMiniLeague league({
  String id = 'L1',
  String name = 'Sunday Crew',
  String code = 'ABC234',
  String owner = 'me',
  Set<String> members = const {'me', 'u2'},
}) =>
    FantasyMiniLeague(
        id: id, name: name, code: code, ownerUid: owner, memberUids: members);

FantasyManager manager(String name) =>
    FantasyManager(teamName: name, nameFlagged: false);

void main() {
  late List<(String, String)> created;
  late List<String> joined;
  late List<String> copied;
  late List<String> shared;
  late List<LeaderboardRowData> openedRows;
  String? clipboard;

  setUp(() {
    created = [];
    joined = [];
    copied = [];
    shared = [];
    openedRows = [];
    clipboard = null;
  });

  Future<void> pumpView(
    WidgetTester tester, {
    required List<FantasyMiniLeague> leagues,
    List<FantasyLeaderboardEntry> overall = const [],
    Map<String, FantasyManager> managers = const {},
    String selfUid = 'me',
    Future<void> Function(String name, String code)? onCreate,
    Future<void> Function(String id)? onJoin,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MiniLeaguesView(
          leagues: leagues,
          overall: overall,
          managers: managers,
          profiles: const <String, PublicProfile>{},
          selfUid: selfUid,
          onOpenManager: openedRows.add,
          onCreateLeague: onCreate ??
              (name, code) async => created.add((name, code)),
          onJoinLeague: onJoin ?? (id) async => joined.add(id),
          copyText: copied.add,
          shareText: shared.add,
          readClipboard: () async => clipboard,
          codeGenerator: () => 'QQ2345',
        ),
      ),
    ));
  }

  testWidgets('signed out → the sign-in face, no create/join', (tester) async {
    await pumpView(tester, leagues: [league()], selfUid: '');
    expect(find.byKey(const ValueKey('mini_leagues_signed_out')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('mini_league_create')), findsNothing);
  });

  testWidgets('lists ONLY my leagues with member count and my rank from '
      'Overall totals', (tester) async {
    await pumpView(
      tester,
      leagues: [
        league(id: 'a', name: 'Sunday Crew', members: {'me', 'u2', 'u3'}),
        league(id: 'b', name: 'Not Mine', members: {'u2'}),
      ],
      overall: const [
        FantasyLeaderboardEntry(uid: 'u2', points: 50, rank: 1),
        FantasyLeaderboardEntry(uid: 'me', points: 40, rank: 2),
      ],
      managers: {'me': manager('My Team'), 'u2': manager('Them')},
    );
    expect(find.byKey(const ValueKey('mini_league_card_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini_league_card_b')), findsNothing);
    expect(find.text("3 members · You're #2"), findsOneWidget);
  });

  testWidgets('no leagues yet → friendly empty card under the actions',
      (tester) async {
    await pumpView(tester, leagues: const []);
    expect(find.byKey(const ValueKey('mini_leagues_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini_league_create')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini_league_join')), findsOneWidget);
  });

  testWidgets('create flow: 3-char minimum, then the fresh code BIG with a '
      'copy button', (tester) async {
    await pumpView(tester, leagues: const []);
    await tester.tap(find.byKey(const ValueKey('mini_league_create')));
    await tester.pumpAndSettle();

    // Too short → Create disabled.
    await tester.enterText(
        find.byKey(const ValueKey('create_league_name')), 'ab');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('create_league_confirm')))
            .onPressed,
        isNull);

    await tester.enterText(
        find.byKey(const ValueKey('create_league_name')), 'The Regulars');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create_league_confirm')));
    await tester.pumpAndSettle();

    expect(created.single, ('The Regulars', 'QQ2345'));
    // The code reveal: big text + copy.
    final codeText = tester
        .widget<Text>(find.byKey(const ValueKey('created_league_code')));
    expect(codeText.data, 'QQ2345');
    expect(codeText.style!.fontSize, greaterThanOrEqualTo(28));
    await tester.tap(find.byKey(const ValueKey('created_league_copy')));
    await tester.pumpAndSettle();
    expect(copied.single, 'QQ2345');
    expect(find.text('Code copied.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('created_league_done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('created_league_code')), findsNothing);
  });

  testWidgets('join flow: PASTE fills the field, the live lookup shows the '
      'PREVIEW, Join writes membership and opens the league', (tester) async {
    clipboard = 'abc-234';
    await pumpView(
      tester,
      leagues: [
        league(
            id: 'other',
            name: 'Office League',
            code: 'ABC234',
            owner: 'u9',
            members: {'u9', 'u8'}),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('mini_league_join')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('join_league_paste')));
    await tester.pumpAndSettle();

    // Preview card: name + member count, Join live.
    expect(find.byKey(const ValueKey('join_league_preview_other')),
        findsOneWidget);
    expect(find.text('Office League'), findsOneWidget);
    expect(find.text('2 members'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('join_league_confirm')));
    await tester.pumpAndSettle();
    expect(joined.single, 'other');
    expect(find.text('Joined Office League!'), findsOneWidget);
    // Lands inside the league (detail view).
    expect(find.byKey(const ValueKey('mini_league_detail_other')),
        findsOneWidget);
  });

  testWidgets('join flow: a complete unknown code says so; an incomplete one '
      'stays quiet; already-a-member disables Join', (tester) async {
    await pumpView(tester, leagues: [league(code: 'ABC234')]);
    await tester.tap(find.byKey(const ValueKey('mini_league_join')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('join_league_code')), 'ZZZ');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join_league_not_found')), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('join_league_code')), 'ZZZ999');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join_league_not_found')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('join_league_confirm')))
            .onPressed,
        isNull);

    // My own league's code: preview shows but Join stays disabled.
    await tester.enterText(
        find.byKey(const ValueKey('join_league_code')), 'abc234');
    await tester.pumpAndSettle();
    expect(find.textContaining("You're already in this league"),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('join_league_confirm')))
            .onPressed,
        isNull);
  });

  testWidgets('league detail: ranked member rows (absent totals rank by name '
      'with 0 pts), Share-code row copies and shares, rows open the squad '
      'viewer, back returns', (tester) async {
    await pumpView(
      tester,
      leagues: [
        league(
            id: 'a',
            name: 'Sunday Crew',
            code: 'KX7Q2M',
            members: {'me', 'u2', 'zed', 'ann'}),
      ],
      overall: const [
        FantasyLeaderboardEntry(uid: 'u2', points: 50, rank: 1),
        FantasyLeaderboardEntry(uid: 'me', points: 40, rank: 2),
      ],
      managers: {
        'me': manager('My Team'),
        'u2': manager('Them'),
        'zed': manager('Zero Pts FC'),
        'ann': manager('Ann United'),
      },
    );
    await tester.tap(find.byKey(const ValueKey('mini_league_card_a')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mini_league_detail_a')), findsOneWidget);
    expect(find.textContaining('KX7Q2M'), findsOneWidget);
    // Same ranked-rows UI scoped to members: podium top 3 (u2, me, then the
    // total-less members by name — ann before zed), the 4th as a tile row.
    expect(find.byKey(const ValueKey('podium_u2')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium_ann')), findsOneWidget);
    expect(find.byKey(const ValueKey('leaderboard_row_zed')), findsOneWidget);
    // Absent totals → 0 pts (ann on the podium, zed's tile).
    expect(find.text('0 pts'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('mini_league_copy')));
    await tester.pumpAndSettle();
    expect(copied.single, 'KX7Q2M');
    await tester.tap(find.byKey(const ValueKey('mini_league_share')));
    expect(shared.single, contains('KX7Q2M'));
    expect(shared.single, contains('Sunday Crew'));

    await tester.tap(find.byKey(const ValueKey('leaderboard_row_zed')));
    await tester.pumpAndSettle();
    expect(openedRows.single.uid, 'zed');
    expect(openedRows.single.name, 'Zero Pts FC');

    await tester.tap(find.byKey(const ValueKey('mini_league_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini_leagues_list')), findsOneWidget);
  });
}

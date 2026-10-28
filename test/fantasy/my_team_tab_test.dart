// P3a feedback, spec §10b — the My Team tab's three stream-driven faces:
// name prompt (no Managers entry), the moderation gate (NameFlagged), and
// the squad placeholder. Naming flow, gate appearance and the stream-driven
// unlock are all proved with fake streams — no Firebase.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/my_team_tab.dart';

void main() {
  late StreamController<FantasyManager?> managers;
  late StreamController<FantasySquad?> squads;
  late List<String> saved;

  setUp(() {
    managers = StreamController<FantasyManager?>.broadcast();
    squads = StreamController<FantasySquad?>.broadcast();
    saved = [];
  });

  tearDown(() {
    managers.close();
    squads.close();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    FantasyManager? initial,
    Future<void> Function(String)? onSave,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyMyTeamTab(
          managerStates: managers.stream,
          initialManager: initial,
          onSaveName: onSave ??
              (name) async {
                saved.add(name);
              },
          configState: FantasyConfigState(
            config: FantasyConfig.futsalDefault(),
            lockOverride: FantasyLockOverride.open,
          ),
          players: const [],
          gameweeks: const [],
          squadStates: squads.stream,
          onSaveSquad: (_) async {},
        ),
      ),
    ));
  }

  group('naming flow', () {
    testWidgets('no Managers entry → prompt, dialog validates then saves',
        (tester) async {
      await pumpTab(tester);

      // The prompt face.
      expect(find.text('Name your team'), findsOneWidget);
      expect(find.text('Choose a name'), findsOneWidget);

      await tester.tap(find.text('Choose a name'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('team_name_field')), findsOneWidget);

      // Too short → inline length error, nothing saved.
      await tester.enterText(
          find.byKey(const ValueKey('team_name_field')), 'ab');
      await tester.tap(find.byKey(const ValueKey('team_name_save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Team names are 3–30'), findsOneWidget);
      expect(saved, isEmpty);

      // Leetspeak profanity → blocked with a reason, nothing saved.
      await tester.enterText(
          find.byKey(const ValueKey('team_name_field')), 'Sh1t Squad');
      await tester.tap(find.byKey(const ValueKey('team_name_save')));
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't allowed"), findsOneWidget);
      expect(saved, isEmpty);

      // A clean name saves (trimmed) and the dialog closes.
      await tester.enterText(
          find.byKey(const ValueKey('team_name_field')), '  Golden Boots ');
      await tester.tap(find.byKey(const ValueKey('team_name_save')));
      await tester.pumpAndSettle();
      expect(saved, ['Golden Boots']);
      expect(find.byKey(const ValueKey('team_name_field')), findsNothing);

      // The write echoes back on the stream → the ready face (the P3b squad
      // builder) replaces the prompt.
      managers.add(
          const FantasyManager(teamName: 'Golden Boots', nameFlagged: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my_team_ready')), findsOneWidget);
    });

    testWidgets('a failed save keeps the dialog open with an error',
        (tester) async {
      await pumpTab(tester,
          onSave: (_) async => throw Exception('rules rejected'));
      await tester.tap(find.text('Choose a name'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('team_name_field')), 'Golden Boots');
      await tester.tap(find.byKey(const ValueKey('team_name_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('team_name_field')), findsOneWidget);
      expect(find.textContaining("Couldn't save"), findsOneWidget);
    });
  });

  group('moderation gate', () {
    testWidgets('NameFlagged replaces the tab with the gate card',
        (tester) async {
      await pumpTab(tester,
          initial:
              const FantasyManager(teamName: 'Bad Name', nameFlagged: true));

      expect(find.byKey(const ValueKey('my_team_flag_gate')), findsOneWidget);
      expect(
          find.textContaining(
              'Your team name was flagged by the league. Choose a new name '
              'to continue.'),
          findsOneWidget);
      // The rename dialog is the only action; the squad face is absent.
      expect(find.text('Choose a new name'), findsOneWidget);
      expect(find.byKey(const ValueKey('my_team_ready')), findsNothing);
    });

    testWidgets('renaming unlocks immediately, driven by the stream',
        (tester) async {
      await pumpTab(tester,
          initial:
              const FantasyManager(teamName: 'Bad Name', nameFlagged: true));

      // The rename dialog opens pre-filled with the flagged name.
      await tester.tap(find.text('Choose a new name'));
      await tester.pumpAndSettle();
      expect(find.text('Bad Name'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('team_name_field')), 'Fresh Start');
      await tester.tap(find.byKey(const ValueKey('team_name_save')));
      await tester.pumpAndSettle();
      expect(saved, ['Fresh Start']);

      // The rules-accepted write echoes back unflagged → gate clears to the
      // squad builder.
      managers.add(
          const FantasyManager(teamName: 'Fresh Start', nameFlagged: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my_team_flag_gate')), findsNothing);
      expect(find.byKey(const ValueKey('my_team_ready')), findsOneWidget);
    });

    testWidgets('a re-flag by the league gates again live', (tester) async {
      await pumpTab(tester,
          initial:
              const FantasyManager(teamName: 'Still Bad', nameFlagged: false));
      expect(find.byKey(const ValueKey('my_team_ready')), findsOneWidget);

      managers.add(
          const FantasyManager(teamName: 'Still Bad', nameFlagged: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('my_team_flag_gate')), findsOneWidget);
    });
  });

  testWidgets('no underlined tappable text (house rule)', (tester) async {
    await pumpTab(tester,
        initial:
            const FantasyManager(teamName: 'Golden Boots', nameFlagged: false));
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.decoration ?? TextDecoration.none, TextDecoration.none,
          reason: '"${t.data}" must not be underlined');
    }
  });
}

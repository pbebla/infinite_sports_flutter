// Final review I1: the chip action sheet (six tiles with Substitute) must
// keep every tile reachable on small phones — no overflow, Remove can be
// scrolled to and tapped — in light and dark mode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_picker_sheet.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';

void main() {
  const longLabel = 'Substitute with Maximiliano Fernández-Castellanos';

  for (final (label, size, bottomInset) in [
    ('375x667', const Size(375, 667), 0.0),
    ('360x640', const Size(360, 640), 0.0),
    ('360x640 with a 3-button nav bar', const Size(360, 640), 48.0),
  ]) {
    for (final (modeName, theme) in [('light', lightMode), ('dark', darkMode)]) {
      testWidgets('$label, $modeName: six tiles fit, Remove is reachable',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = FakeViewPadding(bottom: bottomInset);
        tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
        addTearDown(tester.view.reset);
        SquadChipAction? result;
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showSquadChipActions(
                      context,
                      playerName: 'Att Two',
                      bench: false,
                      showProfile: true,
                      substituteLabel: longLabel,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final key in [
          'action_profile',
          'action_make_captain',
          'action_make_vice',
          'action_substitute',
          'action_swap',
          'action_remove',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        }

        final remove = find.byKey(const ValueKey('action_remove'));
        await tester.ensureVisible(remove);
        await tester.pumpAndSettle();
        // Fully on screen, above the system nav bar.
        final r = tester.getRect(remove);
        expect(r.bottom, lessThanOrEqualTo(size.height - bottomInset));
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(result, SquadChipAction.remove);
      });
    }
  }

  testWidgets('a tall phone: the sheet hugs its tiles, nothing scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: lightMode,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showSquadChipActions(context,
                  playerName: 'Att Two',
                  bench: false,
                  substituteLabel: 'Substitute with Bench Att'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The sheet stays a short sheet at the bottom, not a full-height one.
    final title = tester.getRect(find.text('Att Two'));
    expect(title.top, greaterThan(852 / 2));
  });
}

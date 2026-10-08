// Widget tests for RegistrationPathPage's per-path gating (owner ask,
// Futsal S16): the chooser renders only the paths enabled on the
// registration's Config.Paths, and when exactly one of individual/joiner is
// enabled it skips itself and renders that path's page directly (stubbed via
// the builder seams — the real pages fetch Firebase in initState).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';

void main() {
  const regId = 'Futsal-16';

  Widget wrap(RegistrationConfig config) => MaterialApp(
        home: RegistrationPathPage(
          regId: regId,
          config: config,
          individualFormBuilder: () =>
              const Scaffold(body: Center(child: Text('stub individual form'))),
          joinCodePageBuilder: () =>
              const Scaffold(body: Center(child: Text('stub join page'))),
        ),
      );

  RegistrationConfig config({
    bool individual = true,
    bool joiner = true,
    bool captain = true,
  }) =>
      RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '16',
        status: 'open',
        pathIndividual: individual,
        pathJoiner: joiner,
        pathCaptain: captain,
      );

  testWidgets('all paths on: chooser shows all three cards', (tester) async {
    await tester.pumpWidget(wrap(config()));

    expect(find.text('How are you registering?'), findsOneWidget);
    expect(find.text('Register as an individual'), findsOneWidget);
    expect(find.text('Join a team with a code'), findsOneWidget);
    expect(find.text('Register a new team (captain)'), findsOneWidget);
  });

  testWidgets('two paths: only the enabled cards render', (tester) async {
    await tester.pumpWidget(wrap(config(joiner: false)));

    expect(find.text('How are you registering?'), findsOneWidget);
    expect(find.text('Register as an individual'), findsOneWidget);
    expect(find.text('Join a team with a code'), findsNothing);
    expect(find.text('Register a new team (captain)'), findsOneWidget);
  });

  testWidgets('individual only: chooser is skipped, form renders directly',
      (tester) async {
    await tester.pumpWidget(wrap(config(joiner: false, captain: false)));

    expect(find.text('stub individual form'), findsOneWidget);
    expect(find.text('How are you registering?'), findsNothing);
  });

  testWidgets('joiner only: chooser is skipped, join page renders directly',
      (tester) async {
    await tester.pumpWidget(wrap(config(individual: false, captain: false)));

    expect(find.text('stub join page'), findsOneWidget);
    expect(find.text('How are you registering?'), findsNothing);
  });

  testWidgets('captain only: single-card chooser (dialog flow needs a page)',
      (tester) async {
    await tester.pumpWidget(wrap(config(individual: false, joiner: false)));

    expect(find.text('How are you registering?'), findsOneWidget);
    expect(find.text('Register a new team (captain)'), findsOneWidget);
    expect(find.text('Register as an individual'), findsNothing);
    expect(find.text('Join a team with a code'), findsNothing);
  });
}
